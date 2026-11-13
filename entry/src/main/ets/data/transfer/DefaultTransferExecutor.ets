import { AppError, AppErrorCode } from '../../common/error/AppError';
import { LsLogger } from '../../common/log/LsLogger';
import { Result } from '../../common/result/Result';
import { AppSettings } from '../../config/AppSettings';
import { ProviderRegistry } from '../../domain/provider/ProviderRegistry';
import {
  CloudProviderType,
  TransferCheckpoint,
  TransferJob,
  TransferState
} from '../../model/AppModels';
import { HttpClient } from '../network/HttpClient';
import { DirectDownloader } from './DirectDownloader';
import { HlsDownloader } from './HlsDownloader';
import { Mp4Remuxer } from './Mp4Remuxer';
import { MultipartUploader } from './MultipartUploader';
import {
  CancellationToken,
  TransferCheckpointCallback,
  TransferExecutor,
  TransferProgress,
  TransferProgressCallback
} from './TransferContracts';
import { TransferFileUtils } from './TransferFileUtils';

const TAG: string = 'TransferExecutor';
const DOWNLOAD_PROGRESS_INTERVAL_MS: number = 1000;

class AsyncPermitLimiter {
  private readonly limit: number;
  private active: number = 0;
  private waiters: Array<() => void> = [];

  constructor(limit: number) {
    this.limit = Math.max(1, limit);
  }

  async acquire(): Promise<void> {
    if (this.active < this.limit) {
      this.active++;
      return;
    }
    await new Promise<void>((resolve: () => void) => {
      this.waiters.push(resolve);
    });
  }

  release(): void {
    const next = this.waiters.shift();
    if (next !== undefined) {
      next();
      return;
    }
    this.active = Math.max(0, this.active - 1);
  }
}

class DownloadProgressReporter {
  private readonly job: TransferJob;
  private readonly checkpoint: TransferCheckpoint;
  private readonly onProgress?: TransferProgressCallback;
  private readonly onCheckpoint?: TransferCheckpointCallback;
  private latest?: TransferProgress;
  private timer: number = -1;
  private lastBytes: number;
  private lastUpdateAt: number = Date.now();

  constructor(
    job: TransferJob,
    checkpoint: TransferCheckpoint,
    onProgress?: TransferProgressCallback,
    onCheckpoint?: TransferCheckpointCallback
  ) {
    this.job = job;
    this.checkpoint = checkpoint;
    this.onProgress = onProgress;
    this.onCheckpoint = onCheckpoint;
    this.lastBytes = checkpoint.downloadedBytes;
  }

  start(): void {
    this.timer = setInterval(() => this.flush(), DOWNLOAD_PROGRESS_INTERVAL_MS);
  }

  update(progress: TransferProgress): void {
    this.latest = progress;
  }

  stop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    this.flush();
  }

  private flush(): void {
    if (this.latest === undefined) {
      return;
    }
    this.checkpoint.downloadedBytes = this.latest.completedBytes;
    const now = Date.now();
    const elapsedMs = Math.max(1, now - this.lastUpdateAt);
    this.job.downloadSpeedBytes =
      Math.max(0, Math.floor((this.latest.completedBytes - this.lastBytes) * 1000 / elapsedMs));
    this.job.progress = this.latest.progress;
    this.job.updatedAt = now;
    this.lastBytes = this.latest.completedBytes;
    this.lastUpdateAt = now;
    this.onProgress?.(this.latest);
    this.onCheckpoint?.(this.job);
  }
}

export class DefaultTransferExecutor implements TransferExecutor {
  private readonly filesDirectory: string;
  private readonly settings: AppSettings;
  private readonly providers: ProviderRegistry;
  private readonly directDownloader: DirectDownloader = new DirectDownloader();
  private readonly hlsDownloader: HlsDownloader;
  private readonly mp4Remuxer: Mp4Remuxer = new Mp4Remuxer();
  private readonly uploader: MultipartUploader = new MultipartUploader();
  private readonly downloadLimiter: AsyncPermitLimiter;
  private readonly uploadLimiter: AsyncPermitLimiter;

  constructor(
    filesDirectory: string,
    settings: AppSettings,
    providers: ProviderRegistry,
    client: HttpClient
  ) {
    this.filesDirectory = filesDirectory;
    this.settings = settings;
    this.providers = providers;
    this.hlsDownloader = new HlsDownloader(client);
    this.downloadLimiter = new AsyncPermitLimiter(settings.downloadConcurrency);
    this.uploadLimiter = new AsyncPermitLimiter(settings.uploadConcurrency);
  }

  clearLocalCache(): void {
    TransferFileUtils.clearDirectory(`${this.filesDirectory}/download`);
    LsLogger.info(TAG, 'Download cache cleared');
  }

  async execute(
    job: TransferJob,
    token: CancellationToken,
    onProgress?: TransferProgressCallback,
    onCheckpoint?: TransferCheckpointCallback
  ): Promise<Result<TransferJob>> {
    try {
      this.prepare(job);
      const checkpoint = job.checkpoint as TransferCheckpoint;
      const hls = this.isHls(job.downloadUrl);
      let hlsSourcePath = hls ? this.hlsSourcePath(job) : '';
      const hlsOutputPath = hls ? this.hlsOutputPath(job) : '';
      if (hls && TransferFileUtils.sizeOf(hlsOutputPath) > 0) {
        job.localFile = hlsOutputPath;
        job.state = TransferState.DOWNLOADED;
      }
      const hasMergedHls = hls && TransferFileUtils.sizeOf(hlsSourcePath) > 0;
      const needsDownloadStage = job.state !== TransferState.DOWNLOADED &&
        job.state !== TransferState.UPLOADING || hls && TransferFileUtils.sizeOf(hlsOutputPath) <= 0;
      if (needsDownloadStage) {
        await this.downloadLimiter.acquire();
        try {
          if (token.canceled) {
            return this.fail(job, new AppError(AppErrorCode.CANCELED, '传输已取消'), token, onCheckpoint);
          }
          if (!hasMergedHls && job.state !== TransferState.DOWNLOADED &&
            job.state !== TransferState.UPLOADING) {
            LsLogger.info(TAG, `Download started job=${job.jobId}, hls=${this.isHls(job.downloadUrl)}`);
            job.state = TransferState.DOWNLOADING;
            job.progress = 0;
            job.updatedAt = Date.now();
            onCheckpoint?.(job);
            const progressReporter =
              new DownloadProgressReporter(job, checkpoint, onProgress, onCheckpoint);
            progressReporter.start();
            let download: Result<number>;
            try {
              download = hls ?
                await this.hlsDownloader.download(
                  job.downloadUrl,
                  hlsSourcePath,
                  this.settings.hlsConcurrency,
                  checkpoint.completedSegments,
                  token,
                  (progress: TransferProgress) => progressReporter.update(progress),
                  (playlistUrl: string, segmentCount: number, completed: number[]) => {
                    checkpoint.hlsPlaylistUrl = playlistUrl;
                    checkpoint.hlsSegmentCount = segmentCount;
                    checkpoint.completedSegments = completed;
                  },
                  job.source?.address
                ) :
                await this.directDownloader.download(
                  job.downloadUrl,
                  job.localFile,
                  0,
                  token,
                  (progress: TransferProgress) => progressReporter.update(progress)
                );
            } finally {
              progressReporter.stop();
            }
            if (!download.isSuccess) {
              return this.fail(job, download.error, token, onCheckpoint);
            }
            checkpoint.downloadedBytes = download.value ??
              TransferFileUtils.sizeOf(hls ? hlsSourcePath : job.localFile);
            job.progress = 100;
            job.downloadSpeedBytes = 0;
            job.updatedAt = Date.now();
            LsLogger.info(TAG,
              `Download and merge completed job=${job.jobId}, bytes=${checkpoint.downloadedBytes}`);
            if (!hls) {
              job.state = TransferState.DOWNLOADED;
              onCheckpoint?.(job);
            }
          }
          if (hls && TransferFileUtils.sizeOf(hlsOutputPath) <= 0) {
            job.state = TransferState.CONVERTING;
            job.progress = 100;
            job.updatedAt = Date.now();
            onCheckpoint?.(job);
            hlsSourcePath = this.hlsSourcePath(job);
            const remux = await this.mp4Remuxer.remux(hlsSourcePath, hlsOutputPath, token);
            if (!remux.isSuccess) {
              return this.fail(job, remux.error, token, onCheckpoint);
            }
            TransferFileUtils.deleteIfExists(hlsSourcePath);
            job.localFile = hlsOutputPath;
            checkpoint.downloadedBytes = remux.value ?? TransferFileUtils.sizeOf(hlsOutputPath);
            checkpoint.uploadSession = '';
            checkpoint.completedParts = [];
            checkpoint.uploadEtags = [];
            checkpoint.uploadedBytes = 0;
            job.state = TransferState.DOWNLOADED;
            job.updatedAt = Date.now();
            onCheckpoint?.(job);
          }
        } finally {
          this.downloadLimiter.release();
        }
      }
      if (token.canceled) {
        return this.fail(job, new AppError(AppErrorCode.CANCELED, '传输已取消'), token, onCheckpoint);
      }
      await this.uploadLimiter.acquire();
      try {
        if (token.canceled) {
          return this.fail(job, new AppError(AppErrorCode.CANCELED, '传输已取消'), token, onCheckpoint);
        }
        job.state = TransferState.UPLOADING;
        job.updatedAt = Date.now();
        onCheckpoint?.(job);
        const provider = this.providers.get(job.provider);
        const targetFolder = await this.resolveTargetFolder(job);
        if (!targetFolder.isSuccess || targetFolder.value === undefined) {
          return this.fail(job, targetFolder.error, token, onCheckpoint);
        }
        LsLogger.info(TAG, `Upload started job=${job.jobId}, provider=${job.provider}`);
        const upload = await this.uploader.upload(
          provider,
          job.localFile,
          targetFolder.value,
          this.fileName(job),
          checkpoint.uploadSession,
          checkpoint.completedParts,
          checkpoint.uploadEtags,
          token,
          (progress) => {
            job.progress = 70 + Math.floor(progress.progress * 0.3);
            job.updatedAt = Date.now();
            onProgress?.(progress);
          },
          (session, parts, etags, uploadedBytes) => {
            checkpoint.uploadSession = JSON.stringify(session);
            checkpoint.completedParts = parts;
            checkpoint.uploadEtags = etags;
            checkpoint.uploadedBytes = uploadedBytes;
            job.updatedAt = Date.now();
            onCheckpoint?.(job);
          },
          job.provider === CloudProviderType.ALIYUN ? this.settings.aliyunLockDriveId : undefined
        );
        if (!upload.isSuccess) {
          return this.fail(job, upload.error, token, onCheckpoint);
        }
      } finally {
        this.uploadLimiter.release();
      }
      job.state = TransferState.COMPLETED;
      job.progress = 100;
      job.errorMessage = '';
      job.updatedAt = Date.now();
      onCheckpoint?.(job);
      LsLogger.info(TAG, `Upload completed job=${job.jobId}`);
      return Result.success<TransferJob>(job);
    } catch (error) {
      const appError = error instanceof AppError ? error :
        new AppError(AppErrorCode.UNKNOWN, error instanceof Error ? error.message : String(error));
      return this.fail(job, appError, token, onCheckpoint);
    }
  }

  private prepare(job: TransferJob): void {
    const downloadDirectory = `${this.filesDirectory}/download`;
    TransferFileUtils.ensureDirectory(downloadDirectory);
    if (job.localFile.length === 0) {
      job.localFile = `${downloadDirectory}/${this.safeName(this.fileName(job))}`;
    }
    if (job.checkpoint === undefined) {
      job.checkpoint = {
        downloadedBytes: 0,
        hlsPlaylistUrl: '',
        hlsSegmentCount: 0,
        completedSegments: [],
        uploadSession: '',
        completedParts: [],
        uploadEtags: [],
        uploadedBytes: 0
      };
    }
  }

  private targetFolder(job: TransferJob): string {
    if (job.targetFolderId !== undefined && job.targetFolderId.length > 0) {
      return job.targetFolderId;
    }
    return job.provider === CloudProviderType.ALIYUN ?
      this.settings.aliyunLockRootFolderId : this.settings.quarkTransformRootFolderId;
  }

  private async resolveTargetFolder(job: TransferJob): Promise<Result<string>> {
    if (job.targetFolderId !== undefined && job.targetFolderId.length > 0) {
      return Result.success<string>(job.targetFolderId);
    }
    const source = job.source;
    if (source === undefined || source.type.length === 0) {
      return Result.success<string>(this.targetFolder(job));
    }
    const provider = this.providers.get(job.provider);
    const driveId = job.provider === CloudProviderType.ALIYUN ?
      this.settings.aliyunLockDriveId : undefined;
    const typeFolder = await provider.createFolder(this.targetFolder(job), source.type, driveId);
    if (!typeFolder.isSuccess || typeFolder.value === undefined) {
      return Result.failure<string>(
        typeFolder.error ?? new AppError(AppErrorCode.NETWORK, '创建类型目录失败')
      );
    }
    if (source.subType.length === 0) {
      return typeFolder;
    }
    return provider.createFolder(typeFolder.value, source.subType, driveId);
  }

  private fileName(job: TransferJob): string {
    const name = job.name.length > 0 ? job.name : job.key;
    if (!this.isHls(job.downloadUrl)) {
      return name;
    }
    const dot = name.lastIndexOf('.');
    return `${dot > 0 ? name.substring(0, dot) : name}.mp4`;
  }

  private safeName(name: string): string {
    return name.replace(/[\\/:*?"<>|]/g, '_');
  }

  private isHls(url: string): boolean {
    return /\.m3u8(?:$|[?#])/i.test(url);
  }

  private hlsSourcePath(job: TransferJob): string {
    return job.localFile.toLowerCase().endsWith('.ts') ? job.localFile : `${this.hlsOutputPath(job)}.ts`;
  }

  private hlsOutputPath(job: TransferJob): string {
    const lower = job.localFile.toLowerCase();
    if (lower.endsWith('.mp4')) {
      return job.localFile;
    }
    if (lower.endsWith('.ts')) {
      return `${job.localFile.substring(0, job.localFile.length - 3)}.mp4`;
    }
    return `${job.localFile}.mp4`;
  }

  private fail(
    job: TransferJob,
    error: AppError | undefined,
    token: CancellationToken,
    onCheckpoint?: TransferCheckpointCallback
  ): Result<TransferJob> {
    const failure = error ?? new AppError(AppErrorCode.UNKNOWN, '传输失败');
    job.state = token.canceled || failure.code === AppErrorCode.CANCELED ?
      TransferState.CANCELED : TransferState.FAILED;
    job.errorMessage = failure.message;
    job.updatedAt = Date.now();
    onCheckpoint?.(job);
    return Result.failure<TransferJob>(failure);
  }
}

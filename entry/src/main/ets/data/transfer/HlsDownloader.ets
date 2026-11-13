import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { AppError, AppErrorCode } from '../../common/error/AppError';
import { LsLogger } from '../../common/log/LsLogger';
import { Result } from '../../common/result/Result';
import { HttpClient } from '../network/HttpClient';
import { Aes128Decryptor } from './Aes128Decryptor';
import { CancellationToken, TransferProgressCallback } from './TransferContracts';
import { HlsMediaPlaylist, HlsPlaylistParser, HlsSegment } from './HlsPlaylistParser';
import { TransferFileUtils } from './TransferFileUtils';

const TAG: string = 'HlsDownloader';
const HLS_TIMEOUT_MS: number = 60000;
const HLS_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/128.0 Mobile Safari/537.36';

interface HlsHeaders {
  Accept: string;
  'User-Agent': string;
  Referer?: string;
}

export type HlsCheckpointCallback = (playlistUrl: string, segmentCount: number, completed: number[]) => void;

export class HlsDownloader {
  private readonly client: HttpClient;

  constructor(client: HttpClient) {
    this.client = client;
  }

  async download(
    sourceUrl: string,
    outputPath: string,
    concurrency: number,
    restoredSegments: number[],
    token: CancellationToken,
    onProgress?: TransferProgressCallback,
    onCheckpoint?: HlsCheckpointCallback,
    sourcePageUrl?: string
  ): Promise<Result<number>> {
    try {
      LsLogger.info(TAG, `Playlist download started url=${this.safeUrl(sourceUrl)}`);
      const master = await this.client.requestText({
        url: sourceUrl,
        headers: this.headers(sourcePageUrl),
        timeoutMs: HLS_TIMEOUT_MS,
        retryable: true,
        protocol: http.HttpProtocol.HTTP1_1
      });
      if (!master.isSuccess || master.value === undefined) {
        return Result.failure<number>(master.error ?? new AppError(AppErrorCode.NETWORK, '读取 HLS 播放列表失败'));
      }
      const mediaUrl = HlsPlaylistParser.selectMediaPlaylist(master.value, sourceUrl);
      let mediaContent = master.value;
      if (mediaUrl !== sourceUrl) {
        const media = await this.client.requestText({
          url: mediaUrl,
          headers: this.headers(sourceUrl),
          timeoutMs: HLS_TIMEOUT_MS,
          retryable: true,
          protocol: http.HttpProtocol.HTTP1_1
        });
        if (!media.isSuccess || media.value === undefined) {
          return Result.failure<number>(media.error ?? new AppError(AppErrorCode.NETWORK, '读取 HLS 媒体列表失败'));
        }
        mediaContent = media.value;
      }
      const playlist = HlsPlaylistParser.parseMedia(mediaContent, mediaUrl);
      if (playlist.segments.length === 0) {
        return Result.failure<number>(new AppError(AppErrorCode.PARSE, 'HLS 播放列表没有媒体分片'));
      }
      LsLogger.info(TAG, `Playlist ready segments=${playlist.segments.length}`);
      const segmentDirectory = `${outputPath}.segments`;
      TransferFileUtils.ensureDirectory(segmentDirectory);
      const completed = new Set<number>();
      let completedBytes = 0;
      restoredSegments.forEach((index: number) => {
        const restoredSize = TransferFileUtils.sizeOf(this.segmentPath(segmentDirectory, index));
        if (index >= 0 && index < playlist.segments.length && restoredSize > 0) {
          completed.add(index);
          completedBytes += restoredSize;
        }
      });
      const keyCache = new Map<string, ArrayBuffer>();
      let cursor = 0;
      let failure: AppError | undefined;
      const workers: Promise<void>[] = [];
      const workerCount = Math.max(1, Math.min(8, concurrency));
      for (let worker = 0; worker < workerCount; worker++) {
        workers.push(this.runWorker(
          playlist,
          segmentDirectory,
          completed,
          keyCache,
          token,
          () => cursor++,
          () => failure !== undefined,
          (error: AppError) => failure = error,
          onProgress,
          () => completedBytes,
          (bytes: number) => completedBytes += bytes,
          () => onCheckpoint?.(mediaUrl, playlist.segments.length, Array.from(completed).sort((a, b) => a - b))
        ));
      }
      await Promise.all(workers);
      if (failure !== undefined) {
        return Result.failure<number>(failure);
      }
      if (token.canceled) {
        return Result.failure<number>(new AppError(AppErrorCode.CANCELED, '下载已取消'));
      }
      const temporaryOutput = `${outputPath}.merge`;
      TransferFileUtils.deleteIfExists(temporaryOutput);
      let totalBytes = 0;
      for (let index = 0; index < playlist.segments.length; index++) {
        const path = this.segmentPath(segmentDirectory, index);
        TransferFileUtils.appendFile(temporaryOutput, path);
        totalBytes += TransferFileUtils.sizeOf(path);
      }
      TransferFileUtils.deleteIfExists(outputPath);
      fileIo.renameSync(temporaryOutput, outputPath);
      for (let index = 0; index < playlist.segments.length; index++) {
        TransferFileUtils.deleteIfExists(this.segmentPath(segmentDirectory, index));
      }
      fileIo.rmdirSync(segmentDirectory);
      return Result.success<number>(totalBytes);
    } catch (error) {
      return Result.failure<number>(this.toAppError(error));
    }
  }

  private async runWorker(
    playlist: HlsMediaPlaylist,
    segmentDirectory: string,
    completed: Set<number>,
    keyCache: Map<string, ArrayBuffer>,
    token: CancellationToken,
    takeIndex: () => number,
    hasFailure: () => boolean,
    reportFailure: (error: AppError) => void,
    onProgress?: TransferProgressCallback,
    completedBytes?: () => number,
    addCompletedBytes?: (bytes: number) => void,
    onCheckpoint?: () => void
  ): Promise<void> {
    while (!token.canceled && !hasFailure()) {
      const index = takeIndex();
      if (index >= playlist.segments.length) {
        return;
      }
      if (completed.has(index)) {
        continue;
      }
      const result = await this.downloadSegment(playlist, playlist.segments[index], keyCache);
      if (!result.isSuccess || result.value === undefined) {
        reportFailure(result.error ?? new AppError(AppErrorCode.NETWORK, `HLS 分片 ${index} 下载失败`));
        return;
      }
      TransferFileUtils.write(this.segmentPath(segmentDirectory, index), result.value);
      completed.add(index);
      addCompletedBytes?.(result.value.byteLength);
      onProgress?.({
        completedBytes: completedBytes?.() ?? 0,
        totalBytes: 0,
        progress: Math.floor(completed.size * 100 / playlist.segments.length)
      });
      onCheckpoint?.();
    }
  }

  private async downloadSegment(
    playlist: HlsMediaPlaylist,
    segment: HlsSegment,
    keyCache: Map<string, ArrayBuffer>
  ): Promise<Result<ArrayBuffer>> {
    const response = await this.client.requestBinary({
      url: segment.url,
      headers: this.headers(playlist.segments.length > 0 ? playlist.segments[0].url : undefined),
      retryable: true,
      timeoutMs: HLS_TIMEOUT_MS,
      protocol: http.HttpProtocol.HTTP1_1
    });
    if (!response.isSuccess || response.value === undefined) {
      return Result.failure<ArrayBuffer>(
        response.error ?? new AppError(AppErrorCode.NETWORK, `HLS 分片 ${segment.index} 下载失败`)
      );
    }
    if (segment.key === undefined) {
      return response;
    }
    if (segment.key.method !== 'AES-128') {
      return Result.failure<ArrayBuffer>(new AppError(
        AppErrorCode.UNSUPPORTED,
        `不支持的 HLS 加密方式: ${segment.key.method}`
      ));
    }
    let key = keyCache.get(segment.key.uri);
    if (key === undefined) {
      const keyResponse = await this.client.requestBinary({
        url: segment.key.uri,
        headers: this.headers(segment.url),
        retryable: true,
        timeoutMs: HLS_TIMEOUT_MS,
        protocol: http.HttpProtocol.HTTP1_1
      });
      if (!keyResponse.isSuccess || keyResponse.value === undefined) {
        return Result.failure<ArrayBuffer>(
          keyResponse.error ?? new AppError(AppErrorCode.NETWORK, '下载 HLS 密钥失败')
        );
      }
      key = keyResponse.value;
      keyCache.set(segment.key.uri, key);
    }
    const sequence = playlist.mediaSequence + segment.index;
    const iv = Aes128Decryptor.ivFrom(sequence, segment.key.iv);
    return Result.success<ArrayBuffer>(await Aes128Decryptor.decrypt(response.value, key, iv));
  }

  private segmentPath(directory: string, index: number): string {
    return `${directory}/${index.toString().padStart(8, '0')}.segment`;
  }

  private headers(referer?: string): HlsHeaders {
    const headers: HlsHeaders = {
      Accept: 'application/vnd.apple.mpegurl,application/x-mpegURL,video/mp2t,*/*',
      'User-Agent': HLS_USER_AGENT
    };
    if (referer !== undefined && referer.length > 0) {
      headers.Referer = referer;
    }
    return headers;
  }

  private safeUrl(url: string): string {
    const queryIndex = url.indexOf('?');
    return queryIndex >= 0 ? `${url.substring(0, queryIndex)}?***` : url;
  }

  private toAppError(error: Object): AppError {
    if (error instanceof AppError) {
      return error;
    }
    const message = error instanceof Error ? error.message : String(error);
    return new AppError(AppErrorCode.UNKNOWN, message);
  }
}

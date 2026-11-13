import { LsLogger } from '../../common/log/LsLogger';
import { TransferRepository } from '../../data/transfer/TransferRepository';
import {
  MutableCancellationToken,
  TransferExecutor
} from '../../data/transfer/TransferContracts';
import { CloudProviderType, TransferJob, TransferState } from '../../model/AppModels';
import { TransferBackgroundService } from './TransferBackgroundService';
import { TransferFileUtils } from '../../data/transfer/TransferFileUtils';

const TAG = 'TransferQueue';

export type TransferQueueListener = (jobs: TransferJob[], running: boolean) => void;
export type TransferBatchCompletedHandler = (provider: CloudProviderType) => Promise<void>;

export class TransferQueueController {
  private readonly repository: TransferRepository;
  private readonly executor: TransferExecutor;
  private readonly background: TransferBackgroundService;
  private jobs: TransferJob[] = [];
  private listeners: TransferQueueListener[] = [];
  private running: boolean = false;
  private draining: boolean = false;
  private cancellations: Map<string, MutableCancellationToken> = new Map();
  private idleResolvers: Array<() => void> = [];
  private batchCompletedHandler?: TransferBatchCompletedHandler;

  constructor(
    repository: TransferRepository,
    executor: TransferExecutor,
    background: TransferBackgroundService
  ) {
    this.repository = repository;
    this.executor = executor;
    this.background = background;
  }

  initialize(autoResume: boolean = true): void {
    this.jobs = this.repository.load();
    this.persistAndNotify();
    if (autoResume && this.nextQueued() !== undefined) {
      this.start();
    }
  }

  setBatchCompletedHandler(handler: TransferBatchCompletedHandler): void {
    this.batchCompletedHandler = handler;
  }

  snapshot(): TransferJob[] {
    return this.jobs.map((job: TransferJob): TransferJob => this.copyJob(job));
  }

  isRunning(): boolean {
    return this.running;
  }

  subscribe(listener: TransferQueueListener): () => void {
    this.listeners.push(listener);
    listener(this.snapshot(), this.running);
    return (): void => {
      this.listeners = this.listeners.filter((item: TransferQueueListener) => item !== listener);
    };
  }

  enqueue(newJobs: TransferJob[]): void {
    newJobs.forEach((job: TransferJob) => {
      job.selected = true;
      job.state = TransferState.QUEUED;
      job.updatedAt = Date.now();
      this.repository.upsert(this.jobs, job);
    });
    this.persistAndNotify();
  }

  start(): void {
    if (this.running) {
      return;
    }
    this.jobs.forEach((job: TransferJob) => {
      if (job.selected && (
        job.state === TransferState.PAUSED ||
        job.state === TransferState.CANCELED ||
        job.state === TransferState.FAILED
      )) {
        const failed = job.state === TransferState.FAILED;
        job.state = TransferState.QUEUED;
        job.errorMessage = '';
        if (failed && job.checkpoint !== undefined) {
          job.checkpoint.uploadSession = '';
          job.checkpoint.completedParts = [];
          job.checkpoint.uploadEtags = [];
          job.checkpoint.uploadedBytes = 0;
        }
        job.updatedAt = Date.now();
      }
    });
    if (this.nextQueued() === undefined) {
      LsLogger.info(TAG, 'Start ignored because no selected queued jobs exist');
      this.persistAndNotify();
      return;
    }
    const selectedCount = this.jobs.filter((job: TransferJob) => job.selected).length;
    LsLogger.info(TAG, `Transfer batch started selected=${selectedCount}`);
    this.running = true;
    this.persistAndNotify();
    this.drain();
  }

  pause(): void {
    this.running = false;
    this.cancellations.forEach((token: MutableCancellationToken) => token.cancel());
    this.persistAndNotify();
  }

  retry(jobId: string): void {
    const job = this.find(jobId);
    if (job === undefined || job.state === TransferState.COMPLETED) {
      return;
    }
    job.selected = true;
    job.state = TransferState.QUEUED;
    job.errorMessage = '';
    if (job.checkpoint !== undefined) {
      job.checkpoint.uploadSession = '';
      job.checkpoint.completedParts = [];
      job.checkpoint.uploadEtags = [];
      job.checkpoint.uploadedBytes = 0;
    }
    job.updatedAt = Date.now();
    this.persistAndNotify();
  }

  setSelected(jobId: string, selected: boolean): void {
    const job = this.find(jobId);
    if (job === undefined || this.isActive(job)) {
      return;
    }
    job.selected = selected;
    job.updatedAt = Date.now();
    this.persistAndNotify();
  }

  selectAll(selected: boolean): void {
    this.jobs.forEach((job: TransferJob) => {
      job.selected = selected;
      job.updatedAt = Date.now();
    });
    this.persistAndNotify();
  }

  setProvider(provider: CloudProviderType): void {
    this.jobs.forEach((job: TransferJob) => {
      if (!this.isActive(job) && job.state !== TransferState.COMPLETED) {
        job.provider = provider;
        job.updatedAt = Date.now();
      }
    });
    this.persistAndNotify();
  }

  remove(jobId: string): void {
    const job = this.find(jobId);
    if (job === undefined || this.isActive(job)) {
      return;
    }
    this.jobs = this.jobs.filter((item: TransferJob) => item.jobId !== jobId);
    this.persistAndNotify();
  }

  clearCompleted(): void {
    this.jobs = this.jobs.filter((job: TransferJob) => job.state !== TransferState.COMPLETED);
    this.persistAndNotify();
  }

  clearAll(recordAsCompleted: boolean = false): void {
    this.pause();
    if (recordAsCompleted) {
      this.jobs.forEach((job: TransferJob) => this.repository.recordCompleted(job));
    }
    this.jobs = [];
    this.persistAndNotify();
  }

  async clearAllAndDownloadCache(recordAsCompleted: boolean = false): Promise<void> {
    this.pause();
    if (recordAsCompleted) {
      this.jobs.forEach((job: TransferJob) => this.repository.recordCompleted(job));
    }
    this.jobs = [];
    this.persistAndNotify();
    await this.waitForIdle();
    this.executor.clearLocalCache();
    this.persistAndNotify();
  }

  reload(): void {
    this.pause();
    this.jobs = this.repository.load();
    this.persistAndNotify();
  }

  private async drain(): Promise<void> {
    if (this.draining) {
      return;
    }
    this.draining = true;
    await this.background.start();
    try {
      while (this.running) {
        const queued = this.jobs.filter((job: TransferJob) =>
          job.selected && job.state === TransferState.QUEUED &&
          !this.cancellations.has(job.jobId));
        if (queued.length === 0) {
          break;
        }
        await Promise.all(queued.map((job: TransferJob) => this.executeJob(job)));
      }
    } finally {
      this.cancellations.clear();
      await this.background.stop();
      this.draining = false;
      if (this.running && this.nextQueued() !== undefined) {
        this.drain();
      } else {
        this.running = false;
        this.persistAndNotify();
        if (this.batchSucceeded()) {
          const provider = this.selectedProvider();
          if (provider !== undefined && this.batchCompletedHandler !== undefined) {
            try {
              await this.batchCompletedHandler(provider);
              LsLogger.info(TAG, `Completion log synchronized provider=${provider}`);
            } catch (error) {
              const message = error instanceof Error ? error.message : String(error);
              LsLogger.warn(TAG, `Completion log synchronization failed: ${message}`);
            }
          }
        }
      }
    }
  }

  private async executeJob(job: TransferJob): Promise<void> {
    const cancellation = new MutableCancellationToken();
    this.cancellations.set(job.jobId, cancellation);
    try {
      const result = await this.executor.execute(
        job,
        cancellation,
        undefined,
        (changed: TransferJob) => {
          if (this.find(changed.jobId) !== undefined) {
            this.repository.upsert(this.jobs, changed);
            this.persistAndNotify();
          }
        }
      );
      if (cancellation.canceled && !this.running) {
        job.state = TransferState.PAUSED;
        job.errorMessage = '';
        job.updatedAt = Date.now();
      } else if (!result.isSuccess) {
        LsLogger.warn(TAG, `Transfer failed: ${job.jobId}, ${job.errorMessage}`);
      } else if (job.state === TransferState.COMPLETED) {
        this.repository.recordCompleted(job);
        TransferFileUtils.deleteIfExists(job.localFile);
        LsLogger.info(TAG, `Completion recorded job=${job.jobId}`);
      }
      this.persistAndNotify();
    } finally {
      this.cancellations.delete(job.jobId);
      if (this.cancellations.size === 0) {
        const resolvers = this.idleResolvers;
        this.idleResolvers = [];
        resolvers.forEach((resolve: () => void) => resolve());
      }
    }
  }

  private async waitForIdle(): Promise<void> {
    if (this.cancellations.size === 0) {
      return;
    }
    await new Promise<void>((resolve: () => void) => {
      this.idleResolvers.push(resolve);
    });
  }

  private nextQueued(): TransferJob | undefined {
    return this.jobs.find((job: TransferJob) =>
      job.selected && job.state === TransferState.QUEUED);
  }

  private find(jobId: string): TransferJob | undefined {
    return this.jobs.find((job: TransferJob) => job.jobId === jobId);
  }

  private batchSucceeded(): boolean {
    const selected = this.jobs.filter((job: TransferJob) => job.selected);
    return selected.length > 0 &&
      selected.every((job: TransferJob) => job.state === TransferState.COMPLETED);
  }

  private selectedProvider(): CloudProviderType | undefined {
    return this.jobs.find((job: TransferJob) => job.selected)?.provider;
  }

  private isActive(job: TransferJob): boolean {
    return job.state === TransferState.RESOLVING ||
      job.state === TransferState.DOWNLOADING ||
      job.state === TransferState.CONVERTING ||
      job.state === TransferState.UPLOADING;
  }

  private copyJob(job: TransferJob): TransferJob {
    return {
      jobId: job.jobId,
      name: job.name,
      downloadUrl: job.downloadUrl,
      key: job.key,
      source: job.source,
      provider: job.provider,
      targetFolderId: job.targetFolderId,
      localFile: job.localFile,
      state: job.state,
      progress: job.progress,
      downloadSpeedBytes: job.downloadSpeedBytes,
      errorMessage: job.errorMessage,
      selected: job.selected,
      createdAt: job.createdAt,
      updatedAt: job.updatedAt,
      checkpoint: job.checkpoint
    };
  }

  private persistAndNotify(): void {
    this.repository.save(this.jobs);
    const snapshot = this.snapshot();
    this.listeners.forEach((listener: TransferQueueListener) => listener(snapshot, this.running));
    this.background.update(snapshot);
  }
}

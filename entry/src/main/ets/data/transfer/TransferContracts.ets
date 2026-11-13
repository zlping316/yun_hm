import { Result } from '../../common/result/Result';
import { TransferJob } from '../../model/AppModels';

export interface CancellationToken {
  readonly canceled: boolean;
}

export class MutableCancellationToken implements CancellationToken {
  private value: boolean = false;

  get canceled(): boolean {
    return this.value;
  }

  cancel(): void {
    this.value = true;
  }
}

export interface TransferProgress {
  completedBytes: number;
  totalBytes: number;
  progress: number;
}

export type TransferProgressCallback = (progress: TransferProgress) => void;
export type TransferCheckpointCallback = (job: TransferJob) => void;

export interface TransferExecutor {
  clearLocalCache(): void;

  execute(
    job: TransferJob,
    token: CancellationToken,
    onProgress?: TransferProgressCallback,
    onCheckpoint?: TransferCheckpointCallback
  ): Promise<Result<TransferJob>>;
}

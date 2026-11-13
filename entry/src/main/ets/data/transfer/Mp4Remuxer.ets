import { cancelRemux, RemuxTask, startRemux } from 'libmp4remux.so';
import { AppError, AppErrorCode } from '../../common/error/AppError';
import { LsLogger } from '../../common/log/LsLogger';
import { Result } from '../../common/result/Result';
import { CancellationToken } from './TransferContracts';
import { TransferFileUtils } from './TransferFileUtils';

const TAG: string = 'Mp4Remuxer';
const CANCEL_CHECK_INTERVAL_MS: number = 200;

export class Mp4Remuxer {
  async remux(inputPath: string, outputPath: string, token: CancellationToken): Promise<Result<number>> {
    TransferFileUtils.deleteIfExists(outputPath);
    let taskId: number = -1;
    let cancelTimer: number = -1;
    try {
      const task: RemuxTask = startRemux(inputPath, outputPath);
      taskId = task.taskId;
      if (taskId < 0) {
        return Result.failure<number>(new AppError(AppErrorCode.UNKNOWN, '创建 MP4 转封装任务失败'));
      }
      LsLogger.info(TAG, `System MP4 remux started task=${taskId}`);
      cancelTimer = setInterval(() => {
        if (token.canceled) {
          cancelRemux(taskId);
        }
      }, CANCEL_CHECK_INTERVAL_MS);
      const outputSize: number = await task.promise;
      if (token.canceled) {
        TransferFileUtils.deleteIfExists(outputPath);
        return Result.failure<number>(new AppError(AppErrorCode.CANCELED, 'MP4 转封装已取消'));
      }
      if (outputSize <= 0 || TransferFileUtils.sizeOf(outputPath) <= 0) {
        TransferFileUtils.deleteIfExists(outputPath);
        return Result.failure<number>(new AppError(AppErrorCode.UNKNOWN, 'MP4 转封装输出为空'));
      }
      LsLogger.info(TAG, `System MP4 remux completed task=${taskId}, bytes=${outputSize}`);
      return Result.success<number>(outputSize);
    } catch (error) {
      if (taskId >= 0) {
        cancelRemux(taskId);
      }
      TransferFileUtils.deleteIfExists(outputPath);
      const message = error instanceof Error ? error.message : String(error);
      LsLogger.error(TAG, `System MP4 remux failed task=${taskId}, error=${message}`);
      if (token.canceled) {
        return Result.failure<number>(new AppError(AppErrorCode.CANCELED, 'MP4 转封装已取消'));
      }
      return Result.failure<number>(new AppError(AppErrorCode.UNKNOWN, `MP4 转封装失败: ${message}`));
    } finally {
      if (cancelTimer >= 0) {
        clearInterval(cancelTimer);
      }
    }
  }
}

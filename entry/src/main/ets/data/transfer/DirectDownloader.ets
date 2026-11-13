import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { AppError, AppErrorCode } from '../../common/error/AppError';
import { LsLogger } from '../../common/log/LsLogger';
import { Result } from '../../common/result/Result';
import { CancellationToken, TransferProgressCallback } from './TransferContracts';
import { TransferFileUtils } from './TransferFileUtils';

const TAG: string = 'DirectDownloader';

interface RangeHeaders {
  Range?: string;
}

export class DirectDownloader {
  async download(
    url: string,
    outputPath: string,
    expectedSize: number,
    token: CancellationToken,
    onProgress?: TransferProgressCallback
  ): Promise<Result<number>> {
    const temporaryPath = `${outputPath}.part`;
    let downloaded = TransferFileUtils.sizeOf(temporaryPath);
    if (expectedSize > 0 && downloaded > expectedSize) {
      TransferFileUtils.deleteIfExists(temporaryPath);
      downloaded = 0;
    }
    const headers: RangeHeaders = {};
    if (downloaded > 0) {
      headers.Range = `bytes=${downloaded}-`;
    }
    const request = http.createHttp();
    let file: fileIo.File | undefined;
    try {
      file = fileIo.openSync(
        temporaryPath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE
      );
      let offset = downloaded;
      request.on('dataReceive', (data: ArrayBuffer) => {
        if (token.canceled || file === undefined) {
          if (token.canceled) {
            request.destroy();
          }
          return;
        }
        fileIo.writeSync(file.fd, data, { offset: offset });
        offset += data.byteLength;
        onProgress?.({
          completedBytes: offset,
          totalBytes: expectedSize,
          progress: expectedSize > 0 ? Math.min(100, Math.floor(offset * 100 / expectedSize)) : 0
        });
      });
      const statusCode = await request.requestInStream(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 10000,
        readTimeout: 30000
      });
      if (token.canceled) {
        return Result.failure<number>(new AppError(AppErrorCode.CANCELED, '下载已取消'));
      }
      if (statusCode < 200 || statusCode >= 300) {
        return Result.failure<number>(new AppError(AppErrorCode.NETWORK, `下载失败 [${statusCode}]`, statusCode >= 500));
      }
      if (downloaded > 0 && statusCode === 200) {
        fileIo.closeSync(file);
        file = undefined;
        TransferFileUtils.deleteIfExists(temporaryPath);
        return this.download(url, outputPath, expectedSize, token, onProgress);
      }
      fileIo.fsyncSync(file.fd);
      fileIo.closeSync(file);
      file = undefined;
      fileIo.renameSync(temporaryPath, outputPath);
      LsLogger.info(TAG, `download completed bytes=${offset}`);
      return Result.success<number>(offset);
    } catch (error) {
      if (token.canceled) {
        return Result.failure<number>(new AppError(AppErrorCode.CANCELED, '下载已取消'));
      }
      const message = error instanceof Error ? error.message : String(error);
      return Result.failure<number>(new AppError(AppErrorCode.NETWORK, `下载失败: ${message}`, true));
    } finally {
      request.off('dataReceive');
      request.destroy();
      if (file !== undefined) {
        fileIo.closeSync(file);
      }
    }
  }
}

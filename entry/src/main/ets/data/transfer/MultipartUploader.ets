import { fileIo } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { AppError, AppErrorCode } from '../../common/error/AppError';
import { Result } from '../../common/result/Result';
import { CloudDriveProvider } from '../../domain/provider/CloudDriveProvider';
import { CloudProviderType } from '../../model/AppModels';
import { UploadCreateRequest, UploadSession } from '../../model/drive/CloudDriveModels';
import { CancellationToken, TransferProgressCallback } from './TransferContracts';
import { TransferFileUtils } from './TransferFileUtils';

const DEFAULT_PART_SIZE: number = 2 * 1024 * 1024;
const MAX_PART_COUNT: number = 10000;
const MAX_ATTEMPTS: number = 3;
const HASH_BUFFER_SIZE: number = 2 * 1024 * 1024;

interface FileHashes {
  md5: string;
  sha1: string;
}

export type UploadCheckpointCallback =
  (session: UploadSession, completedParts: number[], etags: string[], uploadedBytes: number) => void;

export class MultipartUploader {
  async upload(
    provider: CloudDriveProvider,
    localPath: string,
    targetFolderId: string,
    fileName: string,
    restoredSession: string,
    restoredParts: number[],
    restoredEtags: string[],
    token: CancellationToken,
    onProgress?: TransferProgressCallback,
    onCheckpoint?: UploadCheckpointCallback,
    targetDriveId?: string
  ): Promise<Result<void>> {
    try {
      const fileSize = TransferFileUtils.sizeOf(localPath);
      if (fileSize <= 0) {
        return Result.failure<void>(new AppError(AppErrorCode.NOT_FOUND, '待上传文件不存在或为空'));
      }
      let session: UploadSession;
      if (restoredSession.length > 0) {
        session = JSON.parse(restoredSession) as UploadSession;
      } else {
        const partSize = this.partSizeFor(fileSize);
        const hashes = provider.type === CloudProviderType.QUARK ?
          await this.fileHashes(localPath) : undefined;
        const request: UploadCreateRequest = {
          driveId: targetDriveId,
          parentFolderId: targetFolderId,
          fileName: fileName,
          size: fileSize,
          partSize: partSize,
          partCount: Math.max(1, Math.ceil(fileSize / partSize)),
          contentType: this.contentType(fileName),
          contentHash: hashes?.sha1,
          md5Hash: hashes?.md5
        };
        const created = await provider.createUpload(request);
        if (!created.isSuccess || created.value === undefined) {
          return Result.failure<void>(created.error ?? new AppError(AppErrorCode.NETWORK, '创建上传会话失败'));
        }
        session = created.value;
      }
      if (session.rapidUpload) {
        return Result.success<void>(undefined);
      }
      const partSize = session.partSize > 0 ? session.partSize : this.partSizeFor(fileSize);
      const partCount = Math.max(1, Math.ceil(fileSize / partSize));
      const completed = new Set<number>();
      restoredParts.forEach((part: number) => {
        if (part >= 1 && part <= partCount) {
          completed.add(part);
        }
      });
      const etags = restoredEtags.slice(0, partCount);
      while (etags.length < partCount) {
        etags.push('');
      }
      let uploadedBytes = 0;
      completed.forEach((part: number) => uploadedBytes += this.partLength(part, partSize, fileSize));
      for (let part = 1; part <= partCount; part++) {
        if (token.canceled) {
          return Result.failure<void>(new AppError(AppErrorCode.CANCELED, '上传已取消'));
        }
        if (completed.has(part)) {
          continue;
        }
        const offset = (part - 1) * partSize;
        const length = this.partLength(part, partSize, fileSize);
        const data = TransferFileUtils.readRange(localPath, offset, length);
        let uploaded: Result<string> | undefined;
        for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
          uploaded = await provider.uploadPart(session, part, data);
          if (uploaded.isSuccess || uploaded.error?.retryable !== true) {
            break;
          }
        }
        if (uploaded === undefined || !uploaded.isSuccess) {
          return Result.failure<void>(
            uploaded?.error ?? new AppError(AppErrorCode.NETWORK, `上传分片 ${part} 失败`)
          );
        }
        completed.add(part);
        etags[part - 1] = uploaded.value ?? '';
        uploadedBytes += length;
        const completedParts = Array.from(completed).sort((a, b) => a - b);
        onProgress?.({
          completedBytes: uploadedBytes,
          totalBytes: fileSize,
          progress: Math.floor(uploadedBytes * 100 / fileSize)
        });
        onCheckpoint?.(session, completedParts, etags, uploadedBytes);
      }
      return provider.completeUpload(session, etags);
    } catch (error) {
      if (error instanceof AppError) {
        return Result.failure<void>(error);
      }
      const message = error instanceof Error ? error.message : String(error);
      return Result.failure<void>(new AppError(AppErrorCode.UNKNOWN, `上传失败: ${message}`));
    }
  }

  private partSizeFor(fileSize: number): number {
    return Math.max(DEFAULT_PART_SIZE, Math.ceil(fileSize / MAX_PART_COUNT));
  }

  private partLength(partNumber: number, partSize: number, fileSize: number): number {
    return Math.min(partSize, fileSize - (partNumber - 1) * partSize);
  }

  private contentType(fileName: string): string {
    const lower = fileName.toLowerCase();
    if (lower.endsWith('.mp4')) {
      return 'video/mp4';
    }
    if (lower.endsWith('.ts')) {
      return 'video/mp2t';
    }
    if (lower.endsWith('.json')) {
      return 'application/json';
    }
    return 'application/octet-stream';
  }

  private async fileHashes(path: string): Promise<FileHashes> {
    const md5 = cryptoFramework.createMd('MD5');
    const sha1 = cryptoFramework.createMd('SHA1');
    let file: fileIo.File | undefined;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(HASH_BUFFER_SIZE);
      let offset = 0;
      while (true) {
        const count = fileIo.readSync(file.fd, buffer, { offset: offset });
        if (count <= 0) {
          break;
        }
        const chunk = new Uint8Array(count === buffer.byteLength ? buffer : buffer.slice(0, count));
        await md5.update({ data: chunk });
        await sha1.update({ data: chunk });
        offset += count;
      }
      const md5Result = await md5.digest();
      const sha1Result = await sha1.digest();
      return {
        md5: this.toHex(new Uint8Array(md5Result.data)),
        sha1: this.toHex(new Uint8Array(sha1Result.data))
      };
    } finally {
      if (file !== undefined) {
        fileIo.closeSync(file);
      }
    }
  }

  private toHex(data: Uint8Array): string {
    let value = '';
    data.forEach((byte: number) => value += byte.toString(16).padStart(2, '0'));
    return value;
  }
}

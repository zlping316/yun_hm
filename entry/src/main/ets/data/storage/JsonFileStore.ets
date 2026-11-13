import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { AppError, AppErrorCode } from '../../common/error/AppError';

export class JsonFileStore {
  private filesDir: string = '';

  initialize(context: common.Context): void {
    this.filesDir = context.filesDir;
  }

  read(fileName: string): string {
    const path = this.pathOf(fileName);
    if (!fileIo.accessSync(path)) {
      return '';
    }
    try {
      return fileIo.readTextSync(path);
    } catch (error) {
      throw this.storageError(`读取 ${fileName} 失败`, error);
    }
  }

  write(fileName: string, content: string): void {
    const path = this.pathOf(fileName);
    const temporaryPath = `${path}.tmp`;
    let file: fileIo.File | undefined;
    try {
      file = fileIo.openSync(
        temporaryPath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      fileIo.writeSync(file.fd, content);
      fileIo.fsyncSync(file.fd);
      fileIo.closeSync(file);
      file = undefined;
      fileIo.renameSync(temporaryPath, path);
    } catch (error) {
      if (file !== undefined) {
        fileIo.closeSync(file);
      }
      if (fileIo.accessSync(temporaryPath)) {
        fileIo.unlinkSync(temporaryPath);
      }
      throw this.storageError(`写入 ${fileName} 失败`, error);
    }
  }

  resolvePath(fileName: string): string {
    return this.pathOf(fileName);
  }

  private pathOf(fileName: string): string {
    if (this.filesDir.length === 0) {
      throw new AppError(AppErrorCode.STORAGE, 'JsonFileStore is not initialized');
    }
    return `${this.filesDir}/${fileName}`;
  }

  private storageError(message: string, error: Object): AppError {
    const detail = error instanceof Error ? error.message : String(error);
    return new AppError(AppErrorCode.STORAGE, `${message}: ${detail}`);
  }
}

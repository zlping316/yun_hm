import { fileIo } from '@kit.CoreFileKit';
import { AppError, AppErrorCode } from '../../common/error/AppError';

export class TransferFileUtils {
  static ensureDirectory(path: string): void {
    if (!fileIo.accessSync(path)) {
      fileIo.mkdirSync(path, true);
    }
  }

  static sizeOf(path: string): number {
    if (!fileIo.accessSync(path)) {
      return 0;
    }
    return fileIo.statSync(path).size;
  }

  static write(path: string, data: ArrayBuffer, append: boolean = false): void {
    let file: fileIo.File | undefined;
    try {
      let mode = fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE;
      if (!append) {
        mode |= fileIo.OpenMode.TRUNC;
      }
      file = fileIo.openSync(path, mode);
      const offset = append ? TransferFileUtils.sizeOf(path) : 0;
      fileIo.writeSync(file.fd, data, { offset: offset });
      fileIo.fsyncSync(file.fd);
    } catch (error) {
      throw TransferFileUtils.storageError(`写入文件失败: ${path}`, error);
    } finally {
      if (file !== undefined) {
        fileIo.closeSync(file);
      }
    }
  }

  static appendFile(targetPath: string, sourcePath: string): void {
    let source: fileIo.File | undefined;
    let target: fileIo.File | undefined;
    try {
      source = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
      target = fileIo.openSync(targetPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE);
      let sourceOffset = 0;
      let targetOffset = TransferFileUtils.sizeOf(targetPath);
      const buffer = new ArrayBuffer(256 * 1024);
      while (true) {
        const count = fileIo.readSync(source.fd, buffer, { offset: sourceOffset });
        if (count <= 0) {
          break;
        }
        const chunk = count === buffer.byteLength ? buffer : buffer.slice(0, count);
        fileIo.writeSync(target.fd, chunk, { offset: targetOffset });
        sourceOffset += count;
        targetOffset += count;
      }
      fileIo.fsyncSync(target.fd);
    } catch (error) {
      throw TransferFileUtils.storageError(`合并文件失败: ${sourcePath}`, error);
    } finally {
      if (source !== undefined) {
        fileIo.closeSync(source);
      }
      if (target !== undefined) {
        fileIo.closeSync(target);
      }
    }
  }

  static readRange(path: string, offset: number, length: number): ArrayBuffer {
    let file: fileIo.File | undefined;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(length);
      const count = fileIo.readSync(file.fd, buffer, { offset: offset });
      return count === length ? buffer : buffer.slice(0, count);
    } catch (error) {
      throw TransferFileUtils.storageError(`读取文件失败: ${path}`, error);
    } finally {
      if (file !== undefined) {
        fileIo.closeSync(file);
      }
    }
  }

  static deleteIfExists(path: string): void {
    if (fileIo.accessSync(path)) {
      fileIo.unlinkSync(path);
    }
  }

  static clearDirectory(path: string): void {
    if (!fileIo.accessSync(path)) {
      return;
    }
    fileIo.listFileSync(path).forEach((name: string) => {
      TransferFileUtils.deleteTree(`${path}/${name}`);
    });
  }

  private static deleteTree(path: string): void {
    if (fileIo.statSync(path).isDirectory()) {
      fileIo.listFileSync(path).forEach((name: string) => {
        TransferFileUtils.deleteTree(`${path}/${name}`);
      });
      fileIo.rmdirSync(path);
      return;
    }
    fileIo.unlinkSync(path);
  }

  private static storageError(message: string, error: Object): AppError {
    const detail = error instanceof Error ? error.message : String(error);
    return new AppError(AppErrorCode.STORAGE, `${message}: ${detail}`);
  }
}

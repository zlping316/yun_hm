import { AppError, AppErrorCode } from '../../common/error/AppError';
import { Result } from '../../common/result/Result';
import { CloudProviderType, ShareTask } from '../../model/AppModels';
import { CloudFile, ShareSaveItem, SharedFile } from '../../model/drive/CloudDriveModels';
import { CloudDriveProvider } from '../provider/CloudDriveProvider';
import { ParsedShareLink, ShareLinkParser } from './ShareLinkParser';
import { ShareRepository } from './ShareRepository';

export const SHARE_TASK_REVISION_KEY: string = 'shareTaskRevision';

export interface AddShareRequest {
  shareUrl: string;
  shareCode: string;
  targetFolderId: string;
  targetFolderName: string;
  autoSync: boolean;
}

export interface ShareSyncSummary {
  savedCount: number;
  failedCount: number;
}

export type ShareSyncProgress = (message: string) => void;

export class ShareController {
  private readonly provider: CloudDriveProvider;
  private readonly repository: ShareRepository;
  private tasks: ShareTask[] = [];

  constructor(provider: CloudDriveProvider, repository: ShareRepository) {
    this.provider = provider;
    this.repository = repository;
  }

  load(): ShareTask[] {
    this.tasks = this.repository.load();
    return this.snapshot();
  }

  async add(request: AddShareRequest): Promise<Result<ShareTask>> {
    try {
      const parsed = ShareLinkParser.parse(this.provider.type, request.shareUrl);
      if (this.hasDuplicate(parsed.normalizedUrl)) {
        return Result.failure<ShareTask>(new AppError(AppErrorCode.INVALID_INPUT, '已经存在！！！'));
      }
      const rootFolderId = this.provider.type === CloudProviderType.ALIYUN ? 'root' : '0';
      const isFolderShare = parsed.folderId !== rootFolderId;
      const subFolderName = request.targetFolderName.trim();
      if (isFolderShare && subFolderName.length === 0) {
        return Result.failure<ShareTask>(new AppError(AppErrorCode.INVALID_INPUT, '请添加子目录！'));
      }
      let title = subFolderName;
      let disabled = false;
      if (!isFolderShare) {
        const metadataResult = await this.provider.getShareMetadata(parsed.shareId, request.shareCode);
        if (metadataResult.isSuccess && metadataResult.value !== undefined) {
          title = metadataResult.value.title.length > 0 ? metadataResult.value.title :
            metadataResult.value.displayName;
          if (title.length === 0) {
            title = '已失效或不存在';
            disabled = true;
          }
        } else {
          title = '已失效或不存在';
          disabled = true;
        }
      }
      const now = Date.now();
      const task: ShareTask = {
        id: `${this.provider.type}_${now}`,
        provider: this.provider.type,
        shareUrl: parsed.normalizedUrl,
        shareCode: request.shareCode,
        title: title,
        targetFolderId: request.targetFolderId,
        targetFolderName: subFolderName,
        autoSync: request.autoSync,
        disabled: disabled,
        status: disabled ? '链接已失效' : '等待同步',
        createdAt: now,
        updatedAt: now
      };
      this.tasks.unshift(task);
      this.repository.save(this.tasks);
      return Result.success<ShareTask>(task);
    } catch (error) {
      return Result.failure<ShareTask>(this.toAppError(error));
    }
  }

  delete(taskId: string): ShareTask[] {
    this.tasks = this.tasks.filter((task: ShareTask) => task.id !== taskId);
    this.repository.save(this.tasks);
    return this.snapshot();
  }

  setAutoSync(taskId: string, enabled: boolean, targetFolderId: string): ShareTask[] {
    const task = this.tasks.find((item: ShareTask) => item.id === taskId);
    if (task !== undefined) {
      task.autoSync = enabled;
      task.targetFolderId = targetFolderId;
      task.updatedAt = Date.now();
      this.repository.save(this.tasks);
    }
    return this.snapshot();
  }

  async checkDisabled(): Promise<Result<number>> {
    let changed = 0;
    for (const task of this.tasks) {
      const parsed = ShareLinkParser.parse(this.provider.type, task.shareUrl);
      const result = await this.provider.getShareToken(parsed.shareId, task.shareCode);
      const disabled = !result.isSuccess;
      if (task.disabled !== disabled) {
        task.disabled = disabled;
        task.updatedAt = Date.now();
        changed++;
      }
      task.status = disabled ? '链接已失效' : '链接有效';
    }
    this.repository.save(this.tasks);
    return Result.success<number>(changed);
  }

  async syncAutoTasks(
    onProgress?: ShareSyncProgress,
    targetFolderId?: string
  ): Promise<Result<ShareSyncSummary>> {
    if (targetFolderId !== undefined) {
      this.tasks.forEach((task: ShareTask) => {
        if (task.autoSync && !task.disabled) {
          task.targetFolderId = targetFolderId;
        }
      });
      this.repository.save(this.tasks);
    }
    let savedCount = 0;
    let failedCount = 0;
    for (const task of this.tasks) {
      if (!task.autoSync || task.disabled) {
        continue;
      }
      const result = await this.sync(task.id);
      if (result.isSuccess && result.value !== undefined) {
        savedCount += result.value;
        onProgress?.(result.value === 0 ?
          `${task.title} -- 无更新！` : `${task.title} -- 更新 ${result.value} 个文件！`);
      } else {
        failedCount++;
        onProgress?.(`${task.title} -- ${result.error?.message ?? '同步失败！'}`);
      }
    }
    return Result.success<ShareSyncSummary>({ savedCount: savedCount, failedCount: failedCount });
  }

  async sync(taskId: string): Promise<Result<number>> {
    const task = this.tasks.find((item: ShareTask) => item.id === taskId);
    if (task === undefined) {
      return Result.failure<number>(new AppError(AppErrorCode.NOT_FOUND, '分享任务不存在'));
    }
    task.status = '同步中';
    task.disabled = false;
    this.repository.save(this.tasks);
    try {
      const parsed = ShareLinkParser.parse(this.provider.type, task.shareUrl);
      const tokenResult = await this.provider.getShareToken(parsed.shareId, task.shareCode);
      if (!tokenResult.isSuccess || tokenResult.value === undefined) {
        task.disabled = true;
        task.status = tokenResult.error?.message ?? '链接已失效';
        this.repository.save(this.tasks);
        return Result.failure<number>(tokenResult.error ??
          new AppError(AppErrorCode.UNKNOWN, '分享凭据读取失败'));
      }
      const targetResult = await this.resolveTargetFolder(task);
      if (!targetResult.isSuccess || targetResult.value === undefined) {
        task.status = targetResult.error?.message ?? '目标目录不可用';
        this.repository.save(this.tasks);
        return Result.failure<number>(targetResult.error ??
          new AppError(AppErrorCode.UNKNOWN, '目标目录不可用'));
      }
      const saved = await this.syncFolder(
        parsed,
        tokenResult.value,
        parsed.folderId,
        targetResult.value
      );
      if (!saved.isSuccess || saved.value === undefined) {
        task.status = saved.error?.message ?? '同步失败';
        this.repository.save(this.tasks);
        return saved;
      }
      task.status = saved.value === 0 ? '没有更新' : `已保存 ${saved.value} 项`;
      task.disabled = false;
      task.updatedAt = Date.now();
      this.repository.save(this.tasks);
      return saved;
    } catch (error) {
      const appError = this.toAppError(error);
      task.status = appError.message;
      this.repository.save(this.tasks);
      return Result.failure<number>(appError);
    }
  }

  snapshot(): ShareTask[] {
    return this.tasks.slice();
  }

  private hasDuplicate(normalizedUrl: string): boolean {
    return this.tasks.some((task: ShareTask) => {
      try {
        return ShareLinkParser.parse(this.provider.type, task.shareUrl).normalizedUrl === normalizedUrl;
      } catch (_) {
        return task.shareUrl === normalizedUrl;
      }
    });
  }

  private async resolveTargetFolder(task: ShareTask): Promise<Result<string>> {
    if (task.targetFolderName.length === 0) {
      return Result.success<string>(task.targetFolderId);
    }
    const localResult = await this.provider.listFiles(task.targetFolderId);
    if (!localResult.isSuccess || localResult.value === undefined) {
      return Result.failure<string>(localResult.error ??
        new AppError(AppErrorCode.UNKNOWN, '目标目录读取失败'));
    }
    const existing = localResult.value.find((item: CloudFile) =>
      this.isCloudFolder(item) && item.name === task.targetFolderName);
    if (existing !== undefined) {
      return Result.success<string>(existing.fileId);
    }
    return this.provider.createFolder(task.targetFolderId, task.targetFolderName);
  }

  private async syncFolder(
    parsed: ParsedShareLink,
    shareToken: string,
    sharedFolderId: string,
    localFolderId: string
  ): Promise<Result<number>> {
    const sharedResult = await this.provider.listSharedFiles(parsed.shareId, shareToken, sharedFolderId);
    if (!sharedResult.isSuccess || sharedResult.value === undefined) {
      return Result.failure<number>(sharedResult.error ??
        new AppError(AppErrorCode.UNKNOWN, '分享目录读取失败'));
    }
    const localResult = await this.provider.listFiles(localFolderId);
    if (!localResult.isSuccess || localResult.value === undefined) {
      return Result.failure<number>(localResult.error ??
        new AppError(AppErrorCode.UNKNOWN, '本地目录读取失败'));
    }
    let savedCount = 0;
    for (const shared of sharedResult.value) {
      const local = localResult.value.find((item: CloudFile) => item.name === shared.name);
      if (local === undefined) {
        const saveItem: ShareSaveItem = {
          shareId: parsed.shareId,
          fileId: shared.fileId,
          targetFolderId: localFolderId,
          shareFidToken: shared.shareFidToken
        };
        const saveResult = await this.provider.saveSharedFiles(shareToken, [saveItem]);
        if (!saveResult.isSuccess) {
          return Result.failure<number>(saveResult.error ??
            new AppError(AppErrorCode.UNKNOWN, `保存 ${shared.name} 失败`));
        }
        savedCount++;
      } else if (this.isSharedFolder(shared) && this.isCloudFolder(local)) {
        const childResult = await this.syncFolder(parsed, shareToken, shared.fileId, local.fileId);
        if (!childResult.isSuccess || childResult.value === undefined) {
          return childResult;
        }
        savedCount += childResult.value;
      }
    }
    return Result.success<number>(savedCount);
  }

  private isCloudFolder(file: CloudFile): boolean {
    return file.type === 'folder' || file.type === '0';
  }

  private isSharedFolder(file: SharedFile): boolean {
    return file.type === 'folder' || file.type === '0';
  }

  private toAppError(error: Object): AppError {
    if (error instanceof AppError) {
      return error;
    }
    const message = error instanceof Error ? error.message : String(error);
    return new AppError(AppErrorCode.UNKNOWN, message);
  }
}

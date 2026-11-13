import { http } from '@kit.NetworkKit';
import { AppError, AppErrorCode } from '../../common/error/AppError';
import { LsLogger } from '../../common/log/LsLogger';
import { Result } from '../../common/result/Result';
import { AppSettings } from '../../config/AppSettings';
import { HttpClient } from '../../data/network/HttpClient';
import { HttpRequestConfig } from '../../data/network/HttpTypes';
import { JsonFileStore } from '../../data/storage/JsonFileStore';
import { MultipartUploader } from '../../data/transfer/MultipartUploader';
import { MutableCancellationToken } from '../../data/transfer/TransferContracts';
import { CloudProviderType, ShareTask } from '../../model/AppModels';
import { CloudFile } from '../../model/drive/CloudDriveModels';
import { ProviderRegistry } from '../provider/ProviderRegistry';
import { ShareRepository } from './ShareRepository';

const TAG: string = 'ShareListBackup';
const ALIYUN_FILE: string = 'link_data.json';
const QUARK_FILE: string = 'quark_link_data.json';
const SHARE_BACKUP_PREFIX: string = 'share_link_';

export class ShareListBackupController {
  private readonly store: JsonFileStore;
  private readonly providers: ProviderRegistry;
  private readonly settings: AppSettings;
  private readonly client: HttpClient;
  private readonly uploader: MultipartUploader = new MultipartUploader();

  constructor(
    store: JsonFileStore,
    providers: ProviderRegistry,
    settings: AppSettings,
    client: HttpClient
  ) {
    this.store = store;
    this.providers = providers;
    this.settings = settings;
    this.client = client;
  }

  async backup(type: CloudProviderType): Promise<Result<string>> {
    try {
      const fileName = this.localFile(type);
      if (this.store.read(fileName).length === 0) {
        this.store.write(fileName, '[]');
      }
      const remoteName = `${SHARE_BACKUP_PREFIX}${Date.now()}.json`;
      const result = await this.uploader.upload(
        this.providers.get(CloudProviderType.QUARK),
        this.store.resolvePath(fileName),
        this.folderId(type),
        remoteName,
        '',
        [],
        [],
        new MutableCancellationToken()
      );
      if (!result.isSuccess) {
        return Result.failure<string>(
          result.error ?? new AppError(AppErrorCode.NETWORK, '备份失败！')
        );
      }
      LsLogger.info(TAG, `Share list uploaded source=${type}, file=${remoteName}`);
      return Result.success<string>(remoteName);
    } catch (error) {
      return Result.failure<string>(this.errorOf('备份失败！', error));
    }
  }

  async restoreLatest(type: CloudProviderType): Promise<Result<number>> {
    try {
      const provider = this.providers.get(CloudProviderType.QUARK);
      const listed = await provider.listFiles(this.folderId(type));
      if (!listed.isSuccess || listed.value === undefined) {
        return Result.failure<number>(
          listed.error ?? new AppError(AppErrorCode.NETWORK, '备份目录读取失败')
        );
      }
      const backups = listed.value.filter((file: CloudFile) =>
        !this.isFolder(file) && file.name.endsWith('.json'));
      if (backups.length === 0) {
        return Result.failure<number>(new AppError(AppErrorCode.NOT_FOUND, '未找到分享清单备份'));
      }
      const latest = backups[0];
      const download = await provider.getDownloadInfo(latest.fileId);
      if (!download.isSuccess || download.value === undefined) {
        return Result.failure<number>(
          download.error ?? new AppError(AppErrorCode.NETWORK, '备份下载地址获取失败')
        );
      }
      const config: HttpRequestConfig = {
        url: download.value.url,
        method: http.RequestMethod.GET,
        retryable: true
      };
      const content = await this.client.requestText(config);
      if (!content.isSuccess || content.value === undefined) {
        return Result.failure<number>(
          content.error ?? new AppError(AppErrorCode.NETWORK, '备份文件下载失败')
        );
      }
      const repository = new ShareRepository(this.store, type);
      const tasks: ShareTask[] = repository.restore(content.value);
      LsLogger.info(TAG, `Share list restored source=${type}, count=${tasks.length}`);
      return Result.success<number>(tasks.length);
    } catch (error) {
      return Result.failure<number>(this.errorOf('分享清单更新失败', error));
    }
  }

  private localFile(type: CloudProviderType): string {
    return type === CloudProviderType.ALIYUN ? ALIYUN_FILE : QUARK_FILE;
  }

  private folderId(type: CloudProviderType): string {
    return type === CloudProviderType.ALIYUN ?
      this.settings.aliyunShareBackupFolderId : this.settings.quarkBackupFolderId;
  }

  private isFolder(file: CloudFile): boolean {
    return file.type === 'folder' || file.type === '0';
  }

  private errorOf(message: string, error: Object): AppError {
    if (error instanceof AppError) {
      return error;
    }
    return new AppError(
      AppErrorCode.UNKNOWN,
      `${message}: ${error instanceof Error ? error.message : String(error)}`
    );
  }
}

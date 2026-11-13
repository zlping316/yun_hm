import { http } from '@kit.NetworkKit';
import { AppError, AppErrorCode } from '../../common/error/AppError';
import { LsLogger } from '../../common/log/LsLogger';
import { Result } from '../../common/result/Result';
import { AppSettings } from '../../config/AppSettings';
import { SettingsRepository } from '../../config/SettingsRepository';
import { HttpClient } from '../../data/network/HttpClient';
import { HttpRequestConfig } from '../../data/network/HttpTypes';
import { JsonFileStore } from '../../data/storage/JsonFileStore';
import { MultipartUploader } from '../../data/transfer/MultipartUploader';
import { MutableCancellationToken } from '../../data/transfer/TransferContracts';
import { CloudProviderType, WebAddress } from '../../model/AppModels';
import { CloudFile } from '../../model/drive/CloudDriveModels';
import { CloudDriveProvider } from '../provider/CloudDriveProvider';
import { ProviderRegistry } from '../provider/ProviderRegistry';

const TAG: string = 'CloudBackup';
const BACKUP_PREFIX: string = 'upload_log_';
const LOCAL_BACKUP_FILE: string = 'upload_log.json';
const ADDRESS_BACKUP_PREFIX: string = 'address_log_';
const LOCAL_ADDRESS_BACKUP_FILE: string = 'address_log.json';

interface TransferHistoryItem {
  downloadUrl: string;
  key: string;
  completedAt: number;
}

interface AndroidWebAddress {
  type: string;
  name: string;
  address: string;
  isSelected: boolean;
}

export function encodeAndroidUploadBackup(content: string): string {
  const history: TransferHistoryItem[] =
    content.length > 0 ? JSON.parse(content) as TransferHistoryItem[] : [];
  const entries: string[] = history.map((item: TransferHistoryItem) =>
    `${item.downloadUrl}||${item.key}`);
  return encodeURIComponent(JSON.stringify(entries));
}

export function decodeAndroidUploadBackup(content: string, completedAt: number): string {
  const entries = JSON.parse(decodeURIComponent(content)) as string[];
  if (!Array.isArray(entries)) {
    throw new Error('upload backup is not an Android string array');
  }
  const history: TransferHistoryItem[] = [];
  const urls = new Set<string>();
  entries.forEach((entry: string | null) => {
    if (entry === null || entry.length === 0) {
      return;
    }
    const separator = entry.indexOf('||');
    const downloadUrl = separator >= 0 ? entry.substring(0, separator) : entry;
    if (downloadUrl.length === 0 || urls.has(downloadUrl)) {
      return;
    }
    urls.add(downloadUrl);
    history.push({
      downloadUrl: downloadUrl,
      key: separator >= 0 ? entry.substring(separator + 2) : '',
      completedAt: completedAt
    });
  });
  return JSON.stringify(history);
}

export function encodeAndroidAddressBackup(content: string): string {
  const addresses: WebAddress[] = content.length > 0 ? JSON.parse(content) as WebAddress[] : [];
  const androidAddresses: AndroidWebAddress[] = addresses.map((address: WebAddress) => {
    const androidAddress: AndroidWebAddress = {
      type: address.type,
      name: address.subType,
      address: address.address,
      isSelected: address.selected
    };
    return androidAddress;
  });
  return encodeURIComponent(JSON.stringify(androidAddresses));
}

export function decodeAndroidAddressBackup(content: string): string {
  const androidAddresses =
    JSON.parse(decodeURIComponent(content)) as AndroidWebAddress[];
  if (!Array.isArray(androidAddresses)) {
    throw new Error('address backup is not an Android address array');
  }
  const addresses: WebAddress[] = [];
  const values = new Set<string>();
  androidAddresses.forEach((address: AndroidWebAddress | null) => {
    if (address === null || address.address.length === 0) {
      return;
    }
    if (address.address.length === 0 || values.has(address.address)) {
      return;
    }
    values.add(address.address);
    addresses.push({
      type: address.type,
      subType: address.name,
      address: address.address,
      selected: address.isSelected
    });
  });
  return JSON.stringify(addresses);
}

interface RangeHeaders {
  Range: string;
  Accept?: string;
  'Accept-Encoding'?: string;
  'User-Agent'?: string;
}

interface QuarkDownloadHeaders extends RangeHeaders {
  Cookie?: string;
}

export class CloudBackupController {
  private readonly store: JsonFileStore;
  private readonly providers: ProviderRegistry;
  private readonly settings: AppSettings;
  private readonly settingsRepository: SettingsRepository;
  private readonly client: HttpClient;
  private readonly uploader: MultipartUploader = new MultipartUploader();

  constructor(
    store: JsonFileStore,
    providers: ProviderRegistry,
    settings: AppSettings,
    settingsRepository: SettingsRepository,
    client: HttpClient
  ) {
    this.store = store;
    this.providers = providers;
    this.settings = settings;
    this.settingsRepository = settingsRepository;
    this.client = client;
  }

  async backup(type: CloudProviderType): Promise<Result<string>> {
    try {
      const createdAt = Date.now();
      this.store.write(
        LOCAL_BACKUP_FILE,
        encodeAndroidUploadBackup(this.store.read('transfer_history.json'))
      );
      this.store.write(
        LOCAL_ADDRESS_BACKUP_FILE,
        encodeAndroidAddressBackup(this.store.read('web_addresses.json'))
      );
      const logFileName = `${BACKUP_PREFIX}${createdAt}.json`;
      const addressFileName = `${ADDRESS_BACKUP_PREFIX}${createdAt}.json`;
      const results = await Promise.all([
        this.uploadFile(type, LOCAL_BACKUP_FILE, this.logFolderId(type), logFileName),
        this.uploadFile(type, LOCAL_ADDRESS_BACKUP_FILE, this.addressFolderId(type), addressFileName)
      ]);
      if (!results[0].isSuccess) {
        return Result.failure<string>(
          this.stageError('上传日志', '备份失败', results[0].error)
        );
      }
      if (!results[1].isSuccess) {
        return Result.failure<string>(
          this.stageError('地址日志', '备份失败', results[1].error)
        );
      }
      LsLogger.info(
        TAG,
        `Backup uploaded provider=${type}, log=${logFileName}, address=${addressFileName}`
      );
      return Result.success<string>(logFileName);
    } catch (error) {
      return Result.failure<string>(this.errorOf('云端备份失败', error));
    }
  }

  async restoreLatest(type: CloudProviderType): Promise<Result<string>> {
    try {
      const provider = this.providers.get(type);
      const logBackup = await this.restoreFirstValid(
        provider,
        type,
        this.logFolderId(type),
        BACKUP_PREFIX,
        '上传日志',
        (content: string): string => decodeAndroidUploadBackup(content, Date.now())
      );
      if (!logBackup.isSuccess || logBackup.value === undefined) {
        return Result.failure<string>(
          logBackup.error ?? new AppError(AppErrorCode.NOT_FOUND, '未找到有效上传日志备份')
        );
      }
      const addressBackup = await this.restoreFirstValid(
        provider,
        type,
        this.addressFolderId(type),
        ADDRESS_BACKUP_PREFIX,
        '地址日志',
        decodeAndroidAddressBackup
      );
      if (!addressBackup.isSuccess || addressBackup.value === undefined) {
        return Result.failure<string>(
          addressBackup.error ?? new AppError(AppErrorCode.NOT_FOUND, '未找到有效地址日志备份')
        );
      }
      this.store.write('transfer_history.json', logBackup.value.content);
      this.store.write('web_addresses.json', addressBackup.value.content);
      LsLogger.info(
        TAG,
        `Backup restored provider=${type}, log=${logBackup.value.file.name}, address=${addressBackup.value.file.name}`
      );
      return Result.success<string>(logBackup.value.file.name);
    } catch (error) {
      return Result.failure<string>(this.errorOf('云端恢复失败', error));
    }
  }

  private async restoreFirstValid(
    provider: CloudDriveProvider,
    type: CloudProviderType,
    folderId: string,
    prefix: string,
    stage: string,
    decoder: (content: string) => string
  ): Promise<Result<RestoredBackup>> {
    const backups = await this.listBackups(provider, type, folderId, prefix, stage);
    if (!backups.isSuccess || backups.value === undefined) {
      return Result.failure<RestoredBackup>(
        backups.error ?? new AppError(AppErrorCode.NOT_FOUND, `未找到${stage}备份`)
      );
    }
    for (const file of backups.value) {
      const content = await this.downloadContent(provider, file, type, stage);
      if (!content.isSuccess || content.value === undefined) {
        return Result.failure<RestoredBackup>(
          this.stageError(stage, '下载失败', content.error)
        );
      }
      try {
        return Result.success<RestoredBackup>({
          file: file,
          content: decoder(content.value)
        });
      } catch (error) {
        LsLogger.warn(
          TAG,
          `Skip invalid ${stage} backup provider=${type}, file=${file.name}, error=${this.messageOf(error)}`
        );
      }
    }
    return Result.failure<RestoredBackup>(
      new AppError(AppErrorCode.PARSE, `未找到有效${stage}备份`)
    );
  }

  private async listBackups(
    provider: CloudDriveProvider,
    type: CloudProviderType,
    folderId: string,
    prefix: string,
    stage: string
  ): Promise<Result<CloudFile[]>> {
    const files = await provider.listFiles(folderId, this.driveId(type));
    if (!files.isSuccess || files.value === undefined) {
      return Result.failure<CloudFile[]>(this.stageError(stage, '目录读取失败', files.error));
    }
    const backups = files.value.filter((file: CloudFile) =>
      this.isFile(type, file) && file.name.startsWith(prefix) && file.name.endsWith('.json'));
    backups.sort((left: CloudFile, right: CloudFile) => right.name.localeCompare(left.name));
    return backups.length > 0 ? Result.success<CloudFile[]>(backups) :
      Result.failure<CloudFile[]>(new AppError(AppErrorCode.NOT_FOUND, `未找到${stage}备份`));
  }

  private async downloadContent(
    provider: CloudDriveProvider,
    file: CloudFile,
    type: CloudProviderType,
    stage: string
  ): Promise<Result<string>> {
    const download = await provider.getDownloadInfo(file.fileId, this.driveId(type));
    if (!download.isSuccess || download.value === undefined) {
      return Result.failure<string>(
        download.error ?? new AppError(AppErrorCode.NETWORK, '备份下载地址获取失败')
      );
    }
    const size = download.value.size > 0 ? download.value.size : file.size;
    if (size <= 0) {
      return Result.failure<string>(new AppError(AppErrorCode.PARSE, '备份文件大小为空'));
    }
    const range = `bytes=0-${size - 1}`;
    const attempts = type === CloudProviderType.QUARK ?
      await this.quarkDownloadHeaders(range) : [{ Range: range } as RangeHeaders];
    let lastError: AppError = new AppError(AppErrorCode.NETWORK, '备份文件下载失败');
    for (let index = 0; index < attempts.length; index++) {
      const headers = attempts[index];
      const config: HttpRequestConfig = {
        url: download.value.url,
        method: http.RequestMethod.GET,
        headers: headers,
        retryable: true,
        timeoutMs: 60000
      };
      const content = await this.client.requestText(config);
      if (content.isSuccess && content.value !== undefined) {
        return content;
      }
      lastError = content.error ?? lastError;
      LsLogger.warn(TAG, `Download backup failed provider=${type}, file=${file.name}, error=${lastError.message}`);
    }
    return Result.failure<string>(lastError);
  }

  private async quarkDownloadHeaders(range: string): Promise<QuarkDownloadHeaders[]> {
    const cookie = (await this.settingsRepository.loadCredentials()).quarkCookie;
    return cookie.length > 0 ? [{
      Range: range,
      Accept: '*/*',
      'Accept-Encoding': 'identity',
      'User-Agent': 'okhttp/4.10.0',
      Cookie: cookie
    }, {
      Range: range,
      Accept: '*/*',
      'Accept-Encoding': 'identity',
      'User-Agent': 'okhttp/4.10.0'
    }] : [{
      Range: range,
      Accept: '*/*',
      'Accept-Encoding': 'identity',
      'User-Agent': 'okhttp/4.10.0'
    }];
  }

  private isFile(type: CloudProviderType, file: CloudFile): boolean {
    return file.type === 'file' || (type === CloudProviderType.QUARK && file.type === '1');
  }

  private uploadFile(
    type: CloudProviderType,
    localFile: string,
    folderId: string,
    remoteFile: string
  ): Promise<Result<void>> {
    return this.uploader.upload(
      this.providers.get(type),
      this.store.resolvePath(localFile),
      folderId,
      remoteFile,
      '',
      [],
      [],
      new MutableCancellationToken(),
      undefined,
      undefined,
      this.driveId(type)
    );
  }

  private logFolderId(type: CloudProviderType): string {
    return type === CloudProviderType.ALIYUN ?
      this.settings.aliyunLogFolderId : this.settings.quarkLogFolderId;
  }

  private addressFolderId(type: CloudProviderType): string {
    return type === CloudProviderType.ALIYUN ?
      this.settings.aliyunAddressFolderId : this.settings.quarkAddressFolderId;
  }

  private driveId(type: CloudProviderType): string | undefined {
    return type === CloudProviderType.ALIYUN ? this.settings.aliyunLockDriveId : undefined;
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

  private messageOf(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }

  private stageError(stage: string, message: string, error?: AppError): AppError {
    if (error === undefined) {
      return new AppError(AppErrorCode.NETWORK, `${stage}${message}`);
    }
    return new AppError(
      error.code,
      `${stage}${message}: ${error.message}`,
      error.retryable,
      error.statusCode
    );
  }
}

interface RestoredBackup {
  file: CloudFile;
  content: string;
}

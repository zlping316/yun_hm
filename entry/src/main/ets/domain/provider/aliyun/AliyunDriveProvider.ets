import { http } from '@kit.NetworkKit';
import { AppError, AppErrorCode } from '../../../common/error/AppError';
import { Result } from '../../../common/result/Result';
import { AppSettings, Credentials } from '../../../config/AppSettings';
import { SettingsRepository } from '../../../config/SettingsRepository';
import { HttpClient } from '../../../data/network/HttpClient';
import { AliyunHeaders } from '../../../data/network/interceptor/AliyunHeaders';
import { CloudProviderType } from '../../../model/AppModels';
import {
  CloudFile,
  DownloadInfo,
  EmptyUploadHeaders,
  ShareMetadata,
  ShareSaveItem,
  SharedFile,
  UploadCreateRequest,
  UploadPart,
  UploadSession
} from '../../../model/drive/CloudDriveModels';
import { CloudDriveProvider } from '../CloudDriveProvider';
import {
  AliyunBatchCopyBody,
  AliyunBatchHeaders,
  AliyunBatchRequest,
  AliyunCreateRaw,
  AliyunDownloadRaw,
  AliyunFileListRaw,
  AliyunFileRaw,
  AliyunPartRaw,
  AliyunPartRequest,
  AliyunRequestBody,
  AliyunShareFileRaw,
  AliyunShareInfoRaw,
  AliyunShareListRaw,
  AliyunTokenRaw,
  AliyunVoidRaw
} from './AliyunApiModels';

const API_BASE: string = 'https://api.aliyundrive.com';
const AUTH_URL: string = 'https://auth.aliyundrive.com/v2/account/token';
const MAX_PAGES: number = 100;

export class AliyunDriveProvider implements CloudDriveProvider {
  readonly type: CloudProviderType = CloudProviderType.ALIYUN;
  private readonly client: HttpClient;
  private readonly settingsRepository: SettingsRepository;
  private readonly settings: AppSettings;

  constructor(client: HttpClient, settingsRepository: SettingsRepository, settings: AppSettings) {
    this.client = client;
    this.settingsRepository = settingsRepository;
    this.settings = settings;
  }

  async listFiles(parentFolderId: string, driveId?: string): Promise<Result<CloudFile[]>> {
    const credentials = await this.settingsRepository.loadCredentials();
    const items: CloudFile[] = [];
    let marker = '';
    for (let page = 0; page < MAX_PAGES; page++) {
      const result = await this.post<AliyunFileListRaw>('/adrive/v3/file/list', {
        drive_id: driveId ?? this.settings.aliyunDriveId,
        parent_file_id: parentFolderId,
        limit: 100,
        marker: marker,
        all: false,
        fields: '*',
        order_by: 'updated_at',
        order_direction: 'DESC'
      }, credentials, true);
      if (!result.isSuccess || result.value === undefined) {
        return Result.failure<CloudFile[]>(this.errorOf(result));
      }
      const rawItems = result.value.items ?? [];
      rawItems.forEach((item: AliyunFileRaw) => items.push(this.mapFile(item)));
      marker = result.value.next_marker ?? '';
      if (marker.length === 0) {
        break;
      }
    }
    return Result.success<CloudFile[]>(items);
  }

  async createFolder(parentFolderId: string, name: string, driveId?: string): Promise<Result<string>> {
    const credentials = await this.settingsRepository.loadCredentials();
    const result = await this.post<AliyunCreateRaw>('/adrive/v2/file/createWithFolders', {
      drive_id: driveId ?? this.settings.aliyunDriveId,
      parent_file_id: parentFolderId,
      name: name,
      check_name_mode: 'refuse',
      type: 'folder'
    }, credentials, false);
    if (!result.isSuccess || result.value === undefined) {
      return Result.failure<string>(this.errorOf(result));
    }
    const fileId = result.value.file_id ?? '';
    return fileId.length > 0 ? Result.success<string>(fileId) :
      Result.failure<string>(new AppError(AppErrorCode.PARSE, '创建目录响应缺少 file_id'));
  }

  async getDownloadInfo(fileId: string, driveId?: string): Promise<Result<DownloadInfo>> {
    const credentials = await this.settingsRepository.loadCredentials();
    const result = await this.post<AliyunDownloadRaw>('/v2/file/get_download_url', {
      drive_id: driveId ?? this.settings.aliyunDriveId,
      file_id: fileId,
      expire_sec: 14400
    }, credentials, true);
    if (!result.isSuccess || result.value === undefined) {
      return Result.failure<DownloadInfo>(this.errorOf(result));
    }
    const value = result.value;
    if ((value.url ?? '').length === 0) {
      return Result.failure<DownloadInfo>(new AppError(AppErrorCode.PARSE, '下载响应缺少 URL'));
    }
    return Result.success<DownloadInfo>({
      url: value.url ?? '',
      size: value.size ?? 0,
      contentHash: value.content_hash ?? '',
      contentHashName: value.content_hash_name ?? '',
      crc64Hash: value.crc64_hash ?? ''
    });
  }

  async getShareToken(shareId: string, password: string = ''): Promise<Result<string>> {
    const credentials = await this.settingsRepository.loadCredentials();
    const result = await this.post<AliyunTokenRaw>('/v2/share_link/get_share_token', {
      share_id: shareId,
      share_pwd: password
    }, credentials, true);
    if (!result.isSuccess || result.value === undefined) {
      return Result.failure<string>(this.errorOf(result));
    }
    const token = result.value.share_token ?? '';
    return token.length > 0 ? Result.success<string>(token) :
      Result.failure<string>(new AppError(AppErrorCode.PARSE, '分享响应缺少 share_token'));
  }

  async getShareMetadata(shareId: string, password: string = ''): Promise<Result<ShareMetadata>> {
    const credentials = await this.settingsRepository.loadCredentials();
    const result = await this.post<AliyunShareInfoRaw>('/adrive/v3/share_link/get_share_by_anonymous', {
      share_id: shareId,
      share_pwd: password
    }, credentials, true);
    if (!result.isSuccess || result.value === undefined) {
      return Result.failure<ShareMetadata>(this.errorOf(result));
    }
    const title = result.value.share_name ?? result.value.share_title ?? '';
    return Result.success<ShareMetadata>({
      shareId: shareId,
      title: title,
      displayName: result.value.display_name ?? ''
    });
  }

  async listSharedFiles(
    shareId: string,
    shareToken: string,
    parentFolderId: string
  ): Promise<Result<SharedFile[]>> {
    const credentials = await this.settingsRepository.loadCredentials();
    const items: SharedFile[] = [];
    let marker = '';
    for (let page = 0; page < MAX_PAGES; page++) {
      const result = await this.post<AliyunShareListRaw>('/adrive/v2/file/list_by_share', {
        share_id: shareId,
        parent_file_id: parentFolderId,
        limit: 100,
        marker: marker,
        order_by: 'name',
        order_direction: 'DESC'
      }, credentials, true, shareToken);
      if (!result.isSuccess || result.value === undefined) {
        return Result.failure<SharedFile[]>(this.errorOf(result));
      }
      const rawItems = result.value.items ?? [];
      rawItems.forEach((item: AliyunShareFileRaw) => {
        const sharedFile: SharedFile = {
          fileId: item.file_id ?? '',
          parentFileId: item.parent_file_id ?? '',
          name: item.file_name ?? item.name ?? '',
          type: item.type ?? '',
          shareFidToken: ''
        };
        items.push(sharedFile);
      });
      marker = result.value.next_marker ?? '';
      if (marker.length === 0) {
        break;
      }
    }
    return Result.success<SharedFile[]>(items);
  }

  async saveSharedFiles(shareToken: string, items: ShareSaveItem[]): Promise<Result<void>> {
    const credentials = await this.settingsRepository.loadCredentials();
    for (const item of items) {
      const copyBody: AliyunBatchCopyBody = {
        file_id: item.fileId,
        share_id: item.shareId,
        auto_rename: true,
        to_parent_file_id: item.targetFolderId,
        to_drive_id: this.settings.aliyunDriveId
      };
      const batchHeaders: AliyunBatchHeaders = { 'Content-Type': 'application/json' };
      const batchRequest: AliyunBatchRequest = {
        body: copyBody,
        headers: batchHeaders,
        id: '0',
        method: 'POST',
        url: '/file/copy'
      };
      const result = await this.post<AliyunVoidRaw>('/adrive/v4/batch', {
        requests: [batchRequest],
        resource: 'file'
      }, credentials, false, shareToken);
      if (!result.isSuccess) {
        return Result.failure<void>(this.errorOf(result));
      }
    }
    return Result.success<void>(undefined);
  }

  async createUpload(request: UploadCreateRequest): Promise<Result<UploadSession>> {
    const credentials = await this.settingsRepository.loadCredentials();
    const partInfoList: AliyunPartRequest[] = [];
    for (let part = 1; part <= request.partCount; part++) {
      const partRequest: AliyunPartRequest = { part_number: part };
      partInfoList.push(partRequest);
    }
    const result = await this.post<AliyunCreateRaw>('/v2/file/create', {
      drive_id: request.driveId ?? this.settings.aliyunDriveId,
      parent_file_id: request.parentFolderId,
      name: request.fileName,
      check_name_mode: 'auto_rename',
      type: 'file',
      part_info_list: partInfoList,
      pre_hash: request.preHash,
      size: request.size,
      content_hash: request.contentHash,
      content_hash_name: request.contentHash === undefined ? undefined : 'sha1',
      proof_code: request.proofCode,
      proof_version: request.proofCode === undefined ? undefined : 'v1'
    }, credentials, false);
    if (!result.isSuccess || result.value === undefined) {
      return Result.failure<UploadSession>(this.errorOf(result));
    }
    return this.toUploadSession(
      result.value,
      request.partSize,
      request.driveId ?? this.settings.aliyunDriveId
    );
  }

  async refreshUploadParts(session: UploadSession, partNumbers: number[]): Promise<Result<UploadSession>> {
    const credentials = await this.settingsRepository.loadCredentials();
    const parts: AliyunPartRequest[] = [];
    partNumbers.forEach((part: number) => {
      const partRequest: AliyunPartRequest = { part_number: part };
      parts.push(partRequest);
    });
    const result = await this.post<AliyunCreateRaw>('/v2/file/get_upload_url', {
      drive_id: session.driveId ?? this.settings.aliyunDriveId,
      file_id: session.fileId,
      upload_id: session.uploadId,
      part_info_list: parts
    }, credentials, false);
    if (!result.isSuccess || result.value === undefined) {
      return Result.failure<UploadSession>(this.errorOf(result));
    }
    session.parts = this.mapParts(result.value.part_info_list ?? []);
    return Result.success<UploadSession>(session);
  }

  async uploadPart(session: UploadSession, partNumber: number, data: ArrayBuffer): Promise<Result<string>> {
    let part = session.parts.find((item: UploadPart) => item.partNumber === partNumber);
    if (part === undefined || part.uploadUrl.length === 0) {
      const refreshed = await this.refreshUploadParts(session, [partNumber]);
      if (!refreshed.isSuccess || refreshed.value === undefined) {
        return Result.failure<string>(this.errorOf(refreshed));
      }
      part = refreshed.value.parts.find((item: UploadPart) => item.partNumber === partNumber);
    }
    if (part === undefined || part.uploadUrl.length === 0) {
      return Result.failure<string>(new AppError(AppErrorCode.PARSE, `上传分片 ${partNumber} 缺少 URL`));
    }
    const result = await this.client.requestRaw({
      url: part.uploadUrl,
      method: http.RequestMethod.PUT,
      headers: session.uploadHeaders,
      body: data,
      retryable: true,
      timeoutMs: 30000
    });
    return result.isSuccess ? Result.success<string>('') :
      Result.failure<string>(this.errorOf(result));
  }

  async completeUpload(session: UploadSession, etags: string[]): Promise<Result<void>> {
    const credentials = await this.settingsRepository.loadCredentials();
    const result = await this.post<AliyunCreateRaw>('/v2/file/complete', {
      drive_id: session.driveId ?? this.settings.aliyunDriveId,
      file_id: session.fileId,
      upload_id: session.uploadId
    }, credentials, false);
    return result.isSuccess ? Result.success<void>(undefined) : Result.failure<void>(this.errorOf(result));
  }

  async refreshAccessToken(): Promise<Result<string>> {
    const credentials = await this.settingsRepository.loadCredentials();
    const refreshBody: AliyunRequestBody = {
      refresh_token: credentials.aliyunRefreshToken,
      grant_type: 'refresh_token'
    };
    const result = await this.client.requestJson<AliyunTokenRaw>({
      url: AUTH_URL,
      method: http.RequestMethod.POST,
      headers: AliyunHeaders.create(),
      body: JSON.stringify(refreshBody),
      retryable: false
    });
    if (!result.isSuccess || result.value === undefined) {
      return Result.failure<string>(this.errorOf(result));
    }
    const accessToken = result.value.access_token ?? '';
    if (accessToken.length === 0) {
      return Result.failure<string>(new AppError(AppErrorCode.PARSE, '刷新响应缺少 access_token'));
    }
    credentials.aliyunAccessToken = accessToken;
    if ((result.value.refresh_token ?? '').length > 0) {
      credentials.aliyunRefreshToken = result.value.refresh_token ?? credentials.aliyunRefreshToken;
    }
    await this.settingsRepository.saveCredentials(credentials);
    return Result.success<string>(accessToken);
  }

  private async post<T>(
    path: string,
    body: AliyunRequestBody,
    credentials: Credentials,
    retryable: boolean,
    shareToken: string = ''
  ): Promise<Result<T>> {
    return this.client.requestJson<T>({
      url: `${API_BASE}${path}`,
      method: http.RequestMethod.POST,
      headers: AliyunHeaders.create({
        accessToken: credentials.aliyunAccessToken,
        shareToken: shareToken
      }),
      body: JSON.stringify(body),
      retryable: retryable
    });
  }

  private mapFile(item: AliyunFileRaw): CloudFile {
    return {
      fileId: item.file_id ?? '',
      parentFileId: item.parent_file_id ?? '',
      name: item.name ?? '',
      type: item.type ?? '',
      size: item.size ?? 0,
      contentHash: item.content_hash ?? '',
      downloadUrl: ''
    };
  }

  private toUploadSession(raw: AliyunCreateRaw, partSize: number, driveId: string): Result<UploadSession> {
    const fileId = raw.file_id ?? '';
    const uploadId = raw.upload_id ?? '';
    if (fileId.length === 0 || uploadId.length === 0) {
      return Result.failure<UploadSession>(new AppError(AppErrorCode.PARSE, '上传响应缺少会话标识'));
    }
    const emptyHeaders: EmptyUploadHeaders = {};
    const session: UploadSession = {
      provider: CloudProviderType.ALIYUN,
      driveId: driveId,
      fileId: fileId,
      uploadId: uploadId,
      fileName: raw.file_name ?? '',
      partSize: partSize,
      rapidUpload: raw.rapid_upload ?? false,
      parts: this.mapParts(raw.part_info_list ?? []),
      uploadHeaders: emptyHeaders,
      providerData: ''
    };
    return Result.success<UploadSession>(session);
  }

  private mapParts(rawParts: AliyunPartRaw[]): UploadPart[] {
    const parts: UploadPart[] = [];
    rawParts.forEach((item: AliyunPartRaw) => {
      const part: UploadPart = {
        partNumber: item.part_number ?? 0,
        uploadUrl: item.upload_url ?? ''
      };
      parts.push(part);
    });
    return parts;
  }

  private errorOf<T>(result: Result<T>): AppError {
    return result.error ?? new AppError(AppErrorCode.UNKNOWN, '阿里云盘请求失败');
  }
}

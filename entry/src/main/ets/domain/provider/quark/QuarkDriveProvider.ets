import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { AppError, AppErrorCode } from '../../../common/error/AppError';
import { LsLogger } from '../../../common/log/LsLogger';
import { Result } from '../../../common/result/Result';
import { UrlUtils } from '../../../common/util/UrlUtils';
import { AppSettings, Credentials } from '../../../config/AppSettings';
import { SettingsRepository } from '../../../config/SettingsRepository';
import { HttpClient } from '../../../data/network/HttpClient';
import { QuarkHeaders } from '../../../data/network/interceptor/QuarkHeaders';
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
  QuarkEnvelope,
  QuarkFileListData,
  QuarkFileRaw,
  QuarkFolderData,
  QuarkPartRaw,
  QuarkPartRequest,
  QuarkProviderData,
  QuarkRequestBody,
  QuarkShareData,
  QuarkShareFileRaw,
  QuarkShareTokenData,
  QuarkUploadData,
  QuarkUploadHeaderMap
} from './QuarkApiModels';

const API_BASE: string = 'https://drive-pc.quark.cn';
const TAG: string = 'QuarkDrive';
const MAX_PAGES: number = 100;
const PAGE_SIZE: number = 100;
const OSS_USER_AGENT: string = 'aliyun-sdk-js/6.6.1 Chrome 98.0.4758.80 on Windows 10 64-bit';
interface QuarkCallbackData {
  callbackUrl?: string;
  callbackBody?: string;
  callbackBodyType?: string;
}

interface OssPartHeaders {
  Authorization: string;
  'Content-Type': string;
  'X-Oss-Date': string;
  'X-Oss-User-Agent': string;
}

interface OssCommitHeaders extends OssPartHeaders {
  'Content-MD5': string;
  'X-Oss-Callback': string;
}

interface UploadResponseHeaders {
  ETag?: string;
  etag?: string;
}

export class QuarkDriveProvider implements CloudDriveProvider {
  readonly type: CloudProviderType = CloudProviderType.QUARK;
  private readonly client: HttpClient;
  private readonly settingsRepository: SettingsRepository;
  private readonly settings: AppSettings;

  constructor(client: HttpClient, settingsRepository: SettingsRepository, settings: AppSettings) {
    this.client = client;
    this.settingsRepository = settingsRepository;
    this.settings = settings;
  }

  async listFiles(parentFolderId: string, _driveId?: string): Promise<Result<CloudFile[]>> {
    const credentials = await this.settingsRepository.loadCredentials();
    const files: CloudFile[] = [];
    for (let page = 1; page <= MAX_PAGES; page++) {
      const query = this.baseQuery();
      query.set('pdir_fid', parentFolderId);
      query.set('_page', page.toString());
      query.set('_size', PAGE_SIZE.toString());
      query.set('_fetch_total', '1');
      query.set('_fetch_sub_dirs', '0');
      query.set('_sort', 'file_type:asc,updated_at:desc');
      const response = await this.get<QuarkEnvelope<QuarkFileListData>>(
        '/1/clouddrive/file/sort',
        query,
        credentials,
        true
      );
      const result = this.unwrap<QuarkFileListData>(response);
      if (!result.isSuccess || result.value === undefined) {
        return Result.failure<CloudFile[]>(this.errorOf(result));
      }
      const pageItems = result.value.list ?? [];
      LsLogger.info(TAG, `List files parent=${parentFolderId}, page=${page}, count=${pageItems.length}`);
      pageItems.forEach((item: QuarkFileRaw) => files.push(this.mapFile(item)));
      if (pageItems.length < PAGE_SIZE) {
        break;
      }
    }
    return Result.success<CloudFile[]>(files);
  }

  async createFolder(parentFolderId: string, name: string, _driveId?: string): Promise<Result<string>> {
    const existing = await this.listFiles(parentFolderId);
    if (existing.isSuccess && existing.value !== undefined) {
      const matched = existing.value.find((item: CloudFile) => item.name === name && item.type === '0');
      if (matched !== undefined) {
        return Result.success<string>(matched.fileId);
      }
    }
    const credentials = await this.settingsRepository.loadCredentials();
    const response = await this.post<QuarkEnvelope<QuarkFolderData>>(
      '/1/clouddrive/file?pr=ucpro&fr=pc&uc_param_str=',
      {
        pdir_fid: parentFolderId,
        file_name: name,
        dir_init_lock: false
      },
      credentials,
      false
    );
    const result = this.unwrap<QuarkFolderData>(response);
    if (!result.isSuccess || result.value === undefined) {
      return Result.failure<string>(this.errorOf(result));
    }
    const fileId = result.value.fid ?? '';
    return fileId.length > 0 ? Result.success<string>(fileId) :
      Result.failure<string>(new AppError(AppErrorCode.PARSE, '创建目录响应缺少 fid'));
  }

  async getDownloadInfo(fileId: string, _driveId?: string): Promise<Result<DownloadInfo>> {
    const credentials = await this.settingsRepository.loadCredentials();
    const response = await this.post<QuarkEnvelope<QuarkFileRaw[]>>(
      '/1/clouddrive/file/download?pr=ucpro&fr=pc',
      { fids: [fileId] },
      credentials,
      true
    );
    const result = this.unwrap<QuarkFileRaw[]>(response);
    if (!result.isSuccess || result.value === undefined || result.value.length === 0) {
      return Result.failure<DownloadInfo>(result.error ??
        new AppError(AppErrorCode.PARSE, '下载响应缺少文件信息'));
    }
    const file = result.value[0];
    const url = file.download_url ?? '';
    if (url.length === 0) {
      return Result.failure<DownloadInfo>(new AppError(AppErrorCode.PARSE, '下载响应缺少 URL'));
    }
    return Result.success<DownloadInfo>({
      url: url,
      size: file.size ?? 0,
      contentHash: '',
      contentHashName: '',
      crc64Hash: ''
    });
  }

  async getShareToken(shareId: string, password: string = ''): Promise<Result<string>> {
    const result = await this.fetchShareToken(shareId, password);
    if (!result.isSuccess || result.value === undefined) {
      return Result.failure<string>(this.errorOf(result));
    }
    const token = result.value.stoken ?? '';
    return token.length > 0 ? Result.success<string>(token) :
      Result.failure<string>(new AppError(AppErrorCode.PARSE, '分享响应缺少 stoken'));
  }

  async getShareMetadata(shareId: string, password: string = ''): Promise<Result<ShareMetadata>> {
    const result = await this.fetchShareToken(shareId, password);
    if (!result.isSuccess || result.value === undefined) {
      return Result.failure<ShareMetadata>(this.errorOf(result));
    }
    return Result.success<ShareMetadata>({
      shareId: shareId,
      title: result.value.title ?? '',
      displayName: ''
    });
  }

  async listSharedFiles(
    shareId: string,
    shareToken: string,
    parentFolderId: string
  ): Promise<Result<SharedFile[]>> {
    const credentials = await this.settingsRepository.loadCredentials();
    const files: SharedFile[] = [];
    for (let page = 1; page <= MAX_PAGES; page++) {
      const query = this.baseQuery();
      query.set('pwd_id', shareId);
      query.set('stoken', shareToken);
      query.set('pdir_fid', parentFolderId);
      query.set('force', '0');
      query.set('_page', page.toString());
      query.set('_size', PAGE_SIZE.toString());
      query.set('_fetch_banner', '0');
      query.set('_fetch_share', '0');
      query.set('_sort', 'file_type:asc,updated_at:desc');
      const response = await this.get<QuarkEnvelope<QuarkShareData>>(
        '/1/clouddrive/share/sharepage/detail',
        query,
        credentials,
        true
      );
      const result = this.unwrap<QuarkShareData>(response);
      if (!result.isSuccess || result.value === undefined) {
        return Result.failure<SharedFile[]>(this.errorOf(result));
      }
      const pageItems = result.value.list ?? [];
      pageItems.forEach((item: QuarkShareFileRaw) => {
        const sharedFile: SharedFile = {
          fileId: item.fid ?? '',
          parentFileId: item.pdir_fid ?? '',
          name: item.file_name ?? item.title ?? '',
          type: String(item.file_type ?? ''),
          shareFidToken: item.share_fid_token ?? ''
        };
        files.push(sharedFile);
      });
      if (pageItems.length < PAGE_SIZE) {
        break;
      }
    }
    return Result.success<SharedFile[]>(files);
  }

  async saveSharedFiles(shareToken: string, items: ShareSaveItem[]): Promise<Result<void>> {
    const credentials = await this.settingsRepository.loadCredentials();
    for (const item of items) {
      const response = await this.post<QuarkEnvelope<Object>>(
        '/1/clouddrive/share/sharepage/save?pr=ucpro&fr=pc',
        {
          fid_list: [item.fileId],
          fid_token_list: [item.shareFidToken],
          to_pdir_fid: item.targetFolderId,
          pwd_id: item.shareId,
          stoken: shareToken,
          pdir_fid: '0',
          scene: 'link'
        },
        credentials,
        false
      );
      const result = this.validateEnvelope<Object>(response);
      if (!result.isSuccess) {
        return Result.failure<void>(this.errorOf(result));
      }
    }
    return Result.success<void>(undefined);
  }

  async createUpload(request: UploadCreateRequest): Promise<Result<UploadSession>> {
    const credentials = await this.settingsRepository.loadCredentials();
    const contentType = request.contentType ?? 'application/xml';
    const preResponse = await this.post<QuarkEnvelope<QuarkUploadData>>(
      '/1/clouddrive/file/upload/pre?pr=ucpro&fr=pc',
      {
        pdir_fid: request.parentFolderId,
        ccp_hash_update: true,
        dir_name: '',
        size: request.size,
        file_name: request.fileName,
        format_type: contentType
      },
      credentials,
      false
    );
    const preResult = this.unwrap<QuarkUploadData>(preResponse);
    if (!preResult.isSuccess || preResult.value === undefined) {
      return Result.failure<UploadSession>(this.errorOf(preResult));
    }
    const data = preResult.value;
    const uploadId = data.upload_id ?? '';
    const taskId = data.task_id ?? '';
    const uploadUrl = data.upload_url ?? '';
    const bucket = data.bucket ?? '';
    const objectKey = data.obj_key ?? '';
    const authInfo = data.auth_info ?? '';
    if (uploadId.length === 0 || taskId.length === 0 || uploadUrl.length === 0 ||
      bucket.length === 0 || objectKey.length === 0 || authInfo.length === 0) {
      return Result.failure<UploadSession>(new AppError(AppErrorCode.PARSE, '上传响应缺少会话标识'));
    }
    if (request.md5Hash !== undefined && request.contentHash !== undefined) {
      const hashResponse = await this.post<QuarkEnvelope<QuarkUploadData>>(
        '/1/clouddrive/file/update/hash?pr=ucpro&fr=pc&uc_param_str=',
        {
          md5: request.md5Hash,
          sha1: request.contentHash,
          task_id: taskId
        },
        credentials,
        false
      );
      const hashResult = this.unwrap<QuarkUploadData>(hashResponse);
      if (!hashResult.isSuccess) {
        return Result.failure<UploadSession>(this.errorOf(hashResult));
      }
    }
    const responsePartSize = preResponse.value?.metadata?.part_size ?? 0;
    const partSize = responsePartSize > 0 ? responsePartSize : request.partSize;
    const partCount = Math.max(1, Math.ceil(request.size / partSize));
    const parts: UploadPart[] = [];
    for (let partNumber = 1; partNumber <= partCount; partNumber++) {
      parts.push({
        partNumber: partNumber,
        uploadUrl: this.createOssUrl(data, partNumber)
      });
    }
    const callbackData: QuarkCallbackData = data.callback === undefined ? {} :
      (typeof data.callback === 'string' ?
        JSON.parse(data.callback) as QuarkCallbackData :
        data.callback as QuarkCallbackData);
    callbackData.callbackBodyType = 'application/x-www-form-urlencoded';
    const callbackJson = JSON.stringify(callbackData);
    const providerData: QuarkProviderData = {
      callbackJson: callbackJson,
      contentType: contentType,
      bucket: bucket,
      objectKey: objectKey,
      uploadUrl: uploadUrl,
      taskId: taskId,
      authInfo: authInfo
    };
    const emptyHeaders: EmptyUploadHeaders = {};
    const session: UploadSession = {
      provider: CloudProviderType.QUARK,
      fileId: data.file_id ?? taskId,
      uploadId: uploadId,
      fileName: data.file_name ?? request.fileName,
      partSize: partSize,
      rapidUpload: data.rapid_upload ?? false,
      parts: parts,
      uploadHeaders: emptyHeaders,
      providerData: JSON.stringify(providerData)
    };
    return Result.success<UploadSession>(session);
  }

  async refreshUploadParts(session: UploadSession, partNumbers: number[]): Promise<Result<UploadSession>> {
    partNumbers.forEach((part: number) => {
      if (session.parts.find((item: UploadPart) => item.partNumber === part) === undefined) {
        const data = JSON.parse(session.providerData) as QuarkProviderData;
        session.parts.push({
          partNumber: part,
          uploadUrl: this.createOssUrlFromProviderData(data, session.uploadId, part)
        });
      }
    });
    return Result.success<UploadSession>(session);
  }

  async uploadPart(session: UploadSession, partNumber: number, data: ArrayBuffer): Promise<Result<string>> {
    const providerData = JSON.parse(session.providerData) as QuarkProviderData;
    const requestDate = new Date().toUTCString();
    const auth = await this.authorizeUpload(
      providerData,
      this.createPartAuthMeta(providerData, session.uploadId, partNumber, requestDate)
    );
    if (!auth.isSuccess || auth.value === undefined) {
      return Result.failure<string>(this.errorOf(auth));
    }
    const headers: OssPartHeaders = {
      Authorization: auth.value,
      'Content-Type': providerData.contentType,
      'X-Oss-Date': requestDate,
      'X-Oss-User-Agent': OSS_USER_AGENT
    };
    const response = await this.client.requestRaw({
      url: this.createOssUrlFromProviderData(providerData, session.uploadId, partNumber),
      method: http.RequestMethod.PUT,
      headers: headers,
      body: data,
      retryable: true,
      timeoutMs: 30000
    });
    if (!response.isSuccess || response.value === undefined) {
      return Result.failure<string>(this.errorOf(response));
    }
    const responseHeaders = response.value.headers as UploadResponseHeaders;
    const etag = responseHeaders.ETag ?? responseHeaders.etag ?? '';
    if (etag.length === 0) {
      return Result.failure<string>(new AppError(AppErrorCode.PARSE, `夸克上传分片 ${partNumber} 缺少 ETag`));
    }
    return Result.success<string>(etag);
  }

  async completeUpload(session: UploadSession, etags: string[]): Promise<Result<void>> {
    const providerData = JSON.parse(session.providerData) as QuarkProviderData;
    if (etags.length === 0) {
      return Result.failure<void>(new AppError(AppErrorCode.INVALID_INPUT, '夸克上传缺少分片 ETag'));
    }
    const xml = this.createCompleteXml(etags);
    const xmlBytes = new util.TextEncoder('utf-8').encode(xml);
    const contentMd5 = await this.md5Base64(xmlBytes);
    const callback = new util.Base64Helper().encodeToStringSync(
      new util.TextEncoder('utf-8').encode(providerData.callbackJson)
    );
    const requestDate = new Date().toUTCString();
    const auth = await this.authorizeUpload(
      providerData,
      this.createCommitAuthMeta(providerData, session.uploadId, requestDate, contentMd5, callback)
    );
    if (!auth.isSuccess || auth.value === undefined) {
      return Result.failure<void>(this.errorOf(auth));
    }
    const headers: OssCommitHeaders = {
      Authorization: auth.value,
      'Content-Type': 'application/xml',
      'Content-MD5': contentMd5,
      'X-Oss-Callback': callback,
      'X-Oss-Date': requestDate,
      'X-Oss-User-Agent': OSS_USER_AGENT
    };
    const commit = await this.client.requestRaw({
      url: this.createOssCommitUrl(providerData, session.uploadId),
      method: http.RequestMethod.POST,
      headers: headers,
      body: xml,
      retryable: false,
      timeoutMs: 30000
    });
    if (!commit.isSuccess) {
      return Result.failure<void>(this.errorOf(commit));
    }
    const credentials = await this.settingsRepository.loadCredentials();
    const finishResponse = await this.post<QuarkEnvelope<QuarkUploadData>>(
      '/1/clouddrive/file/upload/finish?pr=ucpro&fr=pc',
      {
        obj_key: providerData.objectKey,
        task_id: providerData.taskId
      },
      credentials,
      false
    );
    const finish = this.unwrap<QuarkUploadData>(finishResponse);
    if (!finish.isSuccess || finish.value === undefined) {
      return Result.failure<void>(this.errorOf(finish));
    }
    return finish.value.finish === false ?
      Result.failure<void>(new AppError(AppErrorCode.NETWORK, '夸克云盘未完成上传确认')) :
      Result.success<void>(undefined);
  }

  private async fetchShareToken(
    shareId: string,
    password: string
  ): Promise<Result<QuarkShareTokenData>> {
    const credentials = await this.settingsRepository.loadCredentials();
    const response = await this.post<QuarkEnvelope<QuarkShareTokenData>>(
      '/1/clouddrive/share/sharepage/token',
      { pwd_id: shareId, passcode: password },
      credentials,
      true
    );
    return this.unwrap<QuarkShareTokenData>(response);
  }

  private async get<T>(
    path: string,
    query: Map<string, string>,
    credentials: Credentials,
    retryable: boolean
  ): Promise<Result<T>> {
    return this.client.requestJson<T>({
      url: UrlUtils.appendQuery(`${API_BASE}${path}`, query),
      method: http.RequestMethod.GET,
      headers: QuarkHeaders.create({ cookie: credentials.quarkCookie, referer: 'https://pan.quark.cn/' }),
      retryable: retryable
    });
  }

  private async post<T>(
    path: string,
    body: QuarkRequestBody,
    credentials: Credentials,
    retryable: boolean
  ): Promise<Result<T>> {
    return this.client.requestJson<T>({
      url: `${API_BASE}${path}`,
      method: http.RequestMethod.POST,
      headers: QuarkHeaders.create({ cookie: credentials.quarkCookie, referer: 'https://pan.quark.cn/' }),
      body: JSON.stringify(body),
      retryable: retryable
    });
  }

  private unwrap<T>(response: Result<QuarkEnvelope<T>>): Result<T> {
    const validation = this.validateEnvelope<T>(response);
    if (!validation.isSuccess || response.value === undefined) {
      return Result.failure<T>(this.errorOf(validation));
    }
    if (response.value.data === undefined) {
      return Result.failure<T>(new AppError(AppErrorCode.PARSE, '夸克云盘响应缺少 data'));
    }
    return Result.success<T>(response.value.data);
  }

  private validateEnvelope<T>(response: Result<QuarkEnvelope<T>>): Result<void> {
    if (!response.isSuccess || response.value === undefined) {
      return Result.failure<void>(this.errorOf(response));
    }
    const envelope = response.value;
    const code = envelope.code ?? 0;
    const status = envelope.status ?? 200;
    if ((code !== 0 && code !== 200) || status === 401 || status === 403) {
      const message = envelope.message ?? '夸克云盘业务请求失败';
      const unauthorized = status === 401 || status === 403 || message.includes('登录') || message.includes('login');
      return Result.failure<void>(new AppError(
        unauthorized ? AppErrorCode.UNAUTHORIZED : AppErrorCode.NETWORK,
        `${message} [${code}]`,
        false,
        status
      ));
    }
    return Result.success<void>(undefined);
  }

  private baseQuery(): Map<string, string> {
    const query = new Map<string, string>();
    query.set('pr', 'ucpro');
    query.set('fr', 'pc');
    return query;
  }

  private mapFile(item: QuarkFileRaw): CloudFile {
    return {
      fileId: item.fid ?? '',
      parentFileId: item.pdir_fid ?? '',
      name: item.file_name ?? '',
      type: String(item.file_type ?? ''),
      size: item.size ?? 0,
      contentHash: '',
      downloadUrl: item.download_url ?? ''
    };
  }

  private mapParts(rawParts: QuarkPartRaw[]): UploadPart[] {
    const parts: UploadPart[] = [];
    rawParts.forEach((item: QuarkPartRaw) => {
      const part: UploadPart = {
        partNumber: item.part_number ?? 0,
        uploadUrl: item.upload_url ?? ''
      };
      parts.push(part);
    });
    return parts;
  }

  private async authorizeUpload(providerData: QuarkProviderData, authMeta: string): Promise<Result<string>> {
    const credentials = await this.settingsRepository.loadCredentials();
    const response = await this.post<QuarkEnvelope<QuarkUploadData>>(
      '/1/clouddrive/file/upload/auth?pr=ucpro&fr=pc',
      {
        task_id: providerData.taskId,
        auth_info: providerData.authInfo,
        auth_meta: authMeta
      },
      credentials,
      false
    );
    const result = this.unwrap<QuarkUploadData>(response);
    if (!result.isSuccess || result.value === undefined) {
      return Result.failure<string>(this.errorOf(result));
    }
    const authKey = result.value.auth_key ?? '';
    return authKey.length > 0 ? Result.success<string>(authKey) :
      Result.failure<string>(new AppError(AppErrorCode.PARSE, '夸克上传鉴权响应缺少 auth_key'));
  }

  private createPartAuthMeta(
    data: QuarkProviderData,
    uploadId: string,
    partNumber: number,
    requestDate: string
  ): string {
    return `PUT\n\n${data.contentType}\n${requestDate}\n` +
      `x-oss-date:${requestDate}\n` +
      `x-oss-user-agent:${OSS_USER_AGENT}\n` +
      `/${data.bucket}/${data.objectKey}?partNumber=${partNumber}&uploadId=${uploadId}`;
  }

  private createCommitAuthMeta(
    data: QuarkProviderData,
    uploadId: string,
    requestDate: string,
    contentMd5: string,
    callback: string
  ): string {
    return `POST\n${contentMd5}\napplication/xml\n${requestDate}\n` +
      `x-oss-callback:${callback}\n` +
      `x-oss-date:${requestDate}\n` +
      `x-oss-user-agent:${OSS_USER_AGENT}\n` +
      `/${data.bucket}/${data.objectKey}?uploadId=${uploadId}`;
  }

  private createOssUrl(data: QuarkUploadData, partNumber: number): string {
    const providerData: QuarkProviderData = {
      callbackJson: '',
      contentType: data.format_type ?? 'application/octet-stream',
      bucket: data.bucket ?? '',
      objectKey: data.obj_key ?? '',
      uploadUrl: data.upload_url ?? '',
      taskId: data.task_id ?? '',
      authInfo: data.auth_info ?? ''
    };
    return this.createOssUrlFromProviderData(providerData, data.upload_id ?? '', partNumber);
  }

  private createOssUrlFromProviderData(data: QuarkProviderData, uploadId: string, partNumber: number): string {
    return `${this.ossOrigin(data)}/${data.objectKey}?partNumber=${partNumber}&uploadId=${uploadId}`;
  }

  private createOssCommitUrl(data: QuarkProviderData, uploadId: string): string {
    return `${this.ossOrigin(data)}/${data.objectKey}?uploadId=${uploadId}`;
  }

  private ossOrigin(data: QuarkProviderData): string {
    const schemeIndex = data.uploadUrl.indexOf('://');
    const hostStart = schemeIndex >= 0 ? schemeIndex + 3 : 0;
    const pathStart = data.uploadUrl.indexOf('/', hostStart);
    const host = pathStart >= 0 ? data.uploadUrl.substring(hostStart, pathStart) :
      data.uploadUrl.substring(hostStart);
    return `https://${data.bucket}.${host}`;
  }

  private createCompleteXml(etags: string[]): string {
    let xml = '<?xml version="1.0" encoding="UTF-8"?>\n<CompleteMultipartUpload>\n';
    etags.forEach((etag: string, index: number) => {
      xml += `<Part>\n<PartNumber>${index + 1}</PartNumber>\n<ETag>${etag}</ETag>\n</Part>\n`;
    });
    return `${xml}</CompleteMultipartUpload>`;
  }

  private async md5Base64(data: Uint8Array): Promise<string> {
    const digest = cryptoFramework.createMd('MD5');
    await digest.update({ data: data });
    const result = await digest.digest();
    return new util.Base64Helper().encodeToStringSync(result.data);
  }

  private errorOf<T>(result: Result<T>): AppError {
    return result.error ?? new AppError(AppErrorCode.UNKNOWN, '夸克云盘请求失败');
  }
}

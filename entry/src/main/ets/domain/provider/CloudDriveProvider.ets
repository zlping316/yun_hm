import { Result } from '../../common/result/Result';
import { CloudProviderType } from '../../model/AppModels';
import {
  CloudFile,
  DownloadInfo,
  ShareMetadata,
  ShareSaveItem,
  SharedFile,
  UploadCreateRequest,
  UploadSession
} from '../../model/drive/CloudDriveModels';

export interface CloudDriveProvider {
  readonly type: CloudProviderType;

  listFiles(parentFolderId: string, driveId?: string): Promise<Result<CloudFile[]>>;

  createFolder(parentFolderId: string, name: string, driveId?: string): Promise<Result<string>>;

  getDownloadInfo(fileId: string, driveId?: string): Promise<Result<DownloadInfo>>;

  getShareToken(shareId: string, password?: string): Promise<Result<string>>;

  getShareMetadata(shareId: string, password?: string): Promise<Result<ShareMetadata>>;

  listSharedFiles(shareId: string, shareToken: string, parentFolderId: string): Promise<Result<SharedFile[]>>;

  saveSharedFiles(shareToken: string, items: ShareSaveItem[]): Promise<Result<void>>;

  createUpload(request: UploadCreateRequest): Promise<Result<UploadSession>>;

  refreshUploadParts(session: UploadSession, partNumbers: number[]): Promise<Result<UploadSession>>;

  uploadPart(session: UploadSession, partNumber: number, data: ArrayBuffer): Promise<Result<string>>;

  completeUpload(session: UploadSession, etags: string[]): Promise<Result<void>>;
}

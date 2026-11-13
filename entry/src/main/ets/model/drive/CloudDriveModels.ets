import { CloudProviderType } from '../AppModels';

export interface CloudFile {
  fileId: string;
  parentFileId: string;
  name: string;
  type: string;
  size: number;
  contentHash: string;
  downloadUrl: string;
}

export interface ShareMetadata {
  shareId: string;
  title: string;
  displayName: string;
}

export interface SharedFile {
  fileId: string;
  parentFileId: string;
  name: string;
  type: string;
  shareFidToken: string;
}

export interface ShareSaveItem {
  shareId: string;
  fileId: string;
  targetFolderId: string;
  shareFidToken: string;
}

export interface DownloadInfo {
  url: string;
  size: number;
  contentHash: string;
  contentHashName: string;
  crc64Hash: string;
}

export interface UploadPart {
  partNumber: number;
  uploadUrl: string;
}

export interface EmptyUploadHeaders {
  'Content-Type'?: string;
}

export interface UploadCreateRequest {
  driveId?: string;
  parentFolderId: string;
  fileName: string;
  size: number;
  partSize: number;
  partCount: number;
  preHash?: string;
  contentHash?: string;
  md5Hash?: string;
  proofCode?: string;
  contentType?: string;
}

export interface UploadSession {
  provider: CloudProviderType;
  driveId?: string;
  fileId: string;
  uploadId: string;
  fileName: string;
  partSize: number;
  rapidUpload: boolean;
  parts: UploadPart[];
  uploadHeaders: Object;
  providerData: string;
}

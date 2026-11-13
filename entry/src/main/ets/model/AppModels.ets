export enum CloudProviderType {
  ALIYUN = 'aliyun',
  QUARK = 'quark'
}

export interface DriveFile {
  fileId: string;
  parentFileId: string;
  name: string;
  type: string;
  size: number;
}

export interface ShareTask {
  id: string;
  provider: CloudProviderType;
  shareUrl: string;
  shareCode: string;
  title: string;
  targetFolderId: string;
  targetFolderName: string;
  autoSync: boolean;
  disabled: boolean;
  status: string;
  createdAt: number;
  updatedAt: number;
}

export interface SearchResult {
  id: string;
  title: string;
  shareUrl: string;
  shareCode: string;
  provider: CloudProviderType;
  source: string;
}

export interface WebAddress {
  type: string;
  subType: string;
  address: string;
  selected: boolean;
}

export enum TransferState {
  QUEUED = 'queued',
  RESOLVING = 'resolving',
  DOWNLOADING = 'downloading',
  CONVERTING = 'converting',
  DOWNLOADED = 'downloaded',
  UPLOADING = 'uploading',
  COMPLETED = 'completed',
  PAUSED = 'paused',
  FAILED = 'failed',
  CANCELED = 'canceled'
}

export interface TransferJob {
  jobId: string;
  name: string;
  downloadUrl: string;
  key: string;
  source?: WebAddress;
  provider: CloudProviderType;
  targetFolderId?: string;
  localFile: string;
  state: TransferState;
  progress: number;
  downloadSpeedBytes?: number;
  errorMessage: string;
  selected: boolean;
  createdAt: number;
  updatedAt: number;
  checkpoint?: TransferCheckpoint;
}

export interface TransferCheckpoint {
  downloadedBytes: number;
  hlsPlaylistUrl: string;
  hlsSegmentCount: number;
  completedSegments: number[];
  uploadSession: string;
  completedParts: number[];
  uploadEtags: string[];
  uploadedBytes: number;
}

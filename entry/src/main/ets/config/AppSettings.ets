import { CloudProviderType } from '../model/AppModels';

export interface Credentials {
  aliyunAccessToken: string;
  aliyunLockToken: string;
  aliyunRefreshToken: string;
  quarkCookie: string;
  uuAuthorization: string;
}

export interface AppSettings {
  defaultProvider: CloudProviderType;
  aliyunDriveId: string;
  aliyunLockDriveId: string;
  aliyunLockRootFolderId: string;
  aliyunLogFolderId: string;
  aliyunAddressFolderId: string;
  aliyunShareBackupFolderId: string;
  quarkLogFolderId: string;
  quarkAddressFolderId: string;
  quarkTransformRootFolderId: string;
  quarkBackupFolderId: string;
  lanHost: string;
  lanPort: number;
  lanTimeoutMs: number;
  hlsConcurrency: number;
  downloadConcurrency: number;
  uploadConcurrency: number;
  autoResumeOnNetwork: boolean;
}

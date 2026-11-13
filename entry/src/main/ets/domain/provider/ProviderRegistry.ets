import { AppError, AppErrorCode } from '../../common/error/AppError';
import { CloudProviderType } from '../../model/AppModels';
import { CloudDriveProvider } from './CloudDriveProvider';

export class ProviderRegistry {
  private readonly aliyun: CloudDriveProvider;
  private readonly quark: CloudDriveProvider;

  constructor(aliyun: CloudDriveProvider, quark: CloudDriveProvider) {
    this.aliyun = aliyun;
    this.quark = quark;
  }

  get(type: CloudProviderType): CloudDriveProvider {
    if (type === CloudProviderType.ALIYUN) {
      return this.aliyun;
    }
    if (type === CloudProviderType.QUARK) {
      return this.quark;
    }
    throw new AppError(AppErrorCode.UNSUPPORTED, `不支持的云盘类型: ${type}`);
  }
}

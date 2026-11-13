import { AppContainer } from '../AppContainer';
import { CloudDriveView } from '../components/CloudDriveView';
import { CloudProviderType } from '../model/AppModels';

@Entry
@Component
struct AliyunDrivePage {
  @State pendingShareId: string = '';
  @State pendingShareUrl: string = '';
  @State pendingShareCode: string = '';

  onPageShow(): void {
    const pending = AppContainer.getInstance().pendingShareSelection.consume(CloudProviderType.ALIYUN);
    if (pending !== undefined) {
      this.pendingShareId = `${pending.id}_${Date.now()}`;
      this.pendingShareUrl = pending.shareUrl;
      this.pendingShareCode = pending.shareCode;
    }
  }

  build() {
    Column() {
      CloudDriveView({
        providerType: CloudProviderType.ALIYUN,
        pendingShareId: this.pendingShareId,
        pendingShareUrl: this.pendingShareUrl,
        pendingShareCode: this.pendingShareCode
      })
    }
    .width('100%')
    .height('100%')
  }
}

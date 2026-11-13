import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { AppContainer } from '../AppContainer';
import { AppError, AppErrorCode } from '../common/error/AppError';
import { LinkActions } from '../common/platform/LinkActions';
import { QUARK_CREDENTIAL_REVISION_KEY } from '../domain/auth/AuthController';
import { ShareListBackupController } from '../domain/share/ShareListBackupController';
import { ShareFolderUtils } from '../domain/share/ShareFolderUtils';
import {
  AddShareRequest,
  SHARE_TASK_REVISION_KEY,
  ShareController,
  ShareSyncSummary
} from '../domain/share/ShareController';
import { CloudDriveProvider } from '../domain/provider/CloudDriveProvider';
import { CloudProviderType, ShareTask } from '../model/AppModels';
import { CloudFile } from '../model/drive/CloudDriveModels';
import { ShareTaskRow } from './ShareTaskRow';

class FolderOption {
  value: string;

  constructor(value: string) {
    this.value = value;
  }
}

@Component
export struct CloudDriveView {
  @Prop providerType: CloudProviderType = CloudProviderType.ALIYUN;
  @StorageLink(QUARK_CREDENTIAL_REVISION_KEY)
  @Watch('onQuarkCredentialChanged')
  private quarkCredentialRevision: number = 0;
  @StorageLink(SHARE_TASK_REVISION_KEY)
  @Watch('onShareTasksChanged')
  private shareTaskRevision: number = 0;
  @Watch('onPendingShareChanged') @Prop pendingShareId: string = '';
  @Prop pendingShareUrl: string = '';
  @Prop pendingShareCode: string = '';
  @State folders: CloudFile[] = [];
  @State tasks: ShareTask[] = [];
  @State shareUrl: string = '';
  @State shareCode: string = '';
  @State subFolderName: string = '';
  @State selectedFolderIndex: number = 0;
  @State busy: boolean = false;
  @State message: string = '正在初始化';
  private provider?: CloudDriveProvider;
  private shareController?: ShareController;
  private backupController?: ShareListBackupController;
  private handledPendingId: string = '';

  aboutToAppear(): void {
    this.initialize();
  }

  private onPendingShareChanged(): void {
    this.consumePendingShare();
  }

  private onQuarkCredentialChanged(): void {
    if (this.providerType === CloudProviderType.QUARK &&
      this.provider !== undefined && !this.busy) {
      this.refreshRootFolders();
    }
  }

  private onShareTasksChanged(): void {
    if (this.shareController !== undefined) {
      this.tasks = this.shareController.load();
    }
  }

  private async initialize(): Promise<void> {
    this.busy = true;
    try {
      const container = AppContainer.getInstance();
      await container.waitUntilReady();
      if (container.providerRegistry === undefined) {
        throw new AppError(AppErrorCode.UNKNOWN, '云盘服务未初始化');
      }
      this.provider = container.providerRegistry.get(this.providerType);
      this.shareController = container.createShareController(this.providerType);
      this.backupController = container.shareListBackupController;
      this.tasks = this.shareController.load();
      await this.loadRootFolders();
    } catch (error) {
      this.message = this.errorMessage(error);
    } finally {
      this.busy = false;
      this.consumePendingShare();
    }
  }

  private async loadRootFolders(): Promise<void> {
    if (this.provider === undefined) {
      return;
    }
    const result = await this.provider.listFiles(this.rootFolderId());
    if (!result.isSuccess || result.value === undefined) {
      this.message = result.error?.message ?? '目录加载失败';
      return;
    }
    const folders = ShareFolderUtils.rootFolders(result.value);
    this.folders = folders;
    this.selectedFolderIndex = folders.length > 0 ? 0 : -1;
    this.message = '';
  }

  private async refreshRootFolders(): Promise<void> {
    this.busy = true;
    try {
      await this.loadRootFolders();
    } finally {
      this.busy = false;
    }
  }

  private consumePendingShare(): void {
    if (this.pendingShareId.length === 0 || this.pendingShareId === this.handledPendingId ||
      this.shareController === undefined || this.busy) {
      return;
    }
    this.handledPendingId = this.pendingShareId;
    this.shareUrl = this.pendingShareUrl;
    this.shareCode = this.pendingShareCode;
    this.addShare();
  }

  private async addShare(): Promise<void> {
    if (this.shareController === undefined || this.busy) {
      return;
    }
    const url = this.shareUrl.trim();
    if (url.length === 0) {
      this.toast('请添写连接地址！');
      return;
    }
    this.busy = true;
    const request: AddShareRequest = {
      shareUrl: url,
      shareCode: this.shareCode,
      targetFolderId: this.selectedFolderId(),
      targetFolderName: this.subFolderName.trim(),
      autoSync: false
    };
    const result = await this.shareController.add(request);
    if (result.isSuccess) {
      this.tasks = this.shareController.snapshot();
      this.shareUrl = '';
      this.shareCode = '';
      this.subFolderName = '';
      this.message = '';
      if (this.providerType === CloudProviderType.ALIYUN) {
        this.backupAfterAliyunAdd();
      }
    } else {
      this.message = result.error?.message ?? '添加分享失败';
      this.toast(this.message);
    }
    this.busy = false;
  }

  private async backupAfterAliyunAdd(): Promise<void> {
    const result = await this.backupController?.backup(CloudProviderType.ALIYUN);
    if (result !== undefined && !result.isSuccess) {
      this.message = result.error?.message ?? '备份失败！';
    }
  }

  private async syncAll(): Promise<void> {
    if (this.shareController === undefined || this.busy) {
      return;
    }
    this.busy = true;
    this.message = '更新中...';
    const logs: string[] = [];
    const result = await this.shareController.syncAutoTasks((line: string) => {
      logs.push(line);
      this.message = logs.join('\n');
    }, this.selectedFolderId());
    this.tasks = this.shareController.snapshot();
    if (!result.isSuccess) {
      this.message = result.error?.message ?? '同步失败';
    } else if (logs.length === 0) {
      const summary = result.value as ShareSyncSummary;
      this.message = summary.failedCount > 0 ? '同步失败' : '无更新！';
    }
    this.busy = false;
  }

  private async checkDisabled(): Promise<void> {
    if (this.shareController === undefined || this.busy) {
      return;
    }
    this.busy = true;
    const result = await this.shareController.checkDisabled();
    this.tasks = this.shareController.snapshot();
    const message = result.isSuccess && (result.value ?? 0) > 0 ? '有更新！' :
      (result.isSuccess ? '无更新！' : (result.error?.message ?? '检查失败'));
    this.message = message;
    this.toast(message);
    this.busy = false;
  }

  private async backupData(): Promise<void> {
    if (this.backupController === undefined || this.busy) {
      return;
    }
    this.busy = true;
    const result = await this.backupController.backup(this.providerType);
    const message = result.isSuccess ? '备份成功' : (result.error?.message ?? '备份失败！');
    this.message = message;
    this.toast(message);
    this.busy = false;
  }

  private async updateData(): Promise<void> {
    if (this.backupController === undefined || this.shareController === undefined || this.busy) {
      return;
    }
    this.busy = true;
    const result = await this.backupController.restoreLatest(this.providerType);
    if (result.isSuccess) {
      this.tasks = this.shareController.load();
      this.message = `更新成功，共 ${result.value ?? 0} 条`;
    } else {
      this.message = result.error?.message ?? '更新失败';
    }
    this.toast(this.message);
    this.busy = false;
  }

  private deleteTask(taskId: string): void {
    if (this.shareController !== undefined) {
      this.tasks = this.shareController.delete(taskId);
    }
  }

  private setAutoSync(taskId: string, enabled: boolean): void {
    if (this.shareController !== undefined) {
      this.tasks = this.shareController.setAutoSync(taskId, enabled, this.selectedFolderId());
    }
  }

  private async openLink(task: ShareTask): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const result = await LinkActions.open(context, task.shareUrl);
    if (!result.isSuccess) {
      this.toast(result.error?.message ?? '无法打开分享链接');
    }
  }

  private async copyLink(task: ShareTask): Promise<void> {
    const result = await LinkActions.copy(task.shareUrl);
    this.toast(result.isSuccess ? '复制连接成功！' : (result.error?.message ?? '复制连接失败'));
  }

  private openLogin(): void {
    router.pushUrl({ url: 'pages/WebLoginPage', params: { provider: this.providerType } });
  }

  private openSearch(): void {
    router.pushUrl({ url: 'pages/SearchPage', params: { provider: this.providerType } });
  }

  private folderOptions(): FolderOption[] {
    return this.folders.map((file: CloudFile) => new FolderOption(file.name));
  }

  private selectedFolderId(): string {
    if (this.selectedFolderIndex >= 0 && this.selectedFolderIndex < this.folders.length) {
      return this.folders[this.selectedFolderIndex].fileId;
    }
    return this.rootFolderId();
  }

  private selectedFolderName(): string {
    if (this.selectedFolderIndex >= 0 && this.selectedFolderIndex < this.folders.length) {
      return this.folders[this.selectedFolderIndex].name;
    }
    return '';
  }

  private rootFolderId(): string {
    return this.providerType === CloudProviderType.ALIYUN ? 'root' : '0';
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }

  @Builder
  private actionButton(label: string, action: () => void) {
    Button(label)
      .type(ButtonType.Normal)
      .fontSize(13)
      .fontColor(Color.Black)
      .backgroundColor(Color.Transparent)
      .border({ width: 0.5, color: $r('app.color.android_border'), radius: 1 })
      .height(30)
      .layoutWeight(1)
      .margin(5)
      .padding(5)
      .enabled(!this.busy)
      .onClick(action)
  }

  build() {
    Column() {
      Row() {
        Text('链接地址：').fontSize(13)
        TextInput({ text: this.shareUrl })
          .fontSize(13)
          .height(30)
          .layoutWeight(1)
          .padding({ left: 4, right: 4 })
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: $r('app.color.android_border'), radius: 1 })
          .onChange((value: string) => this.shareUrl = value)
      }
      .width('100%')

      Row() {
        Text('文件夹：').fontSize(13)
        Select(this.folderOptions())
          .selected(this.selectedFolderIndex)
          .value(this.selectedFolderName())
          .height(30)
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: $r('app.color.android_border'), radius: 1 })
          .onSelect((index: number) => this.selectedFolderIndex = index)
        Text('子目录：').fontSize(13).margin({ left: 5 })
        TextInput({ text: this.subFolderName })
          .fontSize(13)
          .height(30)
          .layoutWeight(1)
          .padding({ left: 4, right: 4 })
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: $r('app.color.android_border'), radius: 1 })
          .onChange((value: string) => this.subFolderName = value)
      }
      .width('100%')
      .margin({ top: 5 })

      Row() {
        this.actionButton('新增分享', () => this.addShare())
        this.actionButton('更新token', () => this.openLogin())
        this.actionButton('检测有效性', () => this.checkDisabled())
      }
      .width('100%')

      Row() {
        this.actionButton('同步', () => this.syncAll())
        this.actionButton('备份', () => this.backupData())
        this.actionButton('更新', () => this.updateData())
        this.actionButton('搜索', () => this.openSearch())
      }
      .width('100%')

      Text(this.message)
        .fontSize(12)
        .fontColor(Color.Black)
        .width('100%')
        .maxLines(8)

      List() {
        ForEach(this.tasks, (task: ShareTask) => {
          ListItem() {
            ShareTaskRow({
              task: task,
              busy: this.busy,
              onOpen: (item: ShareTask) => this.openLink(item),
              onCopy: (item: ShareTask) => this.copyLink(item),
              onDelete: (taskId: string) => this.deleteTask(taskId),
              onAutoSyncChange: (taskId: string, enabled: boolean) =>
                this.setAutoSync(taskId, enabled)
            })
          }
        }, (task: ShareTask) => task.id)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(10)
    .backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Start)
  }
}

import { router } from '@kit.ArkUI';
import { AppContainer } from '../AppContainer';
import { LsLogger } from '../common/log/LsLogger';
import { AppSettings } from '../config/AppSettings';
import { LanProbe } from '../data/network/LanProbe';
import { CloudProviderType } from '../model/AppModels';

const TAG = 'SettingsPage';

@Entry
@Component
struct SettingsPage {
  @State ready: boolean = false;
  @State saving: boolean = false;
  @State probing: boolean = false;
  @State providerIndex: number = 1;
  @State aliyunDriveId: string = '';
  @State aliyunLockDriveId: string = '';
  @State aliyunLockRootFolderId: string = '';
  @State aliyunLogFolderId: string = '';
  @State aliyunAddressFolderId: string = '';
  @State aliyunShareBackupFolderId: string = '';
  @State quarkLogFolderId: string = '';
  @State quarkAddressFolderId: string = '';
  @State quarkTransformRootFolderId: string = '';
  @State quarkBackupFolderId: string = '';
  @State lanHost: string = '';
  @State lanPort: string = '';
  @State lanTimeoutMs: string = '';
  @State hlsConcurrency: string = '';
  @State downloadConcurrency: string = '';
  @State uploadConcurrency: string = '';
  @State autoResumeOnNetwork: boolean = false;
  private settings?: AppSettings;
  private readonly probe: LanProbe = new LanProbe();

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      const container = AppContainer.getInstance();
      await container.waitUntilReady();
      const settings = container.settings;
      if (settings === undefined) {
        throw new Error('Settings are unavailable');
      }
      this.settings = settings;
      this.providerIndex = settings.defaultProvider === CloudProviderType.ALIYUN ? 0 : 1;
      this.aliyunDriveId = settings.aliyunDriveId;
      this.aliyunLockDriveId = settings.aliyunLockDriveId;
      this.aliyunLockRootFolderId = settings.aliyunLockRootFolderId;
      this.aliyunLogFolderId = settings.aliyunLogFolderId;
      this.aliyunAddressFolderId = settings.aliyunAddressFolderId;
      this.aliyunShareBackupFolderId = settings.aliyunShareBackupFolderId;
      this.quarkLogFolderId = settings.quarkLogFolderId;
      this.quarkAddressFolderId = settings.quarkAddressFolderId;
      this.quarkTransformRootFolderId = settings.quarkTransformRootFolderId;
      this.quarkBackupFolderId = settings.quarkBackupFolderId;
      this.lanHost = settings.lanHost;
      this.lanPort = settings.lanPort.toString();
      this.lanTimeoutMs = settings.lanTimeoutMs.toString();
      this.hlsConcurrency = settings.hlsConcurrency.toString();
      this.downloadConcurrency = settings.downloadConcurrency.toString();
      this.uploadConcurrency = settings.uploadConcurrency.toString();
      this.autoResumeOnNetwork = settings.autoResumeOnNetwork;
      this.ready = true;
    } catch (error) {
      LsLogger.error(TAG, `Settings load failed: ${this.messageOf(error)}`);
      this.toast('设置加载失败');
    }
  }

  private async save(): Promise<void> {
    if (this.settings === undefined || this.saving) {
      return;
    }
    const port = Number(this.lanPort);
    const timeout = Number(this.lanTimeoutMs);
    const hlsConcurrency = Number(this.hlsConcurrency);
    const downloadConcurrency = Number(this.downloadConcurrency);
    const uploadConcurrency = Number(this.uploadConcurrency);
    if (this.lanHost.trim().length === 0 || port < 1 || port > 65535 ||
      timeout < 100 || hlsConcurrency < 1 || hlsConcurrency > 16 ||
      downloadConcurrency < 1 || downloadConcurrency > 8 ||
      uploadConcurrency < 1 || uploadConcurrency > 8) {
      this.toast('请检查主机、端口、超时和并发数');
      return;
    }
    this.saving = true;
    try {
      this.settings.defaultProvider = this.providerIndex === 0 ?
        CloudProviderType.ALIYUN : CloudProviderType.QUARK;
      this.settings.aliyunDriveId = this.aliyunDriveId.trim();
      this.settings.aliyunLockDriveId = this.aliyunLockDriveId.trim();
      this.settings.aliyunLockRootFolderId = this.aliyunLockRootFolderId.trim();
      this.settings.aliyunLogFolderId = this.aliyunLogFolderId.trim();
      this.settings.aliyunAddressFolderId = this.aliyunAddressFolderId.trim();
      this.settings.aliyunShareBackupFolderId = this.aliyunShareBackupFolderId.trim();
      this.settings.quarkLogFolderId = this.quarkLogFolderId.trim();
      this.settings.quarkAddressFolderId = this.quarkAddressFolderId.trim();
      this.settings.quarkTransformRootFolderId = this.quarkTransformRootFolderId.trim();
      this.settings.quarkBackupFolderId = this.quarkBackupFolderId.trim();
      this.settings.lanHost = this.lanHost.trim();
      this.settings.lanPort = port;
      this.settings.lanTimeoutMs = timeout;
      this.settings.hlsConcurrency = hlsConcurrency;
      this.settings.downloadConcurrency = downloadConcurrency;
      this.settings.uploadConcurrency = uploadConcurrency;
      this.settings.autoResumeOnNetwork = this.autoResumeOnNetwork;
      await AppContainer.getInstance().settingsRepository.saveSettings(this.settings);
      this.toast('设置已保存');
    } catch (error) {
      LsLogger.error(TAG, `Settings save failed: ${this.messageOf(error)}`);
      this.toast('设置保存失败');
    } finally {
      this.saving = false;
    }
  }

  private async testLan(): Promise<void> {
    if (this.probing) {
      return;
    }
    const port = Number(this.lanPort);
    const timeout = Number(this.lanTimeoutMs);
    if (this.lanHost.trim().length === 0 || port < 1 || port > 65535 || timeout < 100) {
      this.toast('请先填写有效的局域网参数');
      return;
    }
    this.probing = true;
    const result = await this.probe.probe(this.lanHost.trim(), port, timeout);
    this.probing = false;
    if (result.isSuccess) {
      this.toast(`连接成功，${result.value?.latencyMs ?? 0} ms`);
    } else {
      this.toast(result.error?.message ?? '连接失败');
    }
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private messageOf(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }

  @Builder
  private textSetting(label: string, value: string, change: (value: string) => void) {
    Column({ space: 6 }) {
      Text(label).fontSize(14).fontColor($r('app.color.text_secondary'))
      TextInput({ text: value })
        .width('100%')
        .onChange(change)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private numberSetting(label: string, value: string, change: (value: string) => void) {
    Column({ space: 6 }) {
      Text(label).fontSize(14).fontColor($r('app.color.text_secondary'))
      TextInput({ text: value })
        .type(InputType.Number)
        .width('100%')
        .onChange(change)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Button('‹').type(ButtonType.Normal).onClick(() => router.back())
        Text('设置').fontSize(24).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button(this.saving ? '保存中' : '保存')
          .enabled(this.ready && !this.saving)
          .onClick(() => this.save())
      }.width('100%')

      if (!this.ready) {
        LoadingProgress()
      } else {
        Scroll() {
          Column({ space: 14 }) {
            Text('传输').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
            Row() {
              Text('默认云盘').layoutWeight(1)
              Select([{ value: '阿里云盘' }, { value: '夸克云盘' }])
                .selected(this.providerIndex)
                .onSelect((index: number) => this.providerIndex = index)
            }.width('100%')
            this.numberSetting('HLS 并发数（1-16）', this.hlsConcurrency,
              (value: string) => this.hlsConcurrency = value)
            this.numberSetting('同时下载任务数（1-8）', this.downloadConcurrency,
              (value: string) => this.downloadConcurrency = value)
            this.numberSetting('同时上传任务数（1-8）', this.uploadConcurrency,
              (value: string) => this.uploadConcurrency = value)
            Row() {
              Text('网络恢复后自动继续').layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.autoResumeOnNetwork })
                .onChange((value: boolean) => this.autoResumeOnNetwork = value)
            }.width('100%')

            Divider()
            Text('阿里云盘目录').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
            this.textSetting('资源盘 ID', this.aliyunDriveId,
              (value: string) => this.aliyunDriveId = value)
            this.textSetting('加密盘 ID', this.aliyunLockDriveId,
              (value: string) => this.aliyunLockDriveId = value)
            this.textSetting('上传根目录 ID', this.aliyunLockRootFolderId,
              (value: string) => this.aliyunLockRootFolderId = value)
            this.textSetting('日志目录 ID', this.aliyunLogFolderId,
              (value: string) => this.aliyunLogFolderId = value)
            this.textSetting('地址目录 ID', this.aliyunAddressFolderId,
              (value: string) => this.aliyunAddressFolderId = value)

            Divider()
            Text('夸克云盘目录').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
            this.textSetting('资源同步日志目录 ID', this.quarkLogFolderId,
              (value: string) => this.quarkLogFolderId = value)
            this.textSetting('资源同步地址目录 ID', this.quarkAddressFolderId,
              (value: string) => this.quarkAddressFolderId = value)
            this.textSetting('资源同步 transform 根目录 ID', this.quarkTransformRootFolderId,
              (value: string) => this.quarkTransformRootFolderId = value)
            this.textSetting('阿里分享清单备份目录 ID', this.aliyunShareBackupFolderId,
              (value: string) => this.aliyunShareBackupFolderId = value)
            this.textSetting('夸克分享清单备份目录 ID', this.quarkBackupFolderId,
              (value: string) => this.quarkBackupFolderId = value)

            Divider()
            Text('局域网探测').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
            this.textSetting('主机地址', this.lanHost, (value: string) => this.lanHost = value)
            this.numberSetting('端口', this.lanPort, (value: string) => this.lanPort = value)
            this.numberSetting('连接超时（毫秒）', this.lanTimeoutMs,
              (value: string) => this.lanTimeoutMs = value)
            Button(this.probing ? '探测中' : '测试连接')
              .enabled(!this.probing)
              .onClick(() => this.testLan())
              .width('100%')
          }
          .width('100%')
          .padding({ bottom: 24 })
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding($r('app.float.page_padding'))
    .backgroundColor($r('app.color.page_background'))
    .alignItems(HorizontalAlign.Start)
  }
}

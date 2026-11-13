import { webview } from '@kit.ArkWeb';
import { AppContainer } from '../AppContainer';
import { LsLogger } from '../common/log/LsLogger';
import { LinkActions } from '../common/platform/LinkActions';
import { Credentials } from '../config/AppSettings';
import { LanProbe } from '../data/network/LanProbe';
import { CloudBackupController } from '../domain/backup/CloudBackupController';
import { AddressController } from '../domain/parser/AddressController';
import {
  PageContentLoader,
  ParsingController,
  ParsingSummary
} from '../domain/parser/ParsingController';
import {
  TransferQueueController,
  TransferQueueListener
} from '../domain/transfer/TransferQueueController';
import {
  CloudProviderType,
  TransferJob,
  TransferState,
  WebAddress
} from '../model/AppModels';

const TAG: string = 'SyncPage';
const PARSER_TYPES: string[] = ['0', '1', '2', '3', '4', '5', '6', '7', '8'];

class ParserOption {
  value: string;

  constructor(value: string) {
    this.value = value;
  }
}

@Entry
@Component
struct SyncPage {
  @State jobs: TransferJob[] = [];
  @State addresses: WebAddress[] = [];
  @State running: boolean = false;
  @State ready: boolean = false;
  @State parsing: boolean = false;
  @State busy: boolean = false;
  @State parserIndex: number = 0;
  @State providerIndex: number = 1;
  @State quarkChecked: boolean = true;
  @State aliyunChecked: boolean = false;
  @State addressName: string = '';
  @State addressUrl: string = '';
  @State logText: string = '';
  @State rendererUrl: string = 'about:blank';
  @State expandedJobId: string = '';
  @State allJobsSelected: boolean = false;
  private queue?: TransferQueueController;
  private addressController?: AddressController;
  private parsingController?: ParsingController;
  private backupController?: CloudBackupController;
  private unsubscribe?: () => void;
  private webController: webview.WebviewController = new webview.WebviewController();
  private contentResolve?: (content: string) => void;
  private contentReject?: (error: Error) => void;
  private contentTimer: number = -1;
  private contentCaptureTimer: number = -1;
  private readonly lanProbe: LanProbe = new LanProbe();

  aboutToAppear(): void {
    this.bindControllers();
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
    this.stopParsing(false);
  }

  private async bindControllers(): Promise<void> {
    try {
      const container = AppContainer.getInstance();
      await container.waitUntilReady();
      this.queue = container.transferQueue;
      this.addressController = container.addressController;
      this.parsingController = container.parsingController;
      this.backupController = container.cloudBackupController;
      if (this.queue === undefined || this.addressController === undefined ||
        this.parsingController === undefined || this.backupController === undefined ||
        container.settings === undefined) {
        throw new Error('Sync controllers are unavailable');
      }
      this.addresses = this.addressController.snapshot();
      this.providerIndex = 1;
      this.aliyunChecked = false;
      this.quarkChecked = true;
      const listener: TransferQueueListener = (jobs: TransferJob[], running: boolean): void => {
        this.jobs = jobs;
        this.running = running;
        this.allJobsSelected =
          jobs.length > 0 && jobs.every((job: TransferJob) => job.selected);
      };
      this.unsubscribe = this.queue.subscribe(listener);
      this.ready = true;
    } catch (error) {
      LsLogger.error(TAG, `Sync initialization failed: ${this.messageOf(error)}`);
      this.toast('同步功能初始化失败');
    }
  }

  private currentType(): string {
    return PARSER_TYPES[this.parserIndex];
  }

  private visibleAddresses(): WebAddress[] {
    const type = this.currentType();
    return this.addresses.filter((address: WebAddress) => address.type === type);
  }

  private saveAddress(): void {
    if (this.addressController === undefined || this.parsing) {
      return;
    }
    const result = this.addressController.add(
      this.currentType(),
      this.addressName,
      this.addressUrl
    );
    if (!result.isSuccess || result.value === undefined) {
      this.toast(result.error?.message ?? '添加失败');
      return;
    }
    this.addresses = result.value;
    this.toast('添加成功！');
    this.backupData(false);
  }

  private removeAddress(address: string): void {
    if (this.addressController !== undefined && !this.parsing) {
      this.addresses = this.addressController.remove(address);
    }
  }

  private selectAddress(address: string, selected: boolean): void {
    if (this.addressController !== undefined) {
      this.addresses = this.addressController.setSelected(address, selected);
    }
  }

  private selectVisibleAddresses(selected: boolean): void {
    if (this.addressController !== undefined) {
      this.addresses = this.addressController.selectType(this.currentType(), selected);
    }
  }

  private async copyAddress(address: string): Promise<void> {
    const result = await LinkActions.copy(address);
    this.toast(result.isSuccess ? '复制连接成功！' : (result.error?.message ?? '复制连接失败'));
  }

  private async copyDownloadUrl(job: TransferJob): Promise<void> {
    const result = await LinkActions.copy(job.downloadUrl);
    this.toast(result.isSuccess ? '下载链接已复制' : (result.error?.message ?? '复制下载链接失败'));
  }

  private async parseAddresses(): Promise<void> {
    if (this.parsing || this.parsingController === undefined || this.queue === undefined) {
      return;
    }
    const currentAddresses = this.visibleAddresses();
    const selectedCount = currentAddresses.filter((address: WebAddress) => address.selected).length;
    if (selectedCount === 0) {
      this.toast('请先选择至少一个地址');
      return;
    }
    this.queue.clearAll(false);
    this.parsing = true;
    this.logText = '解析中...';
    try {
      const provider = this.providerIndex === 0 ?
        CloudProviderType.ALIYUN : CloudProviderType.QUARK;
      const loader: PageContentLoader =
        (url: string): Promise<string> => this.loadRenderedContent(url);
      const result = await this.parsingController.parse(currentAddresses, provider, loader);
      if (!result.isSuccess || result.value === undefined) {
        this.logText = result.error?.message ?? '解析失败';
        return;
      }
      this.logText = this.summaryText(result.value);
      if (result.value.errors.length > 0) {
        LsLogger.warn(TAG, `Partial parse failures: ${result.value.errors.join(' | ')}`);
      }
      this.toast('解析完成！');
    } catch (error) {
      this.logText = `解析失败：${this.messageOf(error)}`;
      LsLogger.error(TAG, this.logText);
    } finally {
      this.parsing = false;
    }
  }

  private stopParsing(showToast: boolean = true): void {
    this.parsingController?.cancel();
    this.rejectPending(new Error('解析已停止'));
    this.queue?.pause();
    if (this.parsing) {
      this.parsing = false;
      this.logText = '解析已停止';
      if (showToast) {
        this.toast('解析已停止');
      }
    }
  }

  private beginSync(): void {
    if (this.queue === undefined) {
      return;
    }
    if (!this.aliyunChecked && !this.quarkChecked) {
      this.toast('请选择上传盘！');
      return;
    }
    this.queue.setProvider(this.selectedProvider());
    this.queue.start();
  }

  private selectAllJobs(selected: boolean): void {
    this.allJobsSelected = selected;
    this.queue?.selectAll(selected);
  }

  private async clearDownloads(): Promise<void> {
    try {
      await this.queue?.clearAllAndDownloadCache(true);
      this.logText = '';
      this.toast('下载缓存已清空');
    } catch (error) {
      LsLogger.error(TAG, `Download cache cleanup failed: ${this.messageOf(error)}`);
      this.toast('下载缓存清理失败');
    }
  }

  private async checkToken(): Promise<void> {
    if (this.busy) {
      return;
    }
    const container = AppContainer.getInstance();
    if (container.providerRegistry === undefined || container.settings === undefined) {
      return;
    }
    this.busy = true;
    const settings = container.settings;
    const result = await container.providerRegistry.get(CloudProviderType.ALIYUN)
      .listFiles(settings.aliyunLockRootFolderId, settings.aliyunLockDriveId);
    this.busy = false;
    this.toast(result.isSuccess ? 'Token 有效' : 'Token 失效');
  }

  private async updateToken(): Promise<void> {
    const token = this.addressUrl.trim();
    const container = AppContainer.getInstance();
    const credentials: Credentials = await container.settingsRepository.loadCredentials();
    credentials.aliyunLockToken = token;
    await container.settingsRepository.saveCredentials(credentials);
    container.credentials = credentials;
    this.toast('Token 已更新');
  }

  private async backupData(showResult: boolean = true): Promise<void> {
    if (this.backupController === undefined || this.busy) {
      return;
    }
    this.busy = true;
    const result = await this.backupController.backup(this.selectedProvider());
    this.busy = false;
    if (showResult) {
      this.toast(result.isSuccess ? '备份成功' : (result.error?.message ?? '备份失败！'));
    }
  }

  private async restoreData(): Promise<void> {
    if (this.backupController === undefined || this.addressController === undefined ||
      this.queue === undefined || this.busy) {
      return;
    }
    this.busy = true;
    const result = await this.backupController.restoreLatest(this.selectedProvider());
    if (result.isSuccess) {
      this.addresses = this.addressController.reload();
      this.queue.reload();
    }
    this.busy = false;
    this.toast(result.isSuccess ? '更新成功' : (result.error?.message ?? '更新失败'));
  }

  private async scanLan(): Promise<void> {
    const settings = AppContainer.getInstance().settings;
    if (settings === undefined || this.busy) {
      return;
    }
    this.busy = true;
    const result = await this.lanProbe.probe(
      settings.lanHost,
      settings.lanPort,
      settings.lanTimeoutMs
    );
    this.busy = false;
    this.toast(result.isSuccess ? '连接成功' : (result.error?.message ?? '连接失败'));
  }

  private selectedProvider(): CloudProviderType {
    return this.providerIndex === 0 ? CloudProviderType.ALIYUN : CloudProviderType.QUARK;
  }

  private selectQuark(checked: boolean): void {
    this.quarkChecked = checked;
    if (checked) {
      this.providerIndex = 1;
    }
  }

  private selectAliyun(checked: boolean): void {
    this.aliyunChecked = checked;
    if (checked) {
      this.providerIndex = 0;
    }
  }

  private summaryText(summary: ParsingSummary): string {
    const failed = summary.failedCount > 0 ? `，失败 ${summary.failedCount}` : '';
    return `解析 ${summary.pageCount} 页，新增 ${summary.addedCount}，跳过 ${summary.skippedCount}${failed}`;
  }

  private loadRenderedContent(url: string): Promise<string> {
    this.rejectPending(new Error('页面加载已切换'));
    return new Promise<string>((resolve: (content: string) => void, reject: (error: Error) => void) => {
      this.contentResolve = resolve;
      this.contentReject = reject;
      this.rendererUrl = url;
      try {
        this.webController.loadUrl(url);
      } catch (error) {
        this.rejectPending(new Error(this.messageOf(error)));
        return;
      }
      this.scheduleRenderedCapture(5000, true);
      this.contentTimer = setTimeout(() => this.rejectPending(new Error('页面渲染超时')), 20000);
    });
  }

  private async captureRenderedContent(requireLargeContent: boolean = false): Promise<void> {
    if (this.contentResolve === undefined || this.rendererUrl === 'about:blank') {
      return;
    }
    if (this.contentCaptureTimer >= 0) {
      clearTimeout(this.contentCaptureTimer);
      this.contentCaptureTimer = -1;
    }
    try {
      const content = await this.webController.runJavaScript(
        'document.getElementsByTagName("html")[0].innerHTML'
      );
      if (requireLargeContent && content.length <= 10000) {
        this.scheduleRenderedCapture(5000, true);
        return;
      }
      const resolve = this.contentResolve;
      this.clearPending();
      resolve(content);
    } catch (error) {
      this.rejectPending(new Error(this.messageOf(error)));
    }
  }

  private scheduleRenderedCapture(delayMs: number, requireLargeContent: boolean): void {
    if (this.contentCaptureTimer >= 0) {
      clearTimeout(this.contentCaptureTimer);
    }
    this.contentCaptureTimer =
      setTimeout(() => this.captureRenderedContent(requireLargeContent), delayMs);
  }

  private rejectPending(error: Error): void {
    const reject = this.contentReject;
    this.clearPending();
    reject?.(error);
  }

  private clearPending(): void {
    if (this.contentTimer >= 0) {
      clearTimeout(this.contentTimer);
    }
    if (this.contentCaptureTimer >= 0) {
      clearTimeout(this.contentCaptureTimer);
    }
    this.contentTimer = -1;
    this.contentCaptureTimer = -1;
    this.contentResolve = undefined;
    this.contentReject = undefined;
  }

  private stateText(job: TransferJob): string {
    switch (job.state) {
      case TransferState.QUEUED:
        return '准备';
      case TransferState.RESOLVING:
        return '解析中';
      case TransferState.DOWNLOADING:
        return `下载中 ${job.progress}% | ${Math.floor((job.downloadSpeedBytes ?? 0) / 1024)}K/s | ` +
          `${Math.floor((job.checkpoint?.downloadedBytes ?? 0) / 1024 / 1024)}M`;
      case TransferState.CONVERTING:
        return '正在转换 MP4';
      case TransferState.DOWNLOADED:
        return '等待上传';
      case TransferState.UPLOADING:
        return `上传中 ${job.progress}%`;
      case TransferState.COMPLETED:
        return '已完成';
      case TransferState.PAUSED:
        return '已暂停';
      case TransferState.FAILED:
        return `失败：${job.errorMessage}`;
      case TransferState.CANCELED:
        return '已取消';
      default:
        return job.state;
    }
  }

  private jobTitle(job: TransferJob): string {
    const source = job.source;
    return source === undefined ? job.name : `[${source.type}][${source.subType}]${job.name}`;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private messageOf(error: Object): string {
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
      .enabled(this.ready && !this.busy)
      .onClick(action)
  }

  @Builder
  private addressRow(address: WebAddress) {
    Row() {
      Checkbox()
        .select(address.selected)
        .enabled(!this.parsing)
        .onChange((selected: boolean) => this.selectAddress(address.address, selected))
        .gesture(LongPressGesture().onAction(() => this.selectVisibleAddresses(!address.selected)))
      Text(address.type)
        .fontSize(12)
        .fontColor($r('app.color.android_valid'))
        .margin({ right: 10 })
      Text(address.subType)
        .fontSize(12)
        .fontColor($r('app.color.android_valid'))
        .margin({ right: 10 })
      Text(address.address)
        .fontSize(12)
        .fontColor($r('app.color.android_valid'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .gesture(LongPressGesture().onAction(() => this.copyAddress(address.address)))
      Text('删除')
        .fontSize(12)
        .fontColor($r('app.color.android_link_blue'))
        .onClick(() => this.removeAddress(address.address))
    }
    .width('100%')
    .height(42)
    .padding(10)
  }

  @Builder
  private jobRow(job: TransferJob) {
    Row() {
      Checkbox()
        .select(job.selected)
        .onChange((selected: boolean) => this.queue?.setSelected(job.jobId, selected))
        .gesture(LongPressGesture().onAction(() => this.queue?.selectAll(!job.selected)))
      Text(this.jobTitle(job))
        .fontSize(12)
        .fontColor($r('app.color.android_link_blue'))
        .maxLines(this.expandedJobId === job.jobId ? 5 : 1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .onClick(() => {
          this.expandedJobId = this.expandedJobId === job.jobId ? '' : job.jobId;
        })
      Text(this.stateText(job))
        .fontSize(12)
        .fontColor($r('app.color.android_valid'))
        .maxLines(1)
        .margin({ right: 10 })
      Text('删除')
        .fontSize(12)
        .fontColor($r('app.color.android_link_blue'))
        .onClick(() => this.queue?.remove(job.jobId))
    }
    .width('100%')
    .height(this.expandedJobId === job.jobId ? 76 : 42)
    .padding(10)
    .gesture(LongPressGesture({ fingers: 1 }).onAction(() => this.copyDownloadUrl(job)))
  }

  build() {
    Column() {
      Row() {
        Text('链接地址：').fontSize(13)
        TextInput({ text: this.addressUrl })
          .fontSize(13)
          .height(30)
          .layoutWeight(1)
          .padding({ left: 4, right: 4 })
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: $r('app.color.android_border'), radius: 1 })
          .onChange((value: string) => this.addressUrl = value)
      }
      .width('100%')
      .margin({ top: 10, bottom: 10 })

      Row() {
        Text('网址：').fontSize(13).margin({ left: 10 })
        Select(PARSER_TYPES.map((type: string) => new ParserOption(type)))
          .selected(this.parserIndex)
          .value(this.currentType())
          .width(58)
          .height(30)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: $r('app.color.android_border'), radius: 1 })
          .onSelect((index: number) => this.parserIndex = index)
        Text('类别：').fontSize(13).margin({ left: 10 })
        TextInput({ text: this.addressName })
          .fontSize(13)
          .height(30)
          .layoutWeight(1)
          .padding({ left: 4, right: 4 })
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: $r('app.color.android_border'), radius: 1 })
          .onChange((value: string) => this.addressName = value)
      }
      .width('100%')

      Row() {
        this.actionButton('add', () => this.saveAddress())
        this.actionButton('parse', () => this.parseAddresses())
        this.actionButton('begin', () => this.beginSync())
        this.actionButton('stop', () => this.stopParsing())
        this.actionButton('clear', () => this.clearDownloads())
      }
      .width('100%')

      Row() {
        this.actionButton('CToken', () => this.checkToken())
        this.actionButton('UToken', () => this.updateToken())
        this.actionButton('LBak', () => this.backupData())
        this.actionButton('LUpdate', () => this.restoreData())
        this.actionButton('scan', () => this.scanLan())
      }
      .width('100%')

      Text(this.logText)
        .fontSize(12)
        .width('100%')
        .maxLines(3)

      List() {
        ForEach(this.visibleAddresses(), (address: WebAddress) => {
          ListItem() {
            this.addressRow(address)
          }
        }, (address: WebAddress) => address.address)
      }
      .layoutWeight(1)
      .width('100%')

      Row() {
        Checkbox({ name: '全选', group: 'all' })
          .select(this.allJobsSelected)
          .enabled(false)
        Text('全选').fontSize(13)
        Checkbox({ name: 'quark', group: 'provider' })
          .select(this.quarkChecked)
          .onChange((checked: boolean) => this.selectQuark(checked))
        Text('quark').fontSize(13)
        Checkbox({ name: 'aliyun', group: 'provider' })
          .select(this.aliyunChecked)
          .onChange((checked: boolean) => this.selectAliyun(checked))
        Text('aliyun').fontSize(13)
      }
      .width('100%')
      .height(30)
      .onClick(() => this.selectAllJobs(!this.allJobsSelected))

      List() {
        ForEach(this.jobs, (job: TransferJob) => {
          ListItem() {
            this.jobRow(job)
          }
        }, (job: TransferJob) => `${job.jobId}-${job.selected}-${job.state}-${job.updatedAt}`)
      }
      .layoutWeight(3)
      .width('100%')

      Web({ src: this.rendererUrl, controller: this.webController })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .onPageEnd(() => {
          this.scheduleRenderedCapture(1000, false);
        })
        .onErrorReceive(() => {
          this.rejectPending(new Error('页面渲染失败'));
        })
        .width('100%')
        .height(40)
    }
    .width('100%')
    .height('100%')
    .padding(10)
    .backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Start)
  }
}

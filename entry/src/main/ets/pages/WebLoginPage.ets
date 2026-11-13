import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { AppContainer } from '../AppContainer';
import { LsLogger } from '../common/log/LsLogger';
import {
  AuthController,
  QUARK_CREDENTIAL_REVISION_KEY
} from '../domain/auth/AuthController';
import { CloudProviderType } from '../model/AppModels';

const TAG: string = 'WebLoginPage';
const ALIYUN_LOGIN_URL: string =
  'https://www.alipan.com/sign/in?spm=aliyundrive.index.0.0.7db16f60KDMVKJ';
const QUARK_LOGIN_URL: string = 'https://pan.quark.cn/list#/list/all';
const PC_USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';

interface WebLoginParams {
  provider?: string;
}

@Entry
@Component
struct WebLoginPage {
  @State saving: boolean = false;
  private initialUrl: string = '';
  private webController: webview.WebviewController = new webview.WebviewController();
  private authController: AuthController =
    new AuthController(AppContainer.getInstance().settingsRepository);

  aboutToAppear(): void {
    const params = router.getParams() as WebLoginParams;
    if (params?.provider === CloudProviderType.QUARK) {
      this.initialUrl = QUARK_LOGIN_URL;
    } else if (params?.provider === CloudProviderType.ALIYUN) {
      this.initialUrl = ALIYUN_LOGIN_URL;
    }
  }

  private loadInitialUrl(): void {
    if (this.initialUrl.length === 0) {
      return;
    }
    try {
      this.webController.loadUrl(this.initialUrl);
      LsLogger.info(TAG, `Login page loaded provider=${this.providerName()}`);
    } catch (error) {
      LsLogger.error(TAG, `Login page load failed: ${this.messageOf(error)}`);
      this.toast('页面加载失败，请检查网络后重试');
    }
  }

  private async updateAliyunToken(): Promise<void> {
    if (this.saving) {
      return;
    }
    this.saving = true;
    const result = await this.authController.captureAliyun(this.webController);
    this.saving = false;
    this.toast(result.isSuccess ? '更新成功！' : (result.error?.message ?? '更新失败！'));
  }

  private async updateQuarkToken(): Promise<void> {
    if (this.saving) {
      return;
    }
    this.saving = true;
    const result = await this.authController.captureQuark();
    this.saving = false;
    if (result.isSuccess) {
      AppStorage.setOrCreate<number>(QUARK_CREDENTIAL_REVISION_KEY, Date.now());
    }
    this.toast(result.isSuccess ? '更新成功！' : (result.error?.message ?? '更新失败！'));
  }

  private providerName(): string {
    return this.initialUrl === QUARK_LOGIN_URL ? CloudProviderType.QUARK :
      (this.initialUrl === ALIYUN_LOGIN_URL ? CloudProviderType.ALIYUN : 'none');
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private messageOf(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }

  @Builder
  private tokenButton(label: string, action: () => void) {
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
      .onClick(action)
  }

  build() {
    Column() {
      Row() {
        this.tokenButton('aliyunToken', () => this.updateAliyunToken())
        this.tokenButton('QuarkToken', () => this.updateQuarkToken())
      }
      .width('100%')
      .backgroundColor(Color.White)

      Web({ src: '', controller: this.webController })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        .userAgent(PC_USER_AGENT)
        .onControllerAttached(() => this.loadInitialUrl())
        .onErrorReceive(() => {
          LsLogger.warn(TAG, `Login page request failed provider=${this.providerName()}`);
        })
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(Color.White)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }
}

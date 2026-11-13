import { webview } from '@kit.ArkWeb';
import { AppError, AppErrorCode } from '../../common/error/AppError';
import { Result } from '../../common/result/Result';
import { SettingsRepository } from '../../config/SettingsRepository';
import { WebCredentialExtractor } from './WebCredentialExtractor';

const QUARK_URL: string = 'https://pan.quark.cn/';
export const QUARK_CREDENTIAL_REVISION_KEY: string = 'quarkCredentialRevision';

export class AuthController {
  private readonly settingsRepository: SettingsRepository;

  constructor(settingsRepository: SettingsRepository) {
    this.settingsRepository = settingsRepository;
  }

  async captureAliyun(controller: webview.WebviewController): Promise<Result<void>> {
    try {
      const rawValue = await controller.runJavaScript("window.localStorage.getItem('token')");
      const extracted = WebCredentialExtractor.extractAliyun(rawValue);
      const credentials = await this.settingsRepository.loadCredentials();
      if (extracted.accessToken.length > 0) {
        credentials.aliyunAccessToken = extracted.accessToken;
        credentials.aliyunLockToken = extracted.accessToken;
      }
      if (extracted.refreshToken.length > 0) {
        credentials.aliyunRefreshToken = extracted.refreshToken;
      }
      await this.settingsRepository.saveCredentials(credentials);
      return Result.success<void>(undefined);
    } catch (error) {
      return Result.failure<void>(this.toAppError(error));
    }
  }

  async captureQuark(): Promise<Result<void>> {
    try {
      const rawCookie = await webview.WebCookieManager.fetchCookie(QUARK_URL);
      const cookie = WebCredentialExtractor.validateQuarkCookie(rawCookie);
      const credentials = await this.settingsRepository.loadCredentials();
      credentials.quarkCookie = cookie;
      await this.settingsRepository.saveCredentials(credentials);
      await webview.WebCookieManager.saveCookieAsync();
      return Result.success<void>(undefined);
    } catch (error) {
      return Result.failure<void>(this.toAppError(error));
    }
  }

  private toAppError(error: Object): AppError {
    if (error instanceof AppError) {
      return error;
    }
    const message = error instanceof Error ? error.message : String(error);
    return new AppError(AppErrorCode.UNKNOWN, message);
  }
}

import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import wantConstant from '@ohos.ability.wantConstant';
import { AppError, AppErrorCode } from '../error/AppError';
import { LsLogger } from '../log/LsLogger';
import { Result } from '../result/Result';

const TAG: string = 'LinkActions';

export class LinkActions {
  static async copy(value: string): Promise<Result<void>> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value);
      await pasteboard.getSystemPasteboard().setData(data);
      LsLogger.info(TAG, 'Share link copied');
      return Result.success<void>(undefined);
    } catch (error) {
      const appError = LinkActions.errorOf('复制连接失败', error);
      LsLogger.error(TAG, appError.message);
      return Result.failure<void>(appError);
    }
  }

  static async open(context: common.UIAbilityContext, url: string): Promise<Result<void>> {
    try {
      await context.startAbility({
        action: wantConstant.Action.ACTION_VIEW_DATA,
        uri: url
      });
      return Result.success<void>(undefined);
    } catch (error) {
      const appError = LinkActions.errorOf('无法打开分享链接', error);
      LsLogger.error(TAG, appError.message);
      return Result.failure<void>(appError);
    }
  }

  private static errorOf(message: string, error: Object): AppError {
    const detail = error instanceof Error ? error.message : String(error);
    return new AppError(AppErrorCode.UNKNOWN, `${message}: ${detail}`);
  }
}

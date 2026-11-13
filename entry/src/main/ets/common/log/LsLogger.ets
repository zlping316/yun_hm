import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x3900;
const SECRET_PATTERN: RegExp =
  /(authorization|cookie|access_token|refresh_token|share_pwd|password)(["'=:\s]+)([^,\s}"']+)/gi;

export class LsLogger {
  static info(tag: string, message: string): void {
    hilog.info(DOMAIN, tag, '%{public}s', LsLogger.redact(message));
  }

  static warn(tag: string, message: string): void {
    hilog.warn(DOMAIN, tag, '%{public}s', LsLogger.redact(message));
  }

  static error(tag: string, message: string): void {
    hilog.error(DOMAIN, tag, '%{public}s', LsLogger.redact(message));
  }

  static redact(message: string): string {
    return message
      .replace(SECRET_PATTERN, '$1$2***')
      .replace(/([?&](token|auth|code|pwd)=)[^&\s]+/gi, '$1***');
  }
}

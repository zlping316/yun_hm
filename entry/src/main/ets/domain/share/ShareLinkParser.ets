import { AppError, AppErrorCode } from '../../common/error/AppError';
import { CloudProviderType } from '../../model/AppModels';

export interface ParsedShareLink {
  normalizedUrl: string;
  shareId: string;
  folderId: string;
}

export class ShareLinkParser {
  static parse(provider: CloudProviderType, rawUrl: string): ParsedShareLink {
    const normalizedUrl = ShareLinkParser.normalize(rawUrl);
    const segments = normalizedUrl.split('/').filter((value: string) => value.length > 0);
    const shareIndex = segments.findIndex((value: string) => value === 's');
    if (shareIndex < 0 || shareIndex + 1 >= segments.length) {
      throw new AppError(AppErrorCode.INVALID_INPUT, '分享链接格式不正确');
    }
    const host = segments[1].toLowerCase();
    if (!ShareLinkParser.matchesProvider(provider, host)) {
      throw new AppError(AppErrorCode.INVALID_INPUT, '分享链接与当前云盘不匹配');
    }
    const folderIndex = segments.findIndex((value: string) => value === 'folder');
    return {
      normalizedUrl: normalizedUrl,
      shareId: segments[shareIndex + 1],
      folderId: folderIndex >= 0 && folderIndex + 1 < segments.length ? segments[folderIndex + 1] :
        (provider === CloudProviderType.ALIYUN ? 'root' : '0')
    };
  }

  private static normalize(rawUrl: string): string {
    let value = rawUrl.trim();
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = `https://${value}`;
    }
    const fragmentIndex = value.indexOf('#');
    if (fragmentIndex >= 0) {
      value = value.substring(0, fragmentIndex);
    }
    const queryIndex = value.indexOf('?');
    if (queryIndex >= 0) {
      value = value.substring(0, queryIndex);
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  private static matchesProvider(provider: CloudProviderType, host: string): boolean {
    if (provider === CloudProviderType.ALIYUN) {
      return host.includes('alipan.com') || host.includes('aliyundrive.com');
    }
    return host.includes('pan.quark.cn');
  }
}

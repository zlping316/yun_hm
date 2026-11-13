import { AppError, AppErrorCode } from '../../common/error/AppError';
import { Result } from '../../common/result/Result';
import { WebAddress } from '../../model/AppModels';
import { ParsedDownload, ParserMainResult } from '../../model/parser/ParserModels';

export class ParserUtils {
  static hostOf(address: string): string {
    const match = /^(https?:\/\/[^/]+)/.exec(address);
    if (match === null || match.length < 2) {
      throw new AppError(AppErrorCode.INVALID_INPUT, `地址缺少有效 host: ${address}`);
    }
    return match[1];
  }

  static pathOf(address: string): string {
    const withoutHost = address.replace(/^(https?:\/\/[^/]+)/, '');
    const queryIndex = withoutHost.indexOf('?');
    return queryIndex >= 0 ? withoutHost.substring(0, queryIndex) : withoutHost;
  }

  static queryValue(address: string, key: string): string {
    const queryIndex = address.indexOf('?');
    if (queryIndex < 0) {
      return '';
    }
    const pairs = address.substring(queryIndex + 1).split('&');
    for (const pair of pairs) {
      const separator = pair.indexOf('=');
      const pairKey = separator >= 0 ? pair.substring(0, separator) : pair;
      if (decodeURIComponent(pairKey) === key) {
        return decodeURIComponent(separator >= 0 ? pair.substring(separator + 1) : '');
      }
    }
    return '';
  }

  static extractAll(content: string, pattern: RegExp): string[] {
    const values: string[] = [];
    let match = pattern.exec(content);
    while (match !== null) {
      if (match.length > 1 && match[1].length > 0 && !values.includes(match[1])) {
        values.push(match[1]);
      }
      match = pattern.exec(content);
    }
    return values;
  }

  static first(content: string, pattern: RegExp): string {
    const match = pattern.exec(content);
    return match !== null && match.length > 1 ? match[1] : '';
  }

  static page(address: WebAddress, url: string): WebAddress {
    return {
      type: address.type,
      subType: address.subType,
      address: url,
      selected: false
    };
  }

  static mainResult(
    pages: WebAddress[],
    totalCount: number,
    skippedCount: number
  ): Result<ParserMainResult> {
    return Result.success<ParserMainResult>({
      pages: pages,
      totalCount: totalCount,
      skippedCount: skippedCount
    });
  }

  static download(
    source: WebAddress,
    name: string,
    downloadUrl: string,
    key: string
  ): ParsedDownload {
    return {
      name: name,
      downloadUrl: downloadUrl,
      key: key,
      source: source
    };
  }
}

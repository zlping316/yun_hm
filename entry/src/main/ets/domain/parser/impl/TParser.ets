import { Result } from '../../../common/result/Result';
import { WebAddress } from '../../../model/AppModels';
import { ParsedDownload, ParserMainResult } from '../../../model/parser/ParserModels';
import { PageParser } from '../PageParser';
import { ParserUtils } from '../ParserUtils';

export class TParser implements PageParser {
  readonly type: string = '0';
  readonly name: string = 'T';

  async parseMainPage(
    address: WebAddress,
    content: string,
    uploadedKeys: Set<string>
  ): Promise<Result<ParserMainResult>> {
    const host = ParserUtils.hostOf(address.address);
    const rolePaths = ParserUtils.extractAll(
      content,
      /href=\\?["'](\/index\.php\/vod\/role\/id\/\d+\.html)\\?["']/g
    );
    const pages: WebAddress[] = [];
    let skippedCount = 0;
    rolePaths.forEach((path: string) => {
      if (uploadedKeys.has(path)) {
        skippedCount++;
      } else {
        pages.push(ParserUtils.page(address, `${host}${path}`));
      }
    });
    return ParserUtils.mainResult(pages, rolePaths.length, skippedCount);
  }

  async parseNestedPages(
    address: WebAddress,
    content: string,
    uploadedKeys: Set<string>
  ): Promise<Result<ParserMainResult>> {
    const host = ParserUtils.hostOf(address.address);
    const detailPaths = ParserUtils.extractAll(
      content,
      /window\.location\.href=\\?['"](\/index\.php\/vod\/detail\/id\/\d+\.html)\\?['"]/g
    );
    const pages: WebAddress[] = [];
    let skippedCount = 0;
    detailPaths.forEach((path: string) => {
      if (uploadedKeys.has(path)) {
        skippedCount++;
      } else {
        pages.push(ParserUtils.page(address, `${host}${path}`));
      }
    });
    return ParserUtils.mainResult(pages, detailPaths.length, skippedCount);
  }

  async parseSubPage(address: WebAddress, content: string): Promise<Result<ParsedDownload[]>> {
    const normalized = this.normalizeContent(content);
    const data = ParserUtils.first(
      normalized,
      /id=\\?["']bfz\\?["'][^>]*data-user-name=\\?["']([^"']+)\\?["']/g
    );
    const separator = data.indexOf('$');
    const rawUrl = separator >= 0 ? data.substring(separator + 1) : '';
    const fallbackName = separator >= 0 ? data.substring(0, separator) : '';
    const titleName = this.extractName(normalized);
    const name = titleName.length > 0 ? titleName : fallbackName;
    const url = rawUrl.replace(/&amp;/g, '&');
    const downloads: ParsedDownload[] = [];
    if (/^https?:\/\/[^"'\s<>]+?\.m3u8(?:$|[?#])/.test(url)) {
      downloads.push(ParserUtils.download(address, this.cleanName(name), url, ParserUtils.pathOf(address.address)));
    }
    return Result.success<ParsedDownload[]>(downloads);
  }

  private normalizeContent(content: string): string {
    return content
      .replace(/\\\//g, '/')
      .replace(/\\u0026/g, '&')
      .replace(/\\u003D/g, '=')
      .replace(/\\u003F/g, '?')
      .replace(/\\u003C/g, '<')
      .replace(/\\u003E/g, '>');
  }

  private extractName(content: string): string {
    const titleName = ParserUtils.first(content, /<title>《?([^《》<]+?)》?-/g);
    if (titleName.length > 0) {
      return titleName;
    }
    return ParserUtils.first(content, /<h2>片名：?《?([^《》<]+?)》?<\/h2>/g);
  }

  private cleanName(name: string): string {
    return name
      .replace(/^《/, '')
      .replace(/》$/, '')
      .trim();
  }
}

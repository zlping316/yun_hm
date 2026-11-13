import { http } from '@kit.NetworkKit';
import { AppError, AppErrorCode } from '../../../common/error/AppError';
import { Result } from '../../../common/result/Result';
import { HttpClient } from '../../../data/network/HttpClient';
import { WebAddress } from '../../../model/AppModels';
import { ParsedDownload, ParserMainResult } from '../../../model/parser/ParserModels';
import { PageParser } from '../PageParser';
import { ParserUtils } from '../ParserUtils';

export class AParser implements PageParser {
  readonly type: string = '1';
  readonly name: string = 'A';
  private readonly client: HttpClient;

  constructor(client: HttpClient) {
    this.client = client;
  }

  async parseMainPage(
    address: WebAddress,
    content: string,
    uploadedKeys: Set<string>
  ): Promise<Result<ParserMainResult>> {
    const host = ParserUtils.hostOf(address.address);
    const paths = ParserUtils.extractAll(
      content,
      /\\n\\u003Ca href=\\"\/index\.php\/&amp;m=(.*?)\\" title=/g
    );
    const pages: WebAddress[] = [];
    let skippedCount = 0;
    paths.forEach((path: string) => {
      if (uploadedKeys.has(path)) {
        skippedCount++;
      } else {
        pages.push(ParserUtils.page(address, `${host}/index.php/&m=${path}`));
      }
    });
    return ParserUtils.mainResult(pages, paths.length, skippedCount);
  }

  async parseSubPage(address: WebAddress, content: string): Promise<Result<ParsedDownload[]>> {
    const host = ParserUtils.hostOf(address.address).replace(/^http:/, 'https:');
    const urlKeys = ParserUtils.extractAll(
      content,
      /"link_next\\":\\"\\",\\"link_pre\\":\\"\\",\\"url\\":\\"(.*?)\\",\\"url_next\\":\\"\\",\\"from\\":\\"dplayer/g
    );
    const name = ParserUtils.first(content, /class=\\"content-title\\">(.*?)\\u003C\/h1>/g);
    const key = ParserUtils.queryValue(address.address.replace('/&m=', '?m='), 'm');
    const downloads: ParsedDownload[] = [];
    for (const urlKey of urlKeys) {
      const response = await this.client.requestText({
        url: `${host}/addons/dplayer/?url=${encodeURIComponent(urlKey)}&jump=&t=0.3646015373459002`,
        method: http.RequestMethod.GET,
        retryable: true
      });
      if (!response.isSuccess || response.value === undefined) {
        return Result.failure<ParsedDownload[]>(response.error ??
          new AppError(AppErrorCode.NETWORK, 'DPlayer 地址解析失败'));
      }
      const downloadUrl = ParserUtils.first(response.value, /var urls = "(.*?)";/g);
      if (downloadUrl.length > 0) {
        downloads.push(ParserUtils.download(address, name, downloadUrl, key));
      }
    }
    return Result.success<ParsedDownload[]>(downloads);
  }
}

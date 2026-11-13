import { Result } from '../../../common/result/Result';
import { WebAddress } from '../../../model/AppModels';
import { ParsedDownload, ParserMainResult } from '../../../model/parser/ParserModels';
import { PageParser } from '../PageParser';
import { ParserUtils } from '../ParserUtils';

export class F404Parser implements PageParser {
  readonly type: string = '3';
  readonly name: string = 'F404';

  async parseMainPage(
    address: WebAddress,
    content: string,
    uploadedKeys: Set<string>
  ): Promise<Result<ParserMainResult>> {
    const host = ParserUtils.hostOf(address.address);
    const paths = ParserUtils.extractAll(
      content,
      /class=\\"content\\">\\n\\t\\t\\t\\t\\t\\t\\t\\u003Ca href=\\"(.*?)\\" title=\\"/g
    );
    const pages: WebAddress[] = [];
    let skippedCount = 0;
    paths.forEach((path: string) => {
      const key = this.keyOf(path);
      if (uploadedKeys.has(key)) {
        skippedCount++;
      } else {
        pages.push(ParserUtils.page(address, `${host}${path}/`));
      }
    });
    return ParserUtils.mainResult(pages, paths.length, skippedCount);
  }

  async parseSubPage(address: WebAddress, content: string): Promise<Result<ParsedDownload[]>> {
    const rawUrl = ParserUtils.first(content, /\\"link_pre\\":\\"\\",\\"url\\":\\"(.*?)\\",\\"url_next/g);
    const name = ParserUtils.first(content, /id=\\"Video-Title\\">(.*?)\\u003C\/h3>/g);
    const url = rawUrl.replace(/\\/g, '');
    if (url.length === 0) {
      return Result.success<ParsedDownload[]>([]);
    }
    return Result.success<ParsedDownload[]>([
      ParserUtils.download(address, name, url, this.keyOf(address.address))
    ]);
  }

  private keyOf(path: string): string {
    const values = path.split('/').filter((value: string) => value.length > 0);
    return values.length >= 5 ? values[values.length - 5] : '';
  }
}

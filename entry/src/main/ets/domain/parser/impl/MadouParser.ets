import { Result } from '../../../common/result/Result';
import { WebAddress } from '../../../model/AppModels';
import { ParsedDownload, ParserMainResult } from '../../../model/parser/ParserModels';
import { PageParser } from '../PageParser';
import { ParserUtils } from '../ParserUtils';

export class MadouParser implements PageParser {
  readonly type: string = '4';
  readonly name: string = '麻豆';

  async parseMainPage(
    address: WebAddress,
    content: string,
    uploadedKeys: Set<string>
  ): Promise<Result<ParserMainResult>> {
    const host = ParserUtils.hostOf(address.address);
    const paths = ParserUtils.extractAll(
      content,
      /u003Carticle>\\n\\u003Ca href=\\"(.*?)\\">\\n\\u003Cfigure>\\u003Cimg/g
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
    const rawValue = ParserUtils.first(
      content,
      /data-user-name=\\"(.*?)\\">\\u003C\/mark>\\n\\u003Cscript>/g
    ).replace(/\\/g, '');
    const separator = rawValue.indexOf('$');
    const url = separator >= 0 ? rawValue.substring(separator + 1) : rawValue;
    const name = ParserUtils.first(
      content,
      /style=\\"text-align: center; color: #000000;font-weight: 600;\\">标题：(.*?)\\u003C\/cite>/g
    );
    if (url.length === 0) {
      return Result.success<ParsedDownload[]>([]);
    }
    return Result.success<ParsedDownload[]>([
      ParserUtils.download(address, name, url, this.keyOf(address.address))
    ]);
  }

  private keyOf(path: string): string {
    const normalized = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    const values = normalized.split('/').filter((value: string) => value.length > 0);
    return values.length > 0 ? values[values.length - 1] : '';
  }
}

import { Result } from '../../../common/result/Result';
import { WebAddress } from '../../../model/AppModels';
import { ParsedDownload, ParserMainResult } from '../../../model/parser/ParserModels';
import { PageParser } from '../PageParser';
import { ParserUtils } from '../ParserUtils';

export class HuaDuParser implements PageParser {
  readonly type: string = '2';
  readonly name: string = '花都';

  async parseMainPage(
    address: WebAddress,
    content: string,
    uploadedKeys: Set<string>
  ): Promise<Result<ParserMainResult>> {
    const host = ParserUtils.hostOf(address.address);
    const ids = ParserUtils.extractAll(
      content,
      /href=\\"\/voddetail([^"\\]+?)\.html\\"/g
    );
    const pages: WebAddress[] = [];
    let skippedCount = 0;
    ids.forEach((id: string) => {
      const path = `/vodplay/${id}-1-1.html`;
      if (uploadedKeys.has(path)) {
        skippedCount++;
      } else {
        pages.push(ParserUtils.page(address, `${host}${path}`));
      }
    });
    return ParserUtils.mainResult(pages, ids.length, skippedCount);
  }

  async parseSubPage(address: WebAddress, content: string): Promise<Result<ParsedDownload[]>> {
    const rawUrl = ParserUtils.first(
      content,
      /(https?:\\?\/\\?\/[^"'\s<]+?\.m3u8)/g
    );
    const rawName = ParserUtils.first(content, /title>正在播放 《(.*?)》/g);
    const name = rawName.replace(' - 花都影视-花都资源', '');
    if (rawUrl.length === 0 || name.length === 0) {
      return Result.success<ParsedDownload[]>([]);
    }
    let url = rawUrl.replace(/\\/g, '').replace(/&amp;/g, '&');
    return Result.success<ParsedDownload[]>([
      ParserUtils.download(address, name, url, ParserUtils.pathOf(address.address))
    ]);
  }
}

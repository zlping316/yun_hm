import { Result } from '../../common/result/Result';
import { WebAddress } from '../../model/AppModels';
import { ParsedDownload, ParserMainResult } from '../../model/parser/ParserModels';

export interface PageParser {
  readonly type: string;
  readonly name: string;

  parseMainPage(
    address: WebAddress,
    content: string,
    uploadedKeys: Set<string>
  ): Promise<Result<ParserMainResult>>;

  parseNestedPages?(
    address: WebAddress,
    content: string,
    uploadedKeys: Set<string>
  ): Promise<Result<ParserMainResult>>;

  parseSubPage(address: WebAddress, content: string): Promise<Result<ParsedDownload[]>>;
}

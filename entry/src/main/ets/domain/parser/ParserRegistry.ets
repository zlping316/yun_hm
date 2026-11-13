import { AppError, AppErrorCode } from '../../common/error/AppError';
import { PageParser } from './PageParser';

export class ParserRegistry {
  private readonly parsers: Map<string, PageParser> = new Map<string, PageParser>();

  constructor(parsers: PageParser[]) {
    parsers.forEach((parser: PageParser) => this.parsers.set(parser.type, parser));
  }

  get(type: string): PageParser {
    const parser = this.parsers.get(type);
    if (parser === undefined) {
      throw new AppError(AppErrorCode.UNSUPPORTED, `不支持的解析器类型: ${type}`);
    }
    return parser;
  }

  list(): PageParser[] {
    return Array.from(this.parsers.values());
  }
}

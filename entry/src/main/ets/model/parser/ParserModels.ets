import { WebAddress } from '../AppModels';

export interface ParserMainResult {
  pages: WebAddress[];
  totalCount: number;
  skippedCount: number;
}

export interface ParsedDownload {
  name: string;
  downloadUrl: string;
  key: string;
  source: WebAddress;
}

import { Result } from '../../common/result/Result';
import { CloudProviderType } from '../../model/AppModels';

export interface SearchCandidate {
  shareUrl: string;
  shareCode: string;
  title?: string;
}

export enum SearchExecutionMode {
  DIRECT = 'direct',
  WEB_HTML = 'web_html',
  INTERACTIVE_WEB = 'interactive_web'
}

export interface SearchProvider {
  readonly id: string;
  readonly name: string;
  readonly providerType: CloudProviderType;
  readonly executionMode: SearchExecutionMode;

  search(keyword: string, dynamicHtml?: string): Promise<Result<SearchCandidate[]>>;
}

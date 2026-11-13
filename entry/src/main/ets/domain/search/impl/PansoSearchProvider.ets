import { http } from '@kit.NetworkKit';
import { AppError, AppErrorCode } from '../../../common/error/AppError';
import { LsLogger } from '../../../common/log/LsLogger';
import { Result } from '../../../common/result/Result';
import { HttpClient } from '../../../data/network/HttpClient';
import { HttpRequestConfig } from '../../../data/network/HttpTypes';
import { CloudProviderType } from '../../../model/AppModels';
import { SearchParsing } from '../SearchParsing';
import { SearchCandidate, SearchExecutionMode } from '../SearchProvider';
import { InteractiveSearchProvider, WebSearchItem } from '../WebSearchContracts';

const TAG: string = 'PansoSearch';

interface PansoAdvParams {
  wechat_pwd: string;
  search_code: string;
  platform: string;
  fp_data: string;
}

interface PansoSearchRequest {
  page: number;
  q: string;
  exact: boolean;
  user_distinct: boolean;
  format: string[];
  share_time: string;
  share_year: string;
  size: number;
  order: string;
  type: string;
  search_ticket: string;
  exclude_user: string[];
  adv_params: PansoAdvParams;
}

interface PansoHeaders {
  'Content-Type': string;
  Origin: string;
  Referer: string;
}

export class PansoSearchProvider implements InteractiveSearchProvider {
  readonly id: string;
  readonly name: string = '盘搜';
  readonly providerType: CloudProviderType;
  readonly executionMode: SearchExecutionMode = SearchExecutionMode.WEB_HTML;
  readonly visibleDuringSearch: boolean = false;
  private readonly client: HttpClient;

  constructor(client: HttpClient, providerType: CloudProviderType) {
    this.client = client;
    this.providerType = providerType;
    this.id = `${providerType}_panso`;
  }

  searchUrl(keyword: string): string {
    const type = this.providerType === CloudProviderType.ALIYUN ? 'ALY' : 'QUARK';
    return `https://panso.vip/search?q=${encodeURIComponent(keyword)}&type=${type}`;
  }

  async loadSearchItems(_keyword: string): Promise<Result<WebSearchItem[]>> {
    return Result.failure<WebSearchItem[]>(
      new AppError(AppErrorCode.UNSUPPORTED, '盘搜使用动态页面回退')
    );
  }

  parseSearchItems(content: string): WebSearchItem[] {
    return SearchParsing.extractDocumentIds(content, 10)
      .map((key: string): WebSearchItem => {
        const item: WebSearchItem = { key: key, title: '' };
        return item;
      });
  }

  detailUrl(item: WebSearchItem): string {
    return `https://panso.vip/doc/${encodeURIComponent(item.key)}`;
  }

  challengeScript(): string {
    return `(() => {
      const text = document.body ? document.body.innerText : '';
      return text.includes('设备校验') || text.includes('安全验证') ||
        text.includes('验证码') ? 'true' : 'false';
    })()`;
  }

  triggerScript(_item: WebSearchItem): string {
    return `'ready'`;
  }

  extractScript(): string {
    const host = this.providerType === CloudProviderType.ALIYUN ? 'alipan.com/s/' : 'pan.quark.cn/s/';
    return `(() => {
      const values = Array.from(document.querySelectorAll('a, input'))
        .map((element) => element.href || element.value || element.textContent || '');
      return values.find((value) => value.includes('${host}')) || '';
    })()`;
  }

  async search(_keyword: string, dynamicHtml: string = ''): Promise<Result<SearchCandidate[]>> {
    if (dynamicHtml.length === 0) {
      return this.searchByApi(_keyword);
    }
    return this.resolveDocuments(SearchParsing.extractDocumentIds(dynamicHtml, 10));
  }

  private async searchByApi(keyword: string): Promise<Result<SearchCandidate[]>> {
    const type = this.providerType === CloudProviderType.ALIYUN ? 'ALY' : 'QUARK';
    const advParams: PansoAdvParams = {
      wechat_pwd: '',
      search_code: '',
      platform: 'mobile',
      fp_data: ''
    };
    const request: PansoSearchRequest = {
      page: 1,
      q: keyword,
      exact: false,
      user_distinct: false,
      format: [],
      share_time: '',
      share_year: '',
      size: 10,
      order: '',
      type: type,
      search_ticket: '',
      exclude_user: [],
      adv_params: advParams
    };
    const headers: PansoHeaders = {
      'Content-Type': 'application/json',
      'Origin': 'https://panso.vip',
      'Referer': this.searchUrl(keyword)
    };
    const config: HttpRequestConfig = {
      url: 'https://panso.vip/v1/search/disk',
      method: http.RequestMethod.POST,
      headers: headers,
      body: JSON.stringify(request),
      retryable: false
    };
    const response = await this.client.requestText(config);
    if (!response.isSuccess || response.value === undefined) {
      return Result.failure<SearchCandidate[]>(response.error ??
        new AppError(AppErrorCode.NETWORK, '盘搜接口请求失败'));
    }
    const directLinks = SearchParsing.extractShareLinks(response.value, this.providerType, 10);
    if (directLinks.length > 0) {
      return Result.success<SearchCandidate[]>(directLinks);
    }
    const ids = SearchParsing.extractMatches(response.value, /"doc_id"\s*:\s*"?([^",}]+)"?/g, 10);
    return this.resolveDocuments(ids);
  }

  private async resolveDocuments(documentIds: string[]): Promise<Result<SearchCandidate[]>> {
    const candidates: SearchCandidate[] = [];
    for (const documentId of documentIds) {
      const response = await this.client.requestText({
        url: `https://panso.vip/doc/${encodeURIComponent(documentId)}`,
        method: http.RequestMethod.GET,
        retryable: true
      });
      if (response.isSuccess && response.value !== undefined) {
        candidates.push(...SearchParsing.extractShareLinks(response.value, this.providerType));
      } else {
        LsLogger.warn(TAG, `Detail skipped id=${documentId}`);
      }
    }
    return Result.success<SearchCandidate[]>(candidates);
  }
}

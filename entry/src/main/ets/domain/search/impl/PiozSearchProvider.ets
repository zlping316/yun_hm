import { http } from '@kit.NetworkKit';
import { AppError, AppErrorCode } from '../../../common/error/AppError';
import { Result } from '../../../common/result/Result';
import { HttpClient } from '../../../data/network/HttpClient';
import { CloudProviderType } from '../../../model/AppModels';
import { SearchParsing } from '../SearchParsing';
import { SearchCandidate, SearchExecutionMode } from '../SearchProvider';
import { InteractiveSearchProvider, WebSearchItem } from '../WebSearchContracts';

const FIRST_PAGE_RESULT_LIMIT: number = 20;

export class PiozSearchProvider implements InteractiveSearchProvider {
  readonly id: string = 'quark_pioz';
  readonly name: string = 'KK小站';
  readonly providerType: CloudProviderType = CloudProviderType.QUARK;
  readonly executionMode: SearchExecutionMode = SearchExecutionMode.INTERACTIVE_WEB;
  readonly visibleDuringSearch: boolean = false;
  private readonly client: HttpClient;

  constructor(client: HttpClient) {
    this.client = client;
  }

  async loadSearchItems(keyword: string): Promise<Result<WebSearchItem[]>> {
    const response = await this.client.requestText({
      url: this.searchUrl(keyword),
      method: http.RequestMethod.GET,
      retryable: true
    });
    if (!response.isSuccess || response.value === undefined) {
      return Result.failure<WebSearchItem[]>(response.error ??
        new AppError(AppErrorCode.NETWORK, 'KK小站搜索请求失败'));
    }
    return Result.success<WebSearchItem[]>(this.parseSearchItems(response.value));
  }

  searchUrl(keyword: string): string {
    return `https://www.pioz.cn/search?q=${encodeURIComponent(keyword)}`;
  }

  async search(_keyword: string, _dynamicHtml: string = ''): Promise<Result<SearchCandidate[]>> {
    return Result.success<SearchCandidate[]>([]);
  }

  parseSearchItems(content: string): WebSearchItem[] {
    return SearchParsing.extractDetailItems(content, FIRST_PAGE_RESULT_LIMIT);
  }

  detailUrl(item: WebSearchItem): string {
    return `https://www.pioz.cn/detail/${encodeURIComponent(item.key)}`;
  }

  challengeScript(): string {
    return `(() => {
      const text = document.body ? document.body.innerText : '';
      const nodes = Array.from(document.querySelectorAll(
        '#turnstileModal, iframe[src*="/turnstile/challenge"], [class*="captcha"], [id*="captcha"]'
      ));
      const visible = nodes.some((node) => {
        const style = window.getComputedStyle(node);
        const rect = node.getBoundingClientRect();
        return style.display !== 'none' && style.visibility !== 'hidden' &&
          rect.width > 0 && rect.height > 0;
      });
      return visible || text.includes('安全验证') || text.includes('人机验证') ?
        'true' : 'false';
    })()`;
  }

  triggerScript(_item: WebSearchItem): string {
    return `(() => {
      const button = document.querySelector('#downloadBtn');
      if (!button) return 'missing';
      button.click();
      return 'clicked';
    })()`;
  }

  extractScript(): string {
    return `(() => {
      const input = document.querySelector('#modalLinkInput');
      const open = document.querySelector('#modalOpenBtn');
      const value = input && input.value ? input.value : (open && open.href ? open.href : '');
      return value.includes('pan.quark.cn/s/') ? value : '';
    })()`;
  }
}

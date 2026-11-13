import { http } from '@kit.NetworkKit';
import { AppError, AppErrorCode } from '../../../common/error/AppError';
import { Result } from '../../../common/result/Result';
import { HttpClient } from '../../../data/network/HttpClient';
import { CloudProviderType } from '../../../model/AppModels';
import { SearchParsing } from '../SearchParsing';
import { SearchCandidate, SearchExecutionMode, SearchProvider } from '../SearchProvider';

interface MySiteAttributes {
  slug?: string;
}

interface MySiteData {
  attributes?: MySiteAttributes;
}

interface MySiteResponse {
  data?: MySiteData[];
}

export class MySiteSearchProvider implements SearchProvider {
  readonly id: string;
  readonly name: string = '我的小站';
  readonly providerType: CloudProviderType;
  readonly executionMode: SearchExecutionMode = SearchExecutionMode.DIRECT;
  private readonly client: HttpClient;

  constructor(client: HttpClient, providerType: CloudProviderType) {
    this.client = client;
    this.providerType = providerType;
    this.id = `${providerType}_mysite`;
  }

  async search(keyword: string): Promise<Result<SearchCandidate[]>> {
    const query = encodeURIComponent(`${keyword} tag:video`);
    const response = await this.client.requestJson<MySiteResponse>({
      url: `https://pan666.net/api/discussions?filter%5Bq%5D=${query}&filter%5Btag%5D=video&sort&page%5Boffset%5D=0`,
      method: http.RequestMethod.GET,
      retryable: true
    });
    if (!response.isSuccess || response.value === undefined) {
      return Result.failure<SearchCandidate[]>(response.error ??
        new AppError(AppErrorCode.NETWORK, '我的小站搜索失败'));
    }
    const candidates: SearchCandidate[] = [];
    const items = response.value.data ?? [];
    const count = Math.min(items.length, 5);
    for (let index = 0; index < count; index++) {
      const slug = items[index].attributes?.slug ?? '';
      if (slug.length === 0) {
        continue;
      }
      const detail = await this.client.requestText({
        url: `https://pan666.net/api/discussions/${encodeURIComponent(slug)}?bySlug=true&page%5Bnear%5D=0`,
        method: http.RequestMethod.GET,
        retryable: true
      });
      if (detail.isSuccess && detail.value !== undefined) {
        candidates.push(...SearchParsing.extractShareLinks(detail.value, this.providerType));
      }
    }
    return Result.success<SearchCandidate[]>(candidates);
  }
}

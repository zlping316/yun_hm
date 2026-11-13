import { http } from '@kit.NetworkKit';
import { AppError, AppErrorCode } from '../../../common/error/AppError';
import { Result } from '../../../common/result/Result';
import { HttpClient } from '../../../data/network/HttpClient';
import { CloudProviderType } from '../../../model/AppModels';
import { SearchParsing } from '../SearchParsing';
import { SearchCandidate, SearchExecutionMode, SearchProvider } from '../SearchProvider';

export class QileSearchProvider implements SearchProvider {
  readonly id: string = 'aliyun_qile';
  readonly name: string = '奇乐搜';
  readonly providerType: CloudProviderType = CloudProviderType.ALIYUN;
  readonly executionMode: SearchExecutionMode = SearchExecutionMode.DIRECT;
  private readonly client: HttpClient;

  constructor(client: HttpClient) {
    this.client = client;
  }

  async search(keyword: string): Promise<Result<SearchCandidate[]>> {
    const response = await this.client.requestText({
      url: `https://www.qileso.com/?s=${encodeURIComponent(keyword)}&range=1`,
      method: http.RequestMethod.GET,
      retryable: true
    });
    if (!response.isSuccess || response.value === undefined) {
      return Result.failure<SearchCandidate[]>(response.error ??
        new AppError(AppErrorCode.NETWORK, '奇乐搜请求失败'));
    }
    const detailUrls = SearchParsing.extractMatches(response.value, /<a class="mr-1" href="(.*?)"/g);
    const candidates: SearchCandidate[] = [];
    const count = Math.min(detailUrls.length, 5);
    for (let index = 0; index < count; index++) {
      const detail = await this.client.requestText({
        url: detailUrls[index],
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

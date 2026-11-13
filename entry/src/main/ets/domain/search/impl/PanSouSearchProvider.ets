import { http } from '@kit.NetworkKit';
import { AppError, AppErrorCode } from '../../../common/error/AppError';
import { LsLogger } from '../../../common/log/LsLogger';
import { Result } from '../../../common/result/Result';
import { HttpClient } from '../../../data/network/HttpClient';
import { CloudProviderType } from '../../../model/AppModels';
import { SearchCandidate, SearchExecutionMode, SearchProvider } from '../SearchProvider';

const TAG: string = 'PanSouSearch';
const PRIMARY_ENDPOINT: string = 'https://pansou.noisework.cn';
const BACKUP_ENDPOINT: string = 'https://so.252035.xyz';

interface PanSouItem {
  url?: string;
  password?: string;
  note?: string;
}

interface PanSouMerged {
  quark?: PanSouItem[];
}

interface PanSouData {
  merged_by_type?: PanSouMerged;
}

interface PanSouResponse {
  data?: PanSouData;
}

export class PanSouSearchProvider implements SearchProvider {
  readonly id: string = 'quark_pansou';
  readonly name: string = 'PanSou';
  readonly providerType: CloudProviderType = CloudProviderType.QUARK;
  readonly executionMode: SearchExecutionMode = SearchExecutionMode.DIRECT;
  private readonly client: HttpClient;

  constructor(client: HttpClient) {
    this.client = client;
  }

  async search(keyword: string): Promise<Result<SearchCandidate[]>> {
    const primary = await this.request(PRIMARY_ENDPOINT, keyword);
    if (primary.isSuccess) {
      return primary;
    }
    LsLogger.warn(TAG, 'Primary endpoint failed, switching to backup');
    const backup = await this.request(BACKUP_ENDPOINT, keyword);
    if (backup.isSuccess) {
      return backup;
    }
    LsLogger.warn(TAG, 'Backup endpoint failed');
    return Result.failure<SearchCandidate[]>(backup.error ??
      new AppError(AppErrorCode.NETWORK, 'PanSou 搜索失败'));
  }

  private async request(endpoint: string, keyword: string): Promise<Result<SearchCandidate[]>> {
    const response = await this.client.requestJson<PanSouResponse>({
      url: `${endpoint}/api/search?kw=${encodeURIComponent(keyword)}&cloud_types=quark&res=merge`,
      method: http.RequestMethod.GET,
      retryable: true
    });
    if (!response.isSuccess || response.value === undefined) {
      return Result.failure<SearchCandidate[]>(response.error ??
        new AppError(AppErrorCode.NETWORK, 'PanSou 请求失败'));
    }
    return PanSouSearchProvider.parseResponse(response.value);
  }

  static parseResponse(response: PanSouResponse): Result<SearchCandidate[]> {
    if (response.data === undefined || response.data.merged_by_type === undefined) {
      return Result.failure<SearchCandidate[]>(
        new AppError(AppErrorCode.PARSE, 'PanSou 返回结构异常')
      );
    }
    const candidates: SearchCandidate[] = [];
    const seen = new Set<string>();
    const items = response.data.merged_by_type.quark ?? [];
    for (const item of items) {
      const url = item.url ?? '';
      if (!url.includes('pan.quark.cn/s/') || seen.has(url)) {
        continue;
      }
      seen.add(url);
      candidates.push({
        shareUrl: url,
        shareCode: item.password ?? '',
        title: item.note ?? ''
      });
      if (candidates.length >= 20) {
        break;
      }
    }
    return Result.success<SearchCandidate[]>(candidates);
  }
}

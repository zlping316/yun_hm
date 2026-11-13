import { AppError, AppErrorCode } from '../../common/error/AppError';
import { LsLogger } from '../../common/log/LsLogger';
import { Result } from '../../common/result/Result';
import { CloudProviderType, SearchResult } from '../../model/AppModels';
import { ProviderRegistry } from '../provider/ProviderRegistry';
import { ParsedShareLink, ShareLinkParser } from '../share/ShareLinkParser';
import { SearchCandidate, SearchProvider } from './SearchProvider';

const TAG: string = 'SearchRepository';

export interface SearchResolution {
  results: SearchResult[];
  failedCount: number;
}

export class SearchRepository {
  private readonly registry: ProviderRegistry;

  constructor(registry: ProviderRegistry) {
    this.registry = registry;
  }

  async search(
    provider: SearchProvider,
    keyword: string,
    dynamicHtml: string = ''
  ): Promise<Result<SearchResolution>> {
    const candidateResult = await provider.search(keyword, dynamicHtml);
    if (!candidateResult.isSuccess || candidateResult.value === undefined) {
      return Result.failure<SearchResolution>(candidateResult.error ??
        new AppError(AppErrorCode.UNKNOWN, `${provider.name} 搜索失败`));
    }
    return this.resolveCandidates(provider, candidateResult.value);
  }

  async resolveCandidates(
    provider: SearchProvider,
    candidates: SearchCandidate[]
  ): Promise<Result<SearchResolution>> {
    const results: SearchResult[] = [];
    const seen = new Set<string>();
    let failedCount = 0;
    const driveProvider = this.registry.get(provider.providerType);
    for (const candidate of candidates) {
      let parsed: ParsedShareLink;
      try {
        parsed = ShareLinkParser.parse(provider.providerType, candidate.shareUrl);
      } catch (_error) {
        failedCount++;
        continue;
      }
      if (seen.has(parsed.normalizedUrl)) {
        continue;
      }
      seen.add(parsed.normalizedUrl);
      const metadata = await driveProvider.getShareMetadata(parsed.shareId, candidate.shareCode);
      if (!metadata.isSuccess || metadata.value === undefined) {
        failedCount++;
        continue;
      }
      const metadataTitle = metadata.value.title.length > 0 ?
        metadata.value.title : metadata.value.displayName;
      results.push({
        id: `${provider.id}_${parsed.shareId}`,
        title: metadataTitle.length > 0 ? metadataTitle : (candidate.title ?? parsed.shareId),
        shareUrl: parsed.normalizedUrl,
        shareCode: candidate.shareCode,
        provider: provider.providerType,
        source: provider.name
      });
    }
    if (failedCount > 0) {
      LsLogger.warn(TAG, `Source=${provider.id}, accepted=${results.length}, failed=${failedCount}`);
    }
    return Result.success<SearchResolution>({
      results: results,
      failedCount: failedCount
    });
  }
}

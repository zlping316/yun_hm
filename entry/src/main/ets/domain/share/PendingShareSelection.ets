import { LsLogger } from '../../common/log/LsLogger';
import { CloudProviderType, SearchResult } from '../../model/AppModels';

const TAG: string = 'PendingShareSelection';

export class PendingShareSelection {
  private pending?: SearchResult;

  set(result: SearchResult): void {
    this.pending = result;
    LsLogger.info(TAG, `Pending result set provider=${result.provider}`);
  }

  consume(provider: CloudProviderType): SearchResult | undefined {
    if (this.pending === undefined || this.pending.provider !== provider) {
      return undefined;
    }
    const result = this.pending;
    this.pending = undefined;
    LsLogger.info(TAG, `Pending result consumed provider=${provider}`);
    return result;
  }
}

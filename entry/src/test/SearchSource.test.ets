import {
  describe,
  expect,
  it,
  MockKit,
  when
} from '@ohos/hypium';
import { AppError, AppErrorCode } from '../main/ets/common/error/AppError';
import { Result } from '../main/ets/common/result/Result';
import { LEGACY_SETTINGS } from '../main/ets/config/LegacyDefaults';
import { SettingsRepository } from '../main/ets/config/SettingsRepository';
import { HttpClient } from '../main/ets/data/network/HttpClient';
import { PreferenceStore } from '../main/ets/data/storage/PreferenceStore';
import { ProviderRegistry } from '../main/ets/domain/provider/ProviderRegistry';
import { QuarkDriveProvider } from '../main/ets/domain/provider/quark/QuarkDriveProvider';
import { SearchParsing } from '../main/ets/domain/search/SearchParsing';
import {
  SearchCandidate,
  SearchExecutionMode,
  SearchProvider
} from '../main/ets/domain/search/SearchProvider';
import { SearchRepository } from '../main/ets/domain/search/SearchRepository';
import {
  WebSearchItem,
  WebSearchSession,
  WebSearchStage
} from '../main/ets/domain/search/WebSearchContracts';
import { PansoSearchProvider } from '../main/ets/domain/search/impl/PansoSearchProvider';
import { PanSouSearchProvider } from '../main/ets/domain/search/impl/PanSouSearchProvider';
import { PiozSearchProvider } from '../main/ets/domain/search/impl/PiozSearchProvider';
import { CloudProviderType } from '../main/ets/model/AppModels';
import { ShareMetadata } from '../main/ets/model/drive/CloudDriveModels';

class CandidateProvider implements SearchProvider {
  readonly id: string = 'candidate';
  readonly name: string = 'candidate';
  readonly providerType: CloudProviderType = CloudProviderType.QUARK;
  readonly executionMode: SearchExecutionMode = SearchExecutionMode.DIRECT;
  private readonly candidates: SearchCandidate[];

  constructor(candidates: SearchCandidate[]) {
    this.candidates = candidates;
  }

  async search(_keyword: string): Promise<Result<SearchCandidate[]>> {
    return Result.success<SearchCandidate[]>(this.candidates);
  }
}

function metadata(title: string, displayName: string): ShareMetadata {
  return {
    shareId: 'good',
    title: title,
    displayName: displayName
  };
}

export default function searchSourceTest() {
  describe('Quark search sources', () => {
    it('parses unique Panso document ids on the canonical domain', 0, () => {
      const provider = new PansoSearchProvider(new HttpClient(), CloudProviderType.QUARK);
      const html = '<a href="/doc/100">A</a><a href=\\"/doc/100\\">A</a>' +
        '<a href="/doc/200">B</a>';

      const ids = SearchParsing.extractDocumentIds(html, 10);

      expect(provider.searchUrl('测试')).assertEqual(
        'https://panso.vip/search?q=%E6%B5%8B%E8%AF%95&type=QUARK'
      );
      expect(ids.length).assertEqual(2);
      expect(ids[0]).assertEqual('100');
      expect(ids[1]).assertEqual('200');
    });

    it('parses the complete first Pioz result page', 0, () => {
      const provider = new PiozSearchProvider(new HttpClient());
      let html = '<a href="/detail/593321"><span>资源 A</span></a>' +
        '<a href="/detail/593321">重复</a>';
      for (let index = 1; index < 20; index++) {
        html += `<a href="/detail/${index}">资源 ${index}</a>`;
      }
      const items = provider.parseSearchItems(html);

      expect(items.length).assertEqual(20);
      expect(items[0].key).assertEqual('593321');
      expect(items[0].title).assertEqual('资源 A');
      expect(provider.detailUrl(items[0])).assertEqual('https://www.pioz.cn/detail/593321');
      expect(provider.extractScript().includes('modalLinkInput')).assertTrue();
      expect(provider.challengeScript().includes('turnstileModal')).assertTrue();
      expect(provider.challengeScript().includes('getBoundingClientRect')).assertTrue();
    });

    it('maps and deduplicates PanSou Quark results', 0, () => {
      const result = PanSouSearchProvider.parseResponse({
        data: {
          merged_by_type: {
            quark: [
              { url: 'https://pan.quark.cn/s/one', password: '1234', note: 'One' },
              { url: 'https://pan.quark.cn/s/one', password: '', note: 'Duplicate' },
              { url: 'https://example.com/not-quark', password: '', note: 'Invalid' }
            ]
          }
        }
      });

      expect(result.isSuccess).assertTrue();
      expect(result.value?.length).assertEqual(1);
      expect(result.value?.[0].shareCode).assertEqual('1234');
      expect(result.value?.[0].title).assertEqual('One');
    });

    it('distinguishes empty PanSou results from malformed responses', 0, () => {
      const empty = PanSouSearchProvider.parseResponse({
        data: { merged_by_type: { quark: [] } }
      });
      const malformed = PanSouSearchProvider.parseResponse({});

      expect(empty.isSuccess).assertTrue();
      expect(empty.value?.length).assertEqual(0);
      expect(malformed.isSuccess).assertFalse();
    });

    it('filters trailing punctuation and non-Quark links', 0, () => {
      const values = SearchParsing.extractShareLinks(
        'https://pan.quark.cn/s/one). https://example.com/s/two ' +
        'https:\\/\\/pan.quark.cn\\/s\\/one',
        CloudProviderType.QUARK
      );

      expect(values.length).assertEqual(1);
      expect(values[0].shareUrl).assertEqual('https://pan.quark.cn/s/one');
    });

    it('invalidates old Web sessions after generation changes', 0, () => {
      const session = new WebSearchSession(7, 'source-a', 'keyword');
      const items: WebSearchItem[] = [{ key: '1', title: 'One' }];
      session.begin();
      session.setItems(items);

      expect(session.stage).assertEqual(WebSearchStage.SEARCH_PAGE);
      expect(session.isCurrent(7, 'source-a')).assertTrue();
      expect(session.isCurrent(8, 'source-a')).assertFalse();
      expect(session.currentItem()?.key).assertEqual('1');
      expect(session.advance()).assertFalse();
      session.stage = WebSearchStage.EXTRACTING;
      session.pauseForVerification();
      expect(session.stage).assertEqual(WebSearchStage.WAITING_VERIFICATION);
      expect(session.resumeAfterVerification()).assertEqual(WebSearchStage.EXTRACTING);
    });

    it('uses candidate title fallback and continues after one metadata failure', 0, async () => {
      const settings = new SettingsRepository(new PreferenceStore());
      const drive = new QuarkDriveProvider(new HttpClient(), settings, LEGACY_SETTINGS);
      const mocker = new MockKit();
      const getMetadata = mocker.mockFunc(drive, drive.getShareMetadata);
      when(getMetadata)('bad', '').afterReturn(Promise.resolve(
        Result.failure<ShareMetadata>(new AppError(AppErrorCode.NOT_FOUND, 'missing'))
      ));
      when(getMetadata)('good', '').afterReturn(Promise.resolve(
        Result.success<ShareMetadata>(metadata('', ''))
      ));
      const repository = new SearchRepository(new ProviderRegistry(drive, drive));
      const provider = new CandidateProvider([
        { shareUrl: 'https://pan.quark.cn/s/bad', shareCode: '', title: 'Bad' },
        { shareUrl: 'https://pan.quark.cn/s/good', shareCode: '', title: 'Good title' }
      ]);

      const result = await repository.search(provider, 'keyword');

      expect(result.isSuccess).assertTrue();
      expect(result.value?.results.length).assertEqual(1);
      expect(result.value?.results[0].title).assertEqual('Good title');
      expect(result.value?.failedCount).assertEqual(1);
    });
  });
}

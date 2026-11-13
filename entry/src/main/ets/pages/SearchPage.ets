import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { AppContainer } from '../AppContainer';
import { LsLogger } from '../common/log/LsLogger';
import { LinkActions } from '../common/platform/LinkActions';
import { SearchResultRow } from '../components/SearchResultRow';
import {
  AddShareRequest,
  SHARE_TASK_REVISION_KEY,
  ShareController
} from '../domain/share/ShareController';
import { SearchHistoryEntry, SearchHistoryRepository } from '../domain/search/SearchHistoryRepository';
import {
  SearchCandidate,
  SearchExecutionMode,
  SearchProvider
} from '../domain/search/SearchProvider';
import { SearchRepository, SearchResolution } from '../domain/search/SearchRepository';
import {
  InteractiveSearchProvider,
  WebSearchItem,
  WebSearchSession,
  WebSearchStage
} from '../domain/search/WebSearchContracts';
import { MySiteSearchProvider } from '../domain/search/impl/MySiteSearchProvider';
import { PansoSearchProvider } from '../domain/search/impl/PansoSearchProvider';
import { PanSouSearchProvider } from '../domain/search/impl/PanSouSearchProvider';
import { PiozSearchProvider } from '../domain/search/impl/PiozSearchProvider';
import { QileSearchProvider } from '../domain/search/impl/QileSearchProvider';
import { CloudProviderType, SearchResult } from '../model/AppModels';

const TAG: string = 'SearchPage';
const SEARCH_USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';
const WEB_VIEW_HEIGHT: number = 300;
const KK_RESULT_PAGE_SIZE: number = 10;

interface SearchPageParams {
  provider?: string;
}

class SearchSourceOption {
  value: string;

  constructor(value: string) {
    this.value = value;
  }
}

@Entry
@Component
struct SearchPage {
  @State keyword: string = '';
  @State providerType: CloudProviderType = CloudProviderType.ALIYUN;
  @State sourceIndex: number = 0;
  @State results: SearchResult[] = [];
  @State history: SearchHistoryEntry[] = [];
  @State message: string = '';
  @State searching: boolean = false;
  @State dynamicUrl: string = 'about:blank';
  @State webExpanded: boolean = false;
  @State waitingVerification: boolean = false;
  @State addingResultId: string = '';
  @State hasNextSearchPage: boolean = false;
  private sources: SearchProvider[] = [];
  private searchRepository?: SearchRepository;
  private historyRepository?: SearchHistoryRepository;
  private webController: webview.WebviewController = new webview.WebviewController();
  private generation: number = 0;
  private webSession?: WebSearchSession;
  private webCandidates: SearchCandidate[] = [];
  private pendingWebItems: WebSearchItem[] = [];

  aboutToAppear(): void {
    this.initialize();
  }

  private async initialize(): Promise<void> {
    const container = AppContainer.getInstance();
    await container.waitUntilReady();
    const params = router.getParams() as SearchPageParams;
    this.providerType = params !== undefined && params.provider === CloudProviderType.QUARK ?
      CloudProviderType.QUARK : CloudProviderType.ALIYUN;
    if (container.providerRegistry === undefined) {
      this.message = '搜索服务初始化失败';
      return;
    }
    this.searchRepository = new SearchRepository(container.providerRegistry);
    this.historyRepository = new SearchHistoryRepository(container.jsonFileStore);
    this.sources = this.providerType === CloudProviderType.ALIYUN ? [
      new MySiteSearchProvider(container.httpClient, CloudProviderType.ALIYUN),
      new PansoSearchProvider(container.httpClient, CloudProviderType.ALIYUN),
      new QileSearchProvider(container.httpClient)
    ] : [
      new PiozSearchProvider(container.httpClient),
      new PanSouSearchProvider(container.httpClient)
    ];
    this.history = this.historyRepository.load(this.providerType);
  }

  private sourceOptions(): SearchSourceOption[] {
    return this.sources.map((source: SearchProvider) => new SearchSourceOption(source.name));
  }

  private sourceName(): string {
    return this.sourceIndex >= 0 && this.sourceIndex < this.sources.length ?
      this.sources[this.sourceIndex].name : '';
  }

  private onSourceSelected(index: number): void {
    this.generation++;
    this.sourceIndex = index;
    this.searching = false;
    this.waitingVerification = false;
    this.webExpanded = false;
    this.webSession = undefined;
    this.webCandidates = [];
    this.pendingWebItems = [];
    this.hasNextSearchPage = false;
  }

  private async search(): Promise<void> {
    if (this.keyword.length === 0) {
      this.toast('请输入搜索内容！');
      return;
    }
    if (this.searching || this.sources.length === 0) {
      return;
    }
    this.getUIContext().getFocusController().clearFocus();
    const source = this.sources[this.sourceIndex];
    this.generation++;
    this.searching = true;
    this.waitingVerification = false;
    this.webExpanded = false;
    this.webCandidates = [];
    this.pendingWebItems = [];
    this.hasNextSearchPage = false;
    this.message = '搜索中...';
    if (source.executionMode === SearchExecutionMode.DIRECT) {
      await this.executeSearch(source, '');
      return;
    }
    const webSource = source as InteractiveSearchProvider;
    const session = new WebSearchSession(this.generation, source.id, this.keyword);
    session.begin();
    this.webSession = session;
    if (source.executionMode === SearchExecutionMode.WEB_HTML) {
      const completed = await this.executeSearch(source, '', false);
      if (!completed && this.isActive(session, webSource)) {
        this.startWebSearchFallback(webSource, session);
      }
      return;
    }
    const itemResult = await webSource.loadSearchItems(this.keyword);
    if (!this.isActive(session, webSource)) {
      return;
    }
    if (itemResult.isSuccess && itemResult.value !== undefined) {
      this.setInteractivePageItems(webSource, session, itemResult.value);
      await this.processCurrentItem(webSource, session);
      return;
    }
    LsLogger.warn(TAG, `HTTP search fallback source=${source.id}, ` +
      `message=${itemResult.error?.message ?? 'unknown'}`);
    this.startWebSearchFallback(webSource, session);
  }

  private async executeSearch(
    source: SearchProvider,
    dynamicHtml: string,
    showError: boolean = true
  ): Promise<boolean> {
    if (this.searchRepository === undefined) {
      this.finishWithError('搜索服务未初始化');
      return false;
    }
    const result = await this.searchRepository.search(source, this.keyword, dynamicHtml);
    if (result.isSuccess && result.value !== undefined) {
      this.finishWithResolution(source, result.value);
      return true;
    } else {
      if (showError) {
        this.finishWithError(result.error?.message ?? '搜索失败');
      }
      return false;
    }
  }

  private startWebSearchFallback(
    source: InteractiveSearchProvider,
    session: WebSearchSession
  ): void {
    session.begin();
    this.message = `${source.name}需要页面验证，正在加载...`;
    this.webExpanded = true;
    this.loadWebPage(source.searchUrl(session.keyword));
  }

  private async onWebPageReady(): Promise<void> {
    const session = this.webSession;
    const source = this.currentWebSource();
    if (session === undefined || source === undefined || !this.isActive(session, source)) {
      return;
    }
    if (source.executionMode === SearchExecutionMode.WEB_HTML) {
      try {
        let html = '';
        for (let attempt = 0; attempt < 8; attempt++) {
          if (attempt > 0) {
            await this.wait(700);
          }
          if (!this.isActive(session, source)) {
            return;
          }
          html = await this.webController.runJavaScript('document.documentElement.outerHTML');
          if (source.parseSearchItems(html).length > 0) {
            break;
          }
        }
        if (this.isActive(session, source)) {
          if (source.parseSearchItems(html).length > 0) {
            await this.executeSearch(source, html);
          } else if (await this.hasChallenge(source)) {
            this.pauseForVerification(session, `请完成${source.name}安全验证`);
          } else {
            await this.executeSearch(source, html);
          }
        }
      } catch (error) {
        this.finishWithError(this.messageOf(error, '动态页面读取失败'));
      }
      return;
    }
    if (session.stage === WebSearchStage.SEARCH_PAGE) {
      await this.readInteractiveSearchPage(source, session);
    } else if (session.stage === WebSearchStage.DETAIL_PAGE) {
      await this.triggerAndExtract(source, session);
    }
  }

  private async readInteractiveSearchPage(
    source: InteractiveSearchProvider,
    session: WebSearchSession
  ): Promise<void> {
    try {
      let items: WebSearchItem[] = [];
      for (let attempt = 0; attempt < 6 && items.length === 0; attempt++) {
        if (attempt > 0) {
          await this.wait(700);
        }
        if (!this.isActive(session, source)) {
          return;
        }
        const html = await this.webController.runJavaScript('document.documentElement.outerHTML');
        items = source.parseSearchItems(html);
      }
      if (items.length === 0) {
        const challenge = await this.hasChallenge(source);
        if (challenge) {
          this.pauseForVerification(session, `请完成${source.name}安全验证`);
        } else {
          await this.completeInteractiveSearch(source, session);
        }
        return;
      }
      this.setInteractivePageItems(source, session, items);
      await this.processCurrentItem(source, session);
    } catch (error) {
      this.finishWithError(this.messageOf(error, '搜索页面解析失败'));
    }
  }

  private async processCurrentItem(
    source: InteractiveSearchProvider,
    session: WebSearchSession
  ): Promise<void> {
    if (!this.isActive(session, source)) {
      return;
    }
    const item = session.currentItem();
    if (item === undefined) {
      await this.completeInteractiveSearch(source, session);
      return;
    }
    this.waitingVerification = false;
    this.message = `正在提取第 ${session.currentIndex + 1}/${session.items.length} 项`;
    const detailUrl = source.detailUrl(item);
    if (detailUrl.length > 0) {
      session.stage = WebSearchStage.DETAIL_PAGE;
      this.webExpanded = true;
      this.loadWebPage(detailUrl);
      return;
    }
    await this.triggerAndExtract(source, session);
  }

  private async triggerAndExtract(
    source: InteractiveSearchProvider,
    session: WebSearchSession
  ): Promise<void> {
    const item = session.currentItem();
    if (item === undefined || !this.isActive(session, source)) {
      return;
    }
    session.stage = WebSearchStage.EXTRACTING;
    try {
      await this.webController.runJavaScript(source.triggerScript(item));
      for (let attempt = 0; attempt < 12; attempt++) {
        await this.wait(600);
        if (!this.isActive(session, source)) {
          return;
        }
        const extracted = await this.webController.runJavaScript(source.extractScript());
        const link = this.extractQuarkLink(extracted);
        if (link.length > 0) {
          this.webCandidates.push({
            shareUrl: link,
            shareCode: '',
            title: item.title
          });
          await this.advanceInteractiveSearch(source, session);
          return;
        }
        if (await this.hasChallenge(source)) {
          this.pauseForVerification(session, `请完成${source.name}安全验证`);
          return;
        }
      }
      LsLogger.warn(TAG, `Interactive item skipped source=${source.id}, ` +
        `index=${session.currentIndex}, key=${item.key}`);
      await this.advanceInteractiveSearch(source, session);
    } catch (error) {
      LsLogger.warn(TAG, `Interactive extraction failed source=${source.id}, ` +
        `message=${this.messageOf(error, 'unknown')}`);
      await this.advanceInteractiveSearch(source, session);
    }
  }

  private async advanceInteractiveSearch(
    source: InteractiveSearchProvider,
    session: WebSearchSession
  ): Promise<void> {
    if (session.advance()) {
      await this.processCurrentItem(source, session);
    } else {
      await this.completeInteractiveSearch(source, session);
    }
  }

  private setInteractivePageItems(
    source: InteractiveSearchProvider,
    session: WebSearchSession,
    items: WebSearchItem[]
  ): void {
    if (source.id === 'quark_pioz') {
      session.setItems(items.slice(0, KK_RESULT_PAGE_SIZE));
      this.pendingWebItems = items.slice(KK_RESULT_PAGE_SIZE);
      this.hasNextSearchPage = this.pendingWebItems.length > 0;
      return;
    }
    session.setItems(items);
    this.pendingWebItems = [];
    this.hasNextSearchPage = false;
  }

  private async loadNextSearchPage(): Promise<void> {
    if (this.searching || this.pendingWebItems.length === 0) {
      return;
    }
    const source = this.currentWebSource();
    if (source === undefined) {
      return;
    }
    this.generation++;
    this.searching = true;
    this.waitingVerification = false;
    this.webExpanded = false;
    this.webCandidates = [];
    this.results = [];
    this.message = '下一页搜索中...';
    const session = new WebSearchSession(this.generation, source.id, this.keyword);
    session.begin();
    const items = this.pendingWebItems.slice(0, KK_RESULT_PAGE_SIZE);
    this.pendingWebItems = this.pendingWebItems.slice(KK_RESULT_PAGE_SIZE);
    this.hasNextSearchPage = this.pendingWebItems.length > 0;
    session.setItems(items);
    this.webSession = session;
    await this.processCurrentItem(source, session);
  }

  private async completeInteractiveSearch(
    source: InteractiveSearchProvider,
    session: WebSearchSession
  ): Promise<void> {
    if (!this.isActive(session, source) || this.searchRepository === undefined) {
      return;
    }
    session.stage = WebSearchStage.COMPLETED;
    this.webExpanded = false;
    this.waitingVerification = false;
    const result = await this.searchRepository.resolveCandidates(source, this.webCandidates);
    if (result.isSuccess && result.value !== undefined) {
      this.finishWithResolution(source, result.value);
    } else {
      this.finishWithError(result.error?.message ?? '搜索结果校验失败');
    }
  }

  private async continueExtraction(): Promise<void> {
    const session = this.webSession;
    const source = this.currentWebSource();
    if (session === undefined || source === undefined || !this.isActive(session, source)) {
      return;
    }
    this.waitingVerification = false;
    this.webExpanded = false;
    const resumeStage = session.resumeAfterVerification();
    if (resumeStage === WebSearchStage.SEARCH_PAGE) {
      await this.readInteractiveSearchPage(source, session);
    } else {
      await this.triggerAndExtract(source, session);
    }
  }

  private pauseForVerification(session: WebSearchSession, message: string): void {
    session.pauseForVerification();
    this.waitingVerification = true;
    this.webExpanded = true;
    this.message = message;
  }

  private async hasChallenge(source: InteractiveSearchProvider): Promise<boolean> {
    const result = await this.webController.runJavaScript(source.challengeScript());
    return result === 'true' || result.includes('true');
  }

  private currentWebSource(): InteractiveSearchProvider | undefined {
    if (this.sourceIndex < 0 || this.sourceIndex >= this.sources.length) {
      return undefined;
    }
    const source = this.sources[this.sourceIndex];
    return source.executionMode === SearchExecutionMode.DIRECT ?
      undefined : source as InteractiveSearchProvider;
  }

  private isActive(
    session: WebSearchSession | undefined,
    source: InteractiveSearchProvider | undefined
  ): boolean {
    return session !== undefined && source !== undefined && this.searching &&
      session.isCurrent(this.generation, source.id);
  }

  private finishWithResolution(source: SearchProvider, resolution: SearchResolution): void {
    this.results = resolution.results;
    this.message = resolution.failedCount > 0 ?
      `搜索结束，${resolution.failedCount} 项已失效或解析失败` : '搜索结束';
    this.searching = false;
    this.webExpanded = false;
    this.waitingVerification = false;
    this.saveHistory(source);
  }

  private finishWithError(message: string): void {
    this.message = '搜索结束';
    this.searching = false;
    this.webExpanded = false;
    this.waitingVerification = false;
    this.toast(message);
  }

  private saveHistory(source: SearchProvider): void {
    if (this.historyRepository === undefined) {
      return;
    }
    const entry: SearchHistoryEntry = {
      id: `${this.providerType}_${Date.now()}`,
      keyword: this.keyword,
      sourceId: source.id,
      provider: this.providerType,
      results: this.results,
      createdAt: Date.now()
    };
    this.historyRepository.save(entry);
    this.history = this.historyRepository.load(this.providerType);
  }

  private extractQuarkLink(content: string): string {
    const normalized = content.replace(/\\\//g, '/').replace(/\\/g, '');
    const match = normalized.match(/https?:\/\/pan\.quark\.cn\/s\/[A-Za-z0-9_-]+/);
    return match === null ? '' : match[0];
  }

  private historyLabel(entry: SearchHistoryEntry): string {
    const index = this.sources.findIndex((source: SearchProvider) => source.id === entry.sourceId);
    return `${entry.keyword}-${index < 0 ? 0 : index}`;
  }

  private restoreHistory(entry: SearchHistoryEntry): void {
    this.pendingWebItems = [];
    this.hasNextSearchPage = false;
    this.results = entry.results;
  }

  private async openResult(result: SearchResult): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const openResult = await LinkActions.open(context, result.shareUrl);
    if (!openResult.isSuccess) {
      this.toast(openResult.error?.message ?? '无法打开分享链接');
    }
  }

  private async copyLink(result: SearchResult): Promise<void> {
    const copyResult = await LinkActions.copy(result.shareUrl);
    this.toast(copyResult.isSuccess ? '复制连接成功！' :
      (copyResult.error?.message ?? '复制连接失败'));
  }

  private async copyCode(result: SearchResult): Promise<void> {
    const code = result.shareCode.length >= 4 ?
      result.shareCode.substring(result.shareCode.length - 4) : result.shareCode;
    if (code.length === 0) {
      return;
    }
    const copyResult = await LinkActions.copy(code);
    this.toast(copyResult.isSuccess ? '复制连接成功！' :
      (copyResult.error?.message ?? '复制连接失败'));
  }

  private async addResult(result: SearchResult): Promise<void> {
    if (this.addingResultId.length > 0) {
      return;
    }
    this.addingResultId = result.id;
    try {
      const container = AppContainer.getInstance();
      await container.waitUntilReady();
      const controller: ShareController = container.createShareController(result.provider);
      controller.load();
      const request: AddShareRequest = {
        shareUrl: result.shareUrl,
        shareCode: result.shareCode,
        targetFolderId: result.provider === CloudProviderType.ALIYUN ? 'root' : '0',
        targetFolderName: '',
        autoSync: false
      };
      const addResult = await controller.add(request);
      if (!addResult.isSuccess) {
        this.toast(addResult.error?.message ?? '添加分享失败');
        return;
      }
      AppStorage.setOrCreate<number>(SHARE_TASK_REVISION_KEY, Date.now());
      this.toast('添加成功');
      router.back();
    } catch (error) {
      LsLogger.error(TAG, `Add search result failed: ${this.messageOf(error, 'unknown')}`);
      this.toast(this.messageOf(error, '添加分享失败'));
    } finally {
      this.addingResultId = '';
    }
  }

  private wait(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, milliseconds);
    });
  }

  private loadWebPage(url: string): void {
    this.dynamicUrl = url;
    try {
      this.webController.loadUrl(url);
    } catch (error) {
      LsLogger.warn(TAG, `Web navigation failed message=${this.messageOf(error, 'unknown')}`);
    }
  }

  private messageOf(error: Object, fallback: string): string {
    return error instanceof Error ? error.message : fallback;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  build() {
    Column() {
      Row() {
        Select(this.sourceOptions())
          .selected(this.sourceIndex)
          .value(this.sourceName())
          .width(100)
          .height(30)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: $r('app.color.android_border'), radius: 1 })
          .onSelect((index: number) => this.onSourceSelected(index))

        TextInput({ text: this.keyword })
          .fontSize(13)
          .height(30)
          .layoutWeight(1)
          .margin({ left: 10 })
          .padding({ left: 4, right: 4 })
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: $r('app.color.android_border'), radius: 1 })
          .onChange((value: string) => this.keyword = value)

        Text('搜索')
          .fontSize(14)
          .padding({ left: 20, right: 20, top: 10, bottom: 10 })
          .onClick(() => this.search())
      }
      .width('100%')
      .margin({ left: 10, top: 10 })

      Scroll() {
        Row() {
          ForEach(this.history, (entry: SearchHistoryEntry) => {
            Text(this.historyLabel(entry))
              .fontSize(14)
              .margin({ right: 10 })
              .onClick(() => this.restoreHistory(entry))
          }, (entry: SearchHistoryEntry) => entry.id)
        }
        .padding(10)
      }
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)

      Row() {
        Text(this.message)
          .fontSize(14)
          .layoutWeight(1)
          .padding(10)

        if (this.waitingVerification) {
          Text('继续提取')
            .fontSize(13)
            .padding(10)
            .onClick(() => this.continueExtraction())
        }

        if (this.hasNextSearchPage && !this.searching) {
          Text('下一页')
            .fontSize(13)
            .padding(10)
            .onClick(() => this.loadNextSearchPage())
        }

        if (this.webExpanded) {
          Text('收起网页')
            .fontSize(13)
            .padding(10)
            .onClick(() => this.webExpanded = false)
        }
      }
      .width('100%')

      List() {
        ForEach(this.results, (result: SearchResult) => {
          ListItem() {
            SearchResultRow({
              result: result,
              onOpen: (selected: SearchResult) => this.openResult(selected),
              onCopyLink: (selected: SearchResult) => this.copyLink(selected),
              onCopyCode: (selected: SearchResult) => this.copyCode(selected),
              onAdd: (selected: SearchResult) => this.addResult(selected)
            })
          }
        }, (result: SearchResult) => result.id)
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ left: 10, right: 10 })

      Web({ src: this.dynamicUrl, controller: this.webController })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .userAgent(SEARCH_USER_AGENT)
        .onPageEnd(() => this.onWebPageReady())
        .onErrorReceive(() => {
          LsLogger.warn(TAG, `Web page request failed source=${this.sourceName()}`);
        })
        .width('100%')
        .height(WEB_VIEW_HEIGHT)
        .visibility(this.webExpanded ? Visibility.Visible : Visibility.None)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Start)
  }
}

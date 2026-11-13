import { Result } from '../../common/result/Result';
import { SearchProvider } from './SearchProvider';

export enum WebSearchStage {
  IDLE = 'idle',
  SEARCH_PAGE = 'search_page',
  DETAIL_PAGE = 'detail_page',
  WAITING_VERIFICATION = 'waiting_verification',
  EXTRACTING = 'extracting',
  COMPLETED = 'completed',
  FAILED = 'failed'
}

export interface WebSearchItem {
  key: string;
  title: string;
}

export interface InteractiveSearchProvider extends SearchProvider {
  readonly visibleDuringSearch: boolean;

  loadSearchItems(keyword: string): Promise<Result<WebSearchItem[]>>;

  searchUrl(keyword: string): string;

  parseSearchItems(content: string): WebSearchItem[];

  detailUrl(item: WebSearchItem): string;

  challengeScript(): string;

  triggerScript(item: WebSearchItem): string;

  extractScript(): string;
}

export class WebSearchSession {
  readonly generation: number;
  readonly sourceId: string;
  readonly keyword: string;
  stage: WebSearchStage = WebSearchStage.IDLE;
  items: WebSearchItem[] = [];
  currentIndex: number = 0;
  private resumeStage: WebSearchStage = WebSearchStage.IDLE;

  constructor(generation: number, sourceId: string, keyword: string) {
    this.generation = generation;
    this.sourceId = sourceId;
    this.keyword = keyword;
  }

  isCurrent(generation: number, sourceId: string): boolean {
    return this.generation === generation && this.sourceId === sourceId;
  }

  begin(): void {
    this.stage = WebSearchStage.SEARCH_PAGE;
    this.items = [];
    this.currentIndex = 0;
  }

  setItems(items: WebSearchItem[]): void {
    this.items = items;
    this.currentIndex = 0;
  }

  currentItem(): WebSearchItem | undefined {
    return this.currentIndex < this.items.length ? this.items[this.currentIndex] : undefined;
  }

  advance(): boolean {
    this.currentIndex++;
    return this.currentIndex < this.items.length;
  }

  pauseForVerification(): void {
    this.resumeStage = this.stage;
    this.stage = WebSearchStage.WAITING_VERIFICATION;
  }

  resumeAfterVerification(): WebSearchStage {
    const stage = this.resumeStage;
    this.stage = stage;
    return stage;
  }
}

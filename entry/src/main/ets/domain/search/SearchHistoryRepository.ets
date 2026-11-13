import { JsonFileStore } from '../../data/storage/JsonFileStore';
import { CloudProviderType, SearchResult } from '../../model/AppModels';

const HISTORY_FILE: string = 'search_history.json';
const HISTORY_LIMIT: number = 10;

export interface SearchHistoryEntry {
  id: string;
  keyword: string;
  sourceId: string;
  provider: CloudProviderType;
  results: SearchResult[];
  createdAt: number;
}

export class SearchHistoryRepository {
  private readonly store: JsonFileStore;

  constructor(store: JsonFileStore) {
    this.store = store;
  }

  load(provider: CloudProviderType): SearchHistoryEntry[] {
    const raw = this.store.read(HISTORY_FILE);
    if (raw.length === 0) {
      return [];
    }
    const entries = JSON.parse(raw) as SearchHistoryEntry[];
    return entries.filter((entry: SearchHistoryEntry) => entry.provider === provider)
      .sort((left: SearchHistoryEntry, right: SearchHistoryEntry) => right.createdAt - left.createdAt);
  }

  save(entry: SearchHistoryEntry): void {
    const raw = this.store.read(HISTORY_FILE);
    let entries: SearchHistoryEntry[] = raw.length === 0 ? [] : JSON.parse(raw) as SearchHistoryEntry[];
    entries = entries.filter((item: SearchHistoryEntry) =>
      !(item.provider === entry.provider && item.keyword === entry.keyword && item.sourceId === entry.sourceId));
    entries.unshift(entry);
    if (entries.length > HISTORY_LIMIT) {
      entries = entries.slice(0, HISTORY_LIMIT);
    }
    this.store.write(HISTORY_FILE, JSON.stringify(entries));
  }
}

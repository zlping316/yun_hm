import { CloudProviderType } from '../../model/AppModels';
import { SearchCandidate } from './SearchProvider';

export interface ParsedSearchItem {
  key: string;
  title: string;
}

export class SearchParsing {
  static extractShareLinks(
    content: string,
    provider: CloudProviderType,
    maxCount: number = 20
  ): SearchCandidate[] {
    const normalizedContent = SearchParsing.normalizeContent(content);
    const pattern = /https?:\/\/[^\s"'<>\\]+/g;
    const candidates: SearchCandidate[] = [];
    const seen = new Set<string>();
    let match = pattern.exec(normalizedContent);
    while (match !== null && candidates.length < maxCount) {
      const url = SearchParsing.trimUrl(match[0]);
      const accepted = provider === CloudProviderType.ALIYUN ?
        (url.includes('alipan.com/s/') || url.includes('aliyundrive.com/s/')) :
        url.includes('pan.quark.cn/s/');
      if (accepted && !seen.has(url)) {
        seen.add(url);
        candidates.push({ shareUrl: url, shareCode: '' });
      }
      match = pattern.exec(normalizedContent);
    }
    return candidates;
  }

  static extractMatches(content: string, pattern: RegExp, maxCount: number = 20): string[] {
    const values: string[] = [];
    const seen = new Set<string>();
    let match = pattern.exec(content);
    while (match !== null && values.length < maxCount) {
      if (match.length > 1 && match[1].length > 0 && !seen.has(match[1])) {
        seen.add(match[1]);
        values.push(match[1]);
      }
      match = pattern.exec(content);
    }
    return values;
  }

  static extractDocumentIds(content: string, maxCount: number = 10): string[] {
    const normalized = SearchParsing.normalizeContent(content);
    return SearchParsing.extractMatches(normalized, /href=["']\/doc\/([^"'/?#]+)["']/g, maxCount);
  }

  static extractDetailItems(content: string, maxCount: number = 10): ParsedSearchItem[] {
    const normalized = SearchParsing.normalizeContent(content);
    const pattern = /<a[^>]+href=["']\/detail\/([^"'/?#]+)["'][^>]*>([\s\S]*?)<\/a>/gi;
    const items: ParsedSearchItem[] = [];
    const seen = new Set<string>();
    let match = pattern.exec(normalized);
    while (match !== null && items.length < maxCount) {
      if (!seen.has(match[1])) {
        seen.add(match[1]);
        items.push({
          key: match[1],
          title: SearchParsing.stripHtml(match[2])
        });
      }
      match = pattern.exec(normalized);
    }
    return items;
  }

  static normalizeContent(content: string): string {
    return content
      .replace(/\\u0022/g, '"')
      .replace(/\\u0026/g, '&')
      .replace(/\\\//g, '/')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&amp;/g, '&');
  }

  private static stripHtml(content: string): string {
    return content.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
  }

  private static trimUrl(url: string): string {
    let value = url.replace(/\\/g, '').replace(/&amp;/g, '&');
    while (/[),.;\]}]$/.test(value)) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}

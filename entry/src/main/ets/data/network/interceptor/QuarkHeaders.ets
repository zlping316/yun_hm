export interface QuarkHeaderOptions {
  cookie?: string;
  referer?: string;
  contentType?: string;
}

export interface QuarkHeaderMap {
  'Content-Type': string;
  'Accept': string;
  'User-Agent': string;
  'Cookie'?: string;
  'Referer'?: string;
}

export class QuarkHeaders {
  static create(options: QuarkHeaderOptions = {}): QuarkHeaderMap {
    const headers: QuarkHeaderMap = {
      'Content-Type': options.contentType ?? 'application/json',
      'Accept': 'application/json, text/plain, */*',
      'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS) Yun/1.0'
    };
    if (options.cookie !== undefined && options.cookie.length > 0) {
      headers.Cookie = options.cookie;
    }
    if (options.referer !== undefined && options.referer.length > 0) {
      headers.Referer = options.referer;
    }
    return headers;
  }
}

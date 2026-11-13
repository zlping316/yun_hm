export interface AliyunHeaderOptions {
  accessToken?: string;
  shareToken?: string;
  referer?: string;
}

export interface AliyunHeaderMap {
  'Content-Type': string;
  'Accept': string;
  'User-Agent': string;
  'Authorization': string;
  'x-share-token': string;
  'Referer': string;
}

export class AliyunHeaders {
  static create(options: AliyunHeaderOptions = {}): AliyunHeaderMap {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS) Yun/1.0',
      'Authorization': options.accessToken !== undefined && options.accessToken.length > 0 ?
        `Bearer ${options.accessToken}` : '',
      'x-share-token': options.shareToken ?? '',
      'Referer': options.referer ?? ''
    };
  }
}

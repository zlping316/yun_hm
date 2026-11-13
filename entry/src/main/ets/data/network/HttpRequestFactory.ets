import { http } from '@kit.NetworkKit';
import { HttpRequestConfig } from './HttpTypes';

const DEFAULT_TIMEOUT_MS: number = 10000;

export class HttpRequestFactory {
  static createOptions(config: HttpRequestConfig, dataType: http.HttpDataType): http.HttpRequestOptions {
    return {
      method: config.method ?? http.RequestMethod.GET,
      header: config.headers,
      extraData: config.body,
      expectDataType: dataType,
      connectTimeout: config.timeoutMs ?? DEFAULT_TIMEOUT_MS,
      readTimeout: config.timeoutMs ?? DEFAULT_TIMEOUT_MS,
      usingProtocol: config.protocol,
      usingCache: false
    };
  }
}

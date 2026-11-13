import { http } from '@kit.NetworkKit';

export interface HttpRequestConfig {
  url: string;
  method?: http.RequestMethod;
  headers?: Object;
  body?: string | Object | ArrayBuffer;
  timeoutMs?: number;
  retryable?: boolean;
  protocol?: http.HttpProtocol;
}

export interface HttpRawResponse {
  statusCode: number;
  data: string | ArrayBuffer;
  headers: Object;
}

export interface ProviderErrorPayload {
  code?: string;
  message?: string;
  error?: string;
  error_description?: string;
  status?: number;
}

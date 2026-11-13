import { AppError, AppErrorCode } from '../../common/error/AppError';
import { HttpRawResponse, ProviderErrorPayload } from './HttpTypes';

export class ResponseParser {
  static parseJson<T>(response: HttpRawResponse): T {
    if (typeof response.data !== 'string') {
      throw new AppError(AppErrorCode.PARSE, '服务器返回了非 JSON 数据');
    }
    try {
      return JSON.parse(response.data) as T;
    } catch (error) {
      throw new AppError(AppErrorCode.PARSE, '服务器响应解析失败');
    }
  }

  static ensureSuccess(statusCode: number, body: string = ''): void {
    if (statusCode >= 200 && statusCode < 300) {
      return;
    }
    const payload = ResponseParser.parseProviderError(body);
    const providerCode = payload.code ?? payload.error ?? '';
    const detail = payload.message ?? payload.error_description ?? '';
    const message = detail.length > 0 ? detail : `请求失败 (${statusCode})`;
    const suffix = providerCode.length > 0 ? ` [${providerCode}]` : '';

    if (statusCode === 401 || statusCode === 403) {
      throw new AppError(AppErrorCode.UNAUTHORIZED, `${message}${suffix}`, false, statusCode);
    }
    if (statusCode === 404) {
      throw new AppError(AppErrorCode.NOT_FOUND, `${message}${suffix}`, false, statusCode);
    }
    const retryable = statusCode === 408 || statusCode === 429 || statusCode >= 500;
    throw new AppError(AppErrorCode.NETWORK, `${message}${suffix}`, retryable, statusCode);
  }

  private static parseProviderError(body: string): ProviderErrorPayload {
    if (body.length === 0) {
      return {};
    }
    try {
      return JSON.parse(body) as ProviderErrorPayload;
    } catch (error) {
      return {};
    }
  }
}

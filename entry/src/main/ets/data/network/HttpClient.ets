import { http } from '@kit.NetworkKit';
import { AppError, AppErrorCode } from '../../common/error/AppError';
import { LsLogger } from '../../common/log/LsLogger';
import { Result } from '../../common/result/Result';
import { HttpRequestFactory } from './HttpRequestFactory';
import { HttpRawResponse, HttpRequestConfig } from './HttpTypes';
import { ResponseParser } from './ResponseParser';
import { RetryPolicy } from './RetryPolicy';

const TAG: string = 'HttpClient';
export class HttpClient {
  private readonly retryPolicy: RetryPolicy;

  constructor(retryPolicy: RetryPolicy = new RetryPolicy()) {
    this.retryPolicy = retryPolicy;
  }

  async requestJson<T>(config: HttpRequestConfig): Promise<Result<T>> {
    const response = await this.execute(config, http.HttpDataType.STRING);
    if (!response.isSuccess || response.value === undefined) {
      return Result.failure<T>(response.error ?? new AppError(AppErrorCode.UNKNOWN, '未知网络错误'));
    }
    try {
      return Result.success<T>(ResponseParser.parseJson<T>(response.value));
    } catch (error) {
      return Result.failure<T>(this.toAppError(error));
    }
  }

  async requestText(config: HttpRequestConfig): Promise<Result<string>> {
    const response = await this.execute(config, http.HttpDataType.STRING);
    if (!response.isSuccess || response.value === undefined) {
      return Result.failure<string>(response.error ?? new AppError(AppErrorCode.UNKNOWN, '未知网络错误'));
    }
    if (typeof response.value.data !== 'string') {
      return Result.failure<string>(new AppError(AppErrorCode.PARSE, '服务器返回了非文本数据'));
    }
    return Result.success<string>(response.value.data);
  }

  async requestBinary(config: HttpRequestConfig): Promise<Result<ArrayBuffer>> {
    const response = await this.execute(config, http.HttpDataType.ARRAY_BUFFER);
    if (!response.isSuccess || response.value === undefined) {
      return Result.failure<ArrayBuffer>(response.error ?? new AppError(AppErrorCode.UNKNOWN, '未知网络错误'));
    }
    if (!(response.value.data instanceof ArrayBuffer)) {
      return Result.failure<ArrayBuffer>(new AppError(AppErrorCode.PARSE, '服务器返回了非二进制数据'));
    }
    return Result.success<ArrayBuffer>(response.value.data);
  }

  async requestRaw(config: HttpRequestConfig, dataType: http.HttpDataType = http.HttpDataType.STRING):
    Promise<Result<HttpRawResponse>> {
    return this.execute(config, dataType);
  }

  private async execute(config: HttpRequestConfig, dataType: http.HttpDataType): Promise<Result<HttpRawResponse>> {
    const maxAttempts = config.retryable === true ? this.retryPolicy.maxAttempts : 1;
    let lastError: AppError = new AppError(AppErrorCode.UNKNOWN, '未知网络错误');

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      const startedAt = Date.now();
      const request = http.createHttp();
      try {
        const response = await request.request(
          config.url,
          HttpRequestFactory.createOptions(config, dataType)
        );
        const statusCode = response.responseCode as number;
        const body = typeof response.result === 'string' ? response.result : '';
        ResponseParser.ensureSuccess(statusCode, body);
        const data = response.result instanceof ArrayBuffer ? response.result : body;
        LsLogger.info(TAG, `${config.method ?? http.RequestMethod.GET} ${this.safeUrl(config.url)} ` +
          `${statusCode} ${Date.now() - startedAt}ms`);
        return Result.success<HttpRawResponse>({
          statusCode: statusCode,
          data: data,
          headers: response.header
        });
      } catch (error) {
        lastError = this.toAppError(error);
        LsLogger.warn(TAG, `${config.method ?? http.RequestMethod.GET} ${this.safeUrl(config.url)} ` +
          `${lastError.code} ${Date.now() - startedAt}ms attempt=${attempt}`);
        if (attempt >= maxAttempts || !lastError.retryable) {
          break;
        }
        await this.retryPolicy.wait(attempt);
      } finally {
        request.destroy();
      }
    }
    return Result.failure<HttpRawResponse>(lastError);
  }

  private toAppError(error: Object): AppError {
    if (error instanceof AppError) {
      return error;
    }
    const message = error instanceof Error ? error.message : String(error);
    return new AppError(AppErrorCode.NETWORK, `网络请求失败: ${message}`, true);
  }

  private safeUrl(url: string): string {
    const queryIndex = url.indexOf('?');
    return queryIndex >= 0 ? `${url.substring(0, queryIndex)}?***` : url;
  }
}

export enum AppErrorCode {
  INVALID_INPUT = 'INVALID_INPUT',
  NETWORK = 'NETWORK',
  UNAUTHORIZED = 'UNAUTHORIZED',
  NOT_FOUND = 'NOT_FOUND',
  PARSE = 'PARSE',
  STORAGE = 'STORAGE',
  CANCELED = 'CANCELED',
  UNSUPPORTED = 'UNSUPPORTED',
  UNKNOWN = 'UNKNOWN'
}

export class AppError extends Error {
  readonly code: AppErrorCode;
  readonly retryable: boolean;
  readonly statusCode?: number;

  constructor(code: AppErrorCode, message: string, retryable: boolean = false, statusCode?: number) {
    super(message);
    this.code = code;
    this.retryable = retryable;
    this.statusCode = statusCode;
  }
}

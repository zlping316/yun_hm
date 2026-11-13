import { AppError } from '../error/AppError';

export class Result<T> {
  readonly value?: T;
  readonly error?: AppError;

  private constructor(value?: T, error?: AppError) {
    this.value = value;
    this.error = error;
  }

  get isSuccess(): boolean {
    return this.error === undefined;
  }

  static success<T>(value: T): Result<T> {
    return new Result<T>(value);
  }

  static failure<T>(error: AppError): Result<T> {
    return new Result<T>(undefined, error);
  }
}

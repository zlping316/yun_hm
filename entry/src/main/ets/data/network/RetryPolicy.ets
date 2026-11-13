export class RetryPolicy {
  readonly maxAttempts: number;
  readonly initialDelayMs: number;
  readonly maxDelayMs: number;

  constructor(maxAttempts: number = 3, initialDelayMs: number = 300, maxDelayMs: number = 2000) {
    this.maxAttempts = maxAttempts;
    this.initialDelayMs = initialDelayMs;
    this.maxDelayMs = maxDelayMs;
  }

  delayForAttempt(attempt: number): number {
    const delay = this.initialDelayMs * Math.pow(2, Math.max(0, attempt - 1));
    return Math.min(delay, this.maxDelayMs);
  }

  async wait(attempt: number): Promise<void> {
    const delay = this.delayForAttempt(attempt);
    await new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, delay);
    });
  }
}

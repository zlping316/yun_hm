import { http } from '@kit.NetworkKit';
import { AppError, AppErrorCode } from '../../common/error/AppError';
import { LsLogger } from '../../common/log/LsLogger';
import { Result } from '../../common/result/Result';
import { HttpClient } from '../../data/network/HttpClient';
import { HttpRequestConfig } from '../../data/network/HttpTypes';
import { TransferRepository } from '../../data/transfer/TransferRepository';
import {
  CloudProviderType,
  TransferJob,
  TransferState,
  WebAddress
} from '../../model/AppModels';
import { ParsedDownload } from '../../model/parser/ParserModels';
import { TransferQueueController } from '../transfer/TransferQueueController';
import { ParserRegistry } from './ParserRegistry';

const TAG: string = 'ParsingController';

export interface ParsingSummary {
  addressCount: number;
  pageCount: number;
  addedCount: number;
  skippedCount: number;
  failedCount: number;
  errors: string[];
}

export type PageContentLoader = (url: string) => Promise<string>;

interface HtmlRequestHeaders {
  Accept: string;
}

export class ParsingController {
  private readonly parsers: ParserRegistry;
  private readonly client: HttpClient;
  private readonly repository: TransferRepository;
  private readonly queue: TransferQueueController;
  private generation: number = 0;

  constructor(
    parsers: ParserRegistry,
    client: HttpClient,
    repository: TransferRepository,
    queue: TransferQueueController
  ) {
    this.parsers = parsers;
    this.client = client;
    this.repository = repository;
    this.queue = queue;
  }

  async parse(
    addresses: WebAddress[],
    provider: CloudProviderType,
    contentLoader?: PageContentLoader
  ): Promise<Result<ParsingSummary>> {
    const generation = ++this.generation;
    const selected = addresses.filter((address: WebAddress) => address.selected);
    const summary: ParsingSummary = {
      addressCount: selected.length,
      pageCount: 0,
      addedCount: 0,
      skippedCount: 0,
      failedCount: 0,
      errors: []
    };
    const knownUrls = this.knownUrls();
    const uploadedKeys = this.repository.completedKeys();
    const jobs: TransferJob[] = [];

    for (const address of selected) {
      if (this.isCanceled(generation)) {
        return this.canceled<ParsingSummary>();
      }
      try {
        const parser = this.parsers.get(address.type);
        const encodeMainContent = address.type !== '0';
        const mainContent = address.type === '5' ? '' :
          await this.load(address.address, contentLoader, encodeMainContent, address.type !== '0');
        if (this.isCanceled(generation)) {
          return this.canceled<ParsingSummary>();
        }
        const main = await parser.parseMainPage(address, mainContent, uploadedKeys);
        if (!main.isSuccess || main.value === undefined) {
          throw main.error ?? new Error('主页面解析失败');
        }
        summary.pageCount += main.value.totalCount;
        summary.skippedCount += main.value.skippedCount;
        for (const page of main.value.pages) {
          if (this.isCanceled(generation)) {
            return this.canceled<ParsingSummary>();
          }
          try {
            const content = address.type === '5' ? '' :
              await this.load(page.address, contentLoader, address.type !== '0', address.type !== '0');
            if (this.isCanceled(generation)) {
              return this.canceled<ParsingSummary>();
            }
            const nested = parser.parseNestedPages === undefined ? undefined :
              await parser.parseNestedPages(page, content, uploadedKeys);
            if (nested !== undefined) {
              if (!nested.isSuccess || nested.value === undefined) {
                throw nested.error ?? new Error('中间页面解析失败');
              }
              summary.skippedCount += nested.value.skippedCount;
              for (const nestedPage of nested.value.pages) {
                if (this.isCanceled(generation)) {
                  return this.canceled<ParsingSummary>();
                }
                try {
                  const nestedContent = await this.load(nestedPage.address, contentLoader, false, false);
                  if (this.isCanceled(generation)) {
                    return this.canceled<ParsingSummary>();
                  }
                  const parsed = await parser.parseSubPage(nestedPage, nestedContent);
                  if (!parsed.isSuccess || parsed.value === undefined) {
                    break;
                  }
                  this.appendJobs(parsed.value, knownUrls, jobs, provider, summary);
                } catch (error) {
                  if (this.isCanceled(generation)) {
                    return this.canceled<ParsingSummary>();
                  }
                  this.recordFailure(summary, nestedPage.address, error);
                }
              }
              continue;
            }
            const parsed = await parser.parseSubPage(page, content);
            if (!parsed.isSuccess || parsed.value === undefined) {
              break;
            }
            this.appendJobs(parsed.value, knownUrls, jobs, provider, summary);
          } catch (error) {
            if (this.isCanceled(generation)) {
              return this.canceled<ParsingSummary>();
            }
            this.recordFailure(summary, page.address, error);
          }
        }
      } catch (error) {
        if (this.isCanceled(generation)) {
          return this.canceled<ParsingSummary>();
        }
        this.recordFailure(summary, address.address, error);
      }
    }
    if (jobs.length > 0) {
      this.queue.enqueue(jobs);
    }
    summary.addedCount = jobs.length;
    LsLogger.info(TAG, `Parse complete addresses=${summary.addressCount}, pages=${summary.pageCount}, ` +
      `added=${summary.addedCount}, skipped=${summary.skippedCount}, failed=${summary.failedCount}`);
    return Result.success<ParsingSummary>(summary);
  }

  cancel(): void {
    this.generation++;
  }

  private async load(
    url: string,
    contentLoader?: PageContentLoader,
    encodeForWebView: boolean = true,
    useContentLoader: boolean = true
  ): Promise<string> {
    if (contentLoader !== undefined && useContentLoader) {
      return await contentLoader(url);
    }
    const headers: HtmlRequestHeaders = {
      Accept: 'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8'
    };
    const config: HttpRequestConfig = {
      url: url,
      method: http.RequestMethod.GET,
      headers: headers,
      retryable: true
    };
    const response = await this.client.requestText(config);
    if (!response.isSuccess || response.value === undefined) {
      throw response.error ?? new Error('页面加载失败');
    }
    return encodeForWebView ? this.webViewEncoded(response.value) : response.value;
  }

  private webViewEncoded(content: string): string {
    const encoded = JSON.stringify(content);
    return encoded.substring(1, encoded.length - 1)
      .replace(/</g, '\\u003C')
      .replace(/>/g, '\\u003E');
  }

  private knownUrls(): Set<string> {
    const urls = this.repository.completedUrls();
    this.queue.snapshot().forEach((job: TransferJob) => urls.add(job.downloadUrl));
    return urls;
  }

  private appendJobs(
    downloads: ParsedDownload[],
    knownUrls: Set<string>,
    jobs: TransferJob[],
    provider: CloudProviderType,
    summary: ParsingSummary
  ): void {
    downloads.forEach((download: ParsedDownload) => {
      if (download.downloadUrl.length === 0 || knownUrls.has(download.downloadUrl)) {
        summary.skippedCount++;
        return;
      }
      knownUrls.add(download.downloadUrl);
      jobs.push(this.toJob(download, provider, jobs.length));
    });
  }

  private toJob(download: ParsedDownload, provider: CloudProviderType, index: number): TransferJob {
    const now = Date.now();
    const key = download.key.length > 0 ? download.key : download.downloadUrl;
    return {
      jobId: `${now}-${index}-${this.hash(download.downloadUrl)}`,
      name: download.name.length > 0 ? download.name : key,
      downloadUrl: download.downloadUrl,
      key: key,
      source: download.source,
      provider: provider,
      localFile: '',
      state: TransferState.QUEUED,
      progress: 0,
      errorMessage: '',
      selected: true,
      createdAt: now,
      updatedAt: now
    };
  }

  private hash(value: string): string {
    let result = 0;
    for (let index = 0; index < value.length; index++) {
      result = ((result << 5) - result + value.charCodeAt(index)) | 0;
    }
    return Math.abs(result).toString(36);
  }

  private recordFailure(summary: ParsingSummary, url: string, error: Object): void {
    const message = error instanceof Error ? error.message : String(error);
    summary.failedCount++;
    if (summary.errors.length < 5) {
      summary.errors.push(`${url}: ${message}`);
    }
    LsLogger.warn(TAG, `Parse failed url=${this.safeUrl(url)}, message=${message}`);
  }

  private isCanceled(generation: number): boolean {
    return generation !== this.generation;
  }

  private canceled<T>(): Result<T> {
    return Result.failure<T>(new AppError(AppErrorCode.CANCELED, '解析已停止'));
  }

  private safeUrl(url: string): string {
    const queryIndex = url.indexOf('?');
    return queryIndex >= 0 ? `${url.substring(0, queryIndex)}?***` : url;
  }
}

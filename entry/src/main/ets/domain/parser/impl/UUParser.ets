import { http } from '@kit.NetworkKit';
import { AppError, AppErrorCode } from '../../../common/error/AppError';
import { Result } from '../../../common/result/Result';
import { SettingsRepository } from '../../../config/SettingsRepository';
import { HttpClient } from '../../../data/network/HttpClient';
import { HttpRequestConfig } from '../../../data/network/HttpTypes';
import { WebAddress } from '../../../model/AppModels';
import { ParsedDownload, ParserMainResult } from '../../../model/parser/ParserModels';
import { PageParser } from '../PageParser';
import { ParserUtils } from '../ParserUtils';

const MAX_PAGES: number = 20;

interface UUHeaders {
  Accept: string;
  authorization?: string;
  'Content-Type': string;
}

interface UUCategoryBody {
  type: string;
  page: number;
  limit: string;
}

interface UUVideoBody {
  id: string;
}

interface UUListItem {
  id?: string;
}

interface UUCategoryData {
  lists?: UUListItem[];
}

interface UUCategoryResponse {
  data?: UUCategoryData;
}

interface UUVideo {
  videofile?: string;
  title?: string;
}

interface UUVideoData {
  video?: UUVideo;
}

interface UUVideoResponse {
  data?: UUVideoData;
}

export class UUParser implements PageParser {
  readonly type: string = '5';
  readonly name: string = 'UU';
  private readonly client: HttpClient;
  private readonly settingsRepository: SettingsRepository;

  constructor(client: HttpClient, settingsRepository: SettingsRepository) {
    this.client = client;
    this.settingsRepository = settingsRepository;
  }

  async parseMainPage(
    address: WebAddress,
    _content: string,
    uploadedKeys: Set<string>
  ): Promise<Result<ParserMainResult>> {
    const host = ParserUtils.hostOf(address.address);
    const categoryId = ParserUtils.queryValue(address.address, 'id');
    const pages: WebAddress[] = [];
    let totalCount = 0;
    let skippedCount = 0;
    for (let page = 1; page <= MAX_PAGES; page++) {
      const body: UUCategoryBody = { type: categoryId, page: page, limit: '100' };
      const response = await this.client.requestJson<UUCategoryResponse>(
        this.config(`${host}/api/index/category`, body)
      );
      if (!response.isSuccess || response.value === undefined) {
        return Result.failure<ParserMainResult>(response.error ??
          new AppError(AppErrorCode.NETWORK, 'UU 列表请求失败'));
      }
      const items = response.value.data?.lists ?? [];
      if (items.length === 0) {
        break;
      }
      items.forEach((item: UUListItem) => {
        const id = item.id ?? '';
        if (id.length === 0) {
          return;
        }
        totalCount++;
        if (uploadedKeys.has(this.keyOf(id))) {
          skippedCount++;
        } else {
          pages.push(ParserUtils.page(address, `${host}/pages/video/video?id=${id}`));
        }
      });
      if (pages.length >= 10 || items.length < 100) {
        break;
      }
    }
    return ParserUtils.mainResult(pages, totalCount, skippedCount);
  }

  async parseSubPage(address: WebAddress, _content: string): Promise<Result<ParsedDownload[]>> {
    const host = ParserUtils.hostOf(address.address);
    const id = ParserUtils.queryValue(address.address, 'id');
    const credentials = await this.settingsRepository.loadCredentials();
    const body: UUVideoBody = { id: id };
    const headers: UUHeaders = {
      Accept: 'application/json, text/plain, */*',
      authorization: credentials.uuAuthorization,
      'Content-Type': 'application/json'
    };
    const config: HttpRequestConfig = {
      url: `${host}/api/index/video`,
      method: http.RequestMethod.POST,
      headers: headers,
      body: body,
      retryable: true
    };
    const response = await this.client.requestJson<UUVideoResponse>(config);
    if (!response.isSuccess || response.value === undefined) {
      return Result.failure<ParsedDownload[]>(response.error ??
        new AppError(AppErrorCode.NETWORK, 'UU 视频详情请求失败'));
    }
    const video = response.value.data?.video;
    const url = video?.videofile ?? '';
    if (url.length === 0) {
      return Result.success<ParsedDownload[]>([]);
    }
    return Result.success<ParsedDownload[]>([
      ParserUtils.download(address, video?.title ?? '', url, this.keyOf(id))
    ]);
  }

  private config(url: string, body: UUCategoryBody): HttpRequestConfig {
    const headers: UUHeaders = {
      Accept: 'application/json, text/plain, */*',
      'Content-Type': 'application/json'
    };
    return {
      url: url,
      method: http.RequestMethod.POST,
      headers: headers,
      body: body,
      retryable: true
    };
  }

  private keyOf(id: string): string {
    return `uu5-${id}`;
  }
}

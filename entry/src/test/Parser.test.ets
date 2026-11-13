import {
  ArgumentMatchers,
  describe,
  expect,
  it,
  MockKit,
  when
} from '@ohos/hypium';
import { Credentials } from '../main/ets/config/AppSettings';
import { SettingsRepository } from '../main/ets/config/SettingsRepository';
import { Result } from '../main/ets/common/result/Result';
import { HttpClient } from '../main/ets/data/network/HttpClient';
import { PreferenceStore } from '../main/ets/data/storage/PreferenceStore';
import { AParser } from '../main/ets/domain/parser/impl/AParser';
import { F404Parser } from '../main/ets/domain/parser/impl/F404Parser';
import { HuaDuParser } from '../main/ets/domain/parser/impl/HuaDuParser';
import { MadouParser } from '../main/ets/domain/parser/impl/MadouParser';
import { TParser } from '../main/ets/domain/parser/impl/TParser';
import { UUParser } from '../main/ets/domain/parser/impl/UUParser';
import { WebAddress } from '../main/ets/model/AppModels';
import {
  A_DPLAYER_SAMPLE,
  A_MAIN_SAMPLE,
  A_SUB_SAMPLE,
  F404_MAIN_SAMPLE,
  F404_SUB_SAMPLE,
  HUADU_MAIN_SAMPLE,
  HUADU_SUB_SAMPLE,
  MADOU_MAIN_SAMPLE,
  MADOU_SUB_SAMPLE,
  T_MAIN_SAMPLE,
  T_PLAY_SAMPLE,
  T_ROLE_SAMPLE,
  UU_LIST_SAMPLE,
  UUListSampleResponse,
  UU_VIDEO_SAMPLE,
  UUVideoSampleResponse
} from './fixtures/ParserSamples';

function address(type: string, value: string): WebAddress {
  return {
    type: type,
    subType: '',
    address: value,
    selected: false
  };
}

export default function parserTest() {
  describe('Parser fixed samples', () => {
    it('T parser extracts unique pages and download metadata', 0, async () => {
      const parser = new TParser();
      const source = address('0', 'https://t.test/list');
      const main = await parser.parseMainPage(
        source,
        T_MAIN_SAMPLE,
        new Set<string>(['/index.php/vod/role/id/116866.html'])
      );

      expect(main.isSuccess).assertTrue();
      expect(main.value?.totalCount).assertEqual(2);
      expect(main.value?.skippedCount).assertEqual(1);
      expect(main.value?.pages.length).assertEqual(1);
      expect(main.value?.pages[0].address)
        .assertEqual('https://t.test/index.php/vod/role/id/116865.html');

      const role = await parser.parseNestedPages?.(main.value?.pages[0] ?? source, T_ROLE_SAMPLE, new Set<string>());
      expect(role?.value?.totalCount).assertEqual(1);
      expect(role?.value?.pages[0].address)
        .assertEqual('https://t.test/index.php/vod/detail/id/116865.html');

      const sub = await parser.parseSubPage(role?.value?.pages[0] ?? source, T_PLAY_SAMPLE);
      expect(sub.value?.length).assertEqual(1);
      expect(sub.value?.[0].name).assertEqual('古相思曲 古风营帐中的双女主命运纠葛');
      expect(sub.value?.[0].key).assertEqual('/index.php/vod/detail/id/116865.html');
      expect(sub.value?.[0].downloadUrl)
        .assertEqual('https://c10.hs100.top/20261111/0813d6b502cd0e44/index.m3u8');
    });

    it('A parser resolves dplayer response and preserves source key', 0, async () => {
      const client = new HttpClient();
      const mocker = new MockKit();
      const requestText = mocker.mockFunc(client, client.requestText);
      when(requestText)(ArgumentMatchers.any).afterReturn(
        Promise.resolve(Result.success<string>(A_DPLAYER_SAMPLE))
      );
      const parser = new AParser(client);
      const source = address('1', 'http://a.test/list');
      const main = await parser.parseMainPage(source, A_MAIN_SAMPLE, new Set<string>(['item-b']));

      expect(main.value?.totalCount).assertEqual(2);
      expect(main.value?.skippedCount).assertEqual(1);
      expect(main.value?.pages[0].address).assertEqual('http://a.test/index.php/&m=item-a');

      const sub = await parser.parseSubPage(main.value?.pages[0] ?? source, A_SUB_SAMPLE);
      expect(sub.value?.length).assertEqual(1);
      expect(sub.value?.[0].name).assertEqual('A sample');
      expect(sub.value?.[0].key).assertEqual('item-a');
      expect(sub.value?.[0].downloadUrl).assertEqual('https://media.test/a/master.m3u8');
    });

    it('HuaDu parser filters uploaded paths and normalizes escaped URL', 0, async () => {
      const parser = new HuaDuParser();
      const source = address('2', 'https://huadu.test/list');
      const main = await parser.parseMainPage(
        source,
        HUADU_MAIN_SAMPLE,
        new Set<string>(['/vodplay/hd-b-1-1.html'])
      );

      expect(main.value?.totalCount).assertEqual(2);
      expect(main.value?.skippedCount).assertEqual(1);
      expect(main.value?.pages[0].address).assertEqual('https://huadu.test/vodplay/hd-a-1-1.html');

      const detail = main.value?.pages[0] ?? source;
      const sub = await parser.parseSubPage(detail, HUADU_SUB_SAMPLE);
      expect(sub.value?.length).assertEqual(1);
expect(sub.value?.[0].name).assertEqual('HuaDu sample');
      expect(sub.value?.[0].key).assertEqual('/vodplay/hd-a-1-1.html');
      expect(sub.value?.[0].downloadUrl)
        .assertEqual('https://media.test/huadu/master.m3u8');
    });

    it('F404 parser derives the same key for list and detail pages', 0, async () => {
      const parser = new F404Parser();
      const source = address('3', 'https://f404.test/list');
      const main = await parser.parseMainPage(source, F404_MAIN_SAMPLE, new Set<string>());

      expect(main.value?.totalCount).assertEqual(1);
      expect(main.value?.pages[0].address).assertEqual('https://f404.test/key-f/a/b/c/d/');

      const detail = main.value?.pages[0] ?? source;
      const sub = await parser.parseSubPage(detail, F404_SUB_SAMPLE);
      expect(sub.value?.length).assertEqual(1);
      expect(sub.value?.[0].name).assertEqual('F404 sample');
      expect(sub.value?.[0].key).assertEqual('key-f');
      expect(sub.value?.[0].downloadUrl).assertEqual('https://media.test/f404/master.m3u8');
    });

    it('Madou parser extracts last path segment and URL after separator', 0, async () => {
      const parser = new MadouParser();
      const source = address('4', 'https://madou.test/list');
      const main = await parser.parseMainPage(source, MADOU_MAIN_SAMPLE, new Set<string>());

      expect(main.value?.totalCount).assertEqual(1);
      expect(main.value?.pages[0].address).assertEqual('https://madou.test/posts/madou-a/');

      const detail = main.value?.pages[0] ?? source;
      const sub = await parser.parseSubPage(detail, MADOU_SUB_SAMPLE);
      expect(sub.value?.length).assertEqual(1);
      expect(sub.value?.[0].name).assertEqual('Madou sample');
      expect(sub.value?.[0].key).assertEqual('madou-a');
      expect(sub.value?.[0].downloadUrl).assertEqual('https://media.test/madou/master.m3u8');
    });

    it('UU parser filters uploaded list items and uses stored authorization', 0, async () => {
      const client = new HttpClient();
      const settings = new SettingsRepository(new PreferenceStore());
      const mocker = new MockKit();
      const requestJson = mocker.mockFunc(client, client.requestJson);
      when(requestJson)(ArgumentMatchers.any).afterReturn(
        Promise.resolve(Result.success<UUListSampleResponse>(UU_LIST_SAMPLE))
      );
      const credentials: Credentials = {
        aliyunAccessToken: '',
        aliyunLockToken: '',
        aliyunRefreshToken: '',
        quarkCookie: '',
        uuAuthorization: 'redacted-test-authorization'
      };
      const loadCredentials = mocker.mockFunc(settings, settings.loadCredentials);
      when(loadCredentials)().afterReturn(Promise.resolve(credentials));
      const parser = new UUParser(client, settings);
      const source = address('5', 'https://uu.test/pages/list?id=9');
      const main = await parser.parseMainPage(source, '', new Set<string>(['uu5-102']));

      expect(main.value?.totalCount).assertEqual(2);
      expect(main.value?.skippedCount).assertEqual(1);
      expect(main.value?.pages.length).assertEqual(1);
      expect(main.value?.pages[0].address).assertEqual('https://uu.test/pages/video/video?id=101');

      const videoClient = new HttpClient();
      const videoRequest = mocker.mockFunc(videoClient, videoClient.requestJson);
      when(videoRequest)(ArgumentMatchers.any).afterReturn(
        Promise.resolve(Result.success<UUVideoSampleResponse>(UU_VIDEO_SAMPLE))
      );
      const detailParser = new UUParser(videoClient, settings);
      const sub = await detailParser.parseSubPage(main.value?.pages[0] ?? source, '');
      expect(sub.value?.length).assertEqual(1);
      expect(sub.value?.[0].name).assertEqual('UU sample');
      expect(sub.value?.[0].key).assertEqual('uu5-101');
      expect(sub.value?.[0].downloadUrl).assertEqual('https://media.test/uu/master.m3u8');
    });

    it('pure parsers return no downloads for empty detail content', 0, async () => {
      expect((await new TParser().parseSubPage(address('0', 'https://t.test'), '')).value?.length)
        .assertEqual(0);
      expect((await new HuaDuParser().parseSubPage(address('2', 'https://huadu.test'), '')).value?.length)
        .assertEqual(0);
      expect((await new F404Parser().parseSubPage(address('3', 'https://f404.test'), '')).value?.length)
        .assertEqual(0);
      expect((await new MadouParser().parseSubPage(address('4', 'https://madou.test'), '')).value?.length)
        .assertEqual(0);
    });
  });
}

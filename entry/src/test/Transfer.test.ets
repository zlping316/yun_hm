import {
  ArgumentMatchers,
  describe,
  expect,
  it,
  MockKit,
  when
} from '@ohos/hypium';
import { http } from '@kit.NetworkKit';
import { HttpRequestFactory } from '../main/ets/data/network/HttpRequestFactory';
import { JsonFileStore } from '../main/ets/data/storage/JsonFileStore';
import { Aes128Decryptor } from '../main/ets/data/transfer/Aes128Decryptor';
import { HlsPlaylistParser } from '../main/ets/data/transfer/HlsPlaylistParser';
import { TransferRepository } from '../main/ets/data/transfer/TransferRepository';
import {
  CloudProviderType,
  TransferJob,
  TransferState
} from '../main/ets/model/AppModels';

function job(jobId: string, state: TransferState): TransferJob {
  return {
    jobId: jobId,
    name: jobId,
    downloadUrl: `https://media.test/${jobId}.mp4`,
    key: jobId,
    provider: CloudProviderType.ALIYUN,
    localFile: `/data/${jobId}.mp4`,
    state: state,
    progress: 0,
    errorMessage: '',
    selected: false,
    createdAt: 1,
    updatedAt: 1
  };
}

export default function transferTest() {
  describe('Transfer foundations', () => {
    it('keeps the HLS transport on HTTP 1.1 with the requested timeout', 0, () => {
      const options = HttpRequestFactory.createOptions({
        url: 'https://media.test/master.m3u8',
        timeoutMs: 60000,
        protocol: http.HttpProtocol.HTTP1_1
      }, http.HttpDataType.STRING);

      expect(options.connectTimeout).assertEqual(60000);
      expect(options.readTimeout).assertEqual(60000);
      expect(options.usingProtocol).assertEqual(http.HttpProtocol.HTTP1_1);
    });

    it('selects the highest bandwidth variant and resolves its relative URL', 0, () => {
      const playlist = [
        '#EXTM3U',
        '#EXT-X-STREAM-INF:BANDWIDTH=800000',
        'low/index.m3u8',
        '#EXT-X-STREAM-INF:BANDWIDTH=2400000',
        '../high/index.m3u8'
      ].join('\n');

      expect(HlsPlaylistParser.selectMediaPlaylist(
        playlist,
        'https://media.test/video/master/index.m3u8'
      )).assertEqual('https://media.test/video/high/index.m3u8');
    });

    it('normalizes relative root and protocol-relative URLs', 0, () => {
      const base = 'https://media.test/a/b/master.m3u8?token=redacted';

      expect(HlsPlaylistParser.resolveUrl(base, './segment.ts'))
        .assertEqual('https://media.test/a/b/segment.ts');
      expect(HlsPlaylistParser.resolveUrl(base, '/root/../segment.ts?part=1'))
        .assertEqual('https://media.test/segment.ts?part=1');
      expect(HlsPlaylistParser.resolveUrl(base, '//cdn.test/video.ts'))
        .assertEqual('https://cdn.test/video.ts');
    });

    it('inherits AES key metadata and clears it after METHOD NONE', 0, () => {
      const playlist = [
        '#EXTM3U',
        '#EXT-X-MEDIA-SEQUENCE:12',
        '#EXT-X-KEY:METHOD=AES-128,URI="../keys/key.bin",IV=0x01',
        'first.ts',
        'second.ts',
        '#EXT-X-KEY:METHOD=NONE',
        'third.ts'
      ].join('\n');

      const media = HlsPlaylistParser.parseMedia(
        playlist,
        'https://media.test/video/playlist/index.m3u8'
      );

      expect(media.mediaSequence).assertEqual(12);
      expect(media.segments.length).assertEqual(3);
      expect(media.segments[0].url)
        .assertEqual('https://media.test/video/playlist/first.ts');
      expect(media.segments[0].key?.uri)
        .assertEqual('https://media.test/video/keys/key.bin');
      expect(media.segments[1].key?.iv).assertEqual('0x01');
      expect(media.segments[2].key).assertUndefined();
    });

    it('builds AES IV from explicit hex and media sequence', 0, () => {
      const explicit = new Uint8Array(Aes128Decryptor.ivFrom(0, '0x0102'));
      const sequence = new Uint8Array(Aes128Decryptor.ivFrom(0x0102, ''));

      expect(explicit.length).assertEqual(16);
      expect(explicit[13]).assertEqual(0);
      expect(explicit[14]).assertEqual(1);
      expect(explicit[15]).assertEqual(2);
      expect(sequence[13]).assertEqual(0);
      expect(sequence[14]).assertEqual(1);
      expect(sequence[15]).assertEqual(2);
    });

    it('restores active jobs to queued and persists upserts', 0, () => {
      const store = new JsonFileStore();
      const mocker = new MockKit();
      const read = mocker.mockFunc(store, store.read);
      const write = mocker.mockFunc(store, store.write);
      when(read)('transfer_jobs.json').afterReturn(JSON.stringify([
        job('resolving', TransferState.RESOLVING),
        job('downloading', TransferState.DOWNLOADING),
        job('converting', TransferState.CONVERTING),
        job('uploading', TransferState.UPLOADING),
        job('completed', TransferState.COMPLETED)
      ]));
      when(write)(ArgumentMatchers.any, ArgumentMatchers.any).afterReturn(undefined);
      const repository = new TransferRepository(store);

      const restored = repository.load();
      expect(restored[0].state).assertEqual(TransferState.QUEUED);
      expect(restored[1].state).assertEqual(TransferState.QUEUED);
      expect(restored[2].state).assertEqual(TransferState.QUEUED);
      expect(restored[3].state).assertEqual(TransferState.QUEUED);
      expect(restored[4].state).assertEqual(TransferState.COMPLETED);

      const replacement = job('completed', TransferState.FAILED);
      const inserted = job('new', TransferState.QUEUED);
      repository.upsert(restored, replacement);
      repository.upsert(restored, inserted);
      expect(restored.length).assertEqual(6);
      expect(restored[4].state).assertEqual(TransferState.FAILED);
      expect(restored[5].jobId).assertEqual('new');
    });
  });
}

import {
  ArgumentMatchers,
  describe,
  expect,
  it,
  MockKit,
  when
} from '@ohos/hypium';
import { JsonFileStore } from '../main/ets/data/storage/JsonFileStore';
import { TransferRepository } from '../main/ets/data/transfer/TransferRepository';
import {
  decodeAndroidAddressBackup,
  decodeAndroidUploadBackup,
  encodeAndroidAddressBackup,
  encodeAndroidUploadBackup
} from '../main/ets/domain/backup/CloudBackupController';
import { AddressController } from '../main/ets/domain/parser/AddressController';
import { AddressRepository } from '../main/ets/domain/parser/AddressRepository';
import { ParserRegistry } from '../main/ets/domain/parser/ParserRegistry';
import { TParser } from '../main/ets/domain/parser/impl/TParser';
import {
  CloudProviderType,
  TransferJob,
  TransferState,
  WebAddress
} from '../main/ets/model/AppModels';

function webAddress(address: string): WebAddress {
  return {
    type: '0',
    subType: 'source',
    address: address,
    selected: false
  };
}

function completedJob(): TransferJob {
  return {
    jobId: 'completed',
    name: 'completed',
    downloadUrl: 'https://media.test/completed.m3u8',
    key: 'completed-key',
    provider: CloudProviderType.QUARK,
    localFile: '/data/completed.mp4',
    state: TransferState.COMPLETED,
    progress: 100,
    errorMessage: '',
    selected: true,
    createdAt: 1,
    updatedAt: 2
  };
}

interface AndroidAddressBackup {
  type: string;
  name: string;
  address: string;
  isSelected: boolean;
}

interface TransferHistoryBackup {
  downloadUrl: string;
  key: string;
  completedAt: number;
}

export default function syncWorkflowTest() {
  describe('Sync workflow state', () => {
    it('encodes upload history with Android entry format', 0, () => {
      const encoded = encodeAndroidUploadBackup(JSON.stringify([{
        downloadUrl: 'https://media.test/video.m3u8',
        key: 'video-key',
        completedAt: 1
      } as TransferHistoryBackup]));
      const entries = JSON.parse(decodeURIComponent(encoded)) as string[];

      expect(entries.length).assertEqual(1);
      expect(entries[0]).assertEqual('https://media.test/video.m3u8||video-key');
    });

    it('decodes Android upload history into local records', 0, () => {
      const content = encodeURIComponent(JSON.stringify([
        'https://media.test/a.m3u8||key-a',
        null,
        'https://media.test/a.m3u8||duplicate',
        'https://media.test/b.m3u8||key-b'
      ]));
      const history =
        JSON.parse(decodeAndroidUploadBackup(content, 123)) as TransferHistoryBackup[];

      expect(history.length).assertEqual(2);
      expect(history[0].downloadUrl).assertEqual('https://media.test/a.m3u8');
      expect(history[0].key).assertEqual('key-a');
      expect(history[0].completedAt).assertEqual(123);
      expect(history[1].downloadUrl).assertEqual('https://media.test/b.m3u8');
    });

    it('rejects non Android upload backup payloads', 0, () => {
      let rejected = false;
      try {
        decodeAndroidUploadBackup(JSON.stringify({
          version: 1,
          transferHistory: '[]'
        }), 123);
      } catch (_) {
        rejected = true;
      }

      expect(rejected).assertTrue();
    });

    it('encodes address backup with Android field names', 0, () => {
      const encoded = encodeAndroidAddressBackup(JSON.stringify([{
        type: '2',
        subType: 'source',
        address: 'https://source.test/list?name=中文',
        selected: true
      } as WebAddress]));
      const addresses = JSON.parse(decodeURIComponent(encoded)) as AndroidAddressBackup[];

      expect(addresses.length).assertEqual(1);
      expect(addresses[0].type).assertEqual('2');
      expect(addresses[0].name).assertEqual('source');
      expect(addresses[0].address).assertEqual('https://source.test/list?name=中文');
      expect(addresses[0].isSelected).assertTrue();
    });

    it('decodes Android address backup into local field names', 0, () => {
      const content = encodeURIComponent(JSON.stringify([{
        type: '2',
        name: 'source',
        address: 'https://source.test/list?name=中文',
        isSelected: true
      } as AndroidAddressBackup]));
      const addresses =
        JSON.parse(decodeAndroidAddressBackup(content)) as WebAddress[];

      expect(addresses.length).assertEqual(1);
      expect(addresses[0].type).assertEqual('2');
      expect(addresses[0].subType).assertEqual('source');
      expect(addresses[0].address).assertEqual('https://source.test/list?name=中文');
      expect(addresses[0].selected).assertTrue();
    });

    it('persists address add edit selection and duplicate rejection', 0, () => {
      const repository = new AddressRepository(new JsonFileStore());
      const mocker = new MockKit();
      const load = mocker.mockFunc(repository, repository.load);
      const save = mocker.mockFunc(repository, repository.save);
      when(load)().afterReturn([webAddress('https://source.test/list')]);
      when(save)(ArgumentMatchers.any).afterReturn(undefined);
      const controller = new AddressController(repository, new ParserRegistry([new TParser()]));

      const duplicate = controller.add('0', 'duplicate', 'https://source.test/list');
      expect(duplicate.isSuccess).assertFalse();

      const added = controller.add('0', 'second', 'https://source.test/second');
      expect(added.isSuccess).assertTrue();
      expect(added.value?.length).assertEqual(2);
      expect(added.value?.[0].address).assertEqual('https://source.test/second');
      expect(added.value?.[0].selected).assertFalse();

      const selected = controller.setSelected('https://source.test/list', true);
      expect(selected[1].selected).assertTrue();

      const updated = controller.update(
        'https://source.test/second',
        '0',
        'renamed',
        'https://source.test/new-list'
      );
      expect(updated.value?.[0].subType).assertEqual('renamed');
      expect(updated.value?.[0].address).assertEqual('https://source.test/new-list');

      const removed = controller.remove('https://source.test/list');
      expect(removed.length).assertEqual(1);
      expect(removed[0].address).assertEqual('https://source.test/new-list');
    });

    it('replaces hosts for the same Android address type', 0, () => {
      const repository = new AddressRepository(new JsonFileStore());
      const mocker = new MockKit();
      const load = mocker.mockFunc(repository, repository.load);
      const save = mocker.mockFunc(repository, repository.save);
      when(load)().afterReturn([
        webAddress('https://old.test/list'),
        {
          type: '0',
          subType: 'detail',
          address: 'https://old.test/detail?id=1',
          selected: true
        }
      ]);
      when(save)(ArgumentMatchers.any).afterReturn(undefined);
      const controller = new AddressController(repository, new ParserRegistry([new TParser()]));

      const changed = controller.add('0', 'replacement', 'https://new.test/list');

      expect(changed.isSuccess).assertTrue();
      expect(changed.value?.length).assertEqual(2);
      expect(changed.value?.[0].address).assertEqual('https://new.test/list');
      expect(changed.value?.[1].address).assertEqual('https://new.test/detail?id=1');
    });

    it('records completed transfer URLs and keys independently from queue', 0, () => {
      const store = new JsonFileStore();
      const mocker = new MockKit();
      const read = mocker.mockFunc(store, store.read);
      const write = mocker.mockFunc(store, store.write);
      const job = completedJob();
      when(read)('transfer_history.json').afterReturn(JSON.stringify([{
        downloadUrl: job.downloadUrl,
        key: job.key,
        completedAt: job.updatedAt
      }]));
      when(write)(ArgumentMatchers.any, ArgumentMatchers.any).afterReturn(undefined);
      const repository = new TransferRepository(store);

      expect(repository.completedUrls().has(job.downloadUrl)).assertTrue();
      expect(repository.completedKeys().has(job.key)).assertTrue();
    });
  });
}

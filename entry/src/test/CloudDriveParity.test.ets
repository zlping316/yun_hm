import {
  ArgumentMatchers,
  describe,
  expect,
  it,
  MockKit,
  when
} from '@ohos/hypium';
import { AppError, AppErrorCode } from '../main/ets/common/error/AppError';
import { Result } from '../main/ets/common/result/Result';
import { LEGACY_SETTINGS } from '../main/ets/config/LegacyDefaults';
import { SettingsRepository } from '../main/ets/config/SettingsRepository';
import { HttpClient } from '../main/ets/data/network/HttpClient';
import { JsonFileStore } from '../main/ets/data/storage/JsonFileStore';
import { PreferenceStore } from '../main/ets/data/storage/PreferenceStore';
import { QuarkDriveProvider } from '../main/ets/domain/provider/quark/QuarkDriveProvider';
import { PendingShareSelection } from '../main/ets/domain/share/PendingShareSelection';
import { ShareController } from '../main/ets/domain/share/ShareController';
import { ShareFolderUtils } from '../main/ets/domain/share/ShareFolderUtils';
import { ShareRepository } from '../main/ets/domain/share/ShareRepository';
import { CloudProviderType, SearchResult, ShareTask } from '../main/ets/model/AppModels';
import { CloudFile, ShareMetadata } from '../main/ets/model/drive/CloudDriveModels';

interface ControllerFixture {
  controller: ShareController;
  provider: QuarkDriveProvider;
}

function task(id: string, autoSync: boolean, disabled: boolean = false): ShareTask {
  return {
    id: id,
    provider: CloudProviderType.QUARK,
    shareUrl: `https://pan.quark.cn/s/${id}`,
    shareCode: '',
    title: id,
    targetFolderId: 'old-folder',
    targetFolderName: '',
    autoSync: autoSync,
    disabled: disabled,
    status: '等待同步',
    createdAt: 1,
    updatedAt: 1
  };
}

function cloudFile(id: string, name: string, type: string): CloudFile {
  return {
    fileId: id,
    parentFileId: '0',
    name: name,
    type: type,
    size: 0,
    contentHash: '',
    downloadUrl: ''
  };
}

function controllerWith(
  initial: ShareTask[],
  mocker: MockKit
): ControllerFixture {
  const store = new JsonFileStore();
  const repository = new ShareRepository(store, CloudProviderType.QUARK);
  const load = mocker.mockFunc(repository, repository.load);
  const save = mocker.mockFunc(repository, repository.save);
  when(load)().afterReturn(initial);
  when(save)(ArgumentMatchers.any).afterReturn(undefined);
  const provider = new QuarkDriveProvider(
    new HttpClient(),
    new SettingsRepository(new PreferenceStore()),
    LEGACY_SETTINGS
  );
  const controller = new ShareController(provider, repository);
  controller.load();
  return { controller: controller, provider: provider };
}

export default function cloudDriveParityTest() {
  describe('Android cloud drive parity', () => {
    it('keeps folders only and places shared folder first', 0, () => {
      const folders = ShareFolderUtils.rootFolders([
        cloudFile('file', '普通文件', 'file'),
        cloudFile('folder', '其他目录', 'folder'),
        cloudFile('shared', '来自：分享', '0')
      ]);

      expect(folders.length).assertEqual(2);
      expect(folders[0].name).assertEqual('来自：分享');
      expect(folders[1].name).assertEqual('其他目录');
    });

    it('persists an invalid normal share as disabled', 0, async () => {
      const mocker = new MockKit();
      const values = controllerWith([], mocker);
      const metadata = mocker.mockFunc(values.provider, values.provider.getShareMetadata);
      when(metadata)(ArgumentMatchers.any, ArgumentMatchers.any).afterReturn(
        Promise.resolve(Result.failure<ShareMetadata>(
          new AppError(AppErrorCode.NOT_FOUND, 'missing')
        ))
      );

      const result = await values.controller.add({
        shareUrl: 'https://pan.quark.cn/s/invalid-share',
        shareCode: '',
        targetFolderId: 'target',
        targetFolderName: '',
        autoSync: false
      });

      expect(result.isSuccess).assertTrue();
      expect(result.value?.disabled).assertTrue();
      expect(result.value?.title).assertEqual('已失效或不存在');
      expect(result.value?.autoSync).assertFalse();
    });

    it('requires a subfolder for folder links and uses it as title', 0, async () => {
      const mocker = new MockKit();
      const values = controllerWith([], mocker);
      const missing = await values.controller.add({
        shareUrl: 'https://pan.quark.cn/s/folder-share/folder/child',
        shareCode: '',
        targetFolderId: 'target',
        targetFolderName: '',
        autoSync: false
      });
      expect(missing.isSuccess).assertFalse();
      expect(missing.error?.message).assertEqual('请添加子目录！');

      const added = await values.controller.add({
        shareUrl: 'https://pan.quark.cn/s/folder-share/folder/child',
        shareCode: '',
        targetFolderId: 'target',
        targetFolderName: '电视剧',
        autoSync: false
      });
      expect(added.isSuccess).assertTrue();
      expect(added.value?.title).assertEqual('电视剧');
    });

    it('updates target folder and timestamp when auto sync changes', 0, () => {
      const mocker = new MockKit();
      const values = controllerWith([task('toggle', false)], mocker);
      const updated = values.controller.setAutoSync('toggle', true, 'new-folder');

      expect(updated[0].autoSync).assertTrue();
      expect(updated[0].targetFolderId).assertEqual('new-folder');
      expect(updated[0].updatedAt >= updated[0].createdAt).assertTrue();
    });

    it('reports Android progress text for enabled valid tasks only', 0, async () => {
      const mocker = new MockKit();
      const values = controllerWith([
        task('enabled', true),
        task('disabled-link', true, true),
        task('manual', false)
      ], mocker);
      const sync = mocker.mockFunc(values.controller, values.controller.sync);
      when(sync)(ArgumentMatchers.any).afterReturn(Promise.resolve(Result.success<number>(2)));
      const logs: string[] = [];

      const result = await values.controller.syncAutoTasks((line: string) => logs.push(line));

      expect(result.value?.savedCount).assertEqual(2);
      expect(logs.length).assertEqual(1);
      expect(logs[0]).assertEqual('enabled -- 更新 2 个文件！');
    });

    it('restores Android URI encoded share lists', 0, () => {
      const store = new JsonFileStore();
      const mocker = new MockKit();
      const write = mocker.mockFunc(store, store.write);
      when(write)(ArgumentMatchers.any, ArgumentMatchers.any).afterReturn(undefined);
      const repository = new ShareRepository(store, CloudProviderType.QUARK);
      const raw = JSON.stringify([{
        share_url: 'https://pan.quark.cn/s/restored',
        share_name: '恢复任务',
        save_file_id: 'target',
        save_sub_name: '',
        is_auto_sync: false,
        is_disabled: false,
        add_time: 8
      }]);

      const restored = repository.restore(encodeURIComponent(raw));

      expect(restored.length).assertEqual(1);
      expect(restored[0].title).assertEqual('恢复任务');
      expect(restored[0].updatedAt).assertEqual(8);
    });

    it('consumes search selection once and isolates providers', 0, () => {
      const pending = new PendingShareSelection();
      const result: SearchResult = {
        id: 'selection',
        title: 'selection',
        shareUrl: 'https://pan.quark.cn/s/selection',
        shareCode: '',
        provider: CloudProviderType.QUARK,
        source: 'test'
      };
      pending.set(result);

      expect(pending.consume(CloudProviderType.ALIYUN)).assertUndefined();
      expect(pending.consume(CloudProviderType.QUARK)?.id).assertEqual('selection');
      expect(pending.consume(CloudProviderType.QUARK)).assertUndefined();
    });
  });
}

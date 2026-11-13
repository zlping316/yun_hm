import { JsonFileStore } from '../../data/storage/JsonFileStore';
import { CloudProviderType, ShareTask } from '../../model/AppModels';

const ALIYUN_FILE: string = 'link_data.json';
const QUARK_FILE: string = 'quark_link_data.json';

interface LegacyShareTask {
  id?: string;
  provider?: CloudProviderType;
  shareUrl?: string;
  share_url?: string;
  shareCode?: string;
  share_name?: string;
  title?: string;
  targetFolderId?: string;
  save_file_id?: string;
  targetFolderName?: string;
  save_sub_name?: string;
  autoSync?: boolean;
  is_auto_sync?: boolean;
  disabled?: boolean;
  is_disabled?: boolean;
  status?: string;
  createdAt?: number;
  updatedAt?: number;
  add_time?: number;
}

interface PersistedShareTask {
  id: string;
  provider: CloudProviderType;
  share_url: string;
  shareCode: string;
  share_name: string;
  save_file_id: string;
  save_sub_name: string;
  is_auto_sync: boolean;
  is_disabled: boolean;
  status: string;
  add_time: number;
  updatedAt: number;
}

export class ShareRepository {
  private readonly store: JsonFileStore;
  private readonly provider: CloudProviderType;
  private readonly fileName: string;

  constructor(store: JsonFileStore, provider: CloudProviderType) {
    this.store = store;
    this.provider = provider;
    this.fileName = provider === CloudProviderType.ALIYUN ? ALIYUN_FILE : QUARK_FILE;
  }

  load(): ShareTask[] {
    const raw = this.store.read(this.fileName);
    if (raw.length === 0) {
      return [];
    }
    return this.parse(raw);
  }

  restore(raw: string): ShareTask[] {
    let content = raw.trim();
    try {
      JSON.parse(content);
    } catch (_) {
      content = decodeURIComponent(content);
    }
    const tasks = this.parse(content);
    this.save(tasks);
    return tasks;
  }

  private parse(raw: string): ShareTask[] {
    const values = JSON.parse(raw) as LegacyShareTask[];
    const tasks: ShareTask[] = [];
    values.forEach((value: LegacyShareTask) => {
      const shareUrl = value.shareUrl ?? value.share_url ?? '';
      if (shareUrl.length === 0) {
        return;
      }
      const createdAt = value.createdAt ?? value.add_time ?? 0;
      const updatedAt = value.updatedAt ?? value.add_time ?? createdAt;
      tasks.push({
        id: value.id ?? `${this.provider}_${createdAt}_${tasks.length}`,
        provider: this.provider,
        shareUrl: shareUrl,
        shareCode: value.shareCode ?? '',
        title: value.title ?? value.share_name ?? '未命名分享',
        targetFolderId: value.targetFolderId ?? value.save_file_id ??
          (this.provider === CloudProviderType.ALIYUN ? 'root' : '0'),
        targetFolderName: value.targetFolderName ?? value.save_sub_name ?? '',
        autoSync: value.autoSync ?? value.is_auto_sync ?? false,
        disabled: value.disabled ?? value.is_disabled ?? false,
        status: value.status ?? '等待同步',
        createdAt: createdAt,
        updatedAt: updatedAt
      });
    });
    return tasks.sort((left: ShareTask, right: ShareTask) => right.updatedAt - left.updatedAt);
  }

  save(tasks: ShareTask[]): void {
    const values: PersistedShareTask[] = tasks.map((task: ShareTask) => {
      const value: PersistedShareTask = {
        id: task.id,
        provider: task.provider,
        share_url: task.shareUrl,
        shareCode: task.shareCode,
        share_name: task.title,
        save_file_id: task.targetFolderId,
        save_sub_name: task.targetFolderName,
        is_auto_sync: task.autoSync,
        is_disabled: task.disabled,
        status: task.status,
        add_time: task.updatedAt,
        updatedAt: task.updatedAt
      };
      return value;
    });
    this.store.write(this.fileName, JSON.stringify(values));
  }
}

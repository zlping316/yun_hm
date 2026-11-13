import { AppSettings, Credentials } from './AppSettings';
import { LEGACY_CREDENTIALS, LEGACY_SETTINGS } from './LegacyDefaults';
import { PreferenceStore } from '../data/storage/PreferenceStore';
import { CloudProviderType } from '../model/AppModels';

const SETTINGS_KEY: string = 'app_settings';
const CREDENTIALS_KEY: string = 'credentials';

export class SettingsRepository {
  private readonly store: PreferenceStore;

  constructor(store: PreferenceStore) {
    this.store = store;
  }

  async loadSettings(): Promise<AppSettings> {
    const raw = await this.store.getString(SETTINGS_KEY);
    if (raw.length === 0) {
      await this.saveSettings(LEGACY_SETTINGS);
      return LEGACY_SETTINGS;
    }
    const value = JSON.parse(raw) as AppSettings;
    value.defaultProvider = value.defaultProvider ?? CloudProviderType.QUARK;
    value.aliyunDriveId = value.aliyunDriveId ?? LEGACY_SETTINGS.aliyunDriveId;
    value.aliyunLockDriveId = value.aliyunLockDriveId ?? LEGACY_SETTINGS.aliyunLockDriveId;
    value.aliyunLockRootFolderId = value.aliyunLockRootFolderId ??
      LEGACY_SETTINGS.aliyunLockRootFolderId;
    value.aliyunLogFolderId = value.aliyunLogFolderId ?? LEGACY_SETTINGS.aliyunLogFolderId;
    value.aliyunAddressFolderId = value.aliyunAddressFolderId ??
      LEGACY_SETTINGS.aliyunAddressFolderId;
    value.aliyunShareBackupFolderId = value.aliyunShareBackupFolderId ??
      LEGACY_SETTINGS.aliyunShareBackupFolderId;
    value.quarkLogFolderId = value.quarkLogFolderId ?? LEGACY_SETTINGS.quarkLogFolderId;
    value.quarkAddressFolderId = value.quarkAddressFolderId ?? LEGACY_SETTINGS.quarkAddressFolderId;
    value.quarkTransformRootFolderId = value.quarkTransformRootFolderId ??
      LEGACY_SETTINGS.quarkTransformRootFolderId;
    value.quarkBackupFolderId = value.quarkBackupFolderId ?? LEGACY_SETTINGS.quarkBackupFolderId;
    value.downloadConcurrency = value.downloadConcurrency ?? LEGACY_SETTINGS.downloadConcurrency;
    value.uploadConcurrency = value.uploadConcurrency ?? LEGACY_SETTINGS.uploadConcurrency;
    return value;
  }

  async saveSettings(settings: AppSettings): Promise<void> {
    await this.store.putString(SETTINGS_KEY, JSON.stringify(settings));
  }

  async loadCredentials(): Promise<Credentials> {
    const raw = await this.store.getString(CREDENTIALS_KEY);
    if (raw.length === 0) {
      await this.saveCredentials(LEGACY_CREDENTIALS);
      return LEGACY_CREDENTIALS;
    }
    return JSON.parse(raw) as Credentials;
  }

  async saveCredentials(credentials: Credentials): Promise<void> {
    await this.store.putString(CREDENTIALS_KEY, JSON.stringify(credentials));
  }
}

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'yun_preferences';

export class PreferenceStore {
  private store?: preferences.Preferences;

  async initialize(context: common.Context): Promise<void> {
    this.store = await preferences.getPreferences(context, { name: STORE_NAME });
  }

  async getString(key: string, defaultValue: string = ''): Promise<string> {
    const value = await this.requireStore().get(key, defaultValue);
    return value as string;
  }

  async putString(key: string, value: string): Promise<void> {
    await this.requireStore().put(key, value);
    await this.requireStore().flush();
  }

  async getNumber(key: string, defaultValue: number): Promise<number> {
    const value = await this.requireStore().get(key, defaultValue);
    return value as number;
  }

  async putNumber(key: string, value: number): Promise<void> {
    await this.requireStore().put(key, value);
    await this.requireStore().flush();
  }

  async getBoolean(key: string, defaultValue: boolean): Promise<boolean> {
    const value = await this.requireStore().get(key, defaultValue);
    return value as boolean;
  }

  async putBoolean(key: string, value: boolean): Promise<void> {
    await this.requireStore().put(key, value);
    await this.requireStore().flush();
  }

  private requireStore(): preferences.Preferences {
    if (this.store === undefined) {
      throw new Error('PreferenceStore is not initialized');
    }
    return this.store;
  }
}

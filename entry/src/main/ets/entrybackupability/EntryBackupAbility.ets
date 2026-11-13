import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { LsLogger } from '../common/log/LsLogger';

const TAG = 'EntryBackupAbility';

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup() {
    LsLogger.info(TAG, 'Application data backup completed');
    await Promise.resolve();
  }

  async onRestore(bundleVersion: BundleVersion) {
    LsLogger.info(TAG, `Application data restored from version ${bundleVersion.name}`);
    await Promise.resolve();
  }
}

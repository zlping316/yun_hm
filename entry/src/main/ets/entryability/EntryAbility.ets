import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppContainer } from '../AppContainer';
import { LsLogger } from '../common/log/LsLogger';

const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppContainer.getInstance().initialize(this.context).catch((error: Error) => {
      LsLogger.error(TAG, `Initialization failed: ${error.message}`);
    });
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      LsLogger.error(TAG, `Failed to set color mode: ${JSON.stringify(err)}`);
    }
    LsLogger.info(TAG, 'Ability onCreate');
  }

  onDestroy(): void {
    LsLogger.info(TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    LsLogger.info(TAG, 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        LsLogger.error(TAG, `Failed to load content: ${JSON.stringify(err)}`);
        return;
      }
      LsLogger.info(TAG, 'Content loaded');
    });
  }

  onWindowStageDestroy(): void {
    LsLogger.info(TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    LsLogger.info(TAG, 'Ability onForeground');
  }

  onBackground(): void {
    LsLogger.info(TAG, 'Ability onBackground');
  }
}

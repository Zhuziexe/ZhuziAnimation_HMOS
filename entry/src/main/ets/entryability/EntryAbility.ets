import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import window from '@ohos.window';
import { BusinessError } from '@kit.BasicServicesKit';
import { TempFileManager } from '../common/TempFileManager';
import { deviceInfo } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;
const TAG = '[EntryAbility]';

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
    TempFileManager.init(this.context);
    AppStorage.setOrCreate('shouldSaveAndExit', false);
    AppStorage.setOrCreate('editorIsDirty', false);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err: BusinessError, data: void) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading content. Data: %{public}s', JSON.stringify(data));
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }

  onPrepareToTerminate(): boolean {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onPrepareToTerminate');

    if (deviceInfo.deviceType !== '2in1') {
      console.info('onPrepareToTerminate: deviceType is not 2in1');
      return false;
    }

    const isDirty = AppStorage.get<boolean>('editorIsDirty') || false;
    if (!isDirty) {
      console.info('onPrepareToTerminate: editorIsDirty is false');
      return false;
    }

    if (!AppStorage.get<boolean>('shouldSaveAndExit')) {
      AppStorage.setOrCreate('shouldSaveAndExit', true);
      console.info('onPrepareToTerminate: shouldSaveAndExit set to true');
    }

    return true;
  }
}
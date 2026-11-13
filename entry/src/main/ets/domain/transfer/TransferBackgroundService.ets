import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { LsLogger } from '../../common/log/LsLogger';
import { TransferJob, TransferState } from '../../model/AppModels';

const TAG = 'TransferBackground';
const BUNDLE_NAME = 'com.zlp.hm.yun';
const ABILITY_NAME = 'EntryAbility';
const REQUEST_CODE = 1001;

export class TransferBackgroundService {
  private readonly context: common.Context;
  private active: boolean = false;
  private notificationId: number = 0;
  private agent?: WantAgent;

  constructor(context: common.Context) {
    this.context = context;
  }

  async start(): Promise<void> {
    if (this.active) {
      return;
    }
    try {
      this.agent = await wantAgent.getWantAgent({
        wants: [{
          bundleName: BUNDLE_NAME,
          abilityName: ABILITY_NAME,
          parameters: { destination: 'sync' }
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: REQUEST_CODE,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
      const notification = await backgroundTaskManager.startBackgroundRunning(
        this.context,
        ['dataTransfer'],
        this.agent
      );
      this.notificationId = notification.notificationId;
      this.active = true;
      LsLogger.info(TAG, `Continuous task started: ${this.notificationId}`);
    } catch (error) {
      LsLogger.warn(TAG, `Continuous task unavailable: ${this.messageOf(error)}`);
    }
  }

  async update(jobs: TransferJob[]): Promise<void> {
    if (!this.active || this.notificationId <= 0) {
      return;
    }
    const active = jobs.find((job: TransferJob) =>
      job.state === TransferState.DOWNLOADING || job.state === TransferState.UPLOADING);
    const completed = jobs.filter((job: TransferJob) => job.state === TransferState.COMPLETED).length;
    const pending = jobs.filter((job: TransferJob) =>
      job.selected && job.state !== TransferState.COMPLETED && job.state !== TransferState.CANCELED).length;
    const text = active === undefined ?
      `待处理 ${pending}，已完成 ${completed}` :
      `${active.name} ${active.progress}%`;
    try {
      await notificationManager.publish({
        id: this.notificationId,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: '资源同步',
            text: text
          }
        },
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: true,
        tapDismissed: false,
        wantAgent: this.agent
      });
    } catch (error) {
      LsLogger.warn(TAG, `Notification update failed: ${this.messageOf(error)}`);
    }
  }

  async stop(): Promise<void> {
    if (!this.active) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context);
    } catch (error) {
      LsLogger.warn(TAG, `Continuous task stop failed: ${this.messageOf(error)}`);
    } finally {
      this.active = false;
      this.notificationId = 0;
      this.agent = undefined;
    }
  }

  private messageOf(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}

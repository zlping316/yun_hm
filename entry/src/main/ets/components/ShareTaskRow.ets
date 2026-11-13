import { ShareTask } from '../model/AppModels';

@Component
export struct ShareTaskRow {
  @Prop task: ShareTask;
  @Prop busy: boolean = false;
  onOpen: (task: ShareTask) => void = (_task: ShareTask): void => {};
  onCopy: (task: ShareTask) => void = (_task: ShareTask): void => {};
  onDelete: (taskId: string) => void = (_taskId: string): void => {};
  onAutoSyncChange: (taskId: string, enabled: boolean) => void =
    (_taskId: string, _enabled: boolean): void => {};

  build() {
    Row() {
      Text(this.task.title)
        .fontSize(13)
        .fontColor($r('app.color.android_link_blue'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .gesture(
          GestureGroup(
            GestureMode.Exclusive,
            LongPressGesture({ fingers: 1 }).onAction(() => this.onCopy(this.task)),
            TapGesture({ count: 1 }).onAction(() => this.onOpen(this.task))
          )
        )
      Text(this.task.disabled ? '失效' : '有效')
        .fontSize(12)
        .fontColor(this.task.disabled ?
          $r('app.color.android_invalid') : $r('app.color.android_valid'))
        .width(34)
        .textAlign(TextAlign.Center)
      Row({ space: 4 }) {
        Text('同步')
          .fontSize(12)
          .fontColor(Color.Black)
        Toggle({ type: ToggleType.Switch, isOn: this.task.autoSync })
          .width(34)
          .height(22)
          .enabled(!this.busy)
          .onChange((enabled: boolean) => this.onAutoSyncChange(this.task.id, enabled))
      }
      .width(80)
      .justifyContent(FlexAlign.Center)
      Text('删除')
        .fontSize(12)
        .fontColor($r('app.color.android_link_blue'))
        .width(34)
        .textAlign(TextAlign.Center)
        .enabled(!this.busy)
        .onClick(() => this.onDelete(this.task.id))
    }
    .width('100%')
    .height(32)
  }
}

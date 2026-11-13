import { SearchResult } from '../model/AppModels';

@Component
export struct SearchResultRow {
  @Prop result: SearchResult;
  onOpen: (result: SearchResult) => void = (_result: SearchResult): void => {};
  onCopyLink: (result: SearchResult) => void = (_result: SearchResult): void => {};
  onCopyCode: (result: SearchResult) => void = (_result: SearchResult): void => {};
  onAdd: (result: SearchResult) => void = (_result: SearchResult): void => {};

  private shareKey(): string {
    const parts = this.result.shareUrl.split('/').filter((part: string) => part.length > 0);
    return parts.length > 0 ? parts[parts.length - 1] : this.result.shareUrl;
  }

  build() {
    Row() {
      Text(this.result.title)
        .fontSize(14)
        .fontColor($r('app.color.android_valid'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (this.result.shareCode.length > 0) {
        Text(this.result.shareCode)
          .fontSize(14)
          .fontColor($r('app.color.android_valid'))
          .margin({ left: 10 })
          .gesture(
            LongPressGesture({ fingers: 1 })
              .onAction(() => this.onCopyCode(this.result))
          )
      }

      Text(this.shareKey())
        .fontSize(14)
        .fontColor($r('app.color.android_link_blue'))
        .margin({ left: 10 })
        .gesture(
          GestureGroup(
            GestureMode.Exclusive,
            LongPressGesture({ fingers: 1 }).onAction(() => this.onCopyLink(this.result)),
            TapGesture({ count: 1 }).onAction(() => this.onOpen(this.result))
          )
        )

      Text('添加')
        .fontSize(14)
        .fontColor($r('app.color.android_link_blue'))
        .margin({ left: 10 })
        .onClick(() => this.onAdd(this.result))
    }
    .width('100%')
    .padding(10)
  }
}

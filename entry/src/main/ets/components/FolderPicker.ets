import { CloudFile } from '../model/drive/CloudDriveModels';

@Component
export struct FolderPicker {
  @Prop files: CloudFile[] = [];
  @Prop currentFolderName: string = '';
  @Prop canGoUp: boolean = false;
  onOpenFolder: (file: CloudFile) => void = (_file: CloudFile): void => {};
  onGoUp: () => void = (): void => {};
  onRefresh: () => void = (): void => {};

  private isFolder(file: CloudFile): boolean {
    return file.type === 'folder' || file.type === '0';
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button('上级')
          .type(ButtonType.Normal)
          .enabled(this.canGoUp)
          .onClick(() => this.onGoUp())
        Text(this.currentFolderName)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Button('刷新')
          .type(ButtonType.Normal)
          .onClick(() => this.onRefresh())
      }
      .width('100%')

      if (this.files.length === 0) {
        Text('当前目录为空')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .padding({ top: 8, bottom: 8 })
      } else {
        ForEach(this.files, (file: CloudFile) => {
          Row({ space: 10 }) {
            Text(this.isFolder(file) ? '▣' : '▤')
              .fontSize(18)
              .fontColor(this.isFolder(file) ? $r('app.color.accent') : $r('app.color.text_secondary'))
            Column({ space: 2 }) {
              Text(file.name)
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.isFolder(file) ? '文件夹' : `${file.size} B`)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            if (this.isFolder(file)) {
              Text('›')
                .fontSize(22)
                .fontColor($r('app.color.text_secondary'))
            }
          }
          .width('100%')
          .height(52)
          .padding({ left: 10, right: 10 })
          .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
          .onClick(() => {
            if (this.isFolder(file)) {
              this.onOpenFolder(file);
            }
          })
        }, (file: CloudFile) => file.fileId)
      }
    }
    .width('100%')
  }
}

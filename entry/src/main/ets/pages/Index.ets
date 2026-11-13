import { router } from '@kit.ArkUI';

interface HomeAction {
  title: string;
  description: string;
  route: string;
  color: string;
  hidden?: boolean;
}

const ACTIONS: HomeAction[] = [
  {
    title: '阿里云盘',
    description: '目录、分享转存、上传与备份',
    route: 'pages/AliyunDrivePage',
    color: '#087E8B'
  },
  {
    title: '夸克云盘',
    description: '分享管理、搜索与文件传输',
    route: 'pages/QuarkDrivePage',
    color: '#D1495B'
  },
  {
    title: '网页登录',
    description: '更新阿里 Token 或夸克 Cookie',
    route: 'pages/WebLoginPage',
    color: '#3568A8'
  },
  {
    title: '资源同步',
    description: '网页解析、下载队列与自动上传',
    route: 'pages/SyncPage',
    color: '#6B5B95',
    hidden: true
  }
];

@Entry
@Component
struct Index {
  private open(route: string): void {
    router.pushUrl({ url: route });
  }

  build() {
    Column({ space: 20 }) {
      Row() {
        Column({ space: 4 }) {
          Text($r('app.string.app_name'))
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.home_subtitle'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button('设置')
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontColor($r('app.color.accent'))
          .backgroundColor(Color.Transparent)
          .onClick(() => this.open('pages/SettingsPage'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column({ space: 12 }) {
        ForEach(ACTIONS, (item: HomeAction) => {
          Row({ space: 16 }) {
            Divider()
              .vertical(true)
              .strokeWidth(5)
              .color(item.color)
              .height(44)
            Column({ space: 4 }) {
              Text(item.title)
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text(item.description)
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(2)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('›')
              .fontSize(28)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .height(82)
          .padding({ left: 16, right: 16 })
          .opacity(item.hidden ? 0 : 1)
          .backgroundColor(item.hidden ? Color.Transparent : $r('app.color.surface'))
          .borderRadius(6)
          .onClick(() => {
            if (!item.hidden) {
              this.open(item.route);
            }
          })
          .gesture(LongPressGesture({ fingers: 1 }).onAction(() => {
            if (item.hidden) {
              this.open(item.route);
            }
          }))
        }, (item: HomeAction) => item.route)
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding($r('app.float.page_padding'))
    .backgroundColor($r('app.color.page_background'))
    .alignItems(HorizontalAlign.Start)
  }
}

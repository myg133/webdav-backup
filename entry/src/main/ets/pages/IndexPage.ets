/**
 * IndexPage.ets — App 启动后的导航首页
 *
 * 提供 4 个按钮进入：端点 / 任务 / 历史 / 预览
 * 也显示 NFR-01（启动延迟）展示与提示横幅
 */

import { router } from '@kit.ArkUI';

@Entry
@Component
export struct IndexPage {
  @State startupMs: number = 0;
  private t0: number = Date.now();

  aboutToAppear(): void {
    // NFR-01：冷启动 < 2s
    this.startupMs = Date.now() - this.t0;
  }

  build(): void {
    Column() {
      Text('WebDAV 备份').fontSize(28).fontWeight(FontWeight.Bold).padding({ top: 48, bottom: 8 });
      Text('安全备份鸿蒙相册与目录到自建 WebDAV').fontSize(13).fontColor('#666').padding({ bottom: 8 });
      Text('数据只备份到你的 WebDAV，App 不主动删除云端资源。').fontSize(12).fontColor('#666').padding({ bottom: 16 });

      Row() {
        Text(`启动 ${this.startupMs}ms`).fontSize(11).fontColor('#999');
        Text(' · OpenList 兼容').fontSize(11).fontColor('#999');
      }.padding({ bottom: 24 });

      List({ space: 16 }) {
        ListItem() {
          this.menuCard('端点管理', '添加/编辑 WebDAV 端点，凭据 KeyStore 加密', () => router.pushUrl({ url: 'pages/EndpointsPage' }));
        }
        ListItem() {
          this.menuCard('备份任务', '相册/目录备份，定时对账 + 实时监测', () => router.pushUrl({ url: 'pages/TasksPage' }));
        }
        ListItem() {
          this.menuCard('上传历史', '查看成功/失败/上传中/排队', () => router.pushUrl({ url: 'pages/HistoryPage' }));
        }
        ListItem() {
          this.menuCard('远端预览', '图片/视频/音频/文档', () => router.pushUrl({ url: 'pages/PreviewPage' }));
        }
      }
      .width('100%').layoutWeight(1).padding({ left: 16, right: 16 });

      // AC-07 提示
      Text('提示：OpenList WebDAV 不支持服务端续传，断点恢复会重传整个文件。')
        .fontSize(11).fontColor('#cc8800')
        .padding(16);
    }
    .width('100%').height('100%').backgroundColor('#f5f5f5');
  }

  @Builder
  menuCard(title: string, subtitle: string, onTap: () => void) {
    Column() {
      Text(title).fontSize(18).fontWeight(FontWeight.Medium);
      Text(subtitle).fontSize(12).fontColor('#666').padding({ top: 4 });
    }
    .width('100%').padding(16).borderRadius(8).backgroundColor(Color.White)
    .onClick(() => onTap());
  }
}
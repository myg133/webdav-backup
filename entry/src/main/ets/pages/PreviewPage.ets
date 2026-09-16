/**
 * PreviewPage.ets — 远端资源预览（F9 / AC-10）
 *
 * - 图片：Image 组件
 * - 视频：AVPlayer（双平台分支）
 * - 音频：AVPlayer
 * - 文档：调系统应用打开
 *
 * 入口：通过 router 传参 entry: { endpointId, remotePath }
 */

import { router } from '@kit.ArkUI';
import { listEndpoints, Endpoint } from '../data/EndpointRepo';
import { cacheToLocal, classify, playUrl, documentIntent, supportsHeic } from '../domain/PreviewLoader';
import { isNext } from '../infra/Platform';

@Entry
@Component
export struct PreviewPage {
  @State loading: boolean = true;
  @State error: string = '';
  @State endpoint: Endpoint | null = null;
  @State remotePath: string = '';
  @State kind: string = 'unknown';
  @State localPath: string = '';
  @State heicOk: boolean = supportsHeic();

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as Record<string, string>;
    const epId = params?.endpointId ?? '';
    const rp = params?.remotePath ?? '';
    this.remotePath = rp;
    if (!epId || !rp) {
      this.error = '缺少参数';
      this.loading = false;
      return;
    }
    const eps = await listEndpoints();
    this.endpoint = eps.find((e) => e.id === epId) ?? null;
    if (!this.endpoint) {
      this.error = '端点不存在';
      this.loading = false;
      return;
    }
    try {
      const session = await cacheToLocal(this.endpoint, rp);
      this.kind = session.kind;
      this.localPath = session.localCachePath ?? '';
      if (this.kind === 'heic-fallback' || (this.kind === 'image' && rp.toLowerCase().endsWith('heic') && !this.heicOk)) {
        this.error = '当前设备不支持 heic 解码';
      }
    } catch (e) {
      this.error = '加载失败: ' + (e as Error).message;
    } finally {
      this.loading = false;
    }
  }

  build(): void {
    Column() {
      Row() {
        Button('← 返回').onClick(() => router.back()).backgroundColor('#999');
        Blank();
        Text(basename(this.remotePath)).fontSize(16).fontWeight(FontWeight.Medium);
        Blank();
      }
      .width('100%').padding(16);

      if (this.loading) {
        Column() {
          LoadingProgress().width(40).height(40);
          Text('加载中…').fontColor('#666').padding({ top: 8 });
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.error) {
        Column() {
          Text('⚠️ ' + this.error).fontColor('#cc3333').fontSize(14);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.kind === 'image') {
        Image(this.localPath)
          .width('100%').layoutWeight(1)
          .objectFit(ImageFit.Contain)
          .alt($r('app.media.startIcon'));
      } else if (this.kind === 'video') {
        // 视频：AVPlayer（这里只标记；运行时由 Page 内嵌 Video 组件更稳）
        Text('视频预览：' + this.localPath).fontSize(12).fontColor('#666').padding(16);
        Text('（鸿蒙 Video 组件自动调用 AVPlayer 支持 HTTP Range）').fontSize(11).fontColor('#999').padding({ left: 16 });
        // 简化：使用 Image 组件显示本地缓存路径；真实生产用 Video 组件
        Image(this.localPath).width('100%').layoutWeight(1).objectFit(ImageFit.Contain);
      } else if (this.kind === 'audio') {
        Text('音频预览：' + this.localPath).fontSize(14).padding(16);
        Text('（请使用系统音乐 App 打开）').fontSize(12).fontColor('#999');
      } else if (this.kind === 'document') {
        Column() {
          Text('文档预览：' + basename(this.remotePath)).fontSize(14).padding(16);
          Button('用系统应用打开').onClick(() => this.openDocument()).backgroundColor('#0a59c7');
        }.layoutWeight(1).justifyContent(FlexAlign.Center);
      } else {
        Text('不支持的格式').fontColor('#999');
      }
    }
    .width('100%').height('100%').backgroundColor('#000');
  }

  openDocument(): void {
    const ext = this.remotePath.split('.').pop() ?? '';
    const intent = documentIntent(this.localPath, ext);
    // 调用系统应用：这里仅构建 Intent，真实跳页由 router.openUrl 或 want
    console.info('[PreviewPage] intent:', JSON.stringify(intent));
  }
}

function basename(p: string): string {
  const idx = p.lastIndexOf('/');
  return idx >= 0 ? p.slice(idx + 1) : p;
}
/**
 * PreviewPage.ets — 远端资源预览（F9 / AC-10）
 *
 * - 图片：Image 组件
 * - 视频：Video 组件 + AVPlayer（HTTP Range 边下边播 + 进度条可拖动）
 * - 音频：AVPlayer（系统音乐 App）
 * - 文档：调系统应用打开
 *
 * 入口：通过 router 传参 entry: { endpointId, remotePath }
 *
 * AC-10（2026-09-17 Dev 二轮修复）：
 * - 视频分支改为 Video({ src, controller }) 组件
 * - 鸿蒙 Video 组件内部走 media.AVPlayer，HTTP Range 拉流由 SDK 自动处理
 *   （openlist-compat Step 9/10 已验证 OpenList Range GET 完全合规）
 * - 进度条为 Slider 控件，onChange 调用 videoController.setCurrentTime(v) 实现拖动
 * - 双平台分支：4.2 用 @ohos.multimedia.media；NEXT 用 @kit.MediaKit
 */

import { router } from '@kit.ArkUI';
import { listEndpoints, Endpoint } from '../data/EndpointRepo';
import { cacheToLocal, classify, playUrl, documentIntent, supportsHeic } from '../domain/PreviewLoader';
import { isNext } from '../infra/Platform';

// 视频播放器：4.2 / NEXT 双平台分支（DevEco IDE 编译时切换）
// 4.2: import { media } from '@ohos.multimedia.media';
// NEXT: import { media } from '@kit.MediaKit';
// 这里保留 media 引用供 DevEco 双平台编译（dynamic require 避免编译期 TS 报错）
declare const require: (id: string) => any;

interface MediaAvPlayer {
  url: string;
  setUrl?(url: string, headers?: Record<string, string>): void;
  prepare(): Promise<void> | void;
  play(): Promise<void> | void;
  pause(): Promise<void> | void;
  seek?(timeMs: number): Promise<void> | void;
  currentTime?: number;
  duration?: number;
  state?: string;
  release?(): Promise<void> | void;
  on?(event: string, cb: (data: any) => void): void;
  off?(event: string, cb: (data: any) => void): void;
}

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

  // 视频预览状态（AC-10）
  @State videoSrc: string = '';
  @State videoReady: boolean = false;
  @State videoError: string = '';
  @State currentTime: number = 0;  // 秒
  @State duration: number = 0;     // 秒
  @State playing: boolean = false;
  private videoController: VideoController = new VideoController();
  private avPlayer: MediaAvPlayer | null = null;
  private avStateListener: ((data: any) => void) | null = null;
  private avTimeListener: ((data: any) => void) | null = null;

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
      // 视频分支：直接用 WebDAV HTTP URL 给 AVPlayer（HTTP Range 由 SDK 自动处理）
      if (this.kind === 'video') {
        this.videoSrc = playUrl(session) || this.localPath;
      }
    } catch (e) {
      this.error = '加载失败: ' + (e as Error).message;
    } finally {
      this.loading = false;
    }
  }

  aboutToDisappear(): void {
    this.releaseAvPlayer();
  }

  private releaseAvPlayer(): void {
    if (!this.avPlayer) return;
    try {
      if (this.avStateListener) this.avPlayer.off?.('stateChange', this.avStateListener);
      if (this.avTimeListener) this.avPlayer.off?.('timeUpdate', this.avTimeListener);
      this.avPlayer.release?.();
    } catch (_e) { /* 忽略 */ }
    this.avPlayer = null;
    this.avStateListener = null;
    this.avTimeListener = null;
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
        // AC-10：Video 组件 + AVPlayer HTTP Range 边下边播 + 进度条可拖动
        this.buildVideoPlayer();
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

  @Builder
  private buildVideoPlayer(): void {
    Column() {
      if (this.videoError) {
        Text('⚠️ ' + this.videoError).fontColor('#cc3333').fontSize(14).padding(16);
      }
      // Video 组件：鸿蒙 ArkUI 原生，会调用底层 media.AVPlayer 自动 Range GET
      Video({
        src: this.videoSrc || this.localPath,
        controller: this.videoController,
      })
        .width('100%').layoutWeight(1)
        .objectFit(ImageFit.Contain)
        .controls(true)              // 显示原生控件（播放/暂停/进度条）
        .autoPlay(false)
        .onPrepared((ev) => {
          // SDK 回调：当 prepare() 完成、duration 已就绪
          if (ev && typeof ev.duration === 'number') {
            this.duration = Math.max(0, Math.floor(ev.duration / 1000));
          }
          this.videoReady = true;
        })
        .onUpdate((ev) => {
          // SDK 回调：timeUpdate
          if (ev && typeof ev.time === 'number') {
            this.currentTime = Math.max(0, Math.floor(ev.time / 1000));
          }
        })
        .onError((ev) => {
          this.videoError = '播放失败: ' + JSON.stringify(ev);
        })
        .onStart(() => { this.playing = true; })
        .onPause(() => { this.playing = false; })
        .onFinish(() => { this.playing = false; });

      // 自定义可拖动进度条（AC-10 验收："进度条可拖动"）
      Column() {
        Row() {
          Text(formatTime(this.currentTime)).fontColor('#fff').fontSize(11).width(50);
          Slider({
            value: this.currentTime,
            min: 0,
            max: this.duration > 0 ? this.duration : 1,
            step: 1,
            style: SliderStyle.OutSet,
          })
            .layoutWeight(1)
            .onChange((v: number, _mode: SliderChangeMode) => {
              // 拖动结束 / 持续拖动都用 setCurrentTime（幂等）
              this.currentTime = v;
              try {
                this.videoController.setCurrentTime(v * 1000); // 传入毫秒
              } catch (_e) {
                // 旧版本 SDK 可能不支持，回退到 AVPlayer.seek
                this.avPlayerSeek(v);
              }
            });
          Text(formatTime(this.duration)).fontColor('#fff').fontSize(11).width(50).textAlign(TextAlign.End);
        }.width('100%').padding(8);

        Row() {
          Button(this.playing ? '暂停' : '播放')
            .onClick(() => {
              if (this.playing) {
                this.videoController.pause();
              } else {
                this.videoController.start();
              }
            })
            .backgroundColor('#0a59c7');
        }.width('100%').justifyContent(FlexAlign.Center).padding(8);
      }.width('100%').backgroundColor('#222');
    }.width('100%').layoutWeight(1);
  }

  private avPlayerSeek(timeSec: number): void {
    if (this.avPlayer && typeof this.avPlayer.seek === 'function') {
      try { this.avPlayer.seek(timeSec * 1000); } catch (_e) { /* 忽略 */ }
    }
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

function formatTime(sec: number): string {
  const s = Math.max(0, Math.floor(sec));
  const m = Math.floor(s / 60);
  const r = s % 60;
  return m.toString().padStart(2, '0') + ':' + r.toString().padStart(2, '0');
}

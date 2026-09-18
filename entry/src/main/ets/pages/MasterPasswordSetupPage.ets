/**
 * MasterPasswordSetupPage.ets — 首次启动设置主密码（F9）
 *
 * 流程（REQ-004 F9）：
 *   1. 检测到用户没设过主密码（hasAnyMasterKey() == false）
 *   2. 用户输入主密码 + 确认密码
 *   3. 调用 deriveMasterKey(pwd, salt) → 32 字节 master key
 *   4. 存到 MasterKeyRepo（KeyStore 加密落库）
 *   5. 进入主页（IndexPage）
 *
 * 关键 UI 约束：
 *   - 必须显示"主密码丢失 = 数据永久丢失"警告
 *   - 密码至少 8 位（UX 软约束；不阻塞提交）
 *   - 两次密码必须一致
 *
 * 注：本页"任意端点设过主密码"即视为"已设"；多端点共享同一主密码（与设计概要一致）
 */

import { promptAction, router } from '@kit.ArkUI';
import { deriveMasterKey } from '../domain/MasterKey';
import { saveMasterKey, hasAnyMasterKey } from '../data/MasterKeyRepo';
import { listEndpoints } from '../data/EndpointRepo';

@Entry
@Component
export struct MasterPasswordSetupPage {
  @State password: string = '';
  @State password2: string = '';
  @State busy: boolean = false;
  @State errorText: string = '';

  aboutToAppear(): void {
    // 已有主密码 → 直接进主页
    hasAnyMasterKey().then((exists) => {
      if (exists) {
        router.replaceUrl({ url: 'pages/IndexPage' });
      }
    });
  }

  build(): void {
    Column() {
      Text('设置主密码').fontSize(28).fontWeight(FontWeight.Bold).padding({ top: 48, bottom: 8 });
      Text('WebDAV 备份的端到端加密').fontSize(13).fontColor('#666').padding({ bottom: 24 });

      // 警告横幅（REQ-004 F1.4 关键约束）
      Column() {
        Text('⚠️ 主密码丢失 = 数据永久丢失').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#cc3333');
        Text('本应用**不提供**密码重置通道（除"删除端点重建"）。请妥善保存主密码，建议记录在安全位置。')
          .fontSize(12).fontColor('#666').padding({ top: 4 });
      }
      .width('90%').padding(16).borderRadius(8).backgroundColor('#fff4e6').margin({ bottom: 24 });

      TextInput({ placeholder: '主密码（≥ 8 位）', text: this.password })
        .type(InputType.Password)
        .onChange((v) => this.password = v)
        .width('90%').padding(8).margin({ bottom: 12 });

      TextInput({ placeholder: '再次输入主密码', text: this.password2 })
        .type(InputType.Password)
        .onChange((v) => this.password2 = v)
        .width('90%').padding(8).margin({ bottom: 16 });

      if (this.errorText) {
        Text(this.errorText).fontSize(12).fontColor('#cc3333').padding({ bottom: 12 });
      }

      Button(this.busy ? '处理中…' : '设置主密码').onClick(() => this.submit())
        .width('90%').height(44).backgroundColor(this.busy ? '#999' : '#0a59c7')
        .enabled(!this.busy);
    }
    .width('100%').height('100%').backgroundColor('#f5f5f5');
  }

  async submit(): Promise<void> {
    this.errorText = '';
    if (!this.password || this.password.length < 8) {
      this.errorText = '主密码至少 8 位';
      return;
    }
    if (this.password !== this.password2) {
      this.errorText = '两次密码不一致';
      return;
    }
    this.busy = true;
    try {
      const eps = await listEndpoints();
      // 当前以"任意端点"为 scope：第一个端点（若有）设主密码；否则占位一个 dummy 端点
      // —— 多端点共享同一主密码的设计概要决策
      const epId = eps.length > 0 ? eps[0].id : '__default__';
      const masterKey = await deriveMasterKey(this.password, freshSalt());
      await saveMasterKey(epId, masterKey);
      promptAction.showToast({ message: '主密码设置成功', duration: 1500 });
      router.replaceUrl({ url: 'pages/IndexPage' });
    } catch (e) {
      this.errorText = '设置失败: ' + (e as Error).message;
    } finally {
      this.busy = false;
    }
  }
}

/** 生成新 salt（首次设置；后续用同一 salt 保证幂等） */
function freshSalt(): Uint8Array {
  const out = new Uint8Array(16);
  for (let i = 0; i < 16; i++) out[i] = Math.floor(Math.random() * 256);
  return out;
}
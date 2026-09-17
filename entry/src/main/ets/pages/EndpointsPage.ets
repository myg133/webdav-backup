/**
 * EndpointsPage.ets — 端点管理 UI（AC-01 / AC-02 / F1）
 *
 * - 列表：现有端点 + "新增"按钮
 * - 编辑/新增表单：name / url / username / password / rootPath / enabled
 * - "测试连接"按钮
 * - 删除按钮（二次确认）
 * - 顶部：断点续传限制提示（AC-07 用户体验要求）
 */

import { promptAction, router } from '@kit.ArkUI';
import {
  listEndpoints,
  createEndpoint,
  updateEndpoint,
  deleteEndpoint,
  Endpoint,
  NewEndpointInput,
  revealPassword,
} from '../data/EndpointRepo';
import { testConnection } from '../domain/WebDAVClient';

@Entry
@Component
export struct EndpointsPage {
  @State endpoints: Endpoint[] = [];
  @State showForm: boolean = false;
  @State editing: Endpoint | null = null;
  @State formName: string = '';
  @State formUrl: string = '';
  @State formUser: string = '';
  @State formPass: string = '';
  @State formRoot: string = '/backup';
  @State formEnabled: boolean = true;
  @State testing: Map<string, { ok: boolean; detail: string }> = new Map();

  aboutToAppear(): void {
    this.refresh();
  }

  async refresh(): Promise<void> {
    this.endpoints = await listEndpoints();
  }

  build(): void {
    Column() {
      // 顶部标题栏
      Row() {
        Text('WebDAV 端点').fontSize(22).fontWeight(FontWeight.Bold);
        Blank();
        Button('新增').onClick(() => this.openCreateForm()).backgroundColor('#0a59c7');
      }
      .width('100%').padding(16);

      // AC-07 提示
      Text('提示：OpenList WebDAV 不支持服务端续传，断点恢复时会重传整个文件。')
        .fontSize(12)
        .fontColor(Color.Gray)
        .padding({ left: 16, right: 16, bottom: 8 });

      // 列表
      List({ space: 12 }) {
        ForEach(this.endpoints, (ep: Endpoint) => {
          ListItem() {
            this.endpointCard(ep);
          }
        }, (ep: Endpoint) => ep.id);
      }
      .width('100%').layoutWeight(1).padding({ left: 16, right: 16 });

      // 表单弹层
      if (this.showForm) {
        this.formSheet();
      }
    }
    .width('100%').height('100%').backgroundColor('#f5f5f5');
  }

  @Builder
  endpointCard(ep: Endpoint) {
    Column() {
      Row() {
        Text(ep.name).fontSize(16).fontWeight(FontWeight.Medium);
        Blank();
        Text(ep.enabled ? '已启用' : '已停用')
          .fontSize(12)
          .fontColor(ep.enabled ? '#0a7e2c' : '#999999');
      }
      .width('100%');
      Text(ep.url).fontSize(12).fontColor('#666666').padding({ top: 4 });
      Text(`用户: ${ep.username}   根: ${ep.rootPath}`).fontSize(12).fontColor('#666666').padding({ top: 2 });
      if (ep.passwordFallback) {
        Text('⚠️ 当前使用本地兜底加密（KeyStore 不可用）').fontSize(11).fontColor('#cc8800').padding({ top: 4 });
      }

      Row() {
        Button(this.testing.get(ep.id)?.ok !== undefined ? '测试结果: ' + this.testing.get(ep.id)?.detail : '测试连接')
          .onClick(() => this.testConnection(ep))
          .height(32).fontSize(12).backgroundColor('#5a8bdc');
        Blank();
        Button('编辑').onClick(() => this.openEditForm(ep)).height(32).fontSize(12).backgroundColor('#888888');
        Button('删除').onClick(() => this.confirmDelete(ep)).height(32).fontSize(12).backgroundColor('#cc3333').margin({ left: 8 });
      }
      .width('100%').padding({ top: 8 });
    }
    .width('100%').padding(12).borderRadius(8).backgroundColor(Color.White);
  }

  @Builder
  formSheet() {
    Column() {
      Blank();
      Column() {
        Text(this.editing ? '编辑端点' : '新增端点').fontSize(18).fontWeight(FontWeight.Bold).padding({ bottom: 12 });
        TextInput({ placeholder: '名称', text: this.formName })
          .onChange((v) => this.formName = v).width('100%').padding(8);
        TextInput({ placeholder: 'https://openlist.example.com/dav', text: this.formUrl })
          .onChange((v) => this.formUrl = v).width('100%').padding(8);
        TextInput({ placeholder: '用户名', text: this.formUser })
          .onChange((v) => this.formUser = v).width('100%').padding(8);
        TextInput({ placeholder: '密码', text: this.formPass })
          .onChange((v) => this.formPass = v).width('100%').padding(8).type(InputType.Password);
        TextInput({ placeholder: '根目录', text: this.formRoot })
          .onChange((v) => this.formRoot = v).width('100%').padding(8);
        Row() {
          Text('启用').fontSize(14);
          Blank();
          Toggle({ type: ToggleType.Switch, isOn: this.formEnabled })
            .onChange((v) => this.formEnabled = v);
        }.width('100%').padding({ top: 8, bottom: 12 });

        Row() {
          Button('取消').onClick(() => this.closeForm()).backgroundColor('#999999');
          Blank();
          Button('保存').onClick(() => this.saveForm()).backgroundColor('#0a59c7');
        }.width('100%');
      }
      .width('100%').padding(16).backgroundColor(Color.White).borderRadius({ topLeft: 12, topRight: 12 });
    }
    .width('100%').height('100%').backgroundColor('rgba(0,0,0,0.4)').onClick(() => this.closeForm());
  }

  openCreateForm(): void {
    this.editing = null;
    this.formName = '';
    this.formUrl = '';
    this.formUser = '';
    this.formPass = '';
    this.formRoot = '/backup';
    this.formEnabled = true;
    this.showForm = true;
  }

  openEditForm(ep: Endpoint): void {
    this.editing = ep;
    this.formName = ep.name;
    this.formUrl = ep.url;
    this.formUser = ep.username;
    this.formPass = revealPassword(ep);
    this.formRoot = ep.rootPath;
    this.formEnabled = ep.enabled;
    this.showForm = true;
  }

  closeForm(): void {
    this.showForm = false;
  }

  async saveForm(): Promise<void> {
    if (!this.formName || !this.formUrl || !this.formUser) {
      promptAction.showToast({ message: '请填写完整（名称/URL/用户）', duration: 1500 });
      return;
    }
    try {
      if (this.editing) {
        await updateEndpoint(
          {
            ...this.editing,
            name: this.formName,
            url: this.formUrl,
            username: this.formUser,
            rootPath: this.formRoot,
            enabled: this.formEnabled,
          },
          this.formPass || undefined
        );
      } else {
        if (!this.formPass) {
          promptAction.showToast({ message: '请填写密码', duration: 1500 });
          return;
        }
        const input: NewEndpointInput = {
          name: this.formName,
          url: this.formUrl,
          username: this.formUser,
          password: this.formPass,
          rootPath: this.formRoot,
          enabled: this.formEnabled,
        };
        await createEndpoint(input);
      }
      this.showForm = false;
      await this.refresh();
    } catch (e) {
      promptAction.showToast({ message: '保存失败: ' + (e as Error).message, duration: 2000 });
    }
  }

  async testConnection(ep: Endpoint): Promise<void> {
    this.testing.set(ep.id, { ok: false, detail: '测试中…' });
    this.testing = new Map(this.testing);
    try {
      const r = await testConnection(ep);
      this.testing.set(ep.id, { ok: r.ok, detail: r.detail });
      this.testing = new Map(this.testing);
    } catch (e) {
      this.testing.set(ep.id, { ok: false, detail: (e as Error).message });
      this.testing = new Map(this.testing);
    }
  }

  async confirmDelete(ep: Endpoint): Promise<void> {
    try {
      const confirmed = await promptAction.showDialog({
        title: '删除端点',
        message: `确认删除 "${ep.name}"？远端资源不会被删除。`,
        buttons: [{ text: '取消', color: '#666' }, { text: '删除', color: '#cc3333' }],
      });
      if (confirmed?.index === 1) {
        await deleteEndpoint(ep.id);
        await this.refresh();
      }
    } catch (_e) {}
  }
}
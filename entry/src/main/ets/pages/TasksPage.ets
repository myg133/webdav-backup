/**
 * TasksPage.ets — 备份任务管理 UI（F2 / F3）
 *
 * AC-03 相册 / AC-04 目录 / AC-05 定时对账 / AC-11 仅 Wi-Fi
 */

import { promptAction } from '@kit.ArkUI';
import {
  listTasks, createTask, deleteTask, updateTask,
  BackupTask, SourceType, NewBackupTask,
} from '../data/TaskRepo';
import { listEndpoints, Endpoint } from '../data/EndpointRepo';
import { BackupEngine } from '../domain/BackupEngine';
import { UploadQueue } from '../domain/UploadQueue';

@Entry
@Component
export struct TasksPage {
  @State tasks: BackupTask[] = [];
  @State endpoints: Endpoint[] = [];
  @State showForm: boolean = false;
  @State formEndpointId: string = '';
  @State formSourceType: SourceType = 'gallery';
  @State formSourcePath: string = '/Download';
  @State formDestPath: string = '/photos';
  @State formRealtime: boolean = true;
  @State formCron: 1 | 6 | 12 = 6;
  @State formWifiOnly: boolean = true;
  @State reconciling: Set<string> = new Set();
  private engine: BackupEngine = new BackupEngine(new UploadQueue());

  aboutToAppear(): void {
    this.refresh();
  }

  async refresh(): Promise<void> {
    this.tasks = await listTasks();
    this.endpoints = await listEndpoints();
    if (this.endpoints.length > 0 && !this.formEndpointId) {
      this.formEndpointId = this.endpoints[0].id;
    }
  }

  build(): void {
    Column() {
      Row() {
        Text('备份任务').fontSize(22).fontWeight(FontWeight.Bold);
        Blank();
        Button('新增').onClick(() => this.openCreateForm()).backgroundColor('#0a59c7');
      }
      .width('100%').padding(16);

      if (this.endpoints.length === 0) {
        Text('请先在"端点"页添加至少一个 WebDAV 端点').fontColor('#cc8800').padding(16);
      } else {
        List({ space: 12 }) {
          ForEach(this.tasks, (t: BackupTask) => {
            ListItem() {
              this.taskCard(t);
            }
          }, (t: BackupTask) => t.id);
        }.width('100%').layoutWeight(1).padding({ left: 16, right: 16 });
      }

      if (this.showForm) {
        this.formSheet();
      }
    }
    .width('100%').height('100%').backgroundColor('#f5f5f5');
  }

  @Builder
  taskCard(t: BackupTask) {
    Column() {
      Row() {
        Text(t.sourceType === 'gallery' ? '相册 → ' + t.destPath : '目录 → ' + t.destPath)
          .fontSize(16).fontWeight(FontWeight.Medium);
        Blank();
        Text(t.enabled ? '启用' : '停用').fontSize(12).fontColor(t.enabled ? '#0a7e2c' : '#999');
      }.width('100%');
      Text(`端点: ${this.endpointName(t.endpointId)}`).fontSize(12).fontColor('#666').padding({ top: 4 });
      Text(`源: ${t.sourceType === 'gallery' ? '相册（自动）' : (t.sourcePath ?? '?')}`).fontSize(12).fontColor('#666');
      Text(`实时监测: ${t.realtime ? '是' : '否'} | 对账: ${t.cronInterval}h | 仅Wi-Fi: ${t.wifiOnly ? '是' : '否'}`)
        .fontSize(12).fontColor('#666');

      Row() {
        Button(this.reconciling.has(t.id) ? '对账中…' : '立即对账')
          .onClick(() => this.runReconcile(t))
          .height(32).fontSize(12)
          .backgroundColor(this.reconciling.has(t.id) ? '#888' : '#0a7e2c');
        Blank();
        Button('编辑').onClick(() => this.openEditForm(t)).height(32).fontSize(12).backgroundColor('#888');
        Button('删除').onClick(() => this.deleteOne(t)).height(32).fontSize(12).backgroundColor('#cc3333').margin({ left: 8 });
      }.width('100%').padding({ top: 8 });
    }
    .width('100%').padding(12).borderRadius(8).backgroundColor(Color.White);
  }

  @Builder
  formSheet() {
    Column() {
      Blank();
      Column() {
        Text('备份任务').fontSize(18).fontWeight(FontWeight.Bold).padding({ bottom: 12 });

        // 端点选择
        Row() {
          Text('端点:').fontSize(14);
          Blank();
          Select(this.endpoints.map((e) => ({ value: e.id, text: e.name })))
            .selected(this.endpoints.findIndex((e) => e.id === this.formEndpointId))
            .onSelect((idx) => { this.formEndpointId = this.endpoints[idx].id; })
            .width(200);
        }.width('100%').padding({ top: 4, bottom: 8 });

        // 源类型
        Row() {
          Text('源类型:').fontSize(14);
          Blank();
          Select([
            { value: 'gallery', text: '相册' },
            { value: 'directory', text: '目录' },
          ]).selected(this.formSourceType === 'gallery' ? 0 : 1)
            .onSelect((idx) => {
              this.formSourceType = idx === 0 ? 'gallery' : 'directory';
            })
            .width(200);
        }.width('100%').padding({ bottom: 8 });

        if (this.formSourceType === 'directory') {
          TextInput({ placeholder: '本地目录路径', text: this.formSourcePath })
            .onChange((v) => this.formSourcePath = v).width('100%').padding(8);
        }
        TextInput({ placeholder: '远端目标目录', text: this.formDestPath })
          .onChange((v) => this.formDestPath = v).width('100%').padding(8);

        Row() {
          Text('实时监测').fontSize(14);
          Blank();
          Toggle({ type: ToggleType.Switch, isOn: this.formRealtime })
            .onChange((v) => this.formRealtime = v);
        }.width('100%').padding({ top: 8, bottom: 4 });

        Row() {
          Text('对账间隔:').fontSize(14);
          Blank();
          Select([
            { value: '1', text: '1 小时' },
            { value: '6', text: '6 小时' },
            { value: '12', text: '12 小时' },
          ]).selected(this.formCron === 1 ? 0 : this.formCron === 6 ? 1 : 2)
            .onSelect((idx) => {
              this.formCron = idx === 0 ? 1 : idx === 1 ? 6 : 12;
            })
            .width(120);
        }.width('100%').padding({ bottom: 4 });

        Row() {
          Text('仅 Wi-Fi').fontSize(14);
          Blank();
          Toggle({ type: ToggleType.Switch, isOn: this.formWifiOnly })
            .onChange((v) => this.formWifiOnly = v);
        }.width('100%').padding({ bottom: 12 });

        Row() {
          Button('取消').onClick(() => this.showForm = false).backgroundColor('#999');
          Blank();
          Button('保存').onClick(() => this.saveForm()).backgroundColor('#0a59c7');
        }.width('100%');
      }
      .width('100%').padding(16).backgroundColor(Color.White).borderRadius({ topLeft: 12, topRight: 12 });
    }
    .width('100%').height('100%').backgroundColor('rgba(0,0,0,0.4)').onClick(() => this.showForm = false);
  }

  endpointName(id: string): string {
    return this.endpoints.find((e) => e.id === id)?.name ?? '(?)';
  }

  openCreateForm(): void {
    this.formEndpointId = this.endpoints[0]?.id ?? '';
    this.formSourceType = 'gallery';
    this.formSourcePath = '/Download';
    this.formDestPath = '/photos';
    this.formRealtime = true;
    this.formCron = 6;
    this.formWifiOnly = true;
    this.showForm = true;
  }

  openEditForm(t: BackupTask): void {
    this.formEndpointId = t.endpointId;
    this.formSourceType = t.sourceType;
    this.formSourcePath = t.sourcePath ?? '';
    this.formDestPath = t.destPath;
    this.formRealtime = t.realtime;
    this.formCron = t.cronInterval;
    this.formWifiOnly = t.wifiOnly;
    this.showForm = true;
  }

  async saveForm(): Promise<void> {
    if (!this.formEndpointId || !this.formDestPath) {
      promptAction.showToast({ message: '请选择端点并填写远端目录', duration: 1500 });
      return;
    }
    const input: NewBackupTask = {
      endpointId: this.formEndpointId,
      sourceType: this.formSourceType,
      sourcePath: this.formSourceType === 'directory' ? this.formSourcePath : undefined,
      destPath: this.formDestPath,
      realtime: this.formRealtime,
      cronInterval: this.formCron,
      wifiOnly: this.formWifiOnly,
    };
    try {
      await createTask(input);
      this.showForm = false;
      await this.refresh();
    } catch (e) {
      promptAction.showToast({ message: '保存失败: ' + (e as Error).message, duration: 2000 });
    }
  }

  async deleteOne(t: BackupTask): Promise<void> {
    try {
      const c = await promptAction.showDialog({
        title: '删除任务',
        message: `确认删除 "${t.destPath}"？已上传的远端文件不会被删除。`,
        buttons: [{ text: '取消', color: '#666' }, { text: '删除', color: '#cc3333' }],
      });
      if (c?.index === 1) {
        await deleteTask(t.id);
        await this.refresh();
      }
    } catch (_e) {}
  }

  async runReconcile(t: BackupTask): Promise<void> {
    const ep = this.endpoints.find((e) => e.id === t.endpointId);
    if (!ep) {
      promptAction.showToast({ message: '端点不存在', duration: 1500 });
      return;
    }
    this.reconciling.add(t.id);
    this.reconciling = new Set(this.reconciling);
    try {
      await this.engine.reconcile(t, ep);
      promptAction.showToast({ message: '对账完成', duration: 1500 });
    } catch (e) {
      promptAction.showToast({ message: '对账失败: ' + (e as Error).message, duration: 2000 });
    } finally {
      this.reconciling.delete(t.id);
      this.reconciling = new Set(this.reconciling);
    }
  }
}
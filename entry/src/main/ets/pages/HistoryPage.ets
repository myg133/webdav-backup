/**
 * HistoryPage.ets — 上传历史 UI（F7 / AC-08 / AC-09 状态）
 *
 * - 4 个页签：成功 / 失败 / 上传中 / 排队
 * - 每行：文件名、字节数、时间、状态、错误
 * - 顶部：失败重试按钮
 */

import { promptAction } from '@kit.ArkUI';
import {
  listHistory,
  HistoryRecord,
  HistoryStatus,
  listFailedRetryable,
} from '../data/HistoryRepo';
import { listTasks, BackupTask } from '../data/TaskRepo';
import { listEndpoints, Endpoint } from '../data/EndpointRepo';
import { BackupEngine } from '../domain/BackupEngine';
import { UploadQueue } from '../domain/UploadQueue';

@Entry
@Component
export struct HistoryPage {
  @State tabIndex: number = 0;
  @State allRecords: HistoryRecord[] = [];
  @State tasks: BackupTask[] = [];
  @State endpoints: Endpoint[] = [];
  private engine: BackupEngine = new BackupEngine(new UploadQueue());

  aboutToAppear(): void {
    this.refresh();
  }

  async refresh(): Promise<void> {
    this.allRecords = await listHistory({ limit: 500 });
    this.tasks = await listTasks();
    this.endpoints = await listEndpoints();
  }

  build(): void {
    Column() {
      Row() {
        Text('上传历史').fontSize(22).fontWeight(FontWeight.Bold);
        Blank();
        Button('重试失败').onClick(() => this.retryFailed()).backgroundColor('#cc8800');
      }
      .width('100%').padding(16);

      Tabs({ index: this.tabIndex }) {
        TabContent('成功 ' + this.countOf('success')) { this.listView('success'); }
        TabContent('失败 ' + this.countOf('failed')) { this.listView('failed'); }
        TabContent('上传中 ' + this.countOf('uploading')) { this.listView('uploading'); }
        TabContent('排队 ' + this.countOf('pending')) { this.listView('pending'); }
      }
      .onChange((idx) => { this.tabIndex = idx; })
      .barMode(BarMode.Fixed)
      .width('100%').layoutWeight(1);
    }
    .width('100%').height('100%').backgroundColor('#f5f5f5');
  }

  countOf(status: HistoryStatus): number {
    return this.allRecords.filter((r) => r.status === status).length;
  }

  @Builder
  listView(status: HistoryStatus) {
    const filtered = this.allRecords.filter((r) => r.status === status);
    if (filtered.length === 0) {
      Text('暂无记录').fontColor('#999').padding(20);
    } else {
      List({ space: 8 }) {
        ForEach(filtered, (r: HistoryRecord) => {
          ListItem() {
            this.recordCard(r);
          }
        }, (r: HistoryRecord) => r.id);
      }.width('100%').layoutWeight(1);
    }
  }

  @Builder
  recordCard(r: HistoryRecord) {
    Column() {
      Row() {
        Text(basename(r.filePath)).fontSize(14).fontWeight(FontWeight.Medium);
        Blank();
        Text(r.status).fontSize(12).fontColor(this.statusColor(r.status));
      }.width('100%');
      Text(r.filePath).fontSize(11).fontColor('#666').padding({ top: 2 });
      Text(`→ ${r.remotePath}   ${(r.bytes / 1024).toFixed(1)} KB`).fontSize(11).fontColor('#666');
      Text(`开始: ${formatTime(r.startedAt)}${r.finishedAt ? '   结束: ' + formatTime(r.finishedAt) : ''}`)
        .fontSize(11).fontColor('#666');
      if (r.error) {
        Text('错误: ' + r.error).fontSize(11).fontColor('#cc3333').padding({ top: 2 });
      }
      if (r.status === 'failed' && r.retryCount >= 5) {
        Text('重试次数耗尽').fontSize(11).fontColor('#cc8800');
      }
    }
    .width('100%').padding(10).borderRadius(6).backgroundColor(Color.White);
  }

  statusColor(status: HistoryStatus): string {
    if (status === 'success') return '#0a7e2c';
    if (status === 'failed') return '#cc3333';
    if (status === 'uploading') return '#0a59c7';
    return '#888888';
  }

  async retryFailed(): Promise<void> {
    let total = 0;
    for (const t of this.tasks) {
      const recs = await listFailedRetryable(t.id);
      if (recs.length === 0) continue;
      const ep = this.endpoints.find((e) => e.id === t.endpointId);
      if (!ep) continue;
      const items = recs.map((r) => ({
        task: t,
        endpoint: ep,
        filePath: r.filePath,
        remotePath: r.remotePath,
        fileSize: 0,
      }));
      this.engine['queue'].enqueueBatch(items);
      total += items.length;
    }
    promptAction.showToast({ message: `已入队 ${total} 个重试`, duration: 1500 });
    await this.refresh();
  }
}

function basename(p: string): string {
  const idx = p.lastIndexOf('/');
  return idx >= 0 ? p.slice(idx + 1) : p;
}

function formatTime(ms: number): string {
  if (!ms) return '-';
  const d = new Date(ms);
  return `${d.getMonth() + 1}-${d.getDate()} ${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}
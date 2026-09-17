/**
 * BackupEngine.ets — 增量对账 + 触发编排（设计概要 §4.1 / §4.4）
 *
 * 核心职责：
 * 1. reconcile(task): 增量对账某备份任务（F4.1）
 *    - 列出本地 source 下所有文件
 *    - PROPFIND 远端 destPath
 *    - 对账：远端缺 → 入队上传；本地缺 → 标记"远端保留"；都对账 → 比指纹
 * 2. onGalleryChange / onDirectoryChange: 实时触发（F3.1）
 * 3. onWifiOnline: 网络恢复触发（F3.3）
 * 4. startScheduler / stopScheduler: 定时对账（WorkScheduler）
 *
 * 不删除远端（AC-09）。
 */

import { UploadQueue, QueueItem } from './UploadQueue';
import { propfind, head } from './WebDAVClient';
import {
  computeFingerprint,
  isFingerprintMatch,
} from './Fingerprint';
import {
  BackupTask,
  markReconciled,
} from '../data/TaskRepo';
import {
  listByTask,
  Fingerprint,
} from '../data/FingerprintRepo';
import { Endpoint } from '../data/EndpointRepo';
import { info, warn, error as logError } from '../infra/Logger';
import { isWiFiOnlyOk } from '../infra/NetworkMonitor';

declare const require: (id: string) => any;

export class BackupEngine {
  private queue: UploadQueue;
  private listeners: ((e: any) => void)[] = [];

  constructor(queue: UploadQueue) {
    this.queue = queue;
  }

  on(cb: (e: any) => void): void {
    this.listeners.push(cb);
  }
  off(cb: (e: any) => void): void {
    this.listeners = this.listeners.filter((x) => x !== cb);
  }

  private emit(e: any): void {
    for (const cb of this.listeners) {
      try { cb(e); } catch (_e) {}
    }
  }

  /**
   * 增量对账（F4.1）
   */
  async reconcile(task: BackupTask, endpoint: Endpoint): Promise<void> {
    if (!task.enabled) return;

    // F3.4：Wi-Fi only 检查
    if (task.wifiOnly) {
      const net = await isWiFiOnlyOk();
      if (!net.wifi) {
        warn('[BackupEngine] skip reconcile: not on Wi-Fi', { task: task.id });
        this.emit({ type: 'skipped', reason: 'wifi-only', taskId: task.id });
        return;
      }
    }

    info('[BackupEngine] reconcile start', { task: task.id });

    // 1. 列出本地 source 下文件
    const localFiles = await this.listLocalFiles(task);
    info('[BackupEngine] local files', { count: localFiles.length, task: task.id });

    // 2. 列出远端 PROPFIND
    const remoteEntries = await propfind(endpoint, task.destPath);
    const remoteByName = new Map<string, { contentLength: number; lastModified: string }>();
    for (const e of remoteEntries) {
      if (!e.isCollection) {
        remoteByName.set(decodeURIComponent(e.href.split('/').pop() ?? ''), {
          contentLength: e.contentLength,
          lastModified: e.lastModified,
        });
      }
    }
    info('[BackupEngine] remote files', { count: remoteByName.size, task: task.id });

    // 3. 加载本任务指纹
    const fingerprints = await listByTask(task.id);
    const fpByPath = new Map<string, Fingerprint>();
    for (const fp of fingerprints) fpByPath.set(fp.filePath, fp);

    // 4. 对账
    const items: QueueItem[] = [];
    for (const local of localFiles) {
      const baseName = local.fileName;
      const remoteInfo = remoteByName.get(baseName);
      const fp = fpByPath.get(local.filePath);

      if (!remoteInfo) {
        // 远端缺 → 上传
        items.push({
          task,
          endpoint,
          filePath: local.filePath,
          remotePath: joinPath(task.destPath, baseName),
          fileSize: local.size,
        });
        continue;
      }

      // 远端有 → 比 size+mtime
      const headInfo = await head(endpoint, joinPath(task.destPath, baseName));
      if (headInfo.contentLength === local.size) {
        // size 一致 → 进一步比指纹
        if (fp) {
          // 已经有指纹；重新计算本地指纹对照
          try {
            const cur = await computeFingerprint(local.filePath, local.size, local.mtime);
            if (isFingerprintMatch(fp, cur)) {
              // 跳过
              continue;
            }
          } catch (e) {
            // 读失败 → 入队重传
          }
        } else {
          // 没指纹但 size 一致 → 跳过一次（可能是上轮未落指纹就成功上传）
          continue;
        }
      }

      // size/mtime 不一致 → 入队
      items.push({
        task,
        endpoint,
        filePath: local.filePath,
        remotePath: joinPath(task.destPath, baseName),
        fileSize: local.size,
      });
    }

    // 5. 本地缺、远端有 → 仅标记本地"远端保留"，**不删远端**
    for (const [name, _info] of remoteByName) {
      if (!localFiles.some((l) => l.fileName === name)) {
        this.emit({ type: 'remote-kept', taskId: task.id, file: name });
      }
    }

    // 6. 入队
    if (items.length > 0) {
      this.queue.enqueueBatch(items);
    }

    await markReconciled(task.id);
    this.emit({ type: 'reconciled', taskId: task.id, uploaded: items.length });
  }

  /**
   * 触发一次对账（按所有启用任务）。EntryAbility.onCreate 时调用。
   */
  async reconcileAll(tasks: { task: BackupTask; endpoint: Endpoint }[]): Promise<void> {
    for (const { task, endpoint } of tasks) {
      try {
        await this.reconcile(task, endpoint);
      } catch (e) {
        logError('[BackupEngine] reconcile failed', { err: (e as Error).message, task: task.id });
      }
    }
  }

  /**
   * 实时触发：相册新增
   */
  async onGalleryChange(assets: { uri: string; fileName: string; filePath?: string }[],
                         task: BackupTask, endpoint: Endpoint): Promise<void> {
    for (const a of assets) {
      if (!a.filePath) continue;
      this.queue.enqueue({
        task,
        endpoint,
        filePath: a.filePath,
        remotePath: joinPath(task.destPath, a.fileName),
        fileSize: 0,
      });
    }
  }

  /**
   * 实时触发：目录新增
   */
  async onDirectoryChange(path: string, fileName: string, size: number,
                          task: BackupTask, endpoint: Endpoint): Promise<void> {
    this.queue.enqueue({
      task,
      endpoint,
      filePath: path,
      remotePath: joinPath(task.destPath, fileName),
      fileSize: size,
    });
  }

  // ────────────────────────────────────────────────────────────────
  // 本地文件列举
  // ────────────────────────────────────────────────────────────────

  private async listLocalFiles(task: BackupTask): Promise<{
    filePath: string; fileName: string; size: number; mtime: number;
  }[]> {
    try {
      const fs = require('@ohos.file.fs');
      if (task.sourceType === 'gallery') {
        return this.listGalleryAssets(task);
      }
      if (!task.sourcePath) return [];
      const list = fs.listDirSync(task.sourcePath, { recursion: false } as any);
      return (list ?? []).map((it: any) => ({
        filePath: it.path,
        fileName: it.name,
        size: Number(it.size ?? 0),
        mtime: Number(it.mtime ?? 0),
      })).filter((it: any) => !it.fileName.startsWith('.'));
    } catch (e) {
      logError('[BackupEngine] listLocalFiles failed', { err: (e as Error).message });
      return [];
    }
  }

  private async listGalleryAssets(_task: BackupTask): Promise<{
    filePath: string; fileName: string; size: number; mtime: number;
  }[]> {
    // 占位：真实取 PhotoAccessKit 的资产列表（依赖 Platform 分支）
    // 在测试中返回空数组（由测试层 mock）
    return [];
  }
}

// 路径拼接
function joinPath(a: string, b: string): string {
  if (!a) return b;
  if (a.endsWith('/')) return a + b;
  return a + '/' + b;
}
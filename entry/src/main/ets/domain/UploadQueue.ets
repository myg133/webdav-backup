/**
 * UploadQueue.ets — 上传队列 + 指数退避（AC-08 / F6）
 *
 * 设计概要 §4.3：
 *   attempt = 0
 *   while attempt < 5:
 *     try upload
 *     catch HTTPError:
 *       attempt += 1
 *       sleep(2 ** attempt)  # 1, 2, 4, 8, 16 秒
 *   status = 'failed'
 *
 * 队列模型：
 * - 内部维护 FIFO 队列
 * - 同时只跑 1 个上传任务（WebDAV server-side 单连接友好；避免并发抢占带宽）
 * - 失败后等待指数退避再重试
 * - 5 次后写入 history.failed，停止重试
 *
 * 重要：与 BackupEngine 解耦。UploadQueue 只负责单个文件的重试；调度由 BackupEngine 调用。
 */

import {
  putFile,
  head,
  sha256Hex,
  HeadResult,
} from './WebDAVClient';
import { Endpoint } from '../data/EndpointRepo';
import {
  createHistory,
  updateHistory,
  HistoryRecord,
} from '../data/HistoryRepo';
import { upsertFingerprint } from '../data/FingerprintRepo';
import { BackupTask } from '../data/TaskRepo';
import { info, warn, error as logError } from '../infra/Logger';

export interface QueueItem {
  task: BackupTask;
  endpoint: Endpoint;
  filePath: string;
  remotePath: string;
  fileSize: number;
}

export type QueueEvent =
  | { type: 'enqueued'; item: QueueItem }
  | { type: 'started'; item: QueueItem; historyId: string }
  | { type: 'progress'; item: QueueItem; sent: number; total: number; historyId: string }
  | { type: 'succeeded'; item: QueueItem; historyId: string; sha256: string; bytes: number }
  | { type: 'failed'; item: QueueItem; historyId: string; error: string; retries: number }
  | { type: 'queue-empty' };

export type QueueEventCallback = (e: QueueEvent) => void;

const MAX_RETRIES = 5;

export class UploadQueue {
  private items: QueueItem[] = [];
  private inflight: QueueItem | null = null;
  private listeners: QueueEventCallback[] = [];
  private stopped = false;

  on(cb: QueueEventCallback): void {
    this.listeners.push(cb);
  }

  off(cb: QueueEventCallback): void {
    this.listeners = this.listeners.filter((x) => x !== cb);
  }

  private emit(e: QueueEvent): void {
    for (const cb of this.listeners) {
      try { cb(e); } catch (err) { /* 忽略 */ }
    }
  }

  enqueue(item: QueueItem): void {
    this.items.push(item);
    info('[UploadQueue] enqueued', { file: item.filePath });
    this.emit({ type: 'enqueued', item });
    if (!this.inflight) this.kick();
  }

  enqueueBatch(items: QueueItem[]): void {
    if (items.length === 0) return;
    this.items.push(...items);
    info('[UploadQueue] enqueueBatch', { count: items.length });
    this.emit({ type: 'enqueued', item: items[0] });
    if (!this.inflight) this.kick();
  }

  size(): number {
    return this.items.length + (this.inflight ? 1 : 0);
  }

  stop(): void {
    this.stopped = true;
  }

  resume(): void {
    this.stopped = false;
    if (!this.inflight) this.kick();
  }

  /** 立即处理队列中下一项 */
  private async kick(): Promise<void> {
    if (this.stopped) return;
    if (this.inflight) return;
    const next = this.items.shift();
    if (!next) {
      this.emit({ type: 'queue-empty' });
      return;
    }
    this.inflight = next;
    try {
      await this.runOne(next);
    } finally {
      this.inflight = null;
      if (this.items.length > 0 && !this.stopped) {
        // 异步继续
        setTimeout(() => this.kick(), 0);
      } else if (this.items.length === 0) {
        this.emit({ type: 'queue-empty' });
      }
    }
  }

  /**
   * 单文件上传 + 指数退避
   * 返回是否最终成功
   */
  private async runOne(item: QueueItem): Promise<boolean> {
    let attempt = 0;
    let lastErr = '';

    while (attempt < MAX_RETRIES) {
      const history: HistoryRecord = await createHistory({
        taskId: item.task.id,
        endpointId: item.endpoint.id,
        filePath: item.filePath,
        remotePath: item.remotePath,
        bytes: 0,
        status: attempt === 0 ? 'uploading' : 'pending',
        retryCount: attempt,
      });

      this.emit({ type: 'started', item, historyId: history.id });

      try {
        // AC-07 修订版：每次上传前先 HEAD 探测远端
        // 状态机：
        //   server_len == 0 → 第一次上传（不预判，所有上传都是"整文件"）
        //   server_len == total → 跳过（指纹或 mtime 对账已表明一致）
        //   server_len < total → 重传整文件（OpenList 不支持追加）
        //   server_len > total → 跳过 + 警告（理论不应发生）
        const headInfo: HeadResult = await head(item.endpoint, item.remotePath);
        if (headInfo.contentLength === item.fileSize) {
          // 远端已有同长度文件——按 AC-06 指纹判定逻辑应当已"跳过"；
          // 这里兜底：直接标记成功
          info('[UploadQueue] head: skip (size matched)', { remote: item.remotePath });
          await updateHistory(history.id, {
            status: 'success',
            bytes: item.fileSize,
            finishedAt: Date.now(),
          });
          this.emit({
            type: 'succeeded',
            item,
            historyId: history.id,
            sha256: '',
            bytes: item.fileSize,
          });
          return true;
        }

        // 整文件 PUT
        const r = await putFile(item.endpoint, item.filePath, item.remotePath, {
          progress: (sent, total) => this.emit({ type: 'progress', item, sent, total, historyId: history.id }),
        });

        if (r.ok && r.sha256) {
          await updateHistory(history.id, {
            status: 'success',
            bytes: r.bytes,
            finishedAt: Date.now(),
          });
          // 更新指纹库
          await upsertFingerprint({
            filePath: item.filePath,
            endpointId: item.endpoint.id,
            taskId: item.task.id,
            remotePath: item.remotePath,
            size: r.bytes,
            mtime: Date.now(),
            hashHead: '',
            hashTail: '',
            sha256: r.sha256,
          });
          this.emit({
            type: 'succeeded',
            item,
            historyId: history.id,
            sha256: r.sha256,
            bytes: r.bytes,
          });
          return true;
        }

        // 上传未成功（HTTP 4xx/5xx）
        lastErr = `HTTP ${r.status}`;
      } catch (e) {
        lastErr = (e as Error).message;
        logError('[UploadQueue] upload failed', { err: lastErr, file: item.filePath });
      }

      attempt += 1;
      await updateHistory(history.id, {
        status: 'pending',
        retryCount: attempt,
        error: lastErr,
      });

      if (attempt >= MAX_RETRIES) {
        await updateHistory(history.id, {
          status: 'failed',
          finishedAt: Date.now(),
        });
        this.emit({
          type: 'failed',
          item,
          historyId: history.id,
          error: lastErr,
          retries: attempt,
        });
        return false;
      }

      // 指数退避：1, 2, 4, 8 秒（最后一次 16 秒超出 MAX 但不进；按 attempt 计算）
      const sleepSec = Math.min(16, Math.pow(2, attempt));
      warn(`[UploadQueue] retry in ${sleepSec}s`, { file: item.filePath, attempt });
      await sleep(sleepSec * 1000);
    }

    return false;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

/** 工具：把字符串路径拆出 basename/parent */
export function splitPath(remotePath: string): { parent: string; base: string } {
  const idx = remotePath.lastIndexOf('/');
  if (idx < 0) return { parent: '', base: remotePath };
  return { parent: remotePath.slice(0, idx), base: remotePath.slice(idx + 1) };
}

/** 工具：URL-encode path 各段（保留 /） */
export function encodePathSegments(p: string): string {
  return p.split('/').map((seg) => encodeURIComponent(seg)).join('/');
}
/**
 * UploadQueue.pure.ts — UploadQueue 指数退避重试状态机（纯 TS 实现，便于测试）
 *
 * 与 ArkTS 版本 UploadQueue.ets 等价；可在 Node.js 测试环境跑。
 *
 * 测试关注点：
 *   - 状态机正确转换：started → succeeded/failed
 *   - 指数退避：attempt 1,2,3,4 → sleep 1,2,4,8 秒
 *   - 5 次后 status=failed
 */

export interface PureQueueItem {
  id: string;
  endpointId: string;
  size: number;
  remotePath: string;
}

export type PureQueueEvent =
  | { type: 'started'; item: PureQueueItem; historyId: string; attempt: number }
  | { type: 'progress'; item: PureQueueItem; sent: number; total: number }
  | { type: 'succeeded'; item: PureQueueItem; historyId: string }
  | { type: 'failed'; item: PureQueueItem; historyId: string; retries: number; reason: string }
  | { type: 'retry-scheduled'; item: PureQueueItem; attempt: number; sleepSec: number };

export interface PureUploader {
  upload(item: PureQueueItem): Promise<{ ok: boolean; status: number; bytes: number }>;
}

const MAX_RETRIES = 5;

export class PureUploadQueue {
  private items: PureQueueItem[] = [];
  private listeners: ((e: PureQueueEvent) => void)[] = [];
  private uploader: PureUploader;
  private now = 0;
  private historyCounter = 0;

  constructor(uploader: PureUploader) {
    this.uploader = uploader;
  }

  on(cb: (e: PureQueueEvent) => void): void {
    this.listeners.push(cb);
  }

  private emit(e: PureQueueEvent): void {
    for (const cb of this.listeners) {
      try { cb(e); } catch (_e) {}
    }
  }

  private newHistoryId(): string {
    return 'h' + (++this.historyCounter).toString(36);
  }

  enqueue(item: PureQueueItem): void {
    this.items.push(item);
  }

  size(): number {
    return this.items.length;
  }

  /** 用 fake clock 跑一轮（不真正等待）；返回最终状态 */
  async runOnce(): Promise<{ succeeded: number; failed: number }> {
    let succeeded = 0;
    let failed = 0;
    while (this.items.length > 0) {
      const item = this.items.shift()!;
      const r = await this.runOne(item);
      if (r === 'success') succeeded += 1;
      else failed += 1;
    }
    return { succeeded, failed };
  }

  private async runOne(item: PureQueueItem): Promise<'success' | 'failed'> {
    let attempt = 0;
    let lastErr = '';

    while (attempt < MAX_RETRIES) {
      const historyId = this.newHistoryId();
      this.emit({ type: 'started', item, historyId, attempt });

      try {
        const r = await this.uploader.upload(item);
        if (r.ok) {
          this.emit({ type: 'succeeded', item, historyId });
          return 'success';
        }
        lastErr = `HTTP ${r.status}`;
      } catch (e) {
        lastErr = (e as Error).message;
      }

      attempt += 1;
      if (attempt >= MAX_RETRIES) {
        const historyId2 = this.newHistoryId();
        this.emit({ type: 'failed', item, historyId: historyId2, retries: attempt, reason: lastErr });
        return 'failed';
      }

      // 指数退避序列：[1, 2, 4, 8] 秒（attempt 从 1 开始；MAX_RETRIES=5，第 5 次 attempt 后直接判定 failed 不再 sleep）
      // 设计概要 §4.3 / AC-08 acceptance：1s / 2s / 4s / 8s / 16s（5 次重试）
      // Dev 二轮决策（2026-09-17）：保留文档原意 → attempt=1 → 1s, attempt=2 → 2s, ..., attempt=4 → 8s
      const sleepSec = Math.min(16, Math.pow(2, attempt - 1));
      this.emit({ type: 'retry-scheduled', item, attempt, sleepSec });
    }

    return 'failed';
  }
}
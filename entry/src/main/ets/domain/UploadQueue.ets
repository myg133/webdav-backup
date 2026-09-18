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
  put,
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
import { encryptFile, encryptFilename, E2E_AUTH_ERROR } from './E2ECrypto';
import { loadMasterKey } from '../data/MasterKeyRepo';
import { upsertRemotePath, getRemotePath } from '../data/RemotePathRepo';

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
        // REQ-004：e2e 开关下，远端文件大小 ≠ 明文大小；不依赖 size 比对去重
        // （指纹库已用 sha256 兜底）。e2e 路径跳过 size 比对。
        if (!item.endpoint.e2eEnabled && headInfo.contentLength === item.fileSize) {
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
        let r: { ok: boolean; status: number; bytes: number; sha256?: string };
        if (item.endpoint.e2eEnabled) {
          r = await this.uploadEncrypted(item, history.id);
        } else {
          r = await putFile(item.endpoint, item.filePath, item.remotePath, {
            progress: (sent, total) => this.emit({ type: 'progress', item, sent, total, historyId: history.id }),
          });
        }

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

            // 指数退避序列：[1, 2, 4, 8] 秒（attempt 从 1 开始；MAX_RETRIES=5，第 5 次 attempt 后直接判定 failed 不再 sleep）
      // 设计概要 §4.3 / AC-08 acceptance：1s / 2s / 4s / 8s / 16s（5 次重试）
      // Dev 二轮决策（2026-09-17）：保留文档原意 → attempt=1 → 1s, attempt=2 → 2s, ..., attempt=4 → 8s
      // 注：MAX_RETRIES=5 含义是重试 5 次，但第 5 次失败后不再 sleep，直接判 failed；
      //     所以 5 次重试 对应的实际 sleep 序列是 [1, 2, 4, 8]（4 次 sleep）+ 第 5 次直接 failed。
      //     此决策已与 QA 在 traceability / verification-report 中对齐。
      const sleepSec = Math.min(16, Math.pow(2, attempt - 1));
      warn(`[UploadQueue] retry in ${sleepSec}s`, { file: item.filePath, attempt });
      await sleep(sleepSec * 1000);
    }

    return false;
  }

  /**
   * 加密上传路径（REQ-004 F4）：
   *   1. 读取本地明文
   *   2. master key + salt → 加载；失败抛错（不该走到这、KeyStore 不可用 fallback）
   *   3. AES-256-GCM 加密 → .wde 字节流
   *   4. 文件名加密 → base64url + .wde
   *   5. PUT .wde 到远端
   *   6. 记 RemotePathRepo 映射
   *   7. 计算原明文 sha256 → 记 fingerprint（明文 size）
   *
   * 失败重试 = 整文件重加密 + 重 PUT（与 REQ-001 §4.2 一致）
   */
  private async uploadEncrypted(
    item: QueueItem,
    historyId: string
  ): Promise<{ ok: boolean; status: number; bytes: number; sha256?: string }> {
    // 1. 加载 master key
    const mk = await loadMasterKey(item.endpoint.id);
    if (!mk) {
      throw new Error('e2e enabled but no master key for endpoint');
    }
    const masterKey = mk.masterKey;

    // 2. 读本地文件（依赖注入 fs；MVP 一次性读）
    const fs = tryLoadFs();
    if (!fs) {
      throw new Error('fs 模块不可用');
    }
    const stat = fs.statSync(item.filePath);
    const total = Number(stat?.size ?? 0);
    const stream = fs.createReadStream(item.filePath);
    const buf = stream.read?.() ?? new ArrayBuffer(total);
    const arr = buf instanceof ArrayBuffer ? new Uint8Array(buf) : (buf as Uint8Array);
    if (arr.byteLength !== total) {
      throw new Error(`read size mismatch: got ${arr.byteLength}, expected ${total}`);
    }

    // 3. 计算明文 sha256（记 fingerprint 用）
    const sha256 = await sha256Hex(arr);

    // 4. 加密
    let ctBuf: ArrayBuffer;
    let encRemoteName: string;
    try {
      const origName = baseName(item.remotePath);
      ctBuf = await encryptFile(arr.buffer, origName, arr.byteLength, masterKey);
      encRemoteName = await encryptFilename(origName, masterKey);
    } catch (e) {
      // 加密失败（如 master key 解密错误）→ 抛 E2E_AUTH_ERROR 不外泄
      if ((e as Error).name === 'E2E_AUTH_ERROR') {
        throw e;
      }
      throw new Error(`e2e encrypt error: ${(e as Error).message}`);
    }

    // 5. 拼装远端路径：与原 remotePath 共享 parent，basename 改为 encRemoteName
    const parent = parentOf(item.remotePath);
    const encRemotePath = (parent ? parent + '/' : '') + encRemoteName;

    // 6. PUT 到远端
    try { this.emit({ type: 'progress', item, sent: 0, total: ctBuf.byteLength, historyId }); } catch (_e) {}
    const r = await put(item.endpoint, encRemotePath, new Uint8Array(ctBuf), {
      progress: (sent, total) => this.emit({ type: 'progress', item, sent, total, historyId }),
    });
    try { this.emit({ type: 'progress', item, sent: ctBuf.byteLength, total: ctBuf.byteLength, historyId }); } catch (_e) {}

    if (r.ok) {
      // 7. 记 RemotePathRepo 映射
      try {
        await upsertRemotePath(item.endpoint.id, item.filePath, encRemotePath, parent);
      } catch (e) {
        warn('[UploadQueue] failed to upsert remote path', { err: (e as Error).message });
      }
    }

    return { ok: r.ok, status: r.status, bytes: arr.byteLength, sha256 };
  }
}

/** 工具：取路径中的 basename */
function baseName(p: string): string {
  const idx = p.lastIndexOf('/');
  return idx < 0 ? p : p.slice(idx + 1);
}

/** 工具：取路径中的 parent（不含末尾 /） */
function parentOf(p: string): string {
  const idx = p.lastIndexOf('/');
  return idx < 0 ? '' : p.slice(0, idx);
}

/** 工具：fs 动态加载（与 WebDAVClient 的 tryLoadFs 镜像） */
function tryLoadFs(): any {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    return require('@ohos.file.fs');
  } catch (_e) {
    return null;
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
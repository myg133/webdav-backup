/**
 * Logger.ets — 本地日志（最多 7 天轮转，NFR-04：50MB 上限）
 *
 * - 文件名：log_<yyyy-MM-dd>.txt
 * - 路径：App 私有目录
 * - 轮转策略：启动时清理 > 7 天的旧文件
 * - 上限：单文件 5MB，超过则归档为 .old（简化实现；不依赖 OS 服务）
 *
 * 不上传（按 NFR 与隐私要求）
 */

declare const require: (id: string) => any;
declare const getContext: () => any;

const RETAIN_DAYS = 7;
const MAX_FILE_BYTES = 5 * 1024 * 1024;

function logDir(): string {
  try {
    const fs = require('@ohos.file.fs');
    const ctx = typeof getContext === 'function' ? getContext() : null;
    const base = ctx?.filesDir ?? '/data/storage/el2/base/files';
    return base + '/webdav_logs';
  } catch (_e) {
    return '/data/storage/el2/base/files/webdav_logs';
  }
}

function ensureDir(): void {
  try {
    const fs = require('@ohos.file.fs');
    if (!fs.mkdirSync(fs.pathJoin(logDir(), 'x').replace(/\/x$/, ''))) {
      // 已存在或创建成功，忽略
    }
  } catch (_e) {}
}

function dateStamp(): string {
  const d = new Date();
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

function rotateIfNeeded(): void {
  try {
    const fs = require('@ohos.file.fs');
    const file = logDir() + `/log_${dateStamp()}.txt`;
    if (!fs.accessSync?.(file, fs.AccessSyncMode.EXIST)) return;
    const stat = fs.statSync?.(file);
    if (stat && stat.size > MAX_FILE_BYTES) {
      fs.renameSync(file, file + '.old');
    }
  } catch (_e) {}
}

function cleanupOld(): void {
  try {
    const fs = require('@ohos.file.fs');
    const list = fs.listDirSync(logDir(), { recursion: false } as any);
    const today = Date.now();
    for (const item of list ?? []) {
      const m = /log_(\d{4}-\d{2}-\d{2})\.txt/.exec(item.name);
      if (!m) continue;
      const ts = Date.parse(m[1]);
      if (!isNaN(ts) && (today - ts) > RETAIN_DAYS * 86_400_000) {
        fs.unlinkSync(item.path);
      }
    }
  } catch (_e) {}
}

export function log(level: 'info' | 'warn' | 'error', msg: string, ctx?: Record<string, unknown>): void {
  try {
    ensureDir();
    cleanupOld();
    rotateIfNeeded();

    const fs = require('@ohos.file.fs');
    const file = logDir() + `/log_${dateStamp()}.txt`;
    const line =
      `[${new Date().toISOString()}] [${level.toUpperCase()}] ${msg}` +
      (ctx ? ' ' + JSON.stringify(ctx) : '') +
      '\n';
    const exists = fs.accessSync?.(file, fs.AccessSyncMode.EXIST);
    if (exists) {
      const prev = fs.readTextSync?.(file) ?? '';
      fs.writeTextSync?.(file, prev + line);
    } else {
      fs.writeTextSync?.(file, line);
    }
  } catch (_e) {
    // 静默失败；NFR 要求不上传
  }
}

export function info(msg: string, ctx?: Record<string, unknown>): void {
  log('info', msg, ctx);
}

export function warn(msg: string, ctx?: Record<string, unknown>): void {
  log('warn', msg, ctx);
}

export function error(msg: string, ctx?: Record<string, unknown>): void {
  log('error', msg, ctx);
}

/** 启动时调用一次：清理超期日志 */
export function initLogRetention(): void {
  cleanupOld();
  rotateIfNeeded();
}
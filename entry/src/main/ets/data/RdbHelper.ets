/**
 * RdbHelper.ets — 关系型存储封装
 *
 * 数据模型（设计概要 §3）：
 * - endpoints（WebDAV 端点）
 * - backup_tasks（备份任务）
 * - fingerprints（本地文件指纹：path / size / mtime / head+tail sha1）
 * - history（上传历史）
 *
 * 双平台：使用 `@ohos.data.relationalStore`（API 9 起就稳定；NEXT 兼容）。
 */

declare const require: (id: string) => any;
declare const getContext: () => any;

const DB_NAME = 'webdav_backup.db';

export type RdbStore = any;

let storeInstance: RdbStore | null = null;

const SCHEMA_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS endpoints (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    url TEXT NOT NULL,
    username TEXT NOT NULL,
    password_cipher TEXT NOT NULL,
    password_fallback INTEGER NOT NULL DEFAULT 0,
    root_path TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    e2e_enabled INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS backup_tasks (
    id TEXT PRIMARY KEY,
    endpoint_id TEXT NOT NULL,
    source_type TEXT NOT NULL,           -- 'gallery' | 'directory'
    source_path TEXT,
    dest_path TEXT NOT NULL,
    realtime INTEGER NOT NULL DEFAULT 0,
    cron_interval INTEGER NOT NULL DEFAULT 6,  -- 小时
    wifi_only INTEGER NOT NULL DEFAULT 1,
    enabled INTEGER NOT NULL DEFAULT 1,
    last_reconcile_at INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS fingerprints (
    file_path TEXT NOT NULL,
    endpoint_id TEXT NOT NULL,
    task_id TEXT NOT NULL,
    remote_path TEXT NOT NULL,
    size INTEGER NOT NULL,
    mtime INTEGER NOT NULL,
    hash_head TEXT NOT NULL,
    hash_tail TEXT NOT NULL,
    sha256 TEXT,
    uploaded_at INTEGER NOT NULL,
    PRIMARY KEY (file_path, endpoint_id)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_fp_task ON fingerprints (task_id)`,
  `CREATE INDEX IF NOT EXISTS idx_fp_remote ON fingerprints (endpoint_id, remote_path)`,
  `CREATE TABLE IF NOT EXISTS history (
    id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    endpoint_id TEXT NOT NULL,
    file_path TEXT NOT NULL,
    remote_path TEXT NOT NULL,
    bytes INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL,                -- 'pending'|'uploading'|'success'|'failed'
    retry_count INTEGER NOT NULL DEFAULT 0,
    started_at INTEGER NOT NULL,
    finished_at INTEGER,
    error TEXT
  )`,
  `CREATE INDEX IF NOT EXISTS idx_hist_task ON history (task_id)`,
  `CREATE INDEX IF NOT EXISTS idx_hist_status ON history (status)`,

  // REQ-004 端到端加密新增表
  `CREATE TABLE IF NOT EXISTS master_key_entries (
    endpoint_id TEXT PRIMARY KEY,
    master_key_cipher TEXT NOT NULL,
    master_key_fallback INTEGER NOT NULL DEFAULT 0,
    salt TEXT NOT NULL,
    created_at INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS remote_paths (
    endpoint_id TEXT NOT NULL,
    local_path TEXT NOT NULL,
    remote_path TEXT NOT NULL,
    parent_remote_path TEXT NOT NULL DEFAULT '',
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (endpoint_id, local_path)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_rp_endpoint ON remote_paths (endpoint_id)`,
];

/**
 * 打开/创建数据库。多次调用返回同一实例。
 */
export async function openRdb(): Promise<RdbStore> {
  if (storeInstance) return storeInstance;
  const rdb = require('@ohos.data.relationalStore');
  if (!rdb) throw new Error('relationalStore 模块不可用');

  const ctx = typeof getContext === 'function' ? getContext() : null;
  const config = {
    name: DB_NAME,
    securityLevel: rdb.SecurityLevel?.S1 ?? 1,
  };
  storeInstance = await rdb.getRdbStore(ctx, config);
  await applySchema(storeInstance);
  return storeInstance;
}

/**
 * 关闭数据库（App 退出时调用）
 */
export async function closeRdb(): Promise<void> {
  if (!storeInstance) return;
  try {
    await storeInstance.close();
  } catch (_e) {}
  storeInstance = null;
}

async function applySchema(s: RdbStore): Promise<void> {
  for (const sql of SCHEMA_SQL) {
    try {
      await s.executeSql(sql);
    } catch (e) {
      console.warn(`[RdbHelper] schema sql failed: ${sql} :: ${(e as Error).message}`);
    }
  }
}

/**
 * 重新打开（测试用）
 */
export function _resetForTest(): void {
  storeInstance = null;
}
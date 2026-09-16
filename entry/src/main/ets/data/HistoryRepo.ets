/**
 * HistoryRepo.ets — 上传历史仓库
 *
 * 数据模型（设计概要 §3.4）：
 * (id) → { taskId, endpointId, filePath, remotePath, bytes, status, retryCount, startedAt, finishedAt?, error? }
 *
 * AC-08 / F7：历史记录与状态可视化
 */

import { openRdb } from './RdbHelper';

export type HistoryStatus = 'pending' | 'uploading' | 'success' | 'failed';

export interface HistoryRecord {
  id: string;
  taskId: string;
  endpointId: string;
  filePath: string;
  remotePath: string;
  bytes: number;
  status: HistoryStatus;
  retryCount: number;
  startedAt: number;
  finishedAt?: number;
  error?: string;
}

export interface NewHistory {
  taskId: string;
  endpointId: string;
  filePath: string;
  remotePath: string;
  bytes?: number;
  status: HistoryStatus;
  retryCount?: number;
  error?: string;
}

function uuid(): string {
  return (
    Date.now().toString(36) +
    '-' +
    Math.floor(Math.random() * 1e9).toString(36)
  );
}

export async function createHistory(rec: NewHistory): Promise<HistoryRecord> {
  const s = await openRdb();
  const id = uuid();
  const now = Date.now();
  const out: HistoryRecord = {
    id,
    taskId: rec.taskId,
    endpointId: rec.endpointId,
    filePath: rec.filePath,
    remotePath: rec.remotePath,
    bytes: rec.bytes ?? 0,
    status: rec.status,
    retryCount: rec.retryCount ?? 0,
    startedAt: now,
    error: rec.error,
  };
  await s.executeSql(
    `INSERT INTO history (id, task_id, endpoint_id, file_path, remote_path, bytes, status, retry_count, started_at, error)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      id,
      out.taskId,
      out.endpointId,
      out.filePath,
      out.remotePath,
      out.bytes,
      out.status,
      out.retryCount,
      out.startedAt,
      out.error ?? null,
    ]
  );
  return out;
}

export async function updateHistory(
  id: string,
  patch: Partial<Pick<HistoryRecord, 'status' | 'retryCount' | 'finishedAt' | 'bytes' | 'error'>>
): Promise<void> {
  const s = await openRdb();
  const sets: string[] = [];
  const args: any[] = [];
  if (patch.status !== undefined) {
    sets.push('status=?');
    args.push(patch.status);
  }
  if (patch.retryCount !== undefined) {
    sets.push('retry_count=?');
    args.push(patch.retryCount);
  }
  if (patch.finishedAt !== undefined) {
    sets.push('finished_at=?');
    args.push(patch.finishedAt);
  }
  if (patch.bytes !== undefined) {
    sets.push('bytes=?');
    args.push(patch.bytes);
  }
  if (patch.error !== undefined) {
    sets.push('error=?');
    args.push(patch.error);
  }
  if (sets.length === 0) return;
  args.push(id);
  await s.executeSql(`UPDATE history SET ${sets.join(',')} WHERE id=?`, args);
}

export async function listHistory(
  opts: { status?: HistoryStatus; limit?: number } = {}
): Promise<HistoryRecord[]> {
  const s = await openRdb();
  const limit = opts.limit ?? 200;
  const sql = opts.status
    ? `SELECT * FROM history WHERE status=? ORDER BY started_at DESC LIMIT ${limit}`
    : `SELECT * FROM history ORDER BY started_at DESC LIMIT ${limit}`;
  const args = opts.status ? [opts.status] : [];
  const rs = await s.querySql(sql, args);
  return collect(rs, rsToHistory);
}

/** 列出"失败"且 retryCount > 0 的记录，供重试用 */
export async function listFailedRetryable(taskId: string): Promise<HistoryRecord[]> {
  const s = await openRdb();
  const rs = await s.querySql(
    `SELECT * FROM history WHERE task_id=? AND status='failed' AND retry_count < 5 ORDER BY started_at DESC`,
    [taskId]
  );
  return collect(rs, rsToHistory);
}

/** 清空历史（开发者选项） */
export async function clearHistory(): Promise<void> {
  const s = await openRdb();
  await s.executeSql(`DELETE FROM history`);
}

function rsToHistory(rs: any): HistoryRecord {
  return {
    id: String(rs.getString?.('id') ?? rs.getValue?.('id')),
    taskId: String(rs.getString?.('task_id') ?? rs.getValue?.('task_id')),
    endpointId: String(rs.getString?.('endpoint_id') ?? rs.getValue?.('endpoint_id')),
    filePath: String(rs.getString?.('file_path') ?? rs.getValue?.('file_path')),
    remotePath: String(rs.getString?.('remote_path') ?? rs.getValue?.('remote_path')),
    bytes: Number(rs.getLong?.('bytes') ?? rs.getValue?.('bytes') ?? 0),
    status: String(rs.getString?.('status') ?? rs.getValue?.('status')) as HistoryStatus,
    retryCount: Number(rs.getLong?.('retry_count') ?? rs.getValue?.('retry_count') ?? 0),
    startedAt: Number(rs.getLong?.('started_at') ?? rs.getValue?.('started_at') ?? 0),
    finishedAt: (() => {
      const v = rs.getLong?.('finished_at') ?? rs.getValue?.('finished_at');
      return v == null || Number(v) === 0 ? undefined : Number(v);
    })(),
    error: (() => {
      const v = rs.getString?.('error') ?? rs.getValue?.('error');
      return v ? String(v) : undefined;
    })(),
  };
}

function collect(rs: any, mapper: (rs: any) => HistoryRecord): HistoryRecord[] {
  const out: HistoryRecord[] = [];
  if (!rs?.goToFirstRow) return out;
  if (!rs.goToFirstRow()) return out;
  do {
    out.push(mapper(rs));
  } while (rs.goToNextRow?.());
  return out;
}
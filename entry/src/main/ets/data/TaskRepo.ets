/**
 * TaskRepo.ets — 备份任务仓库
 *
 * 设计概要 §3.2 BackupTask 数据模型：
 * (id) → { endpointId, sourceType, sourcePath?, destPath, realtime, cronInterval, wifiOnly, enabled, lastReconcileAt }
 */

import { openRdb } from './RdbHelper';

export type SourceType = 'gallery' | 'directory';

export interface BackupTask {
  id: string;
  endpointId: string;
  sourceType: SourceType;
  sourcePath?: string;
  destPath: string;
  realtime: boolean;
  cronInterval: 1 | 6 | 12;
  wifiOnly: boolean;
  enabled: boolean;
  lastReconcileAt: number;
  createdAt: number;
}

export interface NewBackupTask {
  id?: string;
  endpointId: string;
  sourceType: SourceType;
  sourcePath?: string;
  destPath: string;
  realtime?: boolean;
  cronInterval?: 1 | 6 | 12;
  wifiOnly?: boolean;
  enabled?: boolean;
}

function uuid(): string {
  return Date.now().toString(36) + '-' + Math.floor(Math.random() * 1e9).toString(36);
}

export async function listTasks(): Promise<BackupTask[]> {
  const s = await openRdb();
  const rs = await s.querySql(`SELECT * FROM backup_tasks ORDER BY created_at DESC`);
  return collect(rs, rsToTask);
}

export async function getTask(id: string): Promise<BackupTask | null> {
  const s = await openRdb();
  const rs = await s.querySql(`SELECT * FROM backup_tasks WHERE id=?`, [id]);
  if (!rs?.goToFirstRow) return null;
  if (!rs.goToFirstRow()) return null;
  return rsToTask(rs);
}

export async function createTask(t: NewBackupTask): Promise<BackupTask> {
  const s = await openRdb();
  const id = t.id ?? uuid();
  const now = Date.now();
  const out: BackupTask = {
    id,
    endpointId: t.endpointId,
    sourceType: t.sourceType,
    sourcePath: t.sourcePath,
    destPath: t.destPath,
    realtime: t.realtime ?? false,
    cronInterval: t.cronInterval ?? 6,
    wifiOnly: t.wifiOnly ?? true,
    enabled: t.enabled ?? true,
    lastReconcileAt: 0,
    createdAt: now,
  };
  await s.executeSql(
    `INSERT INTO backup_tasks (id, endpoint_id, source_type, source_path, dest_path, realtime, cron_interval, wifi_only, enabled, last_reconcile_at, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      out.id,
      out.endpointId,
      out.sourceType,
      out.sourcePath ?? null,
      out.destPath,
      out.realtime ? 1 : 0,
      out.cronInterval,
      out.wifiOnly ? 1 : 0,
      out.enabled ? 1 : 0,
      0,
      out.createdAt,
    ]
  );
  return out;
}

export async function updateTask(t: BackupTask): Promise<void> {
  const s = await openRdb();
  await s.executeSql(
    `UPDATE backup_tasks SET endpoint_id=?, source_type=?, source_path=?, dest_path=?, realtime=?, cron_interval=?, wifi_only=?, enabled=?, last_reconcile_at=? WHERE id=?`,
    [
      t.endpointId,
      t.sourceType,
      t.sourcePath ?? null,
      t.destPath,
      t.realtime ? 1 : 0,
      t.cronInterval,
      t.wifiOnly ? 1 : 0,
      t.enabled ? 1 : 0,
      t.lastReconcileAt,
      t.id,
    ]
  );
}

export async function markReconciled(taskId: string): Promise<void> {
  const s = await openRdb();
  await s.executeSql(`UPDATE backup_tasks SET last_reconcile_at=? WHERE id=?`, [
    Date.now(),
    taskId,
  ]);
}

export async function deleteTask(id: string): Promise<void> {
  const s = await openRdb();
  await s.executeSql(`DELETE FROM backup_tasks WHERE id=?`, [id]);
}

function rsToTask(rs: any): BackupTask {
  return {
    id: String(rs.getString?.('id') ?? rs.getValue?.('id')),
    endpointId: String(rs.getString?.('endpoint_id') ?? rs.getValue?.('endpoint_id')),
    sourceType: (String(rs.getString?.('source_type') ?? rs.getValue?.('source_type')) as SourceType),
    sourcePath: (() => {
      const v = rs.getString?.('source_path') ?? rs.getValue?.('source_path');
      return v ? String(v) : undefined;
    })(),
    destPath: String(rs.getString?.('dest_path') ?? rs.getValue?.('dest_path')),
    realtime: Number(rs.getLong?.('realtime') ?? rs.getValue?.('realtime') ?? 0) === 1,
    cronInterval: Number(rs.getLong?.('cron_interval') ?? rs.getValue?.('cron_interval') ?? 6) as 1 | 6 | 12,
    wifiOnly: Number(rs.getLong?.('wifi_only') ?? rs.getValue?.('wifi_only') ?? 1) === 1,
    enabled: Number(rs.getLong?.('enabled') ?? rs.getValue?.('enabled') ?? 0) === 1,
    lastReconcileAt: Number(rs.getLong?.('last_reconcile_at') ?? rs.getValue?.('last_reconcile_at') ?? 0),
    createdAt: Number(rs.getLong?.('created_at') ?? rs.getValue?.('created_at') ?? 0),
  };
}

function collect(rs: any, mapper: (rs: any) => BackupTask): BackupTask[] {
  const out: BackupTask[] = [];
  if (!rs?.goToFirstRow) return out;
  if (!rs.goToFirstRow()) return out;
  do {
    out.push(mapper(rs));
  } while (rs.goToNextRow?.());
  return out;
}
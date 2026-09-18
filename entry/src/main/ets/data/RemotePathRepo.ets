/**
 * RemotePathRepo.ets — 远端路径映射仓库
 *
 * 用途（REQ-004 F3.3）：客户端维护"本地路径 ↔ 远端路径"映射
 *   - 因为远端路径名是加密的 base64url 字符串，远端不可识别
 *   - 预览、删除、本地重新同步时需要做映射查找
 *
 * 表 `remote_paths`：
 *   - endpoint_id  TEXT NOT NULL
 *   - local_path  TEXT NOT NULL
 *   - remote_path  TEXT NOT NULL       -- 已加密的远端路径（base64url + .wde）
 *   - parent_remote_path  TEXT        -- 父目录的远端路径（加密）
 *   - updated_at  INTEGER NOT NULL
 *   - PRIMARY KEY (endpoint_id, local_path)
 *
 * 重要：本表**不**存储明文原文件路径（localPath 是手机本地路径，本来就是明文；
 * remotePath 一定是加密的 base64url）。
 */

import { openRdb } from './RdbHelper';

export interface RemotePathEntry {
  endpointId: string;
  localPath: string;
  remotePath: string; // 加密的 base64url（带 .wde 后缀）
  parentRemotePath: string;
  updatedAt: number;
}

/**
 * 存远端路径映射（本地路径 → 加密的远端路径）
 */
export async function upsertRemotePath(
  endpointId: string,
  localPath: string,
  remotePath: string,
  parentRemotePath: string
): Promise<void> {
  const s = await openRdb();
  const now = Date.now();
  await s.executeSql(
    `INSERT OR REPLACE INTO remote_paths (endpoint_id, local_path, remote_path, parent_remote_path, updated_at)
     VALUES (?, ?, ?, ?, ?)`,
    [endpointId, localPath, remotePath, parentRemotePath, now]
  );
}

/**
 * 查本地路径对应的远端路径
 */
export async function getRemotePath(
  endpointId: string,
  localPath: string
): Promise<string | null> {
  const s = await openRdb();
  const rs = await s.querySql(
    `SELECT remote_path FROM remote_paths WHERE endpoint_id = ? AND local_path = ?`,
    [endpointId, localPath]
  );
  if (!rs || !rs.goToFirstRow) return null;
  if (!rs.goToFirstRow()) return null;
  return String(rs.getValue('remote_path') ?? '');
}

/**
 * 查远端路径对应的本地路径（用于远端列举 → 本地对账）
 */
export async function getLocalPath(
  endpointId: string,
  remotePath: string
): Promise<string | null> {
  const s = await openRdb();
  const rs = await s.querySql(
    `SELECT local_path FROM remote_paths WHERE endpoint_id = ? AND remote_path = ?`,
    [endpointId, remotePath]
  );
  if (!rs || !rs.goToFirstRow) return null;
  if (!rs.goToFirstRow()) return null;
  return String(rs.getValue('local_path') ?? '');
}

/**
 * 列某端点所有映射条目（用于对账）
 */
export async function listRemotePaths(endpointId: string): Promise<RemotePathEntry[]> {
  const s = await openRdb();
  const rs = await s.querySql(
    `SELECT endpoint_id, local_path, remote_path, parent_remote_path, updated_at
     FROM remote_paths WHERE endpoint_id = ? ORDER BY updated_at DESC`,
    [endpointId]
  );
  const out: RemotePathEntry[] = [];
  if (!rs || !rs.goToFirstRow) return out;
  if (!rs.goToFirstRow()) return out;
  do {
    out.push({
      endpointId: String(rs.getValue('endpoint_id') ?? ''),
      localPath: String(rs.getValue('local_path') ?? ''),
      remotePath: String(rs.getValue('remote_path') ?? ''),
      parentRemotePath: String(rs.getValue('parent_remote_path') ?? ''),
      updatedAt: Number(rs.getValue('updated_at') ?? 0),
    });
  } while (rs.goToNextRow && rs.goToNextRow());
  return out;
}

/**
 * 删除单条映射（本地文件被删除 / 端点删除时调用）
 */
export async function deleteRemotePath(endpointId: string, localPath: string): Promise<void> {
  const s = await openRdb();
  await s.executeSql(
    `DELETE FROM remote_paths WHERE endpoint_id = ? AND local_path = ?`,
    [endpointId, localPath]
  );
}

/**
 * 删端点全部映射（端点删除时调用）
 */
export async function deleteAllForEndpoint(endpointId: string): Promise<void> {
  const s = await openRdb();
  await s.executeSql(`DELETE FROM remote_paths WHERE endpoint_id = ?`, [endpointId]);
}
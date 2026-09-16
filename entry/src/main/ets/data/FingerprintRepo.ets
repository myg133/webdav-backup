/**
 * FingerprintRepo.ets — 本地指纹库
 *
 * 数据模型（设计概要 §3.3）：
 * (filePath, endpointId) → { size, mtime, hashHead, hashTail, remotePath, sha256, uploadedAt }
 *
 * AC-06：增量同步判定依据
 * NFR-02：1000 条查询 < 100ms（relationalStore 已索引）
 */

import { openRdb } from './RdbHelper';

export interface Fingerprint {
  filePath: string;
  endpointId: string;
  taskId: string;
  remotePath: string;
  size: number;
  mtime: number;
  hashHead: string;
  hashTail: string;
  sha256?: string;
  uploadedAt: number;
}

export interface NewFingerprint {
  filePath: string;
  endpointId: string;
  taskId: string;
  remotePath: string;
  size: number;
  mtime: number;
  hashHead: string;
  hashTail: string;
  sha256?: string;
}

export async function upsertFingerprint(fp: NewFingerprint): Promise<void> {
  const s = await openRdb();
  const now = Date.now();
  await s.executeSql(
    `INSERT OR REPLACE INTO fingerprints
      (file_path, endpoint_id, task_id, remote_path, size, mtime, hash_head, hash_tail, sha256, uploaded_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      fp.filePath,
      fp.endpointId,
      fp.taskId,
      fp.remotePath,
      fp.size,
      fp.mtime,
      fp.hashHead,
      fp.hashTail,
      fp.sha256 ?? null,
      now,
    ]
  );
}

export async function getFingerprint(
  filePath: string,
  endpointId: string
): Promise<Fingerprint | null> {
  const s = await openRdb();
  const rs = await s.querySql(
    `SELECT * FROM fingerprints WHERE file_path=? AND endpoint_id=?`,
    [filePath, endpointId]
  );
  if (!rs?.goToFirstRow) return null;
  if (!rs.goToFirstRow()) return null;
  return rsToFp(rs);
}

/** 一次性查某 task 下的全部指纹 */
export async function listByTask(taskId: string): Promise<Fingerprint[]> {
  const s = await openRdb();
  const rs = await s.querySql(`SELECT * FROM fingerprints WHERE task_id=?`, [taskId]);
  return collect(rs, rsToFp);
}

/** 按 endpointId 列指纹（对账时需要把本地列表与远端 PROPFIND 对账） */
export async function listByEndpoint(endpointId: string): Promise<Fingerprint[]> {
  const s = await openRdb();
  const rs = await s.querySql(
    `SELECT * FROM fingerprints WHERE endpoint_id=?`,
    [endpointId]
  );
  return collect(rs, rsToFp);
}

export async function deleteFingerprint(filePath: string, endpointId: string): Promise<void> {
  const s = await openRdb();
  await s.executeSql(`DELETE FROM fingerprints WHERE file_path=? AND endpoint_id=?`, [
    filePath,
    endpointId,
  ]);
}

function rsToFp(rs: any): Fingerprint {
  return {
    filePath: String(rs.getString?.('file_path') ?? rs.getValue?.('file_path')),
    endpointId: String(rs.getString?.('endpoint_id') ?? rs.getValue?.('endpoint_id')),
    taskId: String(rs.getString?.('task_id') ?? rs.getValue?.('task_id')),
    remotePath: String(rs.getString?.('remote_path') ?? rs.getValue?.('remote_path')),
    size: Number(rs.getLong?.('size') ?? rs.getValue?.('size') ?? 0),
    mtime: Number(rs.getLong?.('mtime') ?? rs.getValue?.('mtime') ?? 0),
    hashHead: String(rs.getString?.('hash_head') ?? rs.getValue?.('hash_head')),
    hashTail: String(rs.getString?.('hash_tail') ?? rs.getValue?.('hash_tail')),
    sha256: (() => {
      const v = rs.getString?.('sha256') ?? rs.getValue?.('sha256');
      return v ? String(v) : undefined;
    })(),
    uploadedAt: Number(rs.getLong?.('uploaded_at') ?? rs.getValue?.('uploaded_at') ?? 0),
  };
}

function collect(rs: any, mapper: (rs: any) => Fingerprint): Fingerprint[] {
  const out: Fingerprint[] = [];
  if (!rs?.goToFirstRow) return out;
  if (!rs.goToFirstRow()) return out;
  do {
    out.push(mapper(rs));
  } while (rs.goToNextRow?.());
  return out;
}
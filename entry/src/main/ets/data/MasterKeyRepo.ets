/**
 * MasterKeyRepo.ets — 主密钥运行时仓库
 *
 * 设计要点（REQ-004 F1 / 关键约束）：
 *   - **master key 仅运行时持有**，通过 KeyStore 加密后存到 MasterKeyRepo（数据库表）
 *   - salt 存到 Endpoint 仓库（每端点一个 salt，**不**加密）
 *   - **永远不落盘明文密码**
 *   - **永远不通过网络传任何派生材料**
 *
 * 表 `master_key_entries`：
 *   - endpoint_id  TEXT PRIMARY KEY
 *   - master_key_cipher  TEXT NOT NULL  -- base64(IV || ct || tag) via KeyStore
 *   - master_key_fallback  INTEGER NOT NULL  -- 0/1
 *   - salt  TEXT NOT NULL  -- base64(salt)
 *   - created_at  INTEGER NOT NULL
 *
 * F1.4 关键约束：主密码丢失 = 数据永久丢失。本仓库不提供"重置"路径；
 * 删端点新设主密码 = 删除整条记录。
 */

import { openRdb } from './RdbHelper';
import { encryptSecret, decryptSecret, deleteKey } from '../infra/KeyStore';
import { generateSalt, SALT_BYTES } from '../domain/MasterKey';

declare const require: (id: string) => any;

export interface MasterKeyEntry {
  endpointId: string;
  masterKey: Uint8Array; // 32 字节
  salt: Uint8Array;       // 16 字节
  fallback: boolean;      // true 表示 KeyStore fallback 路径
}

/**
 * 存主密钥到仓库（首次设置主密码时调用）。
 *
 * @param endpointId   端点 ID（用于区分多个端点；salt 也按 endpoint 隔离）
 * @param masterKey    32 字节主密钥（由 deriveMasterKey 派生）
 */
export async function saveMasterKey(
  endpointId: string,
  masterKey: Uint8Array
): Promise<{ salt: Uint8Array }> {
  if (masterKey.length !== 32) {
    throw new Error('master key must be 32 bytes');
  }
  const s = await openRdb();

  // 1. 取出已有 salt（如有）；否则新生成
  let salt = await getSalt(endpointId);
  if (!salt) {
    salt = generateSalt();
  }

  // 2. master key → KeyStore 加密落库
  // 注意：KeyStore 内部生成的 alias 与 endpointId 绑定；加密字节本身是 masterKey 二进制
  // 用 base64 编码为字符串供 KeyStore 处理（KeyStore 的 API 形态按 HUKS 文档）
  const keyB64 = bytesToBase64(masterKey);
  const cipher = encryptSecret(endpointId, keyB64);

  // 3. upsert
  const now = Date.now();
  const existing = await getSalt(endpointId);
  if (existing) {
    await s.executeSql(
      `UPDATE master_key_entries SET master_key_cipher=?, master_key_fallback=?, salt=? WHERE endpoint_id=?`,
      [cipher.cipher, cipher.fallback ? 1 : 0, bytesToBase64(salt), endpointId]
    );
  } else {
    await s.executeSql(
      `INSERT INTO master_key_entries (endpoint_id, master_key_cipher, master_key_fallback, salt, created_at)
       VALUES (?, ?, ?, ?, ?)`,
      [endpointId, cipher.cipher, cipher.fallback ? 1 : 0, bytesToBase64(salt), now]
    );
  }
  return { salt };
}

/**
 * 取主密钥（运行时；解密后内存中持有）
 *
 * @returns 32 字节 master key；如该端点未设置主密钥，返回 null
 * @throws 若 KeyStore 解密失败（开发态 fallback 路径下不应抛错；正常 HUKS 抛错时**不会**重置记录）
 */
export async function loadMasterKey(endpointId: string): Promise<MasterKeyEntry | null> {
  const s = await openRdb();
  const rs = await s.querySql(
    `SELECT master_key_cipher, master_key_fallback, salt FROM master_key_entries WHERE endpoint_id = ?`,
    [endpointId]
  );
  if (!rs || !rs.goToFirstRow) return null;
  if (!rs.goToFirstRow()) return null;

  const cipher = String(rs.getValue('master_key_cipher'));
  const fallback = Number(rs.getValue('master_key_fallback') ?? 0) === 1;
  const saltB64 = String(rs.getValue('salt'));

  try {
    const keyB64 = decryptSecret(endpointId, { cipher, fallback });
    const masterKey = base64ToBytes(keyB64);
    if (masterKey.length !== 32) {
      throw new Error(`decrypted master key has bad length: ${masterKey.length}`);
    }
    const salt = base64ToBytes(saltB64);
    if (salt.length !== SALT_BYTES) {
      throw new Error(`salt has bad length: ${salt.length}`);
    }
    return { endpointId, masterKey, salt, fallback };
  } catch (e) {
    // KeyStore 解密失败 = 主密码错误 或 KeyStore 不可用
    // **不删除记录**（主密码错误时让用户重新尝试；KeyStore 不可用时保留给 fallback）
    return null;
  }
}

/**
 * 取 salt（不需要解密 master key）。首次设置前为 null。
 */
export async function getSalt(endpointId: string): Promise<Uint8Array | null> {
  const s = await openRdb();
  const rs = await s.querySql(
    `SELECT salt FROM master_key_entries WHERE endpoint_id = ?`,
    [endpointId]
  );
  if (!rs || !rs.goToFirstRow) return null;
  if (!rs.goToFirstRow()) return null;
  return base64ToBytes(String(rs.getValue('salt')));
}

/**
 * 是否设过主密码（任意端点）。用于 F9 首次启动判断。
 */
export async function hasAnyMasterKey(): Promise<boolean> {
  const s = await openRdb();
  const rs = await s.querySql(`SELECT COUNT(*) AS c FROM master_key_entries`);
  if (!rs || !rs.goToFirstRow) return false;
  if (!rs.goToFirstRow()) return false;
  return Number(rs.getValue('c') ?? 0) > 0;
}

/**
 * 删端点主密钥（端点删除时调用）。
 * 注意：KeyStore 的密钥也会一并删除（无法恢复已加密的备份）。
 */
export async function deleteMasterKey(endpointId: string): Promise<void> {
  const s = await openRdb();
  deleteKey(endpointId);
  await s.executeSql(`DELETE FROM master_key_entries WHERE endpoint_id = ?`, [endpointId]);
}

// ──────────────────────────────────────────────────────────────────────
// base64 工具
// ──────────────────────────────────────────────────────────────────────

function bytesToBase64(bytes: Uint8Array): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let r = '';
  let i = 0;
  while (i < bytes.length) {
    const a = bytes[i++] & 0xff;
    const b = i < bytes.length ? bytes[i++] & 0xff : NaN;
    const c = i < bytes.length ? bytes[i++] & 0xff : NaN;
    r += chars[a >> 2] + chars[((a & 3) << 4) | (b >> 4)] +
      (isNaN(b) ? '=' : chars[((b & 0xf) << 2) | (c >> 6)]) +
      (isNaN(c) ? '=' : chars[c & 0x3f]);
  }
  return r;
}

function base64ToBytes(b64: string): Uint8Array {
  const lookup = new Int8Array(128);
  for (let i = 0; i < 128; i++) lookup[i] = -1;
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  for (let i = 0; i < chars.length; i++) lookup[chars.charCodeAt(i)] = i;
  const len = b64.length;
  let bufLen = (len * 3) >> 2;
  if (b64[len - 1] === '=') bufLen--;
  if (b64[len - 2] === '=') bufLen--;
  const out = new Uint8Array(bufLen);
  let p = 0;
  for (let i = 0; i < len; i += 4) {
    const a = lookup[b64.charCodeAt(i)];
    const b = lookup[b64.charCodeAt(i + 1)];
    const c = lookup[b64.charCodeAt(i + 2)];
    const d = lookup[b64.charCodeAt(i + 3)];
    out[p++] = (a << 2) | (b >> 4);
    if (b64[i + 2] !== '=') out[p++] = ((b & 0xf) << 4) | (c >> 2);
    if (b64[i + 3] !== '=') out[p++] = ((c & 0x3) << 6) | d;
  }
  return out;
}
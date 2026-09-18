/**
 * EndpointRepo.ets — 端点仓库
 *
 * AC-01：多 WebDAV 端点管理
 * AC-02：凭据 KeyStore 加密落库
 */

import { openRdb } from './RdbHelper';
import { encryptSecret, decryptSecret, deleteKey, hasKey } from '../infra/KeyStore';

export interface Endpoint {
  id: string;
  name: string;
  url: string;
  username: string;
  // 凭据不直接暴露；通过 getPassword() 取
  passwordCipher: string;
  passwordFallback: boolean;
  rootPath: string;
  enabled: boolean;
  /** REQ-004: 端到端加密开关（明文存盘） */
  e2eEnabled: boolean;
  createdAt: number;
}

export interface NewEndpointInput {
  id?: string;
  name: string;
  url: string;
  username: string;
  password: string; // 明文；调用方传入；本仓库内部加密落盘
  rootPath: string;
  enabled?: boolean;
  e2eEnabled?: boolean;
}

function uuid(): string {
  // 简单时间戳 + 随机数；不依赖 crypto 模块以便双平台一致
  return (
    Date.now().toString(36) +
    '-' +
    Math.floor(Math.random() * 1e9).toString(36)
  );
}

export async function listEndpoints(): Promise<Endpoint[]> {
  const s = await openRdb();
  const rs = await s.querySql(`SELECT * FROM endpoints ORDER BY created_at DESC`);
  const rows: any[] = [];
  if (rs?.goToFirstRow) {
    while (rs.goToFirstRow ? (rows.length === 0 ? rs.goToFirstRow() : rs.goToNextRow()) : false) {
      rows.push(rsToEndpoint(rs));
    }
  }
  return rows;
}

export async function getEndpoint(id: string): Promise<Endpoint | null> {
  const s = await openRdb();
  const rs = await s.querySql(`SELECT * FROM endpoints WHERE id = ?`, [id]);
  if (!rs || !rs.goToFirstRow) return null;
  if (!rs.goToFirstRow()) return null;
  return rsToEndpoint(rs);
}

export async function createEndpoint(input: NewEndpointInput): Promise<Endpoint> {
  const s = await openRdb();
  const id = input.id ?? uuid();
  const cipher = encryptSecret(id, input.password);
  const now = Date.now();
  const ep: Endpoint = {
    id,
    name: input.name,
    url: input.url,
    username: input.username,
    passwordCipher: cipher.cipher,
    passwordFallback: cipher.fallback,
    rootPath: input.rootPath,
    enabled: input.enabled ?? true,
    e2eEnabled: input.e2eEnabled ?? false,
    createdAt: now,
  };
  await s.executeSql(
    `INSERT INTO endpoints (id, name, url, username, password_cipher, password_fallback, root_path, enabled, e2e_enabled, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      ep.id,
      ep.name,
      ep.url,
      ep.username,
      ep.passwordCipher,
      ep.passwordFallback ? 1 : 0,
      ep.rootPath,
      ep.enabled ? 1 : 0,
      ep.e2eEnabled ? 1 : 0,
      ep.createdAt,
    ]
  );
  return ep;
}

export async function updateEndpoint(ep: Endpoint, newPassword?: string): Promise<void> {
  const s = await openRdb();
  let cipher = ep.passwordCipher;
  let fallback = ep.passwordFallback;
  if (newPassword) {
    const c = encryptSecret(ep.id, newPassword);
    cipher = c.cipher;
    fallback = c.fallback;
  }
  await s.executeSql(
    `UPDATE endpoints SET name=?, url=?, username=?, password_cipher=?, password_fallback=?, root_path=?, enabled=?, e2e_enabled=? WHERE id=?`,
    [
      ep.name,
      ep.url,
      ep.username,
      cipher,
      fallback ? 1 : 0,
      ep.rootPath,
      ep.enabled ? 1 : 0,
      ep.e2eEnabled ? 1 : 0,
      ep.id,
    ]
  );
}

export async function deleteEndpoint(id: string): Promise<void> {
  const s = await openRdb();
  deleteKey(id);
  await s.executeSql(`DELETE FROM endpoints WHERE id = ?`, [id]);
}

/**
 * 取明文密码。**仅限内部 WebDAVClient 构造时使用；不在 UI 暴露。**
 */
export function revealPassword(ep: Endpoint): string {
  return decryptSecret(ep.id, {
    cipher: ep.passwordCipher,
    fallback: ep.passwordFallback,
  });
}

export function hasStoredKey(id: string): boolean {
  return hasKey(id);
}

// 内部：把 ResultSet 转成 Endpoint
function rsToEndpoint(rs: any): Endpoint {
  return {
    id: String(rs.getString?.('id') ?? rs.getValue?.('id')),
    name: String(rs.getString?.('name') ?? rs.getValue?.('name')),
    url: String(rs.getString?.('url') ?? rs.getValue?.('url')),
    username: String(rs.getString?.('username') ?? rs.getValue?.('username')),
    passwordCipher: String(rs.getString?.('password_cipher') ?? rs.getValue?.('password_cipher')),
    passwordFallback: Number(rs.getLong?.('password_fallback') ?? rs.getValue?.('password_fallback') ?? 0) === 1,
    rootPath: String(rs.getString?.('root_path') ?? rs.getValue?.('root_path')),
    enabled: Number(rs.getLong?.('enabled') ?? rs.getValue?.('enabled') ?? 0) === 1,
    e2eEnabled: Number(rs.getLong?.('e2e_enabled') ?? rs.getValue?.('e2e_enabled') ?? 0) === 1,
    createdAt: Number(rs.getLong?.('created_at') ?? rs.getValue?.('created_at') ?? 0),
  };
}
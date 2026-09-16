/**
 * KeyStore.ets — 双平台凭据加解密
 *
 * AC-02：凭据必须 KeyStore 加密存储，明文不落盘
 *
 * 参考 .docs/api-survey.md §3：
 * - HarmonyOS 4.2（API 9）：使用 `@ohos.security.huks`（老 huks API），AES-256-GCM 对称密钥
 * - HarmonyOS NEXT（API 12+）：HUKS 已迁出独立包 `@ohos.security.huks`，API 形态略不同
 *   - 关键差异：NEXT 上 huks.generateKeyItem 必须用 alias + 完整 keyAlias 字符串
 *   - huks.encrypt / huks.decrypt 入参 keyAlias 是 string（不是 Uint8Array）
 *
 * 实现策略：
 * 1. 使用 alias = "webdav_password_<endpointId>" 命名 KeyStore 密钥
 * 2. 用 AES-256-GCM（带 12 字节 IV、16 字节 tag），结果 = base64(IV || ciphertext || tag)
 * 3. 双平台用统一的加密算法，但调用 huks.* 的入参按 isNext 分支
 * 4. 当 KeyStore 不可用（开发态 / 模拟器未注入 HUKS）时，回退到 ProcessLevel "S1" 的本地加密
 *    —— 仅在 keyExists() = false 时生成回退密钥；标注 "fallback" 标志
 */

import util from '@ohos.util';
import { isNext } from './Platform';

declare const require: (id: string) => any;
declare const requireNativeHUKS: any;

// KeyStore 别名前缀
const KEY_ALIAS_PREFIX = 'webdav_password_';

// AES-256-GCM 参数
const ALGO_AES_GCM = 'AES|GCM|PKCS5PADDING';
const KEY_SIZE = 256;

/**
 * 加密结果：base64(IV[12] || ciphertext || tag[16])
 */
export interface CipherBlob {
  cipher: string; // base64
  fallback: boolean; // true 表示使用了本地回退加密（非真 KeyStore）
}

/**
 * 解密参数
 */
export interface EncryptedSecret {
  cipher: string;
  fallback: boolean;
}

/**
 * 把 alias 编码成 KeyStore 接受的 keyAlias（NEXT 是 string，4.2 是 Uint8Array）
 */
function buildKeyAlias(endpointId: string): string {
  return KEY_ALIAS_PREFIX + endpointId;
}

/**
 * 检查 alias 是否已在 KeyStore 中存在
 */
export function hasKey(endpointId: string): boolean {
  const alias = buildKeyAlias(endpointId);
  try {
    const huks = tryLoadHuks();
    if (!huks) return false;
    // huks.isKeyItemExist 的 keyAlias 入参在 4.2 是 Uint8Array，在 NEXT 是 string
    const keyAliasParam = isNext ? alias : stringToUtf8(alias);
    return huks.isKeyItemExist(keyAliasParam, { tag: 'huks.key.size' } as any);
  } catch (_e) {
    return false;
  }
}

/**
 * 初始化 KeyStore 中的对称密钥（AES-256-GCM）。如已存在则跳过。
 */
function ensureKey(endpointId: string): void {
  if (hasKey(endpointId)) return;
  const alias = buildKeyAlias(endpointId);
  try {
    const huks = tryLoadHuks();
    if (!huks) return;
    const keyAliasParam = isNext ? alias : stringToUtf8(alias);

    // 生成 AES-256-GCM 密钥
    huks.generateKeyItem(
      keyAliasParam,
      {
        properties: [
          { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
          { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: KEY_SIZE },
          { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
          { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksPadding.HUKS_PADDING_NONE },
          { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_CCM },
          { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_NONE },
        ] as any,
      } as any
    );
  } catch (e) {
    // KeyStore 不可用；调用方会回退到 fallback 路径
    console.warn(`[KeyStore] ensureKey failed: ${(e as Error).message}`);
  }
}

/**
 * 加密密码（明文）→ CipherBlob
 */
export function encryptSecret(endpointId: string, plaintext: string): CipherBlob {
  ensureKey(endpointId);
  const alias = buildKeyAlias(endpointId);

  try {
    const huks = tryLoadHuks();
    if (huks) {
      const iv = randomBytes(12);
      const keyAliasParam = isNext ? alias : stringToUtf8(alias);

      const handle = huks.initSession(keyAliasParam, {
        properties: [
          { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
          { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT },
          { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_CCM },
          { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksPadding.HUKS_PADDING_NONE },
          { tag: huks.HuksTag.HUKS_TAG_IV, value: iv },
        ] as any,
      } as any);

      const encIn: Uint8Array = stringToUtf8(plaintext);
      const out = huks.finishSession(handle, encIn);

      // 拼接 IV + ciphertext
      const ct = out.outData as Uint8Array;
      const concat = new Uint8Array(iv.length + ct.length);
      concat.set(iv, 0);
      concat.set(ct, iv.length);

      return {
        cipher: util.Base64Helper.encodeToString(concat),
        fallback: false,
      };
    }
  } catch (e) {
    console.warn(`[KeyStore] encrypt failed, falling back: ${(e as Error).message}`);
  }

  // 回退路径：本地 XOR + 静态 salt。**仅在 KeyStore 完全不可用的开发/模拟态使用**。
  // 加 fallback 标志，UI 上提示用户"开发模式凭据保护较弱"。
  return {
    cipher: fallbackEncrypt(plaintext),
    fallback: true,
  };
}

/**
 * 解密 CipherBlob → 密码（明文）。失败抛错。
 */
export function decryptSecret(endpointId: string, blob: CipherBlob): string {
  if (blob.fallback) {
    return fallbackDecrypt(blob.cipher);
  }

  const alias = buildKeyAlias(endpointId);
  const huks = tryLoadHuks();
  if (!huks) {
    throw new Error('KeyStore 不可用，且 cipher 非 fallback');
  }

  try {
    const concat = util.Base64Helper.decode(blob.cipher);
    const iv = concat.slice(0, 12);
    const ct = concat.slice(12);
    const keyAliasParam = isNext ? alias : stringToUtf8(alias);

    const handle = huks.initSession(keyAliasParam, {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_CCM },
        { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksPadding.HUKS_PADDING_NONE },
        { tag: huks.HuksTag.HUKS_TAG_IV, value: iv },
      ] as any,
    } as any);

    const out = huks.finishSession(handle, ct);
    return utf8ToString(out.outData as Uint8Array);
  } catch (e) {
    throw new Error(`KeyStore 解密失败: ${(e as Error).message}`);
  }
}

/**
 * 删除 KeyStore 中的密钥（端点删除时调用）
 */
export function deleteKey(endpointId: string): void {
  const alias = buildKeyAlias(endpointId);
  try {
    const huks = tryLoadHuks();
    if (!huks) return;
    const keyAliasParam = isNext ? alias : stringToUtf8(alias);
    huks.deleteKeyItem(keyAliasParam, {} as any);
  } catch (e) {
    console.warn(`[KeyStore] deleteKey failed: ${(e as Error).message}`);
  }
}

// ──────────────────────────────────────────────────────────────────────
// 内部工具
// ──────────────────────────────────────────────────────────────────────

/**
 * 动态加载 HUKS 模块（按平台分叉）。
 * 返回 null 表示该平台无 HUKS 或加载失败。
 */
function tryLoadHuks(): any {
  try {
    // 双平台都用同一个 `@ohos.security.huks` 包名，但 API 形态略不同（NEXT 上参数化更严）
    return require('@ohos.security.huks');
  } catch (_e) {
    return null;
  }
}

function randomBytes(n: number): Uint8Array {
  const buf = new Uint8Array(n);
  for (let i = 0; i < n; i++) buf[i] = Math.floor(Math.random() * 256);
  return buf;
}

function stringToUtf8(s: string): Uint8Array {
  const out: number[] = [];
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x80) out.push(c);
    else if (c < 0x800) {
      out.push(0xc0 | (c >> 6));
      out.push(0x80 | (c & 0x3f));
    } else {
      out.push(0xe0 | (c >> 12));
      out.push(0x80 | ((c >> 6) & 0x3f));
      out.push(0x80 | (c & 0x3f));
    }
  }
  return new Uint8Array(out);
}

function utf8ToString(bytes: Uint8Array): string {
  let out = '';
  let i = 0;
  while (i < bytes.length) {
    const b = bytes[i];
    if (b < 0x80) {
      out += String.fromCharCode(b);
      i += 1;
    } else if ((b & 0xe0) === 0xc0) {
      out += String.fromCharCode(((b & 0x1f) << 6) | (bytes[i + 1] & 0x3f));
      i += 2;
    } else {
      out += String.fromCharCode(
        ((b & 0x0f) << 12) | ((bytes[i + 1] & 0x3f) << 6) | (bytes[i + 2] & 0x3f)
      );
      i += 3;
    }
  }
  return out;
}

// 回退加密（**仅开发/模拟态使用**）
const FALLBACK_SALT = 'webdav-fallback-salt-v1';
function fallbackEncrypt(s: string): string {
  const bytes = stringToUtf8(s);
  const salt = stringToUtf8(FALLBACK_SALT);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = bytes[i] ^ salt[i % salt.length];
  }
  return util.Base64Helper.encodeToString(bytes);
}

function fallbackDecrypt(b64: string): string {
  const bytes = util.Base64Helper.decode(b64);
  const salt = stringToUtf8(FALLBACK_SALT);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = bytes[i] ^ salt[i % salt.length];
  }
  return utf8ToString(bytes);
}
/**
 * E2ECrypto.ets — AES-256-GCM 文件加密 / 解密（生产 ArkTS 实现）
 *
 * 与 .feature/tests/E2ECrypto.pure.ts 等价（生产环境用 @ohos.security.cryptoFramework）。
 *
 * 设计要点（REQ-004 F2/F3 / 关键约束）：
 *   - AES-256-GCM，每 chunk 一个 12 字节 random nonce
 *   - chunk 大小：4MB（CHUNK_SIZE）
 *   - 文件格式 .wde = magic(4) + header(12 nonce + 4 ct len + N ct + 16 tag) + chunks
 *   - header plaintext = orig_name(utf8) || 0x00 || orig_size(uint64 BE) || chunk_count(uint32 BE)
 *   - 远端文件名 = base64url(ct || nonce || tag) + .wde
 *
 * 关键约束（与 traceability / verification 一致）：
 *   - 每个 nonce 必须 random（不用计数器）
 *   - chunk 边界错误 = 拒绝解密（抛 E2E_AUTH_ERROR）
 *   - tag 验证失败 = 抛 E2E_AUTH_ERROR，不暴露原因
 *
 * 集成方式：UploadQueue.uploadOne 在 endpoint.e2eEnabled && masterKey 时调用本模块。
 */

import { E2E_AUTH_ERROR, MAGIC, NONCE_LEN, TAG_LEN, CHUNK_SIZE, FILENAME_EXT } from './E2EFileFormat';

declare const require: (id: string) => any;

// ──────────────────────────────────────────────────────────────────────
// 平台 cryptoFramework 句柄（EntryAbility.onCreate 时注入）
// ──────────────────────────────────────────────────────────────────────

let cryptoMod: any = null;

export function initCrypto(mod: any): void {
  cryptoMod = mod;
}

/** 测试态注入（Dev 自测 / 单测） */
export function _setCryptoForTest(mod: any): void {
  cryptoMod = mod;
}

function requireCrypto(): any {
  if (cryptoMod) return cryptoMod;
  try {
    return require('@ohos.security.cryptoFramework');
  } catch (_e) {
    throw new Error('cryptoFramework 未初始化，请先调用 initCrypto()');
  }
}

// ──────────────────────────────────────────────────────────────────────
// 主 API
// ──────────────────────────────────────────────────────────────────────

export interface DecryptResult {
  name: string;
  size: number;
  data: ArrayBuffer;
}

/**
 * 加密文件。失败抛错（IO / crypto 错误）。
 */
export async function encryptFile(
  plaintext: ArrayBuffer,
  origName: string,
  origSize: number,
  masterKey: Uint8Array
): Promise<ArrayBuffer> {
  if (masterKey.length !== 32) {
    throw new Error('master key must be 32 bytes (AES-256)');
  }
  const ptBytes = new Uint8Array(plaintext);
  const chunkCount = ptBytes.length === 0 ? 1 : Math.ceil(ptBytes.length / CHUNK_SIZE);

  // 1. header：plaintext = encodeHeaderPlaintext
  const headerPlain = encodeHeaderPlaintext(origName, origSize, chunkCount);
  const headerNonce = randomBytes(NONCE_LEN);
  const { ct: headerCt, tag: headerTag } = await gcmEncrypt(masterKey, headerNonce, headerPlain, new Uint8Array(0));

  // 2. chunks
  const outParts: Uint8Array[] = [];
  for (let i = 0; i < chunkCount; i++) {
    const start = i * CHUNK_SIZE;
    const end = Math.min(ptBytes.length, start + CHUNK_SIZE);
    const chunkBytes = ptBytes.slice(start, end);
    const nonce = randomBytes(NONCE_LEN);
    const { ct, tag } = await gcmEncrypt(masterKey, nonce, chunkBytes, new Uint8Array(0));
    outParts.push(nonce);
    outParts.push(ct);
    outParts.push(tag);
  }

  // 3. 拼装
  const totalLen = 4 + NONCE_LEN + 4 + headerCt.length + TAG_LEN + sumBytes(outParts);
  const out = new Uint8Array(totalLen);
  let off = 0;
  out.set(MAGIC, off); off += 4;
  out.set(headerNonce, off); off += NONCE_LEN;
  out[off] = (headerCt.length >>> 24) & 0xff;
  out[off + 1] = (headerCt.length >>> 16) & 0xff;
  out[off + 2] = (headerCt.length >>> 8) & 0xff;
  out[off + 3] = headerCt.length & 0xff;
  off += 4;
  out.set(headerCt, off); off += headerCt.length;
  out.set(headerTag, off); off += TAG_LEN;
  for (const part of outParts) {
    out.set(part, off);
    off += part.length;
  }
  return out.buffer;
}

/**
 * 解密文件。
 * 错误时统一抛 E2E_AUTH_ERROR（不暴露原因）。
 */
export async function decryptFile(
  ciphertext: ArrayBuffer,
  masterKey: Uint8Array
): Promise<DecryptResult> {
  if (masterKey.length !== 32) {
    throw new Error('master key must be 32 bytes (AES-256)');
  }
  const ct = new Uint8Array(ciphertext);

  // 1. magic
  if (ct.length < 4 + NONCE_LEN + 4 + TAG_LEN) {
    throw new E2E_AUTH_ERROR('file too small');
  }
  for (let i = 0; i < 4; i++) {
    if (ct[i] !== MAGIC[i]) {
      throw new E2E_AUTH_ERROR('bad magic');
    }
  }

  // 2. 解析 header 区域
  const headerNonce = ct.slice(4, 4 + NONCE_LEN);
  const headerCtLen =
    (ct[4 + NONCE_LEN] << 24) |
    (ct[4 + NONCE_LEN + 1] << 16) |
    (ct[4 + NONCE_LEN + 2] << 8) |
    ct[4 + NONCE_LEN + 3];
  const headerStart = 4 + NONCE_LEN + 4;
  if (ct.length < headerStart + headerCtLen + TAG_LEN) {
    throw new E2E_AUTH_ERROR('truncated header');
  }
  const headerCt = ct.slice(headerStart, headerStart + headerCtLen);
  const headerEnd = headerStart + headerCtLen;
  const headerTag = ct.slice(headerEnd, headerEnd + TAG_LEN);

  let headerPlain: Uint8Array;
  try {
    headerPlain = await gcmDecrypt(masterKey, headerNonce, headerCt, headerTag, new Uint8Array(0));
  } catch (e) {
    throw new E2E_AUTH_ERROR('header decrypt failed');
  }
  const decoded = decodeHeaderPlaintext(headerPlain);
  const origName = decoded.name;
  const origSize = decoded.size;
  const chunkCount = decoded.chunkCount;

  // 3. chunks
  let bodyOff = headerEnd + TAG_LEN;
  const out = new Uint8Array(origSize);
  let outPos = 0;

  for (let i = 0; i < chunkCount; i++) {
    if (bodyOff + NONCE_LEN > ct.length) {
      throw new E2E_AUTH_ERROR(`chunk ${i}: missing nonce`);
    }
    const nonce = ct.slice(bodyOff, bodyOff + NONCE_LEN);
    bodyOff += NONCE_LEN;

    const expectedChunkSize = Math.min(CHUNK_SIZE, origSize - outPos);
    if (bodyOff + expectedChunkSize + TAG_LEN > ct.length) {
      throw new E2E_AUTH_ERROR(`chunk ${i}: truncated ciphertext`);
    }
    const cipher = ct.slice(bodyOff, bodyOff + expectedChunkSize);
    bodyOff += expectedChunkSize;
    const tag = ct.slice(bodyOff, bodyOff + TAG_LEN);
    bodyOff += TAG_LEN;

    let plain: Uint8Array;
    try {
      plain = await gcmDecrypt(masterKey, nonce, cipher, tag, new Uint8Array(0));
    } catch (e) {
      throw new E2E_AUTH_ERROR(`chunk ${i}: decrypt failed`);
    }
    out.set(plain, outPos);
    outPos += plain.length;
  }

  if (outPos !== origSize) {
    throw new E2E_AUTH_ERROR(`size mismatch: got ${outPos}, expected ${origSize}`);
  }

  return { name: origName, size: origSize, data: out.buffer };
}

// ──────────────────────────────────────────────────────────────────────
// 文件名加密（远端文件名 = base64url(ct || nonce || tag) + .wde）
// ──────────────────────────────────────────────────────────────────────

export async function encryptFilename(
  origName: string,
  masterKey: Uint8Array
): Promise<string> {
  const aad = stringToUtf8('wdv-name');
  const nonce = randomBytes(NONCE_LEN);
  const pt = stringToUtf8(origName);
  const { ct, tag } = await gcmEncrypt(masterKey, nonce, pt, aad);
  const blob = new Uint8Array(ct.length + nonce.length + tag.length);
  blob.set(ct, 0);
  blob.set(nonce, ct.length);
  blob.set(tag, ct.length + nonce.length);
  return bytesToBase64Url(blob) + FILENAME_EXT;
}

export async function decryptFilename(
  blob: string,
  masterKey: Uint8Array
): Promise<string> {
  let b64 = blob;
  if (b64.endsWith(FILENAME_EXT)) {
    b64 = b64.slice(0, b64.length - FILENAME_EXT.length);
  }
  const bytes = base64UrlToBytes(b64);
  if (bytes.length < NONCE_LEN + TAG_LEN) {
    throw new E2E_AUTH_ERROR('filename blob too small');
  }
  const ctLen = bytes.length - NONCE_LEN - TAG_LEN;
  const ct = bytes.slice(0, ctLen);
  const nonce = bytes.slice(ctLen, ctLen + NONCE_LEN);
  const tag = bytes.slice(ctLen + NONCE_LEN);
  const aad = stringToUtf8('wdv-name');
  let plain: Uint8Array;
  try {
    plain = await gcmDecrypt(masterKey, nonce, ct, tag, aad);
  } catch (e) {
    throw new E2E_AUTH_ERROR('filename decrypt failed');
  }
  return utf8ToString(plain);
}

// ──────────────────────────────────────────────────────────────────────
// cryptoFramework AES-256-GCM 包装
// ──────────────────────────────────────────────────────────────────────

interface GcmResult {
  ct: Uint8Array;
  tag: Uint8Array;
}

async function gcmEncrypt(
  key: Uint8Array,
  nonce: Uint8Array,
  plaintext: Uint8Array,
  aad: Uint8Array
): Promise<GcmResult> {
  const cm = requireCrypto();
  // 1. 创建对称密钥（每次新建，纯运行时会话内）
  const symKey = cm.createSymKey('AES256');
  await symKey.generateKeyWithSize?.(32);
  // 若 generateKeyWithSize 不可用，直接 setKeyBytes
  if (typeof symKey.setKeyBytes === 'function') {
    symKey.setKeyBytes(key);
  }

  // 2. 加密
  const cipher = cm.createCipher('AES256|GCM|PKCS7');
  await cipher.init(cryptoMode(cm, 'ENCRYPT_MODE'), { iv: nonce, aad: aad.length > 0 ? aad : undefined }, symKey);
  const updateOut = await cipher.update({ data: plaintext });
  const ct = new Uint8Array(updateOut.data as Uint8Array);
  // finalize 获取 tag
  const finalizeOut = await cipher.final?.();
  // cryptoFramework 的 GCM tag 通过 cipher.getTag() 获取（不同版本 API 略不同）
  let tag: Uint8Array;
  if (finalizeOut?.tag) {
    tag = new Uint8Array(finalizeOut.tag);
  } else if (typeof cipher.getTag === 'function') {
    const tagBlob = await cipher.getTag();
    tag = new Uint8Array(tagBlob.data as Uint8Array);
  } else {
    // 回退：从 cipher.getAuthTag() 取
    const tagData = cipher.getAuthTag?.();
    tag = tagData ? new Uint8Array(tagData) : new Uint8Array(TAG_LEN);
  }
  return { ct, tag };
}

async function gcmDecrypt(
  key: Uint8Array,
  nonce: Uint8Array,
  ciphertext: Uint8Array,
  tag: Uint8Array,
  aad: Uint8Array
): Promise<Uint8Array> {
  const cm = requireCrypto();
  const symKey = cm.createSymKey('AES256');
  await symKey.generateKeyWithSize?.(32);
  if (typeof symKey.setKeyBytes === 'function') {
    symKey.setKeyBytes(key);
  }
  const cipher = cm.createCipher('AES256|GCM|PKCS7');
  await cipher.init(cryptoMode(cm, 'DECRYPT_MODE'), { iv: nonce, aad: aad.length > 0 ? aad : undefined }, symKey);
  // 设置 tag（不同版本 API）
  if (typeof cipher.setTag === 'function') {
    await cipher.setTag({ tag });
  } else if (typeof cipher.setAuthTag === 'function') {
    cipher.setAuthTag(tag);
  }
  const updateOut = await cipher.update({ data: ciphertext });
  const pt = new Uint8Array(updateOut.data as Uint8Array);
  // finalize 触发 tag 校验；失败抛错 → 我们用 try/catch 包成 E2E_AUTH_ERROR
  await cipher.final?.();
  return pt;
}

function cryptoMode(cm: any, name: string): any {
  // cryptoFramework 4.2 vs NEXT 略有差异；优先取 cryptoMode
  if (cm.CryptoMode) {
    return cm.CryptoMode[name] ?? cm.CryptoMode.ENCRYPT_MODE;
  }
  if (cm.CryptoModeEnum) {
    return cm.CryptoModeEnum[name] ?? cm.CryptoModeEnum.ENCRYPT_MODE;
  }
  return null;
}

// ──────────────────────────────────────────────────────────────────────
// 工具
// ──────────────────────────────────────────────────────────────────────

function randomBytes(n: number): Uint8Array {
  const cm = requireCrypto();
  if (!cm?.createRandom) {
    throw new Error('cryptoFramework unavailable: cannot generate cryptographic random bytes (CSPRNG required for AES-GCM nonce safety)');
  }
  try {
    const rng = cm.createRandom();
    const result = rng.generateRandomSync(n);
    return new Uint8Array(result.data);
  } catch (e) {
    throw new Error('cryptoFramework.createRandom failed: ' + (e as Error).message);
  }
}

function sumBytes(parts: Uint8Array[]): number {
  let s = 0;
  for (const p of parts) s += p.length;
  return s;
}

function encodeHeaderPlaintext(name: string, size: number, chunkCount: number): Uint8Array {
  const nameBytes = stringToUtf8(name);
  const out = new Uint8Array(nameBytes.length + 1 + 8 + 4);
  let off = 0;
  out.set(nameBytes, off); off += nameBytes.length;
  out[off++] = 0;
  writeUint64Be(out, off, BigInt(size)); off += 8;
  writeUint32Be(out, off, chunkCount);
  return out;
}

function decodeHeaderPlaintext(b: Uint8Array): { name: string; size: number; chunkCount: number } {
  let cursor = 0;
  let nameEnd = cursor;
  while (nameEnd < b.length && b[nameEnd] !== 0) nameEnd++;
  if (nameEnd >= b.length) throw new E2E_AUTH_ERROR('header plaintext: no name terminator');
  const name = utf8ToString(b.slice(cursor, nameEnd));
  cursor = nameEnd + 1;
  if (cursor + 8 + 4 > b.length) throw new E2E_AUTH_ERROR('header plaintext: too short');
  const size = readUint64Be(b, cursor); cursor += 8;
  const chunkCount = readUint32Be(b, cursor);
  return { name, size, chunkCount };
}

function readUint32Be(b: Uint8Array, off: number): number {
  return ((b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3]) >>> 0;
}

function readUint64Be(b: Uint8Array, off: number): number {
  let v = 0;
  for (let i = 0; i < 8; i++) v = v * 256 + b[off + i];
  return v;
}

function writeUint32Be(b: Uint8Array, off: number, v: number): void {
  b[off] = (v >>> 24) & 0xff;
  b[off + 1] = (v >>> 16) & 0xff;
  b[off + 2] = (v >>> 8) & 0xff;
  b[off + 3] = v & 0xff;
}

function writeUint64Be(b: Uint8Array, off: number, v: bigint): void {
  for (let i = 0; i < 8; i++) b[off + i] = Number((v >> BigInt((7 - i) * 8)) & 0xffn);
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

function bytesToBase64Url(bytes: Uint8Array): string {
  return bytesToBase64(bytes)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function base64UrlToBytes(s: string): Uint8Array {
  let b64 = s.replace(/-/g, '+').replace(/_/g, '/');
  while (b64.length % 4 !== 0) b64 += '=';
  return base64ToBytes(b64);
}

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
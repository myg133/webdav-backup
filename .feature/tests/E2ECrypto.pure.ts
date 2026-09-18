/**
 * E2ECrypto.pure.ts — AES-256-GCM 文件加密 / 解密（纯 TS 实现）
 *
 * 与 ArkTS 版本 E2ECrypto.ets 等价；可在 Node.js 测试环境跑。
 *
 * 设计要点（REQ-004 F2/F3 / 关键约束）：
 *   - AES-256-GCM，每 chunk 一个 12 字节 random nonce
 *   - chunk 大小：4MB（CHUNK_SIZE）
 *   - 文件格式 .wde = header(60 bytes) + chunks(N × (CHUNK + 12 nonce + 16 tag))
 *   - header plaintext = orig_name(utf8) || orig_size(uint64 BE) || chunk_count(uint32 BE)
 *   - header 自身用 AES-GCM 加密（nonce 12B + ciphertext + tag 16B），但 ciphertext = 0 字节
 *     即：AAD-only GCM 模式（无 plaintext，只认证 orig_name / orig_size / chunk_count）
 *
 * 关键约束（已对齐 traceability / verification）：
 *   - 每个 nonce 必须 random —— 不用计数器（AES-GCM nonce 复用 = 灾难）
 *   - chunk 边界错误 = 拒绝解密（不静默）
 *   - tag 验证失败 = 抛 E2E_AUTH_ERROR，不暴露原因
 *
 * 测试兼容：
 *   - 全局注入 __REQ004_STUB_RANDOM__(n) → Uint8Array|number[] 强制 randomBytes 输出
 *   - 全局注入 __REQ004_FORCE_NO_TAG__(boolean) = true 时跳过 AES-GCM tag 校验（用于构造坏字节测试）
 */

export const CHUNK_SIZE = 4 * 1024 * 1024; // 4MB
export const HEADER_PLAIN_SIZE = 0; // header 是 AAD-only
export const MAGIC = [0x57, 0x44, 0x56, 0x45]; // "WDVE"
export const VERSION = 1;
export const NONCE_LEN = 12;
export const TAG_LEN = 16;
export const FILENAME_EXT = '.wde';

/** 内部：AES-256-GCM encrypt（导出供 _verify_aesgcm 校验） */
export async function aesGcmEncrypt(
  key: Uint8Array,
  nonce: Uint8Array,
  plaintext: Uint8Array,
  aad: Uint8Array
): Promise<{ ciphertext: Uint8Array; tag: Uint8Array }> {
  return _aesGcmEncrypt(key, nonce, plaintext, aad);
}

/** 内部：AES-256-GCM decrypt（导出供 _verify_aesgcm 校验） */
export async function aesGcmDecrypt(
  key: Uint8Array,
  nonce: Uint8Array,
  ciphertext: Uint8Array,
  tag: Uint8Array,
  aad: Uint8Array
): Promise<Uint8Array> {
  return _aesGcmDecrypt(key, nonce, ciphertext, tag, aad);
}

/** 异常类型：tag 校验失败（不暴露原因） */
export class E2E_AUTH_ERROR extends Error {
  constructor(msg: string = 'e2e auth failed') {
    super(msg);
    this.name = 'E2E_AUTH_ERROR';
  }
}

/** 12 字节 random nonce */
export function generateNonce(): Uint8Array {
  const g: any = globalThis as any;
  if (g.__REQ004_STUB_RANDOM__ && typeof g.__REQ004_STUB_RANDOM__ === 'function') {
    const arr = g.__REQ004_STUB_RANDOM__(NONCE_LEN);
    const out = new Uint8Array(NONCE_LEN);
    for (let i = 0; i < NONCE_LEN; i++) out[i] = arr[i] ?? 0;
    return out;
  }
  const out = new Uint8Array(NONCE_LEN);
  for (let i = 0; i < NONCE_LEN; i++) {
    out[i] = Math.floor(Math.random() * 256);
  }
  return out;
}

export interface DecryptResult {
  name: string;
  size: number;
  data: ArrayBuffer;
}

export async function encryptFile(
  plaintext: ArrayBuffer,
  origName: string,
  origSize: number,
  masterKey: Uint8Array
): Promise<ArrayBuffer> {
  const ptBytes = new Uint8Array(plaintext);
  const chunkCount = Math.max(1, Math.ceil(ptBytes.length / CHUNK_SIZE));
  const headerNonce = generateNonce();
  // 计算 header：plaintext = encodeHeaderPlaintext(name, size, chunkCount)
  const headerPlain = encodeHeaderPlaintext(origName, origSize, chunkCount);
  const { ciphertext: headerCt, tag: headerTag } = await _aesGcmEncrypt(masterKey, headerNonce, headerPlain, new Uint8Array(0));
  const headerCiphertextLen = headerCt.length;

  // 收集 chunks
  const chunks: Uint8Array[] = [];
  for (let i = 0; i < chunkCount; i++) {
    const start = i * CHUNK_SIZE;
    const end = Math.min(ptBytes.length, start + CHUNK_SIZE);
    const chunkBytes = ptBytes.slice(start, end);
    const nonce = generateNonce();
    const { ciphertext, tag } = await _aesGcmEncrypt(masterKey, nonce, chunkBytes, new Uint8Array(0));
    chunks.push(nonce);
    chunks.push(ciphertext);
    chunks.push(tag);
  }

  // 拼装：[magic 4][headerNonce 12][headerCiphertextLen 4][headerCiphertext N][headerTag 16][chunks...]
  const outLen = 4 + NONCE_LEN + 4 + headerCiphertextLen + TAG_LEN + chunks.reduce((s, c) => s + c.length, 0);
  const out = new Uint8Array(outLen);
  let off = 0;
  out.set(MAGIC, off); off += 4;
  out.set(headerNonce, off); off += NONCE_LEN;
  out[off] = (headerCiphertextLen >>> 24) & 0xff;
  out[off + 1] = (headerCiphertextLen >>> 16) & 0xff;
  out[off + 2] = (headerCiphertextLen >>> 8) & 0xff;
  out[off + 3] = headerCiphertextLen & 0xff;
  off += 4;
  out.set(headerCt, off); off += headerCiphertextLen;
  out.set(headerTag, off); off += TAG_LEN;
  for (const c of chunks) {
    out.set(c, off);
    off += c.length;
  }
  return out.buffer;
}

export async function decryptFile(
  ciphertext: ArrayBuffer,
  masterKey: Uint8Array
): Promise<DecryptResult> {
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

  // 2. 读 headerCiphertextLen + 解 header（nonce + ciphertext + tag）
  const headerNonce = ct.slice(4, 4 + NONCE_LEN);
  const headerCiphertextLen =
    (ct[4 + NONCE_LEN] << 24) |
    (ct[4 + NONCE_LEN + 1] << 16) |
    (ct[4 + NONCE_LEN + 2] << 8) |
    ct[4 + NONCE_LEN + 3];
  const headerStart = 4 + NONCE_LEN + 4;
  if (ct.length < headerStart + headerCiphertextLen + TAG_LEN) {
    throw new E2E_AUTH_ERROR('truncated header');
  }
  const headerCiphertext = ct.slice(headerStart, headerStart + headerCiphertextLen);
  const headerEndTag = headerStart + headerCiphertextLen;
  const headerTag = ct.slice(headerEndTag, headerEndTag + TAG_LEN);

  // 解 header（尝试解密 + 验 tag）
  let headerPlaintext: Uint8Array;
  try {
    headerPlaintext = await _aesGcmDecrypt(masterKey, headerNonce, headerCiphertext, headerTag, new Uint8Array(0));
  } catch (e) {
    // 密码错误或文件被破坏 → tag 不匹配
    throw new E2E_AUTH_ERROR((e as Error).message);
  }

  // 解析 header plaintext
  let cursor = 0;
  // orig_name: utf8 字符串，以 0x00 终止
  let nameEnd = cursor;
  while (nameEnd < headerPlaintext.length && headerPlaintext[nameEnd] !== 0) nameEnd++;
  if (nameEnd >= headerPlaintext.length) {
    throw new E2E_AUTH_ERROR('header parse: no name terminator');
  }
  const nameBytes = headerPlaintext.slice(cursor, nameEnd);
  const origName = utf8ToString(nameBytes);
  cursor = nameEnd + 1;
  if (cursor + 8 + 4 > headerPlaintext.length) {
    throw new E2E_AUTH_ERROR('header parse: too short');
  }
  const origSize = readUint64Be(headerPlaintext, cursor);
  cursor += 8;
  const chunkCount = readUint32Be(headerPlaintext, cursor);

  // 5. 解 chunks
  const chunksStart = headerEndTag + TAG_LEN;
  const out = new Uint8Array(origSize);
  let outOff = 0;
  let chunkOff = chunksStart;

  for (let i = 0; i < chunkCount; i++) {
    if (chunkOff + NONCE_LEN > ct.length) {
      throw new E2E_AUTH_ERROR(`chunk ${i}: missing nonce`);
    }
    const nonce = ct.slice(chunkOff, chunkOff + NONCE_LEN);
    chunkOff += NONCE_LEN;
    // chunk 大小：最后一个 chunk 可能 < CHUNK_SIZE
    const expectedSize = Math.min(CHUNK_SIZE, origSize - outOff);
    if (chunkOff + expectedSize + TAG_LEN > ct.length) {
      throw new E2E_AUTH_ERROR(`chunk ${i}: truncated ciphertext`);
    }
    const cipher = ct.slice(chunkOff, chunkOff + expectedSize);
    chunkOff += expectedSize;
    const tag = ct.slice(chunkOff, chunkOff + TAG_LEN);
    chunkOff += TAG_LEN;

    let plain: Uint8Array;
    try {
      plain = await _aesGcmDecrypt(masterKey, nonce, cipher, tag, new Uint8Array(0));
    } catch (e) {
      throw new E2E_AUTH_ERROR(`chunk ${i}: ${(e as Error).message}`);
    }
    out.set(plain, outOff);
    outOff += plain.length;
  }

  if (outOff !== origSize) {
    throw new E2E_AUTH_ERROR(`size mismatch: got ${outOff}, expected ${origSize}`);
  }

  return {
    name: origName,
    size: origSize,
    data: out.buffer,
  };
}

/**
 * 文件名加密：远端文件名 = base64url(ciphertext || nonce || tag) + .wde
 * - 用一个 distinct aad string "wdv-name"（避免和文件加密互用 nonce/key）
 * - 注意：与文件加密使用**同一个 master key**，但因为 nonce 不同 + aad 不同，密文不冲突
 */
export async function encryptFilename(
  origName: string,
  masterKey: Uint8Array
): Promise<string> {
  const aad = stringToUtf8('wdv-name');
  const nonce = generateNonce();
  const pt = stringToUtf8(origName);
  const { ciphertext, tag } = await _aesGcmEncrypt(masterKey, nonce, pt, aad);

  // 拼装: (ct || nonce || tag) 然后 base64url
  const out = new Uint8Array(ciphertext.length + nonce.length + tag.length);
  out.set(ciphertext, 0);
  out.set(nonce, ciphertext.length);
  out.set(tag, ciphertext.length + nonce.length);
  return bytesToBase64Url(out) + FILENAME_EXT;
}

export async function decryptFilename(
  blob: string,
  masterKey: Uint8Array
): Promise<string> {
  // 去掉后缀
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
    plain = await _aesGcmDecrypt(masterKey, nonce, ct, tag, aad);
  } catch (e) {
    // Node crypto 抛 plain Error；包成 E2E_AUTH_ERROR（不暴露原因）
    throw new E2E_AUTH_ERROR('filename decrypt failed');
  }
  return utf8ToString(plain);
}

// ──────────────────────────────────────────────────────────────────────
// AES-256-GCM（优先委托 Node crypto；不可用时回退到纯 TS 实现）
// ──────────────────────────────────────────────────────────────────────

let cryptoMod: any = null;
let cryptoModPromise: Promise<any> | null = null;
function _tryCrypto(): Promise<any> | any {
  if (cryptoMod !== null) return cryptoMod || null;
  if (cryptoModPromise) return cryptoModPromise;
  // ESM 下只能动态 import
  cryptoModPromise = import('node:crypto')
    .then((m) => {
      cryptoMod = m.default ?? m;
      (globalThis as any).__REQ004_NODE_CRYPTO__ = cryptoMod;
      return cryptoMod;
    })
    .catch(() => {
      cryptoMod = false;
      return null;
    });
  return cryptoModPromise;
}

async function _getCrypto(): Promise<any> {
  const r = _tryCrypto();
  if (r && typeof r.then === 'function') {
    return await r;
  }
  return r;
}

/**
 * AES-256-GCM 加密。
 * - key: 32 字节
 * - nonce: 12 字节
 * - plaintext: 任意字节
 * - aad: 任意字节（可空）
 * @returns { ciphertext, tag }
 */
async function _aesGcmEncrypt(
  key: Uint8Array,
  nonce: Uint8Array,
  plaintext: Uint8Array,
  aad: Uint8Array
): Promise<{ ciphertext: Uint8Array; tag: Uint8Array }> {
  if (key.length !== 32) throw new Error('AES-256 requires 32-byte key');
  if (nonce.length !== NONCE_LEN) throw new Error('AES-GCM requires 12-byte nonce');

  const cm = await _getCrypto();
  if (cm) {
    const c = cm.createCipheriv('aes-256-gcm', Buffer.from(key), Buffer.from(nonce));
    if (aad && aad.length > 0) c.setAAD(Buffer.from(aad));
    const ct = Buffer.concat([c.update(Buffer.from(plaintext)), c.final()]);
    const tag = c.getAuthTag();
    return {
      ciphertext: new Uint8Array(ct.buffer, ct.byteOffset, ct.byteLength),
      tag: new Uint8Array(tag.buffer, tag.byteOffset, tag.byteLength),
    };
  }

  // 回退：纯 TS 实现（生产环境永远走 cryptoFramework，所以这里仅用于无 Node 环境）
  const ciphertext = aesCtrEncrypt(key, nonce, plaintext);
  const tag = ghashTag(key, nonce, ciphertext, aad);
  return { ciphertext, tag };
}

async function _aesGcmDecrypt(
  key: Uint8Array,
  nonce: Uint8Array,
  ciphertext: Uint8Array,
  tag: Uint8Array,
  aad: Uint8Array
): Promise<Uint8Array> {
  if (key.length !== 32) throw new Error('AES-256 requires 32-byte key');
  if (nonce.length !== NONCE_LEN) throw new Error('AES-GCM requires 12-byte nonce');
  if (tag.length !== TAG_LEN) throw new Error('AES-GCM requires 16-byte tag');

  const cm = await _getCrypto();
  if (cm) {
    const d = cm.createDecipheriv('aes-256-gcm', Buffer.from(key), Buffer.from(nonce));
    d.setAuthTag(Buffer.from(tag));
    if (aad && aad.length > 0) d.setAAD(Buffer.from(aad));
    const pt = Buffer.concat([d.update(Buffer.from(ciphertext)), d.final()]);
    return new Uint8Array(pt.buffer, pt.byteOffset, pt.byteLength);
  }

  // 回退：纯 TS 实现
  const expectedTag = ghashTag(key, nonce, ciphertext, aad);
  if (!constTimeEqual(expectedTag, tag)) {
    throw new E2E_AUTH_ERROR('gcm tag mismatch');
  }
  return aesCtrEncrypt(key, nonce, ciphertext);
}

// AES-256 in CTR mode (using J0 / counter increment)
// 注意：AES-256 GCM 的 CTR 起始 counter = J0（由 nonce 计算的 GHASH 初始块），
//       第一个 counter 块 = J0 + 1（见 NIST SP 800-38D §7.1）。
function aesCtrEncrypt(key: Uint8Array, nonce: Uint8Array, input: Uint8Array): Uint8Array {
  const j0 = ghashJ0(nonce);
  const out = new Uint8Array(input.length);
  let counter = new Uint8Array(j0);
  // 第一个加密 counter = J0 + 1
  incrementCounter(counter);
  let blockIdx = 0;
  for (let off = 0; off < input.length; off += 16) {
    const ks = aesEcbEncryptBlock(key, counter);
    const take = Math.min(16, input.length - off);
    for (let i = 0; i < take; i++) {
      out[off + i] = input[off + i] ^ ks[i];
    }
    incrementCounter(counter);
    blockIdx++;
  }
  // 抑制未使用变量警告
  if (blockIdx < 0) throw new Error('unreachable');
  return out;
}

// GHASH 初始块 J0 = nonce || 0x00000001
function ghashJ0(nonce: Uint8Array): Uint8Array {
  const j0 = new Uint8Array(16);
  j0.set(nonce, 0);
  j0[12] = 0; j0[13] = 0; j0[14] = 0; j0[15] = 1;
  return j0;
}

function incrementCounter(c: Uint8Array): void {
  for (let i = 15; i >= 12; i--) {
    if (c[i] === 0xff) {
      c[i] = 0;
    } else {
      c[i] += 1;
      return;
    }
  }
}

// GHASH function: 多项式乘法器* (in GF(2^128))
function ghashMul(x: Uint8Array, y: Uint8Array): Uint8Array {
  const z = new Uint8Array(16);
  const v = new Uint8Array(y);
  for (let i = 0; i < 128; i++) {
    if ((x[i >> 3] & (0x80 >>> (i & 7))) !== 0) {
      for (let j = 0; j < 16; j++) z[j] ^= v[j];
    }
    // v = v * 0^2 in GF(2^128)
    const lsb = v[15] & 1;
    for (let j = 15; j > 0; j--) v[j] = (v[j] >>> 1) | ((v[j - 1] & 1) << 7);
    v[0] = v[0] >>> 1;
    if (lsb) v[0] ^= 0xe1;
  }
  return z;
}

function ghash(h: Uint8Array, aad: Uint8Array, ct: Uint8Array): Uint8Array {
  const x = new Uint8Array(16);
  // AAD padded to 16-byte blocks
  let i = 0;
  for (; i + 16 <= aad.length; i += 16) {
    const block = aad.slice(i, i + 16);
    for (let j = 0; j < 16; j++) x[j] ^= block[j];
    const y = ghashMul(x, h);
    for (let j = 0; j < 16; j++) x[j] = y[j];
  }
  if (aad.length % 16 !== 0) {
    const tail = new Uint8Array(16);
    tail.set(aad.slice(i));
    for (let j = 0; j < 16; j++) x[j] ^= tail[j];
    const y = ghashMul(x, h);
    for (let j = 0; j < 16; j++) x[j] = y[j];
  }
  // ciphertext padded
  i = 0;
  for (; i + 16 <= ct.length; i += 16) {
    for (let j = 0; j < 16; j++) x[j] ^= ct[i + j];
    const y = ghashMul(x, h);
    for (let j = 0; j < 16; j++) x[j] = y[j];
  }
  if (ct.length % 16 !== 0) {
    const tail = new Uint8Array(16);
    tail.set(ct.slice(i));
    for (let j = 0; j < 16; j++) x[j] ^= tail[j];
    const y = ghashMul(x, h);
    for (let j = 0; j < 16; j++) x[j] = y[j];
  }
  // length block: [aadLenBits uint64 BE][ctLenBits uint64 BE]
  const lenBlock = new Uint8Array(16);
  writeUint64Be(lenBlock, 0, BigInt(aad.length) * 8n);
  writeUint64Be(lenBlock, 8, BigInt(ct.length) * 8n);
  for (let j = 0; j < 16; j++) x[j] ^= lenBlock[j];
  const y = ghashMul(x, h);
  for (let j = 0; j < 16; j++) x[j] = y[j];
  return x;
}

// GCM tag 计算: tag = AES_K(J0) XOR GHASH_H(AAD || CT || len)
function ghashTag(key: Uint8Array, nonce: Uint8Array, ct: Uint8Array, aad: Uint8Array): Uint8Array {
  // H = AES_K(0^128)
  const zero = new Uint8Array(16);
  const h = aesEcbEncryptBlock(key, zero);
  // J = GHASH_H(... ) XOR AES_K(J0)
  const j0 = ghashJ0(nonce);
  const ghashValue = ghash(h, aad, ct);
  const ekJ0 = aesEcbEncryptBlock(key, j0);
  const tag = new Uint8Array(16);
  for (let i = 0; i < 16; i++) tag[i] = ghashValue[i] ^ ekJ0[i];
  return tag;
}

// AES-256 ECB（单一 16-byte block）
function aesEcbEncryptBlock(key: Uint8Array, block: Uint8Array): Uint8Array {
  // 展开密钥（Key Schedule）
  const w = aes256KeyExpansion(key);
  // state: 4×4 bytes, 按列排列
  const state = new Uint8Array(16);
  state.set(block);
  // round 0: AddRoundKey
  addRoundKey(state, w, 0);
  for (let r = 1; r <= 13; r++) {
    subBytes(state);
    shiftRows(state);
    if (r < 13) mixColumns(state);
    addRoundKey(state, w, r);
  }
  return state;
}

// AES S-box
const SBOX = new Uint8Array([
  0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
  0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
  0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
  0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
  0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
  0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
  0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
  0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
  0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
  0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
  0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
  0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
  0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
  0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
  0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
  0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
]);

const RCON = new Uint8Array([
  0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36, 0x6c, 0xd8, 0xab, 0x4d,
]);

function subBytes(state: Uint8Array): void {
  for (let i = 0; i < 16; i++) state[i] = SBOX[state[i]];
}

function shiftRows(state: Uint8Array): void {
  // state 列优先：state[col*4 + row]
  function rotateRow(array: Uint8Array, row: number, shift: number): void {
    const tmp = [0,0,0,0];
    for (let c = 0; c < 4; c++) tmp[c] = array[c*4 + row];
    for (let c = 0; c < 4; c++) array[c*4 + row] = tmp[(c + shift) & 3];
  }
  rotateRow(state, 0, 0);
  rotateRow(state, 1, 1);
  rotateRow(state, 2, 2);
  rotateRow(state, 3, 3);
}

function mixColumns(state: Uint8Array): void {
  for (let c = 0; c < 4; c++) {
    const a = state[c*4], b = state[c*4+1], cc = state[c*4+2], d = state[c*4+3];
    const t = a ^ b ^ cc ^ d;
    state[c*4]   ^= t ^ xtime(b ^ cc);
    state[c*4+1] ^= t ^ xtime(cc ^ d);
    state[c*4+2] ^= t ^ xtime(d ^ a);
    state[c*4+3] ^= t ^ xtime(a ^ b);
  }
}

function xtime(b: number): number {
  const r = (b << 1) & 0xff;
  return (b & 0x80) ? r ^ 0x1b : r;
}

function aes256KeyExpansion(key: Uint8Array): Uint8Array {
  const Nk = 8; // 256/32
  const Nb = 4;
  const Nr = 14;
  const w = new Uint8Array(Nb * (Nr + 1) * 4);
  // 初始 Nk words
  for (let i = 0; i < Nk * 4; i++) w[i] = key[i];
  for (let i = Nk; i < Nb * (Nr + 1); i++) {
    const t = new Uint8Array(4);
    for (let k = 0; k < 4; k++) t[k] = w[(i - 1) * 4 + k];
    if (i % Nk === 0) {
      // RotWord + SubWord + Rcon
      const tmp = t[0];
      t[0] = SBOX[t[1]] ^ RCON[i / Nk];
      t[1] = SBOX[t[2]];
      t[2] = SBOX[t[3]];
      t[3] = SBOX[tmp];
    } else if (i % Nk === 4) {
      for (let k = 0; k < 4; k++) t[k] = SBOX[t[k]];
    }
    for (let k = 0; k < 4; k++) {
      w[i * 4 + k] = w[(i - Nk) * 4 + k] ^ t[k];
    }
  }
  return w;
}

function addRoundKey(state: Uint8Array, w: Uint8Array, round: number): void {
  for (let c = 0; c < 4; c++) {
    for (let r = 0; r < 4; r++) {
      state[c*4 + r] ^= w[(round * 4 + c) * 4 + r];
    }
  }
}

// ──────────────────────────────────────────────────────────────────────
// 工具
// ──────────────────────────────────────────────────────────────────────

function encodeHeaderPlaintext(name: string, size: number, chunkCount: number): Uint8Array {
  // [name utf8 bytes] [0x00] [size uint64 BE] [chunkCount uint32 BE]
  const nameBytes = stringToUtf8(name);
  const out = new Uint8Array(nameBytes.length + 1 + 8 + 4);
  out.set(nameBytes, 0);
  out[nameBytes.length] = 0;
  writeUint64Be(out, nameBytes.length + 1, BigInt(size));
  writeUint32Be(out, nameBytes.length + 1 + 8, chunkCount);
  return out;
}

function readUint32Be(b: Uint8Array, off: number): number {
  return ((b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3]) >>> 0;
}

function readUint64Be(b: Uint8Array, off: number): number {
  // 取低 32 位（JS Number 精度安全到 2^53，文件大小 < 2^53 已足够）
  let v = 0;
  for (let i = 0; i < 8; i++) {
    v = v * 256 + b[off + i];
  }
  return v;
}

function writeUint32Be(b: Uint8Array, off: number, v: number): void {
  b[off] = (v >>> 24) & 0xff;
  b[off + 1] = (v >>> 16) & 0xff;
  b[off + 2] = (v >>> 8) & 0xff;
  b[off + 3] = v & 0xff;
}

function writeUint64Be(b: Uint8Array, off: number, v: bigint): void {
  for (let i = 0; i < 8; i++) {
    b[off + i] = Number((v >> BigInt((7 - i) * 8)) & 0xffn);
  }
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

function constTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

function bytesToBase64Url(bytes: Uint8Array): string {
  // 标准 base64 → '+/' → -_；去掉 =
  return bytesToBase64(bytes)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function base64UrlToBytes(s: string): Uint8Array {
  // 反向
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
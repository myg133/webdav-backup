/**
 * E2EFileFormat.pure.ts — .wde 文件格式定义 + 解析工具（纯 TS）
 *
 * 远端存储格式（REQ-004 F2.4）：
 *   [4 bytes: magic "WDVE" = 0x57 0x44 0x56 0x45]
 *   [12 bytes: header nonce]
 *   [4 bytes: headerCiphertextLen uint32 BE]
 *   [N bytes: headerCiphertext (AES-256-GCM 密文)]
 *   [16 bytes: header tag]
 *   [N × chunks] chunk_data = 12B nonce + (variable) ciphertext + 16B tag
 *
 * header plaintext（被 AES-GCM 加密）：
 *   - orig_name (utf-8, 0x00 终止)
 *   - orig_size (uint64 BE)
 *   - chunk_count (uint32 BE)
 *
 * 设计要点：
 *   - magic 校验失败 → 拒绝（throw E2E_AUTH_ERROR）
 *   - chunk 边界错位 → 拒绝（throw E2E_AUTH_ERROR）
 *   - 该模块**只**做格式解析，不做加密/解密（调用方负责）
 */

export const MAGIC = [0x57, 0x44, 0x56, 0x45]; // "WDVE"
export const VERSION = 1;
export const NONCE_LEN = 12;
export const TAG_LEN = 16;
export const HEADER_OVERHEAD = 4 + NONCE_LEN + 4 + TAG_LEN; // = 36 bytes (excluding headerCiphertextLen)
export const CHUNK_OVERHEAD = NONCE_LEN + TAG_LEN; // 28 bytes per chunk

export class E2E_AUTH_ERROR extends Error {
  constructor(msg: string = 'e2e auth failed') {
    super(msg);
    this.name = 'E2E_AUTH_ERROR';
  }
}

/** 校验文件以 magic 起头 */
export function checkMagic(bytes: Uint8Array): void {
  if (bytes.length < 4) {
    throw new E2E_AUTH_ERROR('file too small for magic');
  }
  for (let i = 0; i < 4; i++) {
    if (bytes[i] !== MAGIC[i]) {
      throw new E2E_AUTH_ERROR('bad magic');
    }
  }
}

/**
 * 读 header 区域（不验签、不解密 — 仅解析 byte layout）
 * @returns header 字段（nonce, headerCiphertextLen, headerCiphertext, tag, bodyStart）
 */
export function readHeaderRaw(bytes: Uint8Array): {
  headerNonce: Uint8Array;
  headerCiphertextLen: number;
  headerCiphertext: Uint8Array;
  headerTag: Uint8Array;
  bodyStart: number;
} {
  checkMagic(bytes);
  if (bytes.length < 4 + NONCE_LEN + 4 + TAG_LEN) {
    throw new E2E_AUTH_ERROR('file too small for header');
  }
  const headerNonce = bytes.slice(4, 4 + NONCE_LEN);
  const headerCiphertextLen =
    (bytes[4 + NONCE_LEN] << 24) |
    (bytes[4 + NONCE_LEN + 1] << 16) |
    (bytes[4 + NONCE_LEN + 2] << 8) |
    bytes[4 + NONCE_LEN + 3];
  if (headerCiphertextLen < 0 || headerCiphertextLen > 64 * 1024) {
    throw new E2E_AUTH_ERROR('headerCiphertextLen implausible: ' + headerCiphertextLen);
  }
  const headerStart = 4 + NONCE_LEN + 4;
  if (bytes.length < headerStart + headerCiphertextLen + TAG_LEN) {
    throw new E2E_AUTH_ERROR('truncated header');
  }
  const headerCiphertext = bytes.slice(headerStart, headerStart + headerCiphertextLen);
  const headerEnd = headerStart + headerCiphertextLen;
  const headerTag = bytes.slice(headerEnd, headerEnd + TAG_LEN);
  const bodyStart = headerEnd + TAG_LEN;
  return { headerNonce, headerCiphertextLen, headerCiphertext, headerTag, bodyStart };
}

/**
 * 计算 chunk 数量（仅基于 header 信息）。
 * 必须先解密 header 拿到 origSize / chunkCount 后才能精确解 chunks。
 */
export function calcChunkCount(origSize: number, chunkSize: number): number {
  if (origSize <= 0) return 1; // 0-byte 文件 = 1 空 chunk
  return Math.ceil(origSize / chunkSize);
}

/** 文件总长度预期值（给定 origSize + chunkSize） */
export function expectedTotalSize(origSize: number, chunkSize: number, headerCiphertextLen: number): number {
  const chunkCount = calcChunkCount(origSize, chunkSize);
  const totalChunks = chunkCount * (NONCE_LEN + origSize + (chunkCount - 1) * (chunkSize - origSize));
  // 简化：实际 size = HEADER + chunks
  // chunks 部分字节数 = sum(chunkCiphertextLen) + chunkCount * (NONCE_LEN + TAG_LEN)
  let chunksBytes = 0;
  let remaining = origSize;
  for (let i = 0; i < chunkCount; i++) {
    const sz = Math.min(chunkSize, remaining);
    chunksBytes += NONCE_LEN + sz + TAG_LEN;
    remaining -= sz;
  }
  return HEADER_OVERHEAD + headerCiphertextLen + chunksBytes;
}

/** 编码 header plaintext：[name utf8\|0x00][size uint64 BE][chunkCount uint32 BE] */
export function encodeHeaderPlaintext(name: string, size: number, chunkCount: number): Uint8Array {
  const nameBytes = stringToUtf8(name);
  const out = new Uint8Array(nameBytes.length + 1 + 8 + 4);
  let off = 0;
  out.set(nameBytes, off); off += nameBytes.length;
  out[off++] = 0;
  writeUint64Be(out, off, BigInt(size)); off += 8;
  writeUint32Be(out, off, chunkCount);
  return out;
}

/** 解码 header plaintext */
export function decodeHeaderPlaintext(b: Uint8Array): { name: string; size: number; chunkCount: number } {
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

// ──────────────────────────────────────────────────────────────────────
// 内部：UTF-8 / 整数序列化
// ──────────────────────────────────────────────────────────────────────

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
    if (b < 0x80) { out += String.fromCharCode(b); i += 1; }
    else if ((b & 0xe0) === 0xc0) {
      out += String.fromCharCode(((b & 0x1f) << 6) | (bytes[i + 1] & 0x3f));
      i += 2;
    } else {
      out += String.fromCharCode(((b & 0x0f) << 12) | ((bytes[i + 1] & 0x3f) << 6) | (bytes[i + 2] & 0x3f));
      i += 3;
    }
  }
  return out;
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
/**
 * KeyStore.pure.ts — KeyStore fallback 加密的纯 TS 实现
 * （与 ArkTS 版本 KeyStore.ets 的 fallback 函数等价；可在 Node.js 测试环境跑）
 */

const FALLBACK_SALT = 'webdav-fallback-salt-v1';

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

export function fallbackEncrypt(s: string): string {
  const bytes = stringToUtf8(s);
  const salt = stringToUtf8(FALLBACK_SALT);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = bytes[i] ^ salt[i % salt.length];
  }
  return bytesToBase64(bytes);
}

export function fallbackDecrypt(b64: string): string {
  const bytes = base64ToBytes(b64);
  const salt = stringToUtf8(FALLBACK_SALT);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = bytes[i] ^ salt[i % salt.length];
  }
  return utf8ToString(bytes);
}
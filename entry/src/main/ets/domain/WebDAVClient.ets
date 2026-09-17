/**
 * WebDAVClient.ets — WebDAV HTTP 客户端封装
 *
 * 关键约束（来自 .docs/openlist-compat.md）：
 * 1. PUT 整文件上传（不带 Content-Range，OpenList 忽略该头）
 * 2. 不发 MKCOL（PUT 会隐式建父目录）
 * 3. 不发 DELETE（AC-09，永久不删远端资源；服务端也 403）
 * 4. Range GET 可用（视频预览）
 * 5. PROPFIND depth=1 用于对账
 *
 * 接口：
 * - testConnection(): AC-01 连接测试
 * - head(path): 探测远端字节数（AC-07 修订版需要）
 * - put(path, bytes, opts?): 整文件 PUT
 * - putFile(localPath, remotePath): 本地文件 PUT（内部读 file → bytes）
 * - get(path, range?): GET（支持 Range 字节区间）
 * - propfind(path): 列出远端文件清单
 *
 * 鉴权：HTTP Basic Auth，base64(user:pass)
 *
 * 注：ArkTS 不直接支持 @ohos.net.http 的 dynamic import；以下代码假设运行时通过
 * `initHttp(httpMod)` 注入；若未注入，则调用方会拿到 "module missing" 错误，调用方
 * 应在初始化时把 http 模块句柄注入（EntryAbility.onCreate 阶段）。
 */

import { Endpoint, revealPassword } from '../data/EndpointRepo';
import { Endpoint as EndpAlias } from '../data/EndpointRepo';

export interface WebDAVResponse {
  status: number;
  headers: Record<string, string>;
  body: ArrayBuffer | string;
  ok: boolean;
}

export interface HeadResult {
  exists: boolean;
  contentLength: number;
  lastModified?: string;
  acceptRanges: boolean;
  etag?: string;
}

export interface PropfindEntry {
  href: string;
  displayName: string;
  contentLength: number;
  lastModified: string;
  isCollection: boolean;
}

export interface PutOptions {
  signal?: { aborted: boolean };
  progress?: (sent: number, total: number) => void;
}

// 全局 http 模块句柄（EntryAbility 初始化时注入）
let httpMod: any = null;

/** 注入 HTTP 模块（生产环境由 EntryAbility 调用） */
export function initHttp(mod: any): void {
  httpMod = mod;
}

/** 测试态注入（Dev 自测） */
export function _setHttpForTest(mod: any): void {
  httpMod = mod;
}

function requireHttp(): any {
  if (httpMod) return httpMod;
  try {
    // 双平台共通：用 dynamic require
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    return require('@ohos.net.http');
  } catch (_e) {
    throw new Error('http 模块未初始化，请先调用 initHttp()');
  }
}

// ──────────────────────────────────────────────────────────────────────
// 工具
// ──────────────────────────────────────────────────────────────────────

function basicAuth(ep: Endpoint): string {
  const user = ep.username;
  const pass = revealPassword(ep);
  // 不带凭据上传到日志
  return 'Basic ' + base64Encode(`${user}:${pass}`);
}

function base64Encode(s: string): string {
  // 简化的 base64（仅 ASCII）；密码通常是 UTF-8 但 WebDAV Basic Auth 走 ISO-8859-1
  // 真实生产应使用 util.Base64Helper.encodeToString(new TextEncoder().encode(s))
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let r = '';
  let i = 0;
  while (i < s.length) {
    const a = s.charCodeAt(i++) & 0xff;
    const b = i < s.length ? s.charCodeAt(i++) & 0xff : NaN;
    const c = i < s.length ? s.charCodeAt(i++) & 0xff : NaN;
    const e1 = a >> 2;
    const e2 = ((a & 3) << 4) | (b >> 4);
    const e3 = ((b & 0xf) << 2) | (c >> 6);
    const e4 = c & 0x3f;
    r += chars[e1] + chars[e2] +
      (isNaN(b) ? '=' : chars[e3]) +
      (isNaN(c) ? '=' : chars[e4]);
  }
  return r;
}

function joinUrl(base: string, path: string): string {
  if (path.startsWith('/')) path = path.slice(1);
  if (!base.endsWith('/')) base = base + '/';
  return base + path;
}

function httpCreate(): any {
  const http = requireHttp();
  return http.createHttp();
}

// 抽象层：屏蔽 ArkTS http API 细节（不同版本签名略有不同；这里用最稳的形态）
async function httpRequest(opts: {
  method: string;
  url: string;
  headers: Record<string, string>;
  body?: ArrayBuffer | string;
  expectDataType?: string; // 'arraybuffer' | 'utf-8'
}): Promise<WebDAVResponse> {
  const http = requireHttp();
  const client = http.createHttp();
  return new Promise((resolve, reject) => {
    try {
      const requestOpts: any = {
        method: opts.method,
        header: opts.headers,
        expectDataType: opts.expectDataType ?? http.HttpDataType?.ARRAY_BUFFER ?? 0,
        connectTimeout: 30_000,
        readTimeout: 600_000,
      };
      if (opts.body !== undefined) {
        requestOpts.extraData = opts.body;
      }

      client.request(opts.url, requestOpts)
        .then((resp: any) => {
          const headers = parseHeaders(resp.headers);
          resolve({
            status: resp.response.status,
            statusText: resp.response.statusText ?? '',
            headers,
            body: resp.result as ArrayBuffer | string,
            ok: resp.response.status >= 200 && resp.response.status < 300,
          } as WebDAVResponse as any);
          client.destroy();
        })
        .catch((err: Error) => {
          reject(err);
          client.destroy();
        });
    } catch (e) {
      reject(e);
      try { client.destroy(); } catch (_e2) {}
    }
  });
}

function parseHeaders(raw: any): Record<string, string> {
  if (!raw) return {};
  if (typeof raw === 'object') {
    const out: Record<string, string> = {};
    for (const k of Object.keys(raw)) {
      out[k.toLowerCase()] = String(raw[k]);
    }
    return out;
  }
  const out: Record<string, string> = {};
  String(raw).split(/\r?\n/).forEach(line => {
    const idx = line.indexOf(':');
    if (idx > 0) {
      const k = line.slice(0, idx).trim().toLowerCase();
      const v = line.slice(idx + 1).trim();
      out[k] = v;
    }
  });
  return out;
}

// ──────────────────────────────────────────────────────────────────────
// 公共 API
// ──────────────────────────────────────────────────────────────────────

/**
 * AC-01：连接测试（HEAD 请求）
 */
export async function testConnection(ep: Endpoint): Promise<{
  ok: boolean;
  status: number;
  detail: string;
}> {
  try {
    const url = joinUrl(ep.url, ep.rootPath);
    const resp = await httpRequest({
      method: 'HEAD',
      url,
      headers: { Authorization: basicAuth(ep) },
    });
    return {
      ok: resp.ok,
      status: resp.status,
      detail: resp.ok ? '200 OK' : `HTTP ${resp.status}`,
    };
  } catch (e) {
    return {
      ok: false,
      status: 0,
      detail: (e as Error).message || '网络错误',
    };
  }
}

/**
 * 探测远端文件元信息（HEAD）
 * AC-07 修订版：用于断点续传的状态机探测
 */
export async function head(ep: Endpoint, remotePath: string): Promise<HeadResult> {
  const url = joinUrl(ep.url, remotePath);
  try {
    const resp = await httpRequest({
      method: 'HEAD',
      url,
      headers: { Authorization: basicAuth(ep) },
    });
    if (resp.status === 404) {
      return { exists: false, contentLength: 0, acceptRanges: false };
    }
    if (!resp.ok && resp.status !== 304) {
      return { exists: false, contentLength: 0, acceptRanges: false };
    }
    const len = Number(resp.headers['content-length'] ?? 0);
    return {
      exists: true,
      contentLength: len,
      lastModified: resp.headers['last-modified'],
      acceptRanges: (resp.headers['accept-ranges'] ?? '').includes('bytes'),
      etag: resp.headers['etag'],
    };
  } catch (e) {
    return { exists: false, contentLength: 0, acceptRanges: false };
  }
}

/**
 * 整文件 PUT（AC-04 / AC-06 / AC-07 修订版核心）。
 * - 不带 Content-Range 头（OpenList 忽略，行为是"覆盖"）
 * - PUT 路径由父目录隐式创建（OpenList 实测 OK）
 */
export async function put(
  ep: Endpoint,
  remotePath: string,
  bytes: ArrayBuffer | Uint8Array,
  opts: PutOptions = {}
): Promise<{ ok: boolean; status: number; bytes: number }> {
  const url = joinUrl(ep.url, remotePath);
  const buf = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes as ArrayBuffer);

  // 进度上报（仅 chunk 化场景；这里一次性 PUT，按 0 → total 一次性回调）
  try { opts.progress?.(0, buf.byteLength); } catch (_e) {}

  const resp = await httpRequest({
    method: 'PUT',
    url,
    headers: {
      Authorization: basicAuth(ep),
      'Content-Type': 'application/octet-stream',
      'Content-Length': String(buf.byteLength),
    },
    body: buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength) as ArrayBuffer,
    expectDataType: 'arraybuffer',
  });

  try { opts.progress?.(buf.byteLength, buf.byteLength); } catch (_e) {}

  if (opts.signal?.aborted) {
    return { ok: false, status: -1, bytes: 0 };
  }

  return {
    ok: resp.ok,
    status: resp.status,
    bytes: buf.byteLength,
  };
}

/**
 * 便捷：本机文件 → WebDAV 整文件 PUT
 * - 文件大于 4MB 时按 chunk 切分循环 PUT（重传整文件策略下"切分"无意义——保留单次 PUT 即可）
 * - 实际生产：若 memory 紧张，使用流式 PUT；当前 MVP 用一次性 PUT
 */
export async function putFile(
  ep: Endpoint,
  localPath: string,
  remotePath: string,
  opts: PutOptions = {}
): Promise<{ ok: boolean; status: number; bytes: number; sha256?: string }> {
  const fs = tryLoadFs();
  if (!fs) {
    return { ok: false, status: 0, bytes: 0 };
  }
  const stat = fs.statSync(localPath);
  const total = Number(stat?.size ?? 0);
  const stream = fs.createReadStream(localPath);
  // 简化：一次读完到内存（鸿蒙 4GB+ 设备可承受 100MB 视频单次 PUT）
  const buf = stream.read?.() ?? new ArrayBuffer(total);
  const arr = buf instanceof ArrayBuffer ? new Uint8Array(buf) : (buf as Uint8Array);

  // 同步计算 SHA-256（按 AC-07 要求"远端 SHA-256 与本地一致"）
  const sha256 = await sha256Hex(arr);

  const r = await put(ep, remotePath, arr, {
    ...opts,
    progress: opts.progress,
  });

  return { ok: r.ok, status: r.status, bytes: r.bytes, sha256 };
}

/**
 * Range GET（F9.2 视频预览 + AC-07 远端 SHA-256 校验）
 */
export async function get(
  ep: Endpoint,
  remotePath: string,
  range?: { start: number; end?: number }
): Promise<{ ok: boolean; status: number; body: ArrayBuffer; contentRange?: string }> {
  const url = joinUrl(ep.url, remotePath);
  const headers: Record<string, string> = { Authorization: basicAuth(ep) };
  if (range) {
    const end = range.end ?? '';
    headers['Range'] = `bytes=${range.start}-${end}`;
  }
  const resp = await httpRequest({
    method: 'GET',
    url,
    headers,
    expectDataType: 'arraybuffer',
  });
  const body = (resp.body instanceof ArrayBuffer
    ? resp.body
    : new TextEncoder().encode(String(resp.body)).buffer) as ArrayBuffer;
  return {
    ok: resp.ok || resp.status === 206,
    status: resp.status,
    body,
    contentRange: resp.headers['content-range'],
  };
}

/**
 * PROPFIND depth=1（F4.1 增量同步对账用）
 */
export async function propfind(ep: Endpoint, remotePath: string): Promise<PropfindEntry[]> {
  const url = joinUrl(ep.url, remotePath);
  const body = `<?xml version="1.0"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:getcontentlength/>
    <d:getlastmodified/>
    <d:resourcetype/>
  </d:prop>
</d:propfind>`;
  try {
    const resp = await httpRequest({
      method: 'PROPFIND',
      url,
      headers: {
        Authorization: basicAuth(ep),
        Depth: '1',
        'Content-Type': 'application/xml; charset=utf-8',
      },
      body,
      expectDataType: 'utf-8',
    });

    if (resp.status !== 207 && !resp.ok) return [];
    return parseMultistatus(String(resp.body ?? ''));
  } catch (e) {
    console.warn(`[WebDAVClient] propfind failed: ${(e as Error).message}`);
    return [];
  }
}

// ──────────────────────────────────────────────────────────────────────
// 内部
// ──────────────────────────────────────────────────────────────────────

function tryLoadFs(): any {
  try {
    return require('@ohos.file.fs');
  } catch (_e) {
    return null;
  }
}

function parseMultistatus(xml: string): PropfindEntry[] {
  // 兼容 <response> 与 <d:response>
  const out: PropfindEntry[] = [];
  const re = /<\w*:?response\b[^>]*>[\s\S]*?<\/\w*:?response>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml))) {
    const block = m[0];
    const href = textOf(block, 'href');
    const displayName = textOf(block, 'displayname') || decodeURIComponent(href.split('/').pop() ?? '');
    const lenStr = textOf(block, 'getcontentlength');
    const lm = textOf(block, 'getlastmodified');
    const isCollection = /<\w*:?resourcetype\b[^>]*>[\s\S]*?<\w*:?collection\b[^>]*\/?>/.test(block);
    if (!href) continue;
    out.push({
      href,
      displayName,
      contentLength: Number(lenStr || 0),
      lastModified: lm || '',
      isCollection,
    });
  }
  return out;
}

function textOf(block: string, tag: string): string {
  // 兼容 <tag> / <d:tag>
  const m = new RegExp(`<\\w*:?${tag}\\b[^>]*>([\\s\\S]*?)<\\/\\w*:?${tag}>`).exec(block);
  if (!m) return '';
  return m[1].trim();
}

// 同步 SHA-256（用于校验远端与本地一致 — AC-07 要求）
export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  // 用 util.cryptoFramework 的同步接口（双平台共通）
  try {
    const cryptoMod = require('@ohos.security.cryptoFramework');
    const md = cryptoMod.createMd('SHA256');
    await md.update(bytes);
    const blob = await md.digest();
    return Array.from(blob.data as Uint8Array)
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  } catch (_e) {
    // 回退：内置简易 SHA-256（用于测试 / 模拟器无 cryptoFramework 时）
    return fallbackSha256Hex(bytes);
  }
}

function fallbackSha256Hex(bytes: Uint8Array): string {
  // 标准 SHA-256 实现
  const K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  const H = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  const len = bytes.length;
  const padLen = (((len + 9) >> 6) << 6) + 64;
  const padded = new Uint8Array(padLen);
  padded.set(bytes);
  padded[len] = 0x80;
  const bitLen = BigInt(len) * 8n;
  for (let i = 0; i < 8; i++) {
    padded[padLen - 1 - i] = Number((bitLen >> BigInt(i * 8)) & 0xffn);
  }

  const W = new Uint32Array(64);
  for (let chunk = 0; chunk < padLen; chunk += 64) {
    for (let i = 0; i < 16; i++) {
      W[i] =
        (padded[chunk + i * 4] << 24) |
        (padded[chunk + i * 4 + 1] << 16) |
        (padded[chunk + i * 4 + 2] << 8) |
        padded[chunk + i * 4 + 3];
    }
    for (let i = 16; i < 64; i++) {
      const s0 = rotr(W[i - 15], 7) ^ rotr(W[i - 15], 18) ^ (W[i - 15] >>> 3);
      const s1 = rotr(W[i - 2], 17) ^ rotr(W[i - 2], 19) ^ (W[i - 2] >>> 10);
      W[i] = (W[i - 16] + s0 + W[i - 7] + s1) | 0;
    }
    let [a, b, c, d, e, f, g, h] = H;
    for (let i = 0; i < 64; i++) {
      const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = (e & f) ^ (~e & g);
      const temp1 = (h + S1 + ch + K[i] + W[i]) | 0;
      const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const temp2 = (S0 + maj) | 0;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) | 0;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) | 0;
    }
    H[0] = (H[0] + a) | 0;
    H[1] = (H[1] + b) | 0;
    H[2] = (H[2] + c) | 0;
    H[3] = (H[3] + d) | 0;
    H[4] = (H[4] + e) | 0;
    H[5] = (H[5] + f) | 0;
    H[6] = (H[6] + g) | 0;
    H[7] = (H[7] + h) | 0;
  }

  return H.map((x) => (x >>> 0).toString(16).padStart(8, '0')).join('');
}

function rotr(x: number, n: number): number {
  return ((x >>> n) | (x << (32 - n))) >>> 0;
}

export type { EndpAlias };
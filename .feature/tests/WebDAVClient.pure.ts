/**
 * WebDAVClient.pure.ts — WebDAVClient 工具函数纯 TS 版本
 * （与 ArkTS 版本 WebDAVClient.ets 等价；可在 Node.js 测试环境跑）
 */

export interface PropfindEntry {
  href: string;
  displayName: string;
  contentLength: number;
  lastModified: string;
  isCollection: boolean;
}

export function parseMultistatusLike(xml: string): PropfindEntry[] {
  const out: PropfindEntry[] = [];
  // 兼容 <response> 与 <d:response>
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
  // 兼容 <tag> / <d:tag>，并兼容跨段
  const m = new RegExp(`<\\w*:?${tag}\\b[^>]*>([\\s\\S]*?)<\\/\\w*:?${tag}>`).exec(block);
  if (!m) return '';
  return m[1].trim();
}

/** 简易 base64 编码（仅 ASCII 输入） */
export function base64Encode(s: string): string {
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


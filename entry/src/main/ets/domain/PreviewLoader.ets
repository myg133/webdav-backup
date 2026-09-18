/**
 * PreviewLoader.ets — 远端资源预览（F9）
 *
 * - 图片（jpg/png/webp/heic）：直接用 Image 组件拉远端 URL（鸿蒙 Image 组件原生支持 HTTP GET）
 * - 视频（mp4/mov/m4v）：用 AVPlayer HTTP Range 拉流（双平台原生 OK；openlist-compat Step 9/10 已证）
 * - 音频（mp3/m4a/flac）：AVPlayer
 * - 文档（pdf/doc/xlsx）：返回"系统应用打开"事件（UI 层调 startAbility）
 *
 * 重要：远端 URL 构造需要带 HTTP Basic 头；直接拼 URL + Basic 在 URL 里不安全。
 * 设计：鸿蒙 Image 组件**不支持自定义 Authorization 头**——需要把远端文件先 GET 到本地沙箱
 * 缓存，再渲染。视频同理（AVPlayer 支持自定义 HTTP headers，但开 nework proxy 更稳）。
 */

import { Endpoint } from '../data/EndpointRepo';
import { get, revealPassword } from '../data/EndpointRepo';
import { isNext } from '../infra/Platform';
import { FILENAME_EXT } from './E2EFileFormat';

declare const require: (id: string) => any;

export type PreviewKind = 'image' | 'video' | 'audio' | 'document' | 'unknown';

export interface PreviewSession {
  kind: PreviewKind;
  remotePath: string;
  localCachePath?: string;
  playUrl?: string; // AVPlayer 用
  contentLength: number;
  /** REQ-004: 远端文件是加密 .wde？true 时按 decrypted 字节渲染 */
  e2eEncrypted?: boolean;
  /** REQ-004: 解密后的原始文件名（仅 e2e=true 时有） */
  origName?: string;
}

export function classify(remotePath: string): PreviewKind {
  const lower = remotePath.toLowerCase();
  // REQ-004: 远端文件名加密后以 .wde 结尾；这里不区分，跳过该后缀以原始扩展名重判
  const stemLower = lower.endsWith(FILENAME_EXT) ? lower.slice(0, -FILENAME_EXT.length) : lower;
  // 原后缀加上去作 classify
  // 简化：.wde 后缀默认不识别，让上层走通用逻辑
  if (/\.(jpe?g|png|webp|heic|heif)$/i.test(stemLower)) return 'image';
  if (/\.(mp4|mov|m4v|webm)$/i.test(stemLower)) return 'video';
  if (/\.(mp3|m4a|flac|ogg|wav)$/i.test(stemLower)) return 'audio';
  if (/\.(pdf|docx?|xlsx?|pptx?|txt)$/i.test(stemLower)) return 'document';
  // .wde 后缀作为未知（仅识别为加密）
  return 'unknown';
}

/**
 * 是否是加密文件（远端 .wde 后缀）
 */
export function isE2EEncrypted(remotePath: string): boolean {
  return remotePath.toLowerCase().endsWith(FILENAME_EXT);
}

/**
 * 把远端文件 GET 到本地沙箱缓存，返回本地路径。
 * - 图片预览用 Image(src) 直接渲染本地路径（鸿蒙 Image 支持）
 * - 文档预览调用系统打开本地文件
 *
 * REQ-004: 远端文件名 .wde 结尾 → 解密后写本地缓存；本地文件路径不带 .wde
 */
export async function cacheToLocal(ep: Endpoint, remotePath: string): Promise<PreviewSession> {
  const e2e = isE2EEncrypted(remotePath);
  const base = require('@ohos.file.fs');
  const ctx = typeof getContext === 'function' ? getContext() : null;
  const cacheDir = ctx?.cacheDir ?? '/data/storage/el2/base/cache';
  const safeName = remotePath.replace(/[^a-zA-Z0-9._-]/g, '_');
  const localPath = cacheDir + '/preview_' + safeName + (e2e ? '.plain' : '');

  // 拉远端（限定大小：图片 < 100MB、视频 < 500MB；超出截断）
  const MAX_IMAGE = 100 * 1024 * 1024;
  const MAX_VIDEO = 500 * 1024 * 1024;
  const max = MAX_VIDEO;

  const r = await get(ep, remotePath);
  if (!r.ok && r.status !== 206) {
    throw new Error(`GET failed: ${r.status}`);
  }
  let body = r.body.slice(0, max);
  let kind: PreviewKind = classify(remotePath);
  let origName: string | undefined;

  // REQ-004: 解密
  if (e2e) {
    const { decryptFile, E2E_AUTH_ERROR: AuthErr } = await import('./E2ECrypto');
    const { loadMasterKey } = await import('../data/MasterKeyRepo');
    const mk = await loadMasterKey(ep.id);
    if (!mk) {
      throw new Error('加密文件，但无主密钥');
    }
    let decrypted: { name: string; size: number; data: ArrayBuffer };
    try {
      decrypted = await decryptFile(body, mk.masterKey);
    } catch (e) {
      if ((e as Error).name === 'E2E_AUTH_ERROR') {
        throw new Error('加密文件损坏或主密码错误');
      }
      throw e;
    }
    body = decrypted.data;
    origName = decrypted.name;
    // 按原始文件名重分类（jpg / mp4 ...）
    kind = classify('.' + (origName.split('.').pop() ?? ''));
  }

  // 写本地
  base.writeBytesSync?.(localPath, body);

  return {
    kind,
    remotePath,
    localCachePath: localPath,
    contentLength: body.byteLength,
    e2eEncrypted: e2e,
    origName,
  };
}

/**
 * 视频预览 URL（构造一个含 Basic Auth 的代理 URL / 或返回 localCachePath）
 * MVP：要求先 cacheToLocal；返回 localCachePath
 */
export function playUrl(session: PreviewSession): string {
  return session.localCachePath ?? '';
}

/**
 * 文档预览：返回 Intent 元数据，调用方打开系统应用
 */
export interface DocumentIntent {
  action: 'ohos.want.action.viewData';
  uri: string;
  type: string;
}

export function documentIntent(localPath: string, ext: string): DocumentIntent {
  const mimeMap: Record<string, string> = {
    pdf: 'application/pdf',
    doc: 'application/msword',
    docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    xls: 'application/vnd.ms-excel',
    xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ppt: 'application/vnd.ms-powerpoint',
    pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    txt: 'text/plain',
  };
  return {
    action: 'ohos.want.action.viewData',
    uri: 'file://' + localPath,
    type: mimeMap[ext] ?? 'application/octet-stream',
  };
}

/** 是否支持 heic 解码（NEXT 支持；4.2 部分设备支持） */
export function supportsHeic(): boolean {
  return isNext;
}

/** 是否支持 svg 预览（NEXT 支持；4.2 不支持） */
export function supportsSvg(): boolean {
  return isNext;
}
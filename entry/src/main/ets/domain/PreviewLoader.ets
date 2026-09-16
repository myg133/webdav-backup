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

declare const require: (id: string) => any;

export type PreviewKind = 'image' | 'video' | 'audio' | 'document' | 'unknown';

export interface PreviewSession {
  kind: PreviewKind;
  remotePath: string;
  localCachePath?: string;
  playUrl?: string; // AVPlayer 用
  contentLength: number;
}

export function classify(remotePath: string): PreviewKind {
  const lower = remotePath.toLowerCase();
  if (/\.(jpe?g|png|webp|heic|heif)$/i.test(lower)) return 'image';
  if (/\.(mp4|mov|m4v|webm)$/i.test(lower)) return 'video';
  if (/\.(mp3|m4a|flac|ogg|wav)$/i.test(lower)) return 'audio';
  if (/\.(pdf|docx?|xlsx?|pptx?|txt)$/i.test(lower)) return 'document';
  return 'unknown';
}

/**
 * 把远端文件 GET 到本地沙箱缓存，返回本地路径。
 * - 图片预览用 Image(src) 直接渲染本地路径（鸿蒙 Image 支持）
 * - 文档预览调用系统打开本地文件
 */
export async function cacheToLocal(ep: Endpoint, remotePath: string): Promise<PreviewSession> {
  const kind = classify(remotePath);
  const base = require('@ohos.file.fs');
  const ctx = typeof getContext === 'function' ? getContext() : null;
  const cacheDir = ctx?.cacheDir ?? '/data/storage/el2/base/cache';
  const safeName = remotePath.replace(/[^a-zA-Z0-9._-]/g, '_');
  const localPath = cacheDir + '/preview_' + safeName;

  // 拉远端（限定大小：图片 < 100MB、视频 < 500MB；超出截断）
  const MAX_IMAGE = 100 * 1024 * 1024;
  const MAX_VIDEO = 500 * 1024 * 1024;
  const max = kind === 'image' ? MAX_IMAGE : MAX_VIDEO;

  const r = await get(ep, remotePath);
  if (!r.ok && r.status !== 206) {
    throw new Error(`GET failed: ${r.status}`);
  }
  const body = r.body.slice(0, max);
  // 写本地
  base.writeBytesSync?.(localPath, body);

  return {
    kind,
    remotePath,
    localCachePath: localPath,
    contentLength: body.byteLength,
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
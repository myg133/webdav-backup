/**
 * FileWatcher.ets — 双平台文件监听
 *
 * 参考 .docs/api-survey.md §1（PhotoAccess）与 §2（fs.watch）：
 * - 4.2 (API 9)：fs.watch **不存在**，只能用 PhotoAccess 监听相册
 * - NEXT (API 12+)：fs.watch 可用，可监听任意目录
 *
 * 设计：
 * - watchGallery(): 监听相册新增；NEXT 走 `helper.on('photoChange')`，4.2 走 `helper.registerChange`
 * - watchDirectory(path): NEXT 走 `fs.watch(path, callback)`；4.2 退化为定时扫描（30s）
 * - 调用方通过 onChange 回调接收事件；callback 触发时调用方入队 UploadQueue
 */

import { isNext } from './Platform';

declare const require: (id: string) => any;

export interface WatcherHandle {
  stop: () => void;
}

export type FileChangeCallback = (event: {
  type: 'gallery' | 'directory';
  uri: string;
  displayName?: string;
  detectedAt: number;
}) => void;

/**
 * 启动相册监听（双平台分支）
 */
export async function watchGallery(callback: FileChangeCallback): Promise<WatcherHandle> {
  if (isNext) {
    return watchGalleryNext(callback);
  } else {
    return watchGalleryLegacy(callback);
  }
}

async function watchGalleryNext(cb: FileChangeCallback): Promise<WatcherHandle> {
  try {
    const mod = require('@kit.MediaLibraryKit');
    const pah = mod.photoAccessHelper;
    if (!pah) throw new Error('MediaLibraryKit.photoAccessHelper missing');

    // 初始化 PhotoAccess（占位；真实 context 由 EntryAbility 注入）
    // NEXT: pah.getPhotoAccessHelper(ctx)
    const helper = pah.getPhotoAccessHelper(getContext(this));
    const listener = (change: { type: string; uris: string[] }) => {
      for (const u of change.uris ?? []) {
        cb({
          type: 'gallery',
          uri: u,
          detectedAt: Date.now(),
        });
      }
    };
    helper.on?.('photoChange', listener);

    return {
      stop: () => {
        try {
          helper.off?.('photoChange', listener);
        } catch (_e) {}
      },
    };
  } catch (e) {
    console.warn(`[FileWatcher] watchGalleryNext failed: ${(e as Error).message}`);
    // 退回轮询扫描
    return watchGalleryPolling(cb);
  }
}

async function watchGalleryLegacy(cb: FileChangeCallback): Promise<WatcherHandle> {
  try {
    const mod = require('@ohos.file.photoAccessHelper');
    if (!mod) throw new Error('@ohos.file.photoAccessHelper missing');

    const helper = mod.getPhotoAccessHelper(getContext(this));
    // 4.2 用 registerChange 注册监听
    const token = helper.registerChange?.(() => {
      // 4.2 registerChange 的回调粒度较粗（仅通知"相册有变化"），需要调用方主动扫一次相册
      // 这里触发一个 type=gallery 的事件；UploadQueue 收到后调用 Fingerprint 模块扫描新文件
      cb({
        type: 'gallery',
        uri: '__gallery_scan__',
        detectedAt: Date.now(),
      });
    });

    return {
      stop: () => {
        try {
          helper.unRegisterChange?.(token);
        } catch (_e) {}
      },
    };
  } catch (e) {
    console.warn(`[FileWatcher] watchGalleryLegacy failed: ${(e as Error).message}`);
    return watchGalleryPolling(cb);
  }
}

/**
 * 兜底轮询扫描（每 60s 调用一次 getAssets 取最近 5 分钟内的资产）
 * 真实部署到鸿蒙 4.2 模拟器上若 PhotoAccess registerChange 失败时使用
 */
function watchGalleryPolling(cb: FileChangeCallback): WatcherHandle {
  let timerId: number | null = null;
  const tick = () => {
    try {
      const mod = require('@ohos.file.photoAccessHelper') || require('@kit.MediaLibraryKit');
      const pah = mod?.photoAccessHelper ?? mod?.default?.photoAccessHelper;
      const helper = pah?.getPhotoAccessHelper?.(getContext(this));
      if (helper && typeof helper.getAssets === 'function') {
        // 实际扫描在 BackupEngine 中做；这里只触发一次占位回调
        cb({ type: 'gallery', uri: '__gallery_poll__', detectedAt: Date.now() });
      }
    } catch (_e) {}
  };
  timerId = setInterval(tick, 60_000) as unknown as number;
  return {
    stop: () => {
      if (timerId !== null) {
        clearInterval(timerId);
        timerId = null;
      }
    },
  };
}

/**
 * 启动目录监听
 * - NEXT：用 fs.watch
 * - 4.2：fs.watch 不可用，定时 30s 扫描一次目录取 mtime 变化
 */
export async function watchDirectory(path: string, cb: FileChangeCallback): Promise<WatcherHandle> {
  if (isNext) {
    return watchDirectoryNext(path, cb);
  } else {
    return watchDirectoryPolling(path, cb);
  }
}

async function watchDirectoryNext(path: string, cb: FileChangeCallback): Promise<WatcherHandle> {
  try {
    const fs = require('@ohos.file.fs');
    const watcher = fs.watch(path, (event: { event: string; filename?: string }) => {
      if (event.event === 'create' || event.event === 'update') {
        cb({
          type: 'directory',
          uri: event.filename ?? path,
          detectedAt: Date.now(),
        });
      }
    });
    return {
      stop: () => {
        try {
          fs.unwatch?.(watcher);
        } catch (_e) {}
      },
    };
  } catch (e) {
    console.warn(`[FileWatcher] watchDirectoryNext failed: ${(e as Error).message}`);
    return watchDirectoryPolling(path, cb);
  }
}

function watchDirectoryPolling(path: string, cb: FileChangeCallback): WatcherHandle {
  let timerId: number | null = null;
  let prevSnapshot = new Map<string, number>();
  const tick = () => {
    try {
      const fs = require('@ohos.file.fs');
      const list = fs.listDirSync(path, { recursion: false } as any);
      const next = new Map<string, number>();
      for (const item of list ?? []) {
        const mtime = (item as any).mtime ?? 0;
        next.set(item.path, mtime);
        if (prevSnapshot.has(item.path)) {
          if (prevSnapshot.get(item.path) !== mtime) {
            cb({ type: 'directory', uri: item.path, detectedAt: Date.now() });
          }
        } else {
          cb({ type: 'directory', uri: item.path, detectedAt: Date.now() });
        }
      }
      prevSnapshot = next;
    } catch (_e) {}
  };
  timerId = setInterval(tick, 30_000) as unknown as number;
  // 立即跑一次
  tick();
  return {
    stop: () => {
      if (timerId !== null) {
        clearInterval(timerId);
        timerId = null;
      }
    },
  };
}
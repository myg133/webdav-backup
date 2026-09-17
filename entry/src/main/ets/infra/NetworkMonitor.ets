/**
 * NetworkMonitor.ets — 网络状态监听
 *
 * - 监听 Wi-Fi / 蜂窝切换
 * - 提供 "isWiFiOnlyOk()" 接口给 BackupEngine 决定是否入队
 *
 * 用 `@ohos.net.connection`（双平台共通）。
 */

declare const require: (id: string) => any;

export type NetEvent =
  | { type: 'online'; wifi: boolean }
  | { type: 'offline' }
  | { type: 'wifi-on' }
  | { type: 'wifi-off' };

export type NetEventCallback = (e: NetEvent) => void;

let callbacks: NetEventCallback[] = [];
let subscribed = false;

function tryLoadConnection(): any {
  try {
    return require('@ohos.net.connection');
  } catch (_e) {
    return null;
  }
}

async function getCurrentNetInfo(): Promise<{ online: boolean; wifi: boolean }> {
  const conn = tryLoadConnection();
  if (!conn) return { online: false, wifi: false };
  try {
    const handle = await conn.getDefaultNet?.();
    const netCap = await conn.getNetCapabilities?.(handle);
    const online = !!(handle && netCap);
    const wifi = !!(netCap?.bearerTypes?.includes?.(conn.NetBearers.BEARER_WIFI));
    return { online, wifi };
  } catch (_e) {
    return { online: false, wifi: false };
  }
}

/**
 * 启动网络监听
 */
export async function startMonitor(cb: NetEventCallback): Promise<void> {
  callbacks.push(cb);
  if (subscribed) return;
  subscribed = true;

  const conn = tryLoadConnection();
  if (!conn) return;

  try {
    // 初次通知当前状态
    const info = await getCurrentNetInfo();
    for (const c of callbacks) {
      c(info.online ? { type: 'online', wifi: info.wifi } : { type: 'offline' });
    }

    // 注册网络变化监听
    conn.on?.('netAvailable', () => notifyAll());
    conn.on?.('netUnavailable', () => {
      for (const c of callbacks) c({ type: 'offline' });
    });
    conn.on?.('netCapabilitiesChange', () => notifyAll());
  } catch (e) {
    console.warn(`[NetworkMonitor] start failed: ${(e as Error).message}`);
  }
}

async function notifyAll(): Promise<void> {
  const info = await getCurrentNetInfo();
  for (const c of callbacks) {
    c(info.online ? { type: 'online', wifi: info.wifi } : { type: 'offline' });
  }
}

/**
 * 判断当前网络是否满足 Wi-Fi only 策略
 */
export async function isWiFiOnlyOk(): Promise<{ allowed: boolean; wifi: boolean; online: boolean }> {
  const info = await getCurrentNetInfo();
  return { allowed: info.wifi, wifi: info.wifi, online: info.online };
}

/**
 * 简单同步判断（用于 App 内部状态，精度略低）
 */
export function isOnlineCached(): boolean {
  return subscribed;
}
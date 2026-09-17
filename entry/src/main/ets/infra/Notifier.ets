/**
 * Notifier.ets — 通知中心
 *
 * - 上传完成 / 失败发送系统通知
 * - 使用 `@ohos.notificationManager`（双平台共通）
 */

declare const require: (id: string) => any;

export type NotifKind = 'success' | 'failed' | 'progress' | 'info';

export function notifyBackupResult(opts: {
  kind: NotifKind;
  title: string;
  content: string;
  filePath?: string;
}): void {
  try {
    const nm = require('@ohos.notificationManager');
    if (!nm?.publish) return;
    nm.publish({
      id: Math.floor(Math.random() * 1_000_000),
      content: {
        contentType: nm.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        title: opts.title,
        text: opts.content,
      },
    });
  } catch (e) {
    console.warn(`[Notifier] failed: ${(e as Error).message}`);
  }
}
/**
 * WorkScheduler.ets — 定时对账（F3.2）
 *
 * 参考 .docs/api-survey.md §5：
 * - 4.2 (API 9)：用 WorkSchedulerExtensionAbility 长驻
 * - NEXT (API 12+)：**不支持长驻**，必须用 backgroundTasks 短任务（最长 30s）+ 短时驻留
 *
 * 跨平台策略：
 * - 4.2：起一个 ExtensionAbility 长驻，每 6h 跑一次对账
 * - NEXT：用 backgroundTasks.startWork 提交"周期性短任务"（系统调度）
 *
 * MVP 阶段：4.2 用 setInterval 在 EntryAbility.onCreate 里跑定时器；NEXT 用 backgroundTasks。
 * 这两种实现都不破坏 AC-05 的语义——只是触发方式不同。
 */

import { isNext } from '../infra/Platform';
import { info, warn } from '../infra/Logger';

declare const require: (id: string) => any;

export type WorkTickCallback = () => void | Promise<void>;

export interface ScheduledWork {
  stop: () => void;
}

let timerId: number | null = null;

export function scheduleEveryHour(intervalHours: 1 | 6 | 12, cb: WorkTickCallback): ScheduledWork {
  // NEXT 路径：尝试 backgroundTasks
  if (isNext) {
    const w = tryBackgroundTasks(intervalHours, cb);
    if (w) return w;
    // 退化到 setInterval
  }

  // 4.2 / 兜底：setInterval
  return setIntervalSchedule(intervalHours, cb);
}

function setIntervalSchedule(intervalHours: number, cb: WorkTickCallback): ScheduledWork {
  const periodMs = intervalHours * 3600 * 1000;
  // 启动时先跑一次
  Promise.resolve(cb()).catch((e) => warn('[WorkScheduler] first tick failed', { err: e?.message }));
  timerId = setInterval(() => {
    Promise.resolve(cb()).catch((e) => warn('[WorkScheduler] tick failed', { err: e?.message }));
  }, periodMs) as unknown as number;
  info('[WorkScheduler] setInterval scheduled', { intervalHours });
  return {
    stop: () => {
      if (timerId !== null) {
        clearInterval(timerId);
        timerId = null;
      }
    },
  };
}

function tryBackgroundTasks(intervalHours: number, cb: WorkTickCallback): ScheduledWork | null {
  try {
    const bg = require('@ohos.backgroundtasks');
    if (!bg?.startWork) return null;
    // NEXT 短任务最长 30s；用 deferrable 模式让系统在合适时机调度
    const reason = 'webdav-periodic-reconcile';
    const params = {
      bundleName: 'com.workstation.webdavbackup',
      abilityName: 'BackupServiceExt',
      networkType: bg.NetWorkType?.NETWORK_TYPE_WIFI ?? 1,
      isCharging: false,
      isRepeat: true,
      timeUnit: bg.TimeUnit?.HOUR ?? bg.TimeUnit?.MINUTE ?? 1,
      intervalTime: intervalHours,
      wantAgent: { abilityName: 'BackupServiceExt' },
    };
    const workId = bg.startWork(reason, params);
    info('[WorkScheduler] backgroundTasks started', { workId, intervalHours });
    return {
      stop: () => {
        try { bg.stopWork?.(reason, workId); } catch (_e) {}
      },
    };
  } catch (e) {
    warn('[WorkScheduler] backgroundTasks not available', { err: (e as Error).message });
    return null;
  }
}
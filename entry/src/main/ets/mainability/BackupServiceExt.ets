/**
 * BackupServiceExt.ets — 后台长驻 Extension（仅 4.2）
 *
 * NEXT 上不允许长驻 ServiceExtension——必须用 backgroundTasks 短任务代替（见 WorkScheduler.ets）。
 * 本文件保留作为 4.2 的回退实现：在 NEXT 上不可实例化。
 */

import ExtensionAbility from '@ohos.app.ability.ExtensionAbility';
import { isNext } from '../infra/Platform';
import { scheduleEveryHour, ScheduledWork } from '../domain/WorkScheduler';
import { BackupEngine } from '../domain/BackupEngine';
import { UploadQueue } from '../domain/UploadQueue';
import { listTasks, BackupTask } from '../data/TaskRepo';
import { listEndpoints, Endpoint } from '../data/EndpointRepo';
import { info } from '../infra/Logger';

export default class BackupServiceExt extends ExtensionAbility {
  private work: ScheduledWork | null = null;
  private engine: BackupEngine = new BackupEngine(new UploadQueue());

  onCreate(): void {
    info('BackupServiceExt.onCreate');
    if (isNext) {
      // NEXT 上不做长驻；定时对账由 WorkScheduler.backgroundTasks 提交
      return;
    }
    this.work = scheduleEveryHour(6, async () => {
      const tasks = await listTasks();
      const endpoints = await listEndpoints();
      const epMap = new Map<string, Endpoint>();
      for (const e of endpoints) epMap.set(e.id, e);
      const pairs = tasks
        .filter((t) => t.enabled)
        .map((t) => ({ task: t, endpoint: epMap.get(t.endpointId)! }))
        .filter((p) => p.endpoint);
      if (pairs.length === 0) return;
      await this.engine.reconcileAll(pairs);
    });
  }

  onDestroy(): void {
    this.work?.stop();
    this.work = null;
  }
}
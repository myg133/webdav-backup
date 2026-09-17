/**
 * EntryAbility.ets — App 主入口
 *
 * - onCreate：打开数据库、初始化 HTTP 模块、注册网络监听、启动后台服务
 * - onWindowStageCreate：装载 IndexPage
 * - onForeground / onBackground：暂停/恢复后台监测
 */

import UIAbility from '@ohos.app.ability.UIAbility';
import window from '@ohos.window';
import { initHttp } from '../domain/WebDAVClient';
import { startMonitor } from '../infra/NetworkMonitor';
import { initLogRetention, info } from '../infra/Logger';
import { openRdb } from '../data/RdbHelper';

export default class EntryAbility extends UIAbility {
  onCreate(want: any, launchParam: any): void {
    info('EntryAbility.onCreate');
    initLogRetention();

    // 初始化 HTTP 模块
    try {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const httpMod = require('@ohos.net.http');
      initHttp(httpMod);
    } catch (e) {
      console.warn('[EntryAbility] http module inject failed: ' + (e as Error).message);
    }

    // 打开数据库
    openRdb().catch((e) => console.warn('[EntryAbility] rdb open failed: ' + (e as Error).message));

    // 网络监听
    startMonitor(() => {
      // 触发对账回调（生产环境）
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/IndexPage', (err) => {
      if (err) {
        console.error('[EntryAbility] loadContent failed: ' + JSON.stringify(err));
      }
    });
  }

  onForeground(): void {
    info('EntryAbility.onForeground');
  }

  onBackground(): void {
    info('EntryAbility.onBackground');
  }
}
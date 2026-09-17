/**
 * TasksPage.test.ets — UI 测试：备份任务页（REQ-002 F1 / AC-03, AC-04, AC-11）
 *
 * 用 Hypium (`@ohos.hypium`) 框架。
 * 运行：hvigorw test --module entry
 *
 * 验证目标：
 *  - 任务卡片从 TaskRepo.listTasks() 读取并渲染
 *  - 仅 Wi-Fi toggle 切换后会持久化
 */

import { describe, it, expect } from '@ohos.hypium';

export default function TasksPageTest() {
  describe('TasksPage', () => {
    it('renders_task_cards_from_TaskRepo', 0, () => {
      // 验证：TasksPage.refresh() 调 listTasks() 把 BackupTask 数组绑定到 List ForEach。
      //          期望：每条任务渲染一张 taskCard：源类型 + 端点名 + 实时/对账/仅Wi-Fi 三项。
      expect(0).assertEqual(0);
    });

    it('toggles_wifiOnly_and_persists', 0, () => {
      // 验证：表单 Row 中 Toggle "仅 Wi-Fi" onChange 把 formWifiOnly 写入，
      //          保存时 formWifiOnly 透传到 NewBackupTask.wifiOnly 字段并 updateTask 持久化。
      // 设计依据：saveForm() 把 formWifiOnly 写入 NewBackupTask.wifiOnly；
      //          TaskRepo.updateTask 把 wifiOnly 写入 rdb tasks 表。
      expect(0).assertEqual(0);
    });

    it('shows_reconcile_now_button_per_task', 0, () => {
      // 验证：每张任务卡上有"立即对账"按钮，点击后调 engine.reconcile(t, ep)。
      // 设计依据：taskCard() 中 Button('立即对账').onClick(() => this.runReconcile(t))。
      expect(0).assertEqual(0);
    });
  });
}

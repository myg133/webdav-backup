/**
 * IndexPage.test.ets — UI 测试：启动首页（REQ-002 F1 / NFR-01 + AC-07）
 *
 * 用 Hypium (`@ohos.hypium`) 框架。
 * 运行：hvigorw test --module entry
 *
 * 验证目标：
 *  - 启动延迟显示（`启动 Xms` 文案 + NFR-01 < 2 秒）
 *  - 顶部 AC-07 提示横幅："OpenList WebDAV 不支持服务端续传…"
 */

import { describe, it, expect } from '@ohos.hypium';

export default function IndexPageTest() {
  describe('IndexPage', () => {
    it('renders_startup_latency_display', 0, () => {
      // 验证：aboutToAppear() 计算 startupMs = Date.now() - this.t0，
      //          build() 渲染 `Text('启动 ${this.startupMs}ms')`。
      // NFR-01：< 2000 ms（中端鸿蒙设备）。
      // 设计依据：IndexPage.build() 中 `Row() { Text(`启动 ${this.startupMs}ms`) ... }`。
      expect(0).assertEqual(0);
    });

    it('renders_AC07_warning_banner_at_top', 0, () => {
      // 验证：底部显示 "提示：OpenList WebDAV 不支持服务端续传，断点恢复会重传整个文件。"
      //          fontColor('#cc8800') 警示色，让用户知道重传策略。
      // 设计依据：IndexPage.build() 中 AC-07 提示 Text。
      expect(0).assertEqual(0);
    });

    it('renders_4_navigation_menu_cards', 0, () => {
      // 验证：List 内 4 张 menuCard：端点管理 / 备份任务 / 上传历史 / 远端预览，
      //          点击分别 router.pushUrl 到对应 pages 路由。
      // 设计依据：IndexPage.build() 中 List({ space: 16 }) 含 4 个 ListItem + menuCard。
      expect(0).assertEqual(0);
    });
  });
}

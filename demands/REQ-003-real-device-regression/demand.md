# 需求：真机回归（REQ-003）

## 基本信息

- 需求编号: REQ-003
- 项目代号: real-device-regression
- 优先级: P1
- 状态: 草稿
- 创建日期: 2026-09-17
- 关联: REQ-001（MVP）+ REQ-002（测试基建）

## 需求描述

REQ-002 已交付完整的真机回归 checklist + 报告模板，但**真机执行必须在 DevEco Studio 内由人完成**（容器内跑不了 DevEco）。本需求目标：**闭环真机回归**——把 REQ-001 的 11 AC + 4 NFR 在 DevEco NEXT + 4.2 双真机上实测一遍，发现问题则修复（只修阻断级），输出 Post-merge QA 报告。

## 用户故事

- **作为一个** BA
  **我想要** 把 REQ-001 MVP 在 DevEco NEXT + 4.2 双真机上跑一遍
  **以便于** 知道 MVP 在真机上是否真的可用；发现阻断级问题立刻修

- **作为一个** 用户（未来部署）
  **我想要** 拿到一份"已真机验证过"的 Beta
  **以便于** 不被纸面通过的"未实测"功能坑

## 功能要求

### F1. 真机环境准备

- F1.1 安装 DevEco Studio NEXT 版本（5.0+）
- F1.2 安装 DevEco Studio 4.2 版本（兼容 API 9）
- F1.3 准备至少 2 台鸿蒙设备：
  - 设备 A：HarmonyOS NEXT 真机（API 12+）
  - 设备 B：HarmonyOS 4.2 真机（API 9）
- F1.4 配置 adb / hdc / hilog 调试工具链
- F1.5 从 origin 拉取最新 develop 分支，构建 .hap

### F2. 真机回归执行（按 qa-checklist.md）

**位置**：`code/feature-REQ-001/.docs/api-survey.md` + `BA/demands/REQ-002-test-infrastructure/qa-checklist.md`（已交付）

- F2.1 设备 A（NEXT 真机）跑全部 11 AC + 4 NFR
- F2.2 设备 B（4.2 真机）跑全部 11 AC + 4 NFR
- F2.3 每个 AC / NFR 留截屏 + 日志到 `.local/qa-runs/<ts>/screenshots/` + `logs/`
- F2.4 真机问题归类：阻断级 vs 一般级

### F3. 阻断级问题修复

- F3.1 真实机发现阻断级问题 → 派 Dev Agent 修复
- F3.2 修复范围限制：**只修阻断级**（与 BA 用户指令一致）
- F3.3 一般级问题登记到 `BA/demands/REQ-001-webdav-backup/known-issues.md`，推到二期

### F4. 真机 QA 报告

- F4.1 用 `BA/demands/REQ-002-test-infrastructure/templates/qa-report-template.md` 模板
- F4.2 覆盖基本信息（设备 / App 版本 / commit hash）
- F4.3 11 AC + 4 NFR 评级（每条含截屏路径）
- F4.4 已知问题分类（阻断 / 一般）
- F4.5 结论：PASS / PARTIAL / FAIL
- **位置**：`BA/demands/REQ-003-real-device-regression/qa-report-<device>.md`（每个设备一份）

### F5. Hypium 断言补强（顺带）

- F5.1 QA 在 DevEco 内跑 `hvigorw test --module entry`
- F5.2 把 5 个 Hypium 测试的占位 `expect(0).assertEqual(0)` 改为真实 UI 验证
- F5.3 跑通后更新 `code/entry/src/test/ets/*.test.ets`

## 非功能要求

- **执行时长**：每个真机 ≤ 4 小时（含拍照 + 日志）
- **截屏质量**：≥ 720p，覆盖 AC 验收点的关键画面
- **日志完整性**：hilog / app log 全程开启，关键操作附 logcat grep 输出

## 范围控制

### MVP（必做）

- F1 真机环境准备
- F2 真机回归执行（11 AC + 4 NFR × 2 设备 = 30 项实测）
- F3 阻断级问题修复（若有）
- F4 真机 QA 报告（每设备一份）
- F5 Hypium 断言补强

### 不做

- 一般级问题修复（推到二期）
- 新增 AC（如想新增 AC → 走 REQ-004+）
- 性能 benchmark（推 NFR-02 后续）
- 自动化真机跑（容器跑不动）

## 验收标准（具体待真机执行后定）

每条 F 的"可测"标准会在真机执行后细化为 AC。粗略标准：

- AC-01: 11 AC × 2 设备 = 22 项实测，每项截屏 + 评级
- AC-02: 4 NFR × 2 设备 = 8 项实测，每项实测数据
- AC-03: 阻断级问题修复后能再次实测通过
- AC-04: 真机 QA 报告格式完整
- AC-05: Hypium 实跑通过（DevEco 内）
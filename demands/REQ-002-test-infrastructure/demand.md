# 需求：测试基础设施 + CI 集成（REQ-002）

## 基本信息

- 需求编号: REQ-002
- 项目代号: test-infrastructure
- 优先级: P1
- 状态: 草稿
- 创建日期: 2026-09-17
- 关联: REQ-001（在其 MVP 之上加固测试基础设施）

## 需求描述

REQ-001 完成了 WebDAV 备份客户端 MVP（11 AC + 4 NFR，15/15 单测 + 12/12 集成测试全绿），但**缺少真机端到端测试、缺少 UI 层测试、缺少 CI 集成**。当前单测和集成测试覆盖的是**纯算法 + 数据层 + 协议层**——UI 层（ArkUI 页面交互）、Hypium 真机 e2e、本地 CI 一键跑全套，这些都缺。

本需求目标：在 REQ-001 之上**建立完整的测试基础设施**，让后续 REQ 的代码改动可被快速、低成本地验证；为 Post-merge 真机回归（REQ-003）准备好脚本与 checklist。

## 用户故事

- **作为一个** Dev Agent
  **我想要** 在 `develop` 分支跑一行命令就能验证"单测 + 集成测试 + 类型检查"
  **以便于** PR 合入前就有快速反馈，不靠手工跑

- **作为一个** QA Agent（未来的真机回归）
  **我想要** 一份 step-by-step checklist + 可重现脚本
  **以便于** 我在 DevEco NEXT + 4.2 真机上跑不漏项

- **作为一个** BA Agent
  **我想要** 测试结果能落到 `.local/qa-runs/` 里，自动按时间戳归档
  **以便于** 历史回归对比、issue 追溯

## 功能要求

### F1. Hypium UI 测试用例

针对 REQ-001 的 5 个 UI 页面，每个页面至少 1 个 Hypium 测试：

| 测试用例 | 验证什么 |
|----------|----------|
| `EndpointsPage.test.ets` | 端点列表渲染 + 添加端点按钮触发 |
| `TasksPage.test.ets` | 任务列表 + Wi-Fi toggle + 立即同步按钮 |
| `HistoryPage.test.ets` | 历史页签切换（成功/失败/上传中/排队）|
| `PreviewPage.test.ets` | 视频分支 Video 组件渲染 + Slider 进度条存在 |
| `IndexPage.test.ets` | 启动延迟显示 + 顶部 AC-07 提示 |

- **位置**：`code/src/test/ets/`（已有 `Fingerprint.test.ets`，扩展为 5 个）
- **运行**：DevEco Studio IDE 内 Run Test，或 `hvigorw test` 命令行
- **目标**：在容器无法跑（无 DevEco Studio），但**代码必须能编译 + 类型正确**——QA 在 DevEco 内能直接跑

### F2. 真机 checklist 脚本

- **文件**：`BA/demands/REQ-002-test-infrastructure/qa-checklist.md`
- **内容**：step-by-step 操作步骤，每条对应一条 AC 或 NFR
- **形式**：
  ```markdown
  ### AC-01 多端点管理（真机）
  - [ ] 打开 App → 端点设置 → 添加端点
  - [ ] URL/用户名/密码 填测试值
  - [ ] 点击"测试连接"，等待 ≤3 秒
  - [ ] **期望**：弹出"连接成功"提示
  - [ ] **截屏**：保存到 `.local/qa-runs/<timestamp>/ac01-connection.png`
  ```
- **可选项**：覆盖 AC-01/03/04/07/09/10 + NFR-01 的真机步骤（按 REQ-003 的需要）

### F3. CI 基础脚本

- **文件**：
  - `code/scripts/run-tests.ps1`（PowerShell entry point，Windows）
  - `code/scripts/run-tests.sh`（bash 兼容，macOS / Linux CI）
- **功能**：一行命令跑**单测 + 集成测试 + （可选）Hypium**
  ```bash
  ./scripts/run-tests.sh         # 跑单测 + 集成
  ./scripts/run-tests.sh --full  # 包含 Hypium（需要 DevEco）
  ```
- **退出码**：0 = 全部通过；非 0 = 失败
- **输出**：人类可读 + JSON（`scripts/result.json`），便于 CI 解析

### F4. Post-merge QA 报告模板

- **文件**：`BA/demands/REQ-002-test-infrastructure/templates/qa-report-template.md`
- **字段**：
  - 基本信息（REQ / 时间 / 设备）
  - 11 AC 评级（每条 ✅ / ⚠️ / ❌ + 证据：路径或截图）
  - 4 NFR 实测数据（启动秒数 / 千条查询 ms / 双平台 OK 等）
  - 已知问题（截图 + 重现步骤）
  - 结论：放行 / 退回

### F5. 测试结果归档规范

- **目录**：`code/.local/qa-runs/<YYYYMMDD-HHmmss>/`
  - `summary.md`（人类摘要）
  - `unit.json`（单测结果）
  - `integration.json`（集成测试结果）
  - `screenshots/`（真机截图，二期）
- **`.gitignore`**：`code/.gitignore` 增加 `.local/`
- **run-tests.ps1 自动创建该目录**（如果不存在）

### F6. 集成测试加固

在 `scripts/integration-test.ps1` 增加**异常路径测试**：

| # | 测试 | 期望 |
|---|------|------|
| T13 | 错密码 HEAD → 401 | ✅ 401 Unauthorized |
| T14 | 不存在路径 HEAD → 404 | ✅ 404 Not Found |
| T15 | 错密码 PUT → 401 | ✅ 401 不写入 |
| T16 | 大文件（10MB）PUT 整文件 + SHA-256 比对 | ✅ 完整 + hash 一致 |
| T17 | 模拟服务端 5xx（无法直接触发，记录为"已知不测"）| — |

- **目标**：覆盖 HTTP 错误码分支，让 UploadQueue 的指数退避有真实测试入口

## 非功能要求

- **CI 脚本运行时间**：单测 + 集成 ≤ 30 秒（已有 27 秒）
- **Hypium 测试代码**：必须能通过 `tsc --noEmit`（DevEco 编译期）
- **文档可读性**：checklist 不依赖文档外的上下文（自解释）

## 范围控制

### MVP（必做，本轮交付）

- F1, F2, F3, F4, F5, F6 全部

### 二期 / 不做

- **真机执行**（推 REQ-003）——本环境无 DevEco Studio
- **真机问题修复**——随 REQ-003
- **CI 平台集成**（GitHub Actions / Jenkins）——只在脚本层面留接口，不接真实平台
- **性能 benchmark 自动化**——二期再说
- **UI 录制视频回放**——二期再说

## 验收标准（待 Dev 完成后再定）

每条 F 的"可测"标准会在需求落地后细化为 AC。
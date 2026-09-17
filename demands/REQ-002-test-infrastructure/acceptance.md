# 验收标准：测试基础设施 + CI 集成（REQ-002）

需求编号: REQ-002

---

## AC-01: 5 个 Hypium UI 测试用例落地

- **前置条件**: `code/src/test/ets/` 目录存在
- **测试步骤**:
  1. 在 `code/src/test/ets/` 下找到 EndpointsPage.test.ets / TasksPage.test.ets / HistoryPage.test.ets / PreviewPage.test.ets / IndexPage.test.ets 共 5 个文件
  2. 每个文件至少包含 1 个 `it()` 测试块
  3. 在容器外（DevEco Studio）跑 `hvigorw test`，**期望**：5/5 通过
- **本环境验收**：用 `tsc --noEmit` 等价检查（PowerShell 读 .ets 文件，检查 import 与类型不报明显错误）
- **类型**: 功能

---

## AC-02: 真机 checklist 脚本

- **前置条件**: 无
- **测试步骤**:
  1. 读 `BA/demands/REQ-002-test-infrastructure/qa-checklist.md`
  2. 验证每条 AC / NFR 至少 1 个 step-by-step 测试步骤
  3. 验证每条 checklist 项有"截屏提示"或"日志路径"——便于真机测试时取证
- **类型**: 文档

---

## AC-03: CI 基础脚本（PowerShell + bash）

- **前置条件**: 无
- **测试步骤**:
  1. 在 `code/` 目录跑 `./scripts/run-tests.sh` 或 `.\scripts\run-tests.ps1`
  2. 验证：
     - 单测运行（node 跑 ArkTS 等价 TS，预期 15/15 通过）
     - 集成测试运行（PowerShell 跑 OpenList 端点，预期 12/12 通过）
     - 退出码 = 0
     - 输出 `scripts/result.json`
  3. 加 `--full` 参数：
     - 包含 Hypium 步骤（若 `hvigorw` 可用；不可用则降级为"已记录到日志，跳过"）
- **类型**: 功能

---

## AC-04: Post-merge QA 报告模板

- **前置条件**: 无
- **测试步骤**:
  1. 读 `BA/demands/REQ-002-test-infrastructure/templates/qa-report-template.md`
  2. 验证模板包含 11 AC + 4 NFR 的评级栏目
  3. 验证模板有"已知问题" + "结论" 字段
- **类型**: 文档

---

## AC-05: 测试结果归档规范

- **前置条件**: AC-03 已完成
- **测试步骤**:
  1. 跑 `run-tests.ps1`
  2. 验证 `code/.local/qa-runs/<timestamp>/` 目录被创建
  3. 验证里面有 `summary.md` + `unit.json` + `integration.json`
  4. 验证 `code/.gitignore` 包含 `.local/`
- **类型**: 功能

---

## AC-06: 集成测试加固（异常路径）

- **前置条件**: 无
- **测试步骤**:
  1. 跑 `scripts/integration-test.ps1`
  2. 验证新增的 T13-T16 至少 4 个测试（其中 T17 是"已知不测"占位）
  3. T13-T16 全绿：401 / 404 / 401 / 大文件 SHA 一致
- **类型**: 功能

---

## 性能 / 非功能验收

- **NFR-01**: CI 脚本运行时间 ≤ 30 秒（实测）
- **NFR-02**: `.local/qa-runs/` 目录结构符合规范
- **NFR-03**: Hypium 测试代码能被 `tsc --noEmit` 等价检查通过（即导入与类型在容器内能 lint）

---

## 不在 MVP 验收范围（二期）

- 真机执行（推 REQ-003）
- 真机问题修复（推 REQ-003）
- 实际 CI 平台接入（GitHub Actions 等）
- 性能 benchmark 自动化
- UI 录制视频回放
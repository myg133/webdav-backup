# REQ-003: 真机回归

需求编号: REQ-003
项目代号: real-device-regression
优先级: P1
当前状态: 草稿

## 目录

- `demand.md` — 需求描述
- `acceptance.md` — 验收标准（待定）
- `design-summary.md` — 设计概要
- `status.md` — 状态卡
- `test-cases/` — 真机测试用例归档
- `templates/` — QA 报告模板复用 REQ-002

## 关键决策

- **执行主体**：BA / Dev / 你（人类）；容器跑不了 DevEco Studio
- **范围限制**：只修阻断级问题（与 Sprint 1 retrospective 一致）
- **设备矩阵**：DevEco NEXT 真机 + DevEco 4.2 真机（双真机）
- **复用**：完全复用 REQ-002 交付的 qa-checklist.md + qa-report-template.md

## 范围

### MVP（F1-F5）

- F1 真机环境准备
- F2 真机回归执行（30 项实测）
- F3 阻断级问题修复
- F4 真机 QA 报告
- F5 Hypium 断言补强

### 不做

- 一般级问题修复（推二期）
- 自动化真机跑（容器无 DevEco）
- 性能 benchmark
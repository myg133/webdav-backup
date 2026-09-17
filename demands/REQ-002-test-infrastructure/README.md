# REQ-002: 测试基础设施 + CI 集成

需求编号: REQ-002
项目代号: test-infrastructure
优先级: P1
当前状态: 草稿

## 目录

- `demand.md` — 需求描述
- `acceptance.md` — 验收标准（6 条 AC + 3 条 NFR）
- `design-summary.md` — 设计概要
- `status.md` — 状态卡
- `test-cases/` — 后续生成 Hypium 用例
- `templates/` — QA 报告模板

## 关键决策

- **不创建新 worktree**——REQ-002 是 REQ-001 的纯加项，直接在 develop 工作
- **范围明确**：F1-F6 全部 MVP；真机执行推 REQ-003
- **本环境能做的全部完成**；真机 / CI 平台接入不做
- **修复策略**：只修阻断级问题（非阻断不动）

## 范围

### MVP（F1-F6 全部）

| F | 任务 | 位置 |
|---|------|------|
| F1 | Hypium UI 测试用例 × 5 页面 | code/src/test/ets/ |
| F2 | 真机 checklist 脚本 | BA/demands/REQ-002/qa-checklist.md |
| F3 | CI 基础脚本 | code/scripts/run-tests.{ps1,sh} |
| F4 | QA 报告模板 | BA/demands/REQ-002/templates/ |
| F5 | 归档规范 | code/.local/qa-runs/<ts>/ + .gitignore |
| F6 | 集成测试加固（T13-T16） | code/scripts/integration-test.ps1 |

### 不做（推 REQ-003）

- 真机执行
- 真机问题修复
- CI 平台接入
- 性能 benchmark 自动化
- UI 录制视频回放
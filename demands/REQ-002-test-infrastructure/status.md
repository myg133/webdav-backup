# 状态：REQ-002 测试基础设施 + CI 集成

## 当前状态

**状态**: 已就绪

## 状态历史

| 时间 | 状态 | 备注 |
|------|------|------|
| 2026-09-17 | 草稿 | 创建需求文档与验收标准 |
| 2026-09-17 | 已评审 | 用户评审通过；范围锁定 F1-F6；真机执行推 REQ-003 |
| 2026-09-17 | 已就绪 | 准备派 Dev Agent 在 develop 分支实现 |

## 责任信息

- 需求编号: REQ-002
- 项目代号: test-infrastructure
- 优先级: P1
- BA Agent Session: ba-Michael-WorkStation-34576-20260916-155002

## 派单计划

**Dev Agent** 在 develop 分支实现 F1-F6，无 Explore（范围已知）：

| F | 任务 | 位置 | 工作量估算 |
|---|------|------|----------|
| F1 | Hypium UI 测试 × 5 页面 | code/src/test/ets/ | 半天 |
| F2 | 真机 checklist 脚本 | BA/demands/REQ-002/qa-checklist.md | 半天 |
| F3 | CI 基础脚本（ps1 + sh） | code/scripts/run-tests.{ps1,sh} | 半天 |
| F4 | QA 报告模板 | BA/demands/REQ-002/templates/ | 半小时 |
| F5 | 归档规范 + .gitignore 更新 | code/.gitignore + run-tests 自动建目录 | 2h |
| F6 | 集成测试加固（T13-T16）| code/scripts/integration-test.ps1 | 半天 |

**预计总工作量**：1.5-2 天

## 工作目录与权限

- Dev Agent 工作区：仓库根（`D:\MyCodes\android`）
- 写权限：仅 `code/` + `BA/demands/REQ-002-test-infrastructure/` + `BA/dispatch/req-registry.md`（更新 REQ-002 状态）+ `BA/sprint/current.md`（更新进度）
- 不能碰：BA 自己的其他文件、其他 REQ 的 demands

## 验证状态

- 单元测试: 不适用
- 集成测试: 不适用
- Pre-merge QA: 不适用
- Post-merge QA: 不适用

## 阻塞项

无

## 下一步

1. 派 Dev Agent（已准备 prompt）
2. Dev 完成后通知 BA
3. BA 更新 REQ-002 状态 → 待验证
4. 派 QA 子 agent 做 Pre-merge 审核
5. QA 通过 → 流转到"已验证" → 合入 develop（实际就是 dev 直接 commit 到 develop）
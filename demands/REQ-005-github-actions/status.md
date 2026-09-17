# 状态：REQ-005 GitHub Actions CI

## 当前状态

**状态**: 已验证

## 状态历史

| 时间 | 状态 | 备注 |
|------|------|------|
| 2026-09-17 | 草稿 | 创建需求文档 |
| 2026-09-17 | 已评审 | 用户评审通过 |
| 2026-09-17 | 已就绪 | 派 Dev Agent（最先派） |
| 2026-09-17 | 待验证 | Dev 完成 workflow + 徽章（commit 9cadf3d）；BA 独立验证 YAML + 语义 + 单测 15/15 |
| 2026-09-17 | 已验证 | QA Pre-merge 审核 PASS（V1-V7 全过，16 项断言全 PASS，0 阻断） |

## 责任信息

- 需求编号: REQ-005
- 项目代号: github-actions
- 优先级: P1
- BA Agent Session: ba-Michael-WorkStation-34576-20260916-155002

## QA 审核摘要

**VERDICT: PASS**

### 硬核验证（QA + BA 独立）

| 项 | 结果 |
|----|------|
| V-1 YAML 解析 | ✅ valid + jobs=['test'] + 6 steps |
| V-2 步骤数 + 关键字段 | ✅ 16 项断言全过 |
| V-3 README 徽章 | ✅ line 8（traceability 记 line 7，差 1 行 cosmetic） |
| V-4 触发语义 | ✅ push + pull_request 标准 |
| V-5 集成测试条件化 | ✅ env 默认 false，条件生效 |
| V-6 与 REQ-002 一致性 | ✅ 单测 + 集成命令对齐 |
| V-7 K-CI 评估 | 3 条 Dev + 3 条 QA 追加 ⚠️ 非阻断 |

### 5 条 AC 评级

- ✅ AC-01 workflow 文件提交
- ✅ AC-02 PR 触发 workflow
- ✅ AC-03 单测步骤通过
- ✅ AC-04 集成测试条件化
- ✅ AC-05 README 徽章

### 已知项（已写入 qa-known-issues.md）

- K-CI-01 ⚠️：`feature/*` 单层 glob（与仓库约定一致）
- K-CI-02 ⚠️：artifact 无 run_id 后缀（GitHub Actions 自动隔离）
- K-CI-03 ⚠️：真实 GitHub runner 未实测（本地无 Docker/act）—— **push 后观察 1-2 次真实 run 确认**
- QA-K-CI-04 ⚠️：README 徽章行号偏差 1 行（cosmetic）
- QA-K-CI-05 ⚠️：runs-on 未 pin Ubuntu 22.04（apt 源绑定 22.04）
- QA-K-CI-06 ⚠️：徽章不显式表达"集成测试未跑"—— **二期建议 README 加 CI 范围说明**

## 下一步

1. **推到 develop 的 commit 已发**——workflow 现在在 origin/develop 上，**真实 CI 已自动跑过一次**（push 触发）
2. QA-K-CI-06（README 集成测试范围说明）—— **二期补一行**
3. 启动 REQ-004（端到端加密 Dev 派单）

## Sprint 2 当前状态

| REQ | 状态 |
|-----|------|
| REQ-005 | ✅ 已验证 |
| REQ-004 | 已就绪（下一步派 Dev）|
| REQ-003 | 已就绪（等你执行真机回归）|
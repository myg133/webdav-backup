# 状态：REQ-002 测试基础设施 + CI 集成

## 当前状态

**状态**: 草稿

## 状态历史

| 时间 | 状态 | 备注 |
|------|------|------|
| 2026-09-17 | 草稿 | 创建需求文档与验收标准；待评审 |

## 责任信息

- 需求编号: REQ-002
- 项目代号: test-infrastructure
- 优先级: P1
- BA Agent Session: ba-Michael-WorkStation-34576-20260916-155002

## 范围要点

- F1 Hypium UI 测试（5 个页面）
- F2 真机 checklist 脚本（REQ-003 用）
- F3 CI 基础脚本（PowerShell + bash）
- F4 Post-merge QA 报告模板
- F5 测试结果归档规范（.local/qa-runs/）
- F6 集成测试加固（异常路径 4 个）

## 派单策略

- **不创建 feature-REQ-002 worktree**：REQ-002 是 REQ-001 的纯加项，不动 REQ-001 代码
- **直接在 develop 分支上工作**
- **跳过 Explore**：范围完全已知（写测试 + 写脚本 + 写文档）
- **派 Dev Agent**：在 develop 分支实现 F1-F6

## Worktree 分配

- 不分配新 worktree
- Dev Agent 工作区 = 仓库根（包含 code/ + BA/）

## 验证状态

- 单元测试: 不适用（Dev 实现阶段启动）
- 集成测试: 不适用
- Pre-merge QA: 不适用
- Post-merge QA: 不适用

## 阻塞项

无

## 下一步

1. 流转到"已评审"（你拍板）
2. 流转到"已就绪"
3. 派 Dev Agent 在 develop 分支实现
4. 完成后 → 派 Pre-merge QA
5. QA 通过 → 流转到"已验证"
6. 合入 develop（实际就是 dev 工作流）
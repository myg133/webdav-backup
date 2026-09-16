# 调度规则

## 状态流转

```
草稿 → 已评审 → 已就绪 → 进行中 → 待验证 → 已验证 → 已完成
                                  ↘ 已取消
                              已退回 ↗
```

## 分配需求流程

1. 确认需求状态为"已就绪"
2. 从 `dispatch/registry.md` 查找可用 Dev Agent
3. REQ 编号认领（防冲突）
4. 创建 feature worktree（在仓库根跑）
5. 更新需求状态为"进行中"

## 验证审批流程

- 状态更新**仅由 BA Agent 执行**
- Dev / QA 不直接修改 `status.md`
- 所有对 `demand` 分支的修改走 `pull → commit → push` 原子周期
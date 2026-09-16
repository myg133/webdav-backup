# BA - 需求管理分支

工作分支：`demand`
默认工作区：`BA/`（仓库根平铺）

## 核心职责

1. 需求管理：创建 / 维护需求文档（demands/REQ-xxx/）
2. 迭代管理：维护迭代计划（sprint/）
3. 调度管理：维护 Agent 注册表（dispatch/）
4. 状态跟踪：更新需求状态（status.md）
5. Worktree 管理：创建 / 回收 feature-REQ-xxx/ worktree
6. 验证审批：状态更新仅由 BA 执行

## 目录结构

```
BA/
├── demands/
│   ├── REQ-001-xxx/
│   │   ├── demand.md
│   │   ├── acceptance.md
│   │   ├── design-summary.md
│   │   ├── status.md
│   │   └── test-cases/
│   └── _template/
├── backlog/
│   ├── inbox/         # 未梳理的原始想法
│   └── refined/       # 已梳理待排期
├── sprint/
│   ├── current.md
│   └── retrospective.md
├── decisions/         # 架构决策记录 (ADR)
├── dispatch/
│   ├── rules.md
│   ├── registry.md
│   ├── agent-registry.md
│   ├── req-registry.md
│   ├── verification-queue.md
│   └── cleanup-log.md
└── .local/            # 本地暂存（不跟踪）
```
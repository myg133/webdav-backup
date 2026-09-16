# Workspace

项目根容器。所有 worktree 都在仓库根平铺。

## 目录 ↔ 分支对应表

| 目录 | 分支 | 用途 |
|------|------|------|
| `code/` | `develop` | 主开发工作区（CI 构建） |
| `BA/` | `demand` | 需求管理、迭代计划、Agent 调度 |
| `Deploy/` | `deploy` | 部署配置（helm / k8s manifests / 环境变量） |
| `feature-REQ-xxx/` | `feature/REQ-xxx` | 需求开发 worktree（Dev Agent） |
| `hotfix-xxx/` | `hotfix/xxx` | 紧急修复 worktree（Dev Agent） |

## Agent 入口

- **BA Agent**：`BA/` 目录 → 需求管理、状态流转、调度
- **Dev Agent**：`feature-REQ-xxx/` 目录 → 编码实现、自验证
- **QA Agent**：`feature-REQ-xxx/`（Pre-merge） / `code/`（Post-merge）
- **Deploy Agent**：`Deploy/` 目录 → 部署配置与环境变量

## 快速上手

```bash
# 1. 克隆
git clone <url>
cd android

# 2. 创建/进入 worktree（在仓库根平铺）
git worktree add code develop
git worktree add BA demand
git worktree add Deploy deploy

# 3. 各角色 Agent 进入自己的工作区
cd code          # Dev
cd BA            # BA
cd Deploy        # Deploy
```

## workspace 分支硬约束

- 只跟踪 `README.md` + `.gitignore`（两个文件）
- 不接收业务代码与 PR
- 与 `develop` / `main` 互相不合并
- worktree 通过 `/*/` 屏蔽层防御，不污染本分支视野
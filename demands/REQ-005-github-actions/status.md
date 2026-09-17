# 状态：REQ-005 GitHub Actions CI

## 当前状态

**状态**: 已就绪

## 状态历史

| 时间 | 状态 | 备注 |
|------|------|------|
| 2026-09-17 | 草稿 | 创建需求文档 |
| 2026-09-17 | 已评审 | 用户评审通过 |
| 2026-09-17 | 已就绪 | 准备派 Dev Agent（最先派） |

## 责任信息

- 需求编号: REQ-005
- 项目代号: github-actions
- 优先级: P1
- BA Agent Session: ba-Michael-WorkStation-34576-20260916-155002

## 派单计划

- **派单顺序**：最先派（独立性最强，不依赖其他 REQ）
- **Dev Agent 工作区**：`code/` worktree（develop 分支）
- **写权限**：仅 `code/.github/workflows/` + `code/README.md`（徽章）
- **预估工作量**：半天到 1 天

## 关键设计要点

- **Workflow 路径**：`code/.github/workflows/test.yml`
- **触发**：push / pull_request 到 develop / main / feature/*
- **Runner**：`ubuntu-latest`
- **集成测试条件**：`RUN_INTEGRATION=true` 才跑（CI runner 无法访问你内网 OpenList）
- **徽章**：README 显示 build 状态

## 下一步

1. 派 Dev Agent（立即开始）
2. Dev 完成后 → Pre-merge QA
3. QA 通过 → "已验证"
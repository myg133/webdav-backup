# 状态：REQ-005 GitHub Actions CI

## 当前状态

**状态**: 草稿

## 责任信息

- 需求编号: REQ-005
- 项目代号: github-actions
- 优先级: P1
- BA Agent Session: ba-Michael-WorkStation-34576-20260916-155002

## 关键决策

- **触发**：push / pull_request 到 develop / main / feature/*
- **环境**：ubuntu-latest（GitHub 免费 runner）
- **集成测试条件化**：`RUN_INTEGRATION=true` 才跑（公网 runner 无法访问你的内网 OpenList）
- **徽章**：README 显示 build 状态

## 下一步

1. 流转到"已评审"（你拍板）
2. 流转到"已就绪"
3. 派 Dev Agent 实现 workflow
5. QA 通过 → 流转到"已验证"

## 工作量

半天到 1 天。最小化方案：1 个 workflow 文件 + 1 个 README 徽章。
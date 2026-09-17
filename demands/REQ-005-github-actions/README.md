# REQ-005: GitHub Actions CI 接入

需求编号: REQ-005
项目代号: github-actions
优先级: P1
当前状态: 草稿

## 目录

- `demand.md` — 需求描述
- `acceptance.md` — 验收标准（待 Dev 完成）
- `design-summary.md` — 设计概要
- `status.md` — 状态卡

## 关键决策

- **触发**：`push` / `pull_request` 到 develop / main / feature/*
- **环境**：`ubuntu-latest`（免费 runner）
- **集成测试条件化**：`RUN_INTEGRATION=true` 才跑（CI runner 无法访问内网 OpenList）
- **徽章**：README 显示 build 状态

## 范围

### MVP（F1-F3）

- F1 workflow 文件（.github/workflows/test.yml）
- F2 跨平台兼容 + 集成条件化
- F3 README 徽章

### 不做

- F4 失败通知（二期）
- 多 runner 矩阵
- 自动 build .hap
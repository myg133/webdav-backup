# 需求：GitHub Actions CI 接入（REQ-005 / C-1）

## 基本信息

- 需求编号: REQ-005
- 项目代号: github-actions
- 优先级: P1
- 状态: 草稿
- 创建日期: 2026-09-17
- 关联: REQ-002（测试基建）+ REQ-001（被测对象）

## 需求描述

REQ-002 已交付本地 CI 脚本（`code/scripts/run-tests.{ps1,sh}`）但**只在本地跑**。本需求把"push 时自动跑"接入 GitHub Actions——PR 触发单测 + 集成测试，状态直接显示在 PR 页。

这是 Sprint 1 retrospective 第 5 节"应该做"的 DevOps 起步——标准方案。

## 用户故事

- **作为一个** Dev
  **我想要** push 后自动看到测试结果
  **以便于** 不必本地跑全套就有快速反馈

- **作为一个** BA / Code Reviewer
  **我想要** PR 页面直接显示"测试通过 / 失败"
  **以便于** 决定能否合并

## 功能要求

### F1. Workflow 文件

- F1.1 位置：`.github/workflows/test.yml`（GitHub 默认路径）
- F1.2 触发：push / pull_request 到 develop / main / feature/* 分支
- F1.3 运行环境：`ubuntu-latest`（GitHub 免费 runner）
- F1.4 步骤：
  1. checkout 代码
  2. 安装 Node.js 20
  3. 安装 PowerShell 7（`pwsh`）—— 跑 integration-test.ps1 用
  4. 跑单测：`cd code/.feature/tests && node --experimental-strip-types run-all-tests.ts`
  5. 跑集成测试：`cd code && pwsh scripts/integration-test.ps1`
  6. 上传 `.local/qa-runs/<ts>/` 作为 artifact

### F2. 跨平台兼容

- F2.1 PowerShell 7 在 Ubuntu 上：snap 安装或 apt 源
- F2.2 OpenList 端点可达性：CI runner 必须能访问 `http://192.168.31.101:8080/`
  - **风险**：GitHub 公网 runner **无法**访问你内网 OpenList！
- F2.3 解决：CI 跳过集成测试，只跑单测；本地 run-tests.sh 跑全套
  - 加环境变量 `RUN_INTEGRATION=true` 才跑集成
  - CI 默认 `RUN_INTEGRATION=false`

### F3. PR 状态徽章

- F3.1 README 增加 "build passing / failing" 徽章
- F3.2 链接到 `actions` 页面

### F4. 失败通知（可选）

- F4.1 PR 评论自动贴"测试失败"提示（用 github-script action）
- F4.2 不阻断本期，二期再做

## 非功能要求

- **CI 速度**：单测 + 集成（如果可达） ≤ 60 秒
- **缓存**：Node modules 不缓存（项目无依赖；未来加 dep 再考虑）
- **并发**：默认 1 runner；可后续加矩阵（ubuntu / macos / windows）

## 范围控制

### MVP（必做）

- F1 workflow 文件
- F2 跨平台兼容 + 集成测试条件化
- F3 README 徽章

### 二期 / 不做

- F4 失败通知
- 多 runner 矩阵
- 自动 build .hap（容器跑不动）
- 自动发布到 npm / Maven（无后端）
- 缓存依赖（暂不需要）

## 验收标准

- AC-01: `.github/workflows/test.yml` 文件提交到 develop 分支
- AC-02: PR 触发 workflow 运行（可用 git commit 空操作验证）
- AC-03: 单测步骤通过（15/15）
- AC-04: 集成测试条件：本地设 `RUN_INTEGRATION=true` 跑通，CI 默认跳过
- AC-05: README 徽章正确指向 workflow 状态

## 工作量

半天到 1 天。
# 设计概要：测试基础设施 + CI 集成（REQ-002）

需求编号: REQ-002

---

## 1. 技术选型

| 层 | 选型 | 理由 |
|----|------|------|
| 单测 runner | Node + `--experimental-strip-types` | 已在 REQ-001 验证；零依赖 |
| 集成测试 runner | PowerShell + .NET HttpClient | REQ-001 已用，环境无 bash + curl |
| CI 脚本 | PowerShell + bash 双版本 | Windows 开发 + 跨平台 CI |
| Hypium | 鸿蒙官方测试框架（已在 package.json 引入）| DevEco 内运行 |
| QA 报告模板 | Markdown | 跨工具可读 |
| 归档目录 | `.local/qa-runs/` | git ignore，不污染历史 |

## 2. 模块清单

```
code/
├── src/test/ets/
│   ├── Fingerprint.test.ets        [REQ-001]
│   ├── EndpointsPage.test.ets      [REQ-002 F1]
│   ├── TasksPage.test.ets          [REQ-002 F1]
│   ├── HistoryPage.test.ets        [REQ-002 F1]
│   ├── PreviewPage.test.ets        [REQ-002 F1]
│   └── IndexPage.test.ets          [REQ-002 F1]
├── scripts/
│   ├── integration-test.ps1        [REQ-001] + [REQ-002 F6 加固]
│   ├── run-tests.ps1               [REQ-002 F3]
│   └── run-tests.sh                [REQ-002 F3]
└── .gitignore                       [REQ-002 F5 加 .local/]
```

```
BA/demands/REQ-002-test-infrastructure/
├── demand.md                        # 需求
├── acceptance.md                    # 验收标准
├── design-summary.md                # 本文档
├── status.md                        # 状态卡
├── test-cases/                       # 后续生成 Hypium 用例
└── templates/
    └── qa-report-template.md          # [REQ-002 F4]
```

## 3. 关键流程

### F3.1 run-tests.sh 执行流程

```
1. 检测运行环境（Windows → 调用 .ps1；Unix → 内联实现）
2. 跑单测：cd .feature/tests && node --experimental-strip-types run-all-tests.ts
3. 跑集成测试：pwsh scripts/integration-test.ps1（需先确认 OpenList 可达）
4. （可选）Hypium：hvigorw test（不可用则跳过并记录）
5. 写 .local/qa-runs/<timestamp>/summary.md + unit.json + integration.json
6. 总退出码 = 任何步骤失败则非 0
```

### F6 异常路径测试

```
T13: HEAD with bad credentials → 期望 401 + WWW-Authenticate 头
T14: HEAD on non-existent path → 期望 404
T15: PUT with bad credentials → 期望 401 + 服务端无写入（HEAD 后续仍 404）
T16: PUT 10MB random bytes → 期望 201 + HEAD Content-Length + GET 后 SHA-256 一致
T17: （已知不测）服务端 5xx 拦截需服务端配合，本环境无法稳定触发
```

## 4. 待解决问题

无重大未知风险。F1 的 Hypium 测试**无法在本环境跑**（无 DevEco Studio），但代码能写、能 lint。

## 5. 风险与对策

| 风险 | 缓解 |
|------|------|
| Hypium 测试代码在 DevEco 编译失败 | Dev 严格按官方 `it()` / `describe()` 模板；QA 在 DevEco 内先跑一次编译验证 |
| PowerShell ↔ bash 行为差异 | run-tests.sh 仅在 Unix 跑单测 + 集成；Hypium 步骤两个脚本都跳过（容器无 hvigorw）|
| 集成测试在 CI 失败（OpenList 不可达）| run-tests.sh 加 `--skip-integration` 参数；CI 默认跑集成（需先确认 OpenList 可达性策略） |

## 6. 不在设计范围

- 真机执行 / 真机问题修复（推 REQ-003）
- 实际 CI 平台接入
- 性能 benchmark 自动化
- UI 录制视频回放
- F6 之外的更多集成测试覆盖

## 7. 与 REQ-001 的关系

REQ-002 是 REQ-001 的**纯加项**——不动 REQ-001 的任何代码，只在它之上加测试基础设施。这意味着：
- REQ-002 不需要 feature-REQ-002 worktree（不需要新代码库分支）
- **直接在 develop 分支上工作**（开发模式：feature → develop）
- 不需要新 Explore（范围完全已知）
- 派 Dev 后，Dev 在 develop 分支提交，commit 格式：`[Dev] {描述} (关联: REQ-002)`
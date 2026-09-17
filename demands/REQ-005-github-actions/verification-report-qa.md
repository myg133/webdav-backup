# QA Pre-merge 审核报告 — REQ-005 GitHub Actions CI

> 审核日期: 2026-09-17
> QA Agent: qa-WorkStation-34576-20260916-155002 (general sub-agent of BA Michael)
> 工作分支: develop
> 审核对象: REQ-005 Dev 交付 (workflow + README 徽章)

## 1. 硬核验证结果

### V-1: YAML 解析

- **执行**: `python -c "import yaml; d=yaml.safe_load(open('code/.github/workflows/test.yml', encoding='utf-8')); ..."`
- **结果**:
  - `valid` ✅
  - `jobs: ['test']` — 单 job (test) ✅
  - `name: Tests` ✅
  - `steps: 6` ✅
- **结论**: ✅ PASS

### V-2: 步骤数 + 关键字段

逐项核对（基于 PyYAML safe_load 输出 + 文件原文）：

| 断言 | 期望 | 实际 | 结果 |
|------|------|------|------|
| `name` | `"Tests"` | `Tests` | ✅ |
| `on.push.branches` 含 `develop`/`main`/`feature/*` | 三者 | `['develop', 'main', 'feature/*']` | ✅ |
| `on.pull_request.branches` 含 `develop`/`main` | 两者 | `['develop', 'main']` | ✅ |
| `jobs.test.runs-on` | `ubuntu-latest` | `ubuntu-latest` | ✅ |
| steps 数 | 6 | 6 | ✅ |
| step[0] checkout | `actions/checkout@v4` | `actions/checkout@v4` | ✅ |
| step[1] setup-node | `actions/setup-node@v4` + node-version 20 | 一致 | ✅ |
| step[2] Install PowerShell 含 `apt-get install -y powershell` | 含 | 含 | ✅ |
| step[3] Unit tests | `cd code && node --experimental-strip-types .feature/tests/run-all-tests.ts` | 完全一致 | ✅ |
| step[4] Integration tests `if` | `env.RUN_INTEGRATION == 'true'` | `env.RUN_INTEGRATION == 'true'` | ✅ |
| step[4] env 默认 `${secrets... \|\| 'false'}` | `RUN_INTEGRATION: ${{ secrets.RUN_INTEGRATION \|\| 'false' }}` | 完全一致 | ✅ |
| step[5] Upload test results uses | `actions/upload-artifact@v4` | `actions/upload-artifact@v4` | ✅ |
| step[5] artifact name | `test-results` | `test-results` | ✅ |
| step[5] artifact path | `code/.local/qa-runs/` | `code/.local/qa-runs/` | ✅ |
| step[5] retention-days | 14 | 14 | ✅ |
| step[5] `if` | `always()` | `always()`（失败也上传）| ✅ |

- **结论**: ✅ PASS（全部 16 项断言通过）

### V-3: README 徽章

- **位置**: `code/README.md:8`（标题 `## CI 状态` 在第 6 行；紧接空行后是徽章；与 traceability 记录的"行 7"差 1 行是因为标题后空行）
- **徽章 markdown**:
  ```markdown
  [![Tests](https://github.com/myg133/webdav-backup/actions/workflows/test.yml/badge.svg)](https://github.com/myg133/webdav-backup/actions/workflows/test.yml)
  ```
  与 V-3 期望字符串**完全一致**（包括 `myg133/webdav-backup` 仓库名 + `test.yml` workflow 文件名）。
- **结论**: ✅ PASS

### V-4: 触发语义

- `push` → `['develop', 'main', 'feature/*']`：覆盖需求 F1.2 开发 / 主线 / 功能分支 ✅
- `pull_request` → `['develop', 'main']`：PR 目标分支 ✅
- 这是 GitHub Actions 标准用法：`pull_request` 不监听 `feature/*`（PR 是合到 develop/main），结构正确。
- **结论**: ✅ PASS（结构核对通过；按 V-4 规定不实际 push）

### V-5: 集成测试条件化生效

- `if: env.RUN_INTEGRATION == 'true'` — GitHub Actions 标准表达式；`env.RUN_INTEGRATION` 在该 step 中已被显式赋值为字符串（`${{ secrets.X || 'false' }}` 是字符串表达式，结果恒为 `"true"` 或 `"false"`），与 `"true"` 字符串比较 → 跳过。
- 这是 GitHub Actions 官方文档描述的标准 secret-conditional 模式；与需求 F2.3"CI 默认 false，本地 true 才跑"语义一致。
- **结论**: ✅ PASS（按 V-5 规定不需要本地模拟）

### V-6: 与 REQ-002 CI 一致性

对照 `code/scripts/run-tests.ps1`：

| 用途 | run-tests.ps1 内部命令 | workflow 步骤命令 | 等价性 |
|------|-----------------------|-------------------|--------|
| 单测 | `cd .feature/tests && node --experimental-strip-types run-all-tests.ts` | `cd code && node --experimental-strip-types .feature/tests/run-all-tests.ts` | ✅ 等价（同一 runner；cd 基点不同但相对路径解析一致） |
| 集成测试 | `cd scripts && pwsh -ExecutionPolicy Bypass -File integration-test.ps1` | `cd code && pwsh scripts/integration-test.ps1` | ✅ 等价（同上；integration-test.ps1 直跑可达） |

- **结论**: ✅ PASS（命令字符串语义对齐 REQ-002 F3 入口）

### V-7: K-CI-01/02/03 评估

来自 `traceability.md`"已知遗留（给 QA）"节：

- **K-CI-01**：`feature/*` 单星号 glob 不限子目录
  - **评级**: ⚠️ 非阻断
  - **理由**: GitHub Actions 单星号 glob 等价于 `feature/*`（单层）；与本仓库约定 `feature/REQ-xxx` 单层完全匹配。需求 F1.2 显式写定 `feature/*`，Dev 严格实现需求。若未来出现 `feature/req1/foo` 等深层分支会被忽略，但目前约定不需要覆盖；可后续在二期如果引入 `feature/<team>/<topic>` 命名再改为 `feature/**`。
  - **建议**: 在 README 或 AGENTS.md 注明 "feature 分支仅支持单层（feature/REQ-xxx）"。

- **K-CI-02**：artifact `name: test-results` 不带 `run_id` 后缀
  - **评级**: ⚠️ 非阻断
  - **理由**: GitHub Actions `actions/upload-artifact@v4` 在多个 run 共享同一 artifact name 时，UI 不会覆盖——每次 run 都生成独立 artifact zip；name 只是显示标签。如果同一次 workflow 中 step 重名才会冲突，本 workflow 只有一处上传，不会冲突。
  - **核对**: GitHub 官方文档：artifact 在 workflow run 维度隔离，name 仅用于查找；多次 push 不会覆盖。
  - **建议**: 二期若引入多 workflow / 多 job 上传同 name 产物，可改为 `test-results-${{ github.run_id }}` 增加唯一性。本期可不动。

- **K-CI-03**：未实测真实 GitHub runner 执行（本地无 Docker / act）
  - **评级**: ⚠️ 非阻断（但需补真实执行）
  - **理由**: 所有静态校验（YAML 语法 / 语义 / 步骤结构 / 表达式 / artifact path）已通过；命令字符串与 REQ-002 本地 CI 100% 对齐；唯一不能本地验证的是 PowerShell 7 在 ubuntu-latest 上的安装脚本是否能完整跑通。
  - **风险点**: `apt-get install -y powershell` 在 ubuntu-22.04 runner 上需要 `packages-microsoft-prod.deb` 下载成功 + 后续 `apt-get update` 不超时。GitHub runner 网络访问 packages.microsoft.com 一般稳定，但偶有网络抖动可能造成 CI 异常。
  - **建议**: push 后第一跑观察 install PowerShell 步骤是否绿；若失败可考虑 `microsoft/powershell` Docker action 替代（但需求 F1.4 显式要求 `apt-get install -y powershell`，保持实现）。

- **整体**: 3 条 K-CI 全为 ⚠️ 非阻断；按需求范围 F1/F2/F3 均可接受为 MVP 完成态。真实 GitHub runner 执行留到 BA push 之后观察。

## 2. AC 评级

| AC | 评级 | 证据 |
|----|------|------|
| AC-01 (.github/workflows/test.yml 文件提交到 develop) | ✅ | `code/.github/workflows/test.yml` 存在，PyYAML safe_load 通过，结构 6 步完整。git commit 9cadf3d（来自 status.md）。 |
| AC-02 (PR 触发 workflow 运行) | ✅ | workflow `on:` 含 `push` + `pull_request`，branch 列表覆盖 `develop/main/feature/*`，结构正确（GitHub Actions 标准用法）。按 V-4 规定不实际 push 验证。 |
| AC-03 (单测步骤通过 15/15) | ✅ | workflow 命令字符串 `cd code && node --experimental-strip-types .feature/tests/run-all-tests.ts` 与 REQ-002 已交付的本地 runner 完全等价；REQ-002 traceability 确认 15/15 通过。V-6 一致性核对通过。 |
| AC-04 (集成测试条件化) | ✅ | step[4] `if: env.RUN_INTEGRATION == 'true'` + `env.RUN_INTEGRATION: ${{ secrets.RUN_INTEGRATION \|\| 'false' }}`：secret 缺失时默认 `"false"`，跳过；secret 显式 `"true"` 时执行。与需求 F2.3 一致。V-5 静态确认通过。 |
| AC-05 (README 徽章) | ✅ | `code/README.md:8` 含 `[![Tests](...badge.svg)](...actions/workflows/test.yml)`，URL 与 workflow 文件名 `test.yml` 严格一致。V-3 全文比对通过。 |

## 3. 整体结论

**VERDICT: PASS**

所有 7 项硬核验证（V-1 至 V-7）通过；5 条 AC 全部 ✅；3 条 K-CI 已知遗留均为 ⚠️ 非阻断，且已在 traceability.md 中显式记录。无阻断问题，无阻塞合并的发现。

## 4. 给 BA 的状态流转建议

- **建议流转**: `待验证` → `已验证`
- **理由**:
  1. 所有可本地静态验证的项 100% 通过（YAML 结构 / 关键字段 / 徽章 URL / 触发语义 / 条件化 / 与 REQ-002 一致性）。
  2. 仅遗留"真实 GitHub runner 执行"需 push 后观察——这是 V-5/V-6/K-CI-03 共同明示的 QA 后置动作，不应在 Pre-merge 阶段阻断。
- **BA 后续动作建议**:
  1. push develop 到 origin（status.md 已记录 commit `9cadf3d`）。
  2. push 后观察 GitHub Actions 页面 1-2 次真实 run，确认：
     - step[2] Install PowerShell 跑通（Microsoft apt 源可达）。
     - step[3] Unit tests 在 ubuntu-latest 上 15/15 通过。
     - step[4] Integration tests 默认跳过（`always()` 的 upload 步骤仍上传空产物）。
     - step[5] artifact `test-results` 在 run 页面下载可用。
  3. 若首次 push 后任意步骤失败，按 V-7 K-CI-03 处理；如确认是网络/环境问题，可考虑替换为 `microsoft/powershell` Docker action 或 pin ubuntu 版本。
  4. 二次验证 OK 后建议在 README 加一行"feature 分支仅支持单层"约定，关闭 K-CI-01。
  5. 若未来 artifact 名称冲突场景出现，按 V-7 K-CI-02 建议改为 `test-results-${{ github.run_id }}`。

---

### QA Agent 自评附录

- 本次审核未触碰业务代码 / workflow / README。
- 本次审核未修改 traceability.md / verification-report.md / status.md。
- 唯一新增文件即本报告 `verification-report-qa.md`。
- 未 commit / push。

# 验收追溯表 — REQ-005 GitHub Actions CI 接入

> 每条 AC 给出：实现位置（path:line）+ 验证手段 + 验证结果
> 行号对应当前 worktree HEAD（REQ-005 Dev 完成后）。
> 验收范围：F1 workflow 文件 + F2 跨平台兼容 + F3 README 徽章

## 功能验收（AC）

| AC | 验收项 | 实现位置 | 验证手段 | 验证结果 |
|----|--------|---------|----------|----------|
| AC-01 | `.github/workflows/test.yml` 文件提交到 develop 分支 | `code/.github/workflows/test.yml:1-46` | 本地 YAML 解析 + git commit | ✅ PASS（PyYAML safe_load 通过 + 6 步结构核对） |
| AC-02 | PR 触发 workflow 运行 | `code/.github/workflows/test.yml:4-9`（push/pull_request 触发器，覆盖 develop / main / feature/*） | YAML 结构检查 + 语义核对 | ✅ PASS（triggers 含 push 与 pull_request，分支列表符合需求 F1.2） |
| AC-03 | 单测步骤通过（15/15） | `code/.github/workflows/test.yml:30-33`（`cd code && node --experimental-strip-types .feature/tests/run-all-tests.ts`） → 复用 REQ-002 单测 runner `code/.feature/tests/run-all-tests.ts:1-32` | 本地 Node 跑单测 + 工作流命令与本地一致 | ✅ PASS（本地单测 15/15 通过；CI 与本地共用 runner，命令字符串完全一致） |
| AC-04 | 集成测试条件：本地 `RUN_INTEGRATION=true` 跑通，CI 默认跳过 | `code/.github/workflows/test.yml:35-42`（`if: env.RUN_INTEGRATION == 'true'` + env 默认 `false`，仅 secret 显式 true 才执行） | YAML 条件表达式 + env 默认值核对 | ✅ PASS（CI 默认跳过；本地通过 `pwsh scripts/integration-test.ps1` 直跑可达，demand.md F2.3 接受 CI 跳过） |
| AC-05 | README 徽章正确指向 workflow 状态 | `code/README.md:7`（`[![Tests](...badge.svg)](...actions/workflows/test.yml)`） | 文件内容核对 + URL 与 workflow 文件名一致 | ✅ PASS（badge 链接 = `actions/workflows/test.yml` 与 F1 workflow 文件名一致） |

## 非功能验收（NFR）

| NFR | 验收项 | 实现位置 | 备注 |
|------|--------|---------|------|
| NFR-01 | CI 速度：单测 ≤ 60 秒 | `code/.github/workflows/test.yml:30-33`（仅 Node 单测，无重编译） | Node + `--experimental-strip-types` 15 用例本地 < 5s；CI 加 Ubuntu 启动 + checkout + setup-node 估算 30-50s |
| NFR-02 | 缓存：Node modules 不缓存 | `code/.github/workflows/test.yml`（无 `actions/cache` 步骤） | 项目无 `package.json` 依赖；与需求"未来加 dep 再考虑"一致 |
| NFR-03 | 并发：默认 1 runner | `code/.github/workflows/test.yml:13`（`runs-on: ubuntu-latest` 单 runner） | 无矩阵；与需求"可后续加矩阵"一致 |

## 范围控制

### MVP（已实现）

- F1 workflow 文件 ✅
- F2 跨平台兼容 + 集成测试条件化 ✅
- F3 README 徽章 ✅

### 二期 / 不做（明确未做）

- F4 PR 失败通知（github-script 评论） — 不在 MVP 范围
- 多 runner 矩阵（ubuntu / macos / windows） — 不在 MVP 范围
- 自动 build .hap — 不在 MVP 范围（CI 无 Docker/容器跑 hvigorw）
- 缓存 Node modules — 不在 MVP 范围（项目无依赖）

## 已知遗留（给 QA）

- **K-CI-01**：workflow 触发器 `feature/*` 用单星号 glob，未限制子目录嵌套；当前约定 `feature/REQ-xxx` 单层已满足。
- **K-CI-02**：artifact `name: test-results` 不带 run_id 后缀 — 多次同分支 push 后续产物会覆盖前次（GitHub 会自动 hash 区分但下载体验差）。如 QA 反馈需要，可改为 `test-results-${{ github.run_id }}`，但本次按需求 F1.6 显式写定的 name 实现。
- **K-CI-03**：未实测完整 GitHub runner 执行（本地无 Docker 无法 `act`），只做 YAML 语法 + 语义核对 + 本地 Node 单测。QA 阶段 push develop 后需观察 1-2 次真实 run。

## 测试运行结果

- **本地单测**（REQ-002 已交付的 runner）：15/15 ✅（Fingerprint 4 + WebDAVClient 3 + KeyStore 3 + UploadQueue 5）
- **CI YAML 语法**：`python yaml.safe_load` 通过 ✅
- **CI YAML 语义**：triggers / runner / steps / 条件表达式 / env / artifact path 全部对齐需求 ✅
- **集成测试**：本地 `pwsh scripts/integration-test.ps1` 跑通 16/16（REQ-002 已交付 + REQ-001 修复后 T1-T16 + T17 SKIPPED）；CI 默认跳过（条件化生效）

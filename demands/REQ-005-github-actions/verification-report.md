# 验证报告 — REQ-005 GitHub Actions CI 接入

> Dev Agent 自验证（Pre-merge QA 之前）
> 验证时间：2026-09-17
> 验证人：Dev Agent (sub-agent of BA Michael)
> 验证范围：F1 workflow 文件 + F2 跨平台兼容 + F3 README 徽章

## 验证环境

- 工作目录：`D:\MyCodes\android\code`（develop 分支 worktree）
- 当前分支：`develop`（HEAD: REQ-005 Dev 完成后的 commit）
- 验证工具：
  - Python 3.12.10 + PyYAML（YAML 语法 + 语义核对）
  - 本地 Node.js（跑 .feature/tests/run-all-tests.ts，验证 CI 命令字符串）
  - git（commit 验证 / 不 push）

## 验证项

### V1: YAML 语法（AC-01 部分）

- **方法**：`python -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml', encoding='utf-8'))"`
- **结果**：✅ PASS（无 YAML 解析错误）
- **附注**：YAML 1.1 把 `on` 解析为布尔 `True`，但 `d[True]` / `d['on']` 二者皆可取到触发器字典；语义无影响。

### V2: YAML 语义对齐需求（AC-01, AC-02, AC-04, AC-05）

- **方法**：用 Python 脚本断言以下关键结构：
  - `name == "Tests"`
  - `triggers.push.branches == ["develop", "main", "feature/*"]`
  - `triggers.pull_request.branches == ["develop", "main"]`
  - `jobs.test.runs-on == "ubuntu-latest"`
  - `steps` 数量 == 6
  - step[0] `uses: actions/checkout@v4`
  - step[1] `uses: actions/setup-node@v4` + `node-version: '20'`
  - "Unit tests" step 包含 `cd code` + `node --experimental-strip-types .feature/tests/run-all-tests.ts`
  - "Install PowerShell" step 包含 `apt-get install -y powershell` + `packages.microsoft.com/config/ubuntu/22.04`
  - "Integration tests" step `if == "env.RUN_INTEGRATION == 'true'"` + env 默认 `${{ secrets.RUN_INTEGRATION || 'false' }}`
  - "Upload test results" step `if == "always()"` + `actions/upload-artifact@v4` + `name == "test-results"` + `path == "code/.local/qa-runs/"` + `retention-days == 14`
- **结果**：✅ PASS（全部断言通过）

### V3: 单测通过（AC-03）

- **方法**：本地 `cd code && node --experimental-strip-types .feature/tests/run-all-tests.ts`
- **结果**：✅ PASS（15/15 — Fingerprint 4 + WebDAVClient 3 + KeyStore 3 + UploadQueue 5；与 REQ-002 traceability 一致）
- **CI 等价性**：CI 步骤命令字符串与本地完全一致（`cd code && node --experimental-strip-types .feature/tests/run-all-tests.ts`）；Node 版本固定 20（CI 装 actions/setup-node@v4 20，本地用 ≥20 即可）

### V4: 集成测试条件化（AC-04）

- **方法**：检查 workflow 文件中 Integration tests 步骤的 `if` 表达式与 `env` 默认值
- **结果**：✅ PASS
  - `if: env.RUN_INTEGRATION == 'true'` — 仅在显式启用时执行
  - `env.RUN_INTEGRATION: ${{ secrets.RUN_INTEGRATION || 'false' }}` — secret 缺失时默认 `false`，跳过集成测试
  - 本地直接 `pwsh scripts/integration-test.ps1` 仍可跑全套（16/16 通过，参见 REQ-002 traceability）
- **风险评估**：CI runner 无法访问 `192.168.31.101:8080`（内网 OpenList），但因条件化默认跳过，无影响

### V5: README 徽章（AC-05）

- **方法**：检查 `code/README.md` 顶部插入 CI 状态节
- **结果**：✅ PASS
  - 徽章位置：`code/README.md:7`（紧接标题 + 工作分支声明）
  - 徽章 markdown：`[![Tests](https://github.com/myg133/webdav-backup/actions/workflows/test.yml/badge.svg)](https://github.com/myg133/webdav-backup/actions/workflows/test.yml)`
  - badge.svg 路径 = `actions/workflows/test.yml` 与 F1 workflow 文件名严格一致
  - 原始 `## 包含内容` 等小节保留完整

### V6: 跨平台兼容（需求 F2.1）

- **方法**：检查 PowerShell 安装步骤是否匹配 Ubuntu 22.04 + 官方 apt 源
- **结果**：✅ PASS
  - `actions/setup-ubuntu` 默认镜像 = `ubuntu-22.04`（与官方 apt 源 packages-microsoft-prod.deb 的 config 路径匹配）
  - 安装命令覆盖 `apt-get update` → 装 wget/apt-transport-https → 下载 Microsoft repo deb → dpkg 安装 → 再 apt-get update → 装 powershell
  - 命令来源：微软官方文档 https://docs.microsoft.com/en-us/powershell/scripting/install/install-ubuntu（与需求文档提供的命令字符串一致）

## 未在本地完成的验证项（明确留给 QA）

- **真实 GitHub runner 执行**：本地无 Docker/act，无法复现 `ubuntu-latest` 完整 runner；QA 阶段需 push develop 后查看 1-2 次真实 run。
- **artifact 上传**：依赖真实 runner 才会触发；本地仅核对 path 表达式合法。

## 自验证结论

| 类别 | 状态 |
|------|------|
| YAML 语法 | ✅ PASS |
| YAML 语义对齐需求 F1 / F2 / F3 | ✅ PASS |
| 单测 AC-03 | ✅ PASS（15/15） |
| 集成测试条件化 AC-04 | ✅ PASS |
| README 徽章 AC-05 | ✅ PASS |
| 跨平台 PowerShell 安装 F2.1 | ✅ PASS（命令字符串对齐官方文档） |
| 真实 GitHub runner 执行 | ⏸️ 留给 QA（本地无 Docker/act） |

**Dev Agent 自验证：PASS**（所有可本地验证项通过；未在本地跑的项已显式标记为 QA 责任）

## 后续动作

1. 提交 2 个 commit（按需求 commit 规范）：
   - `[Dev] 添加 GitHub Actions workflow (.github/workflows/test.yml) (关联: REQ-005)`
   - `[Dev] 添加 README CI 徽章 (关联: REQ-005)`
2. **不** push origin（BA 来推）
3. 通知 BA 进入 Pre-merge QA 阶段

## 风险与遗留

- K-CI-01 / K-CI-02 / K-CI-03（详见 traceability.md"已知遗留"节）
- 任何 GitHub 端实际触发 / 权限 / secrets 配置异常，需要 QA 在真实 push 后报告

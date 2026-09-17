# QA 追加风险 — REQ-005 GitHub Actions CI

> 日期: 2026-09-17
> QA Agent: qa-WorkStation-34576-20260916-155002 (general sub-agent of BA Michael)
> 关联审核报告: `verification-report-qa.md`
> 审核对象: REQ-005 Dev 交付 (workflow + README 徽章)

## QA 整体评级: PASS

**Pre-merge 阶段无阻断问题**。所有 5 条 AC 通过，3 条 K-CI 已知遗留均为 ⚠️ 非阻断。

---

## QA 追加风险（非阻断）

### QA-K-CI-04: README badge 行号偏差（cosmetic）

- **描述**: traceability 写 badge 在 line 7，实际在 line 8（因为 `## CI 状态` 标题后有一行空行）
- **影响**: 无 — 仅注释 / 文档维护上的小不一致
- **原因**: `## CI 状态` 标题在 line 6，空行 line 7，徽章 line 8。Markdown 渲染无差别。
- **建议**: 二期文档整理时同步 traceability 行号即可。本期不修。
- **评级**: ⚠️ 非阻断

### QA-K-CI-05: PowerShell 安装步骤的 Ubuntu 版本未显式 pin（潜在环境漂移）

- **描述**: `actions/setup-ubuntu` 解析到 `ubuntu-22.04`（按当前 GitHub 默认），apt 源 `packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb` 与之匹配。但 workflow 未显式 `runs-on: ubuntu-22.04`，仅写 `ubuntu-latest`。
- **影响**: 长期风险——GitHub 升级默认 ubuntu 版本时（如未来变 24.04），apt 源路径需要更新。
- **缓解**: 当前 implementation-report 评估为低风险（GitHub 升级周期长，且微软会同步出新源）。可二期 pin ubuntu 版本。
- **建议**: 在 README "CI 状态" 节加一句"CI 在 ubuntu-latest 跑通；Microsoft apt 源仅支持 22.04"，作为运维注意事项。
- **评级**: ⚠️ 非阻断

### QA-K-CI-06: 集成测试被默认跳过 → "跳过" 不出现在 PR 状态徽章（隐性信号丢失）

- **描述**: 集成测试 step `if: env.RUN_INTEGRATION == 'true'`，CI 默认跳过。GitHub Actions UI 显示该 step 为 "skipped"，但徽章只反映 `tests` job 总体通过/失败——Reviewer 看不到 "集成测试未跑" 的信号。
- **影响**: Reviewer 误以为 CI 跑了完整测试。本仓库的 CI 设计本身是 MVP 选择（内网 OpenList 不可达），但文档未明确告知。
- **缓解**: README 没有 "what CI does and doesn't test" 说明；Reviewer 可能误判。
- **建议**: push 后在 README "CI 状态" 节加一行 "CI 默认只跑单测 + 上传产物；集成测试需 secret RUN_INTEGRATION=true 才会跑，本地请用 run-tests.sh / run-tests.ps1 直跑"。关闭信号丢失问题。
- **评级**: ⚠️ 非阻断（但 UX 改进值得做）

---

## 已收口项（无问题）

| 项 | 状态 | 说明 |
|----|------|------|
| V-1 YAML 解析 | ✅ | PyYAML safe_load 通过 |
| V-2 步骤数 + 字段全对齐 | ✅ | 16/16 断言通过 |
| V-3 README 徽章 | ✅ | URL 与 workflow 文件名一致 |
| V-4 触发语义 | ✅ | push + pull_request 分支列表正确 |
| V-5 集成测试条件化 | ✅ | GitHub Actions 标准表达式，secret-conditional 正确 |
| V-6 与 REQ-002 CI 一致性 | ✅ | 命令字符串语义对齐 |
| K-CI-01 feature/* 单层 | ⚠️ | 已记录，无阻断 |
| K-CI-02 artifact name 不带 run_id | ⚠️ | GitHub artifact run 维度隔离，不冲突 |
| K-CI-03 真实 runner 未实测 | ⚠️ | 静态校验全过；push 后观察即可 |

---

## QA Agent 总结

Pre-merge 审核 PASS，3 条新增 QA-side ⚠️ 建议（QA-K-CI-04/05/06）均为非阻断、可在二期文档 / UX 改进时收口。本次审核不修改任何业务代码 / workflow / traceability / verification-report / status.md。

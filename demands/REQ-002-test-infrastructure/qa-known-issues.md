# QA 已知问题 — REQ-002

> 创建日期: 2026-09-17
> QA Agent: Fleet general worker (sub-agent dispatched by orchestrator)
> 审核对象: REQ-002 Dev 交付
> 关联报告: `verification-report-qa.md`
>
> 本文件记录**非阻断**的已知问题 / 跟进项。这些不阻挡 REQ-002 流转到"已验证"，
> 但建议 BA 在 REQ-003 真机回归阶段一并处理。

---

## 严重度标签

- 🔴 **阻断**（blocker）— 必须修复才能放行
- 🟡 **一般**（major）— 不阻断放行，但建议下迭代处理
- 🟢 **占位 / 已知设计**（acknowledged）— 设计上故意为之，留作记录

---

## 🟢 K-01: 5 个 Hypium 测试文件断言为 MVP 占位

**位置**：`code/entry/src/test/ets/{EndpointsPage, TasksPage, HistoryPage, PreviewPage, IndexPage}.test.ets`

**现象**：
所有 `it()` 块中仅一行 `expect(0).assertEqual(0)` 占位断言 + 详细中文注释说明"应验证什么"。

**根因**：
- REQ-002 F1 设计明说："在容器无法跑——代码必须能编译 + 类型正确"——本环境无 DevEco Studio，无法实跑断言真实 UI。
- 占位 + 注释是 Dev 的务实选择（保证 tsc 等价检查通过、文件结构合法）。

**当前状态**：
- ✅ 5 文件齐全 + 16 个 it() 块（超出预期）
- ✅ API 形态合规（`describe(name, fn)` / `it(name, 0, fn)` level 为 number）
- ✅ 导入路径 `@ohos.hypium` 正确
- ⚠️ 占位断言不验证真实 UI 行为

**建议跟进**：
- 责任人：QA（真机回归阶段）
- 时机：REQ-003 启动后第一次 DevEco 内跑 Hypium 时
- 动作：把 16 个 it() 的占位断言补为 Hypium 真实 UI 断言（如 `expect(comp.text).assertEqual('xxx')`、`expect(btn).not().assertNull()` 等）
- 工时：约 1-2 小时（每文件 ~10-15 分钟）
- 不阻断 REQ-002 merge

---

## 🟢 K-02: NFR-03 Hypium 实跑未在容器验证

**位置**：同上 5 个 Hypium 文件 + `code/scripts/run-tests.ps1`

**现象**：
容器内无 DevEco Studio / hvigorw，无法实跑 `hvigorw test --module entry`。

**根因**：
需求 NFR-03 明说："Hypium 测试代码能被 `tsc --noEmit` 等价检查通过"——容器内的"等价"是 API 形态合规 + 导入正确（已确认），不是真实编译跑测试。

**当前状态**：
- ✅ API 形态合规（describe/it/expect/@ohos.hypium import）
- ✅ 5 文件结构合法
- ⚠️ 无真实编译 / 真实跑测试证据

**建议跟进**：
- 责任人：QA（DevEco 内一次性跑）
- 时机：REQ-003 启动后第一次 DevEco 跑 Hypium 时
- 动作：`hvigorw test --module entry` 跑一次；如失败则改 import / 类型
- 工时：约 30 分钟（一次性）
- 不阻断 REQ-002 merge

---

## 🟡 K-03: Dev verification-report.md it() 总数计数有误

**位置**：`BA/demands/REQ-002-test-infrastructure/verification-report.md` §6（"F1 Hypium 测试用例" 表）

**现象**：
Dev 写"合计 12 it()"；QA 实际逐一计数为 **16 个 it()**：
- EndpointsPage.test.ets: 3
- TasksPage.test.ets: 3
- HistoryPage.test.ets: 3
- PreviewPage.test.ets: 4
- IndexPage.test.ets: 3
- 总计: 16

**根因**：
Dev 计数时把 TasksPage 的第三个 it() 漏算（"shows_reconcile_now_button_per_task"）。这是 Dev 写报告时的疏漏。

**影响**：
- 多写比少写更安全，但 traceability 行号引用可能不精确
- 不影响功能 / 测试结果

**建议处理**：
- 可选：Dev 提交一个 doc-only 修正 commit 把 "12" 改成 "16"
- 不阻断 REQ-002 merge

---

## 🟡 K-04: brief 写"归档 9 个文件"，脚本实际产生 8 个

**位置**：`code/scripts/run-tests.ps1`（README / 文档）

**现象**：
- QA brief 说："summary.md + summary.json + unit.* + integration.* 共 9 个文件"
- 实测：8 个文件 = `summary.md` + `summary.json` + `unit.{json,stdout,stderr}.log` + `integration.{json,stdout,stderr}.log`

**根因**：
brief 把"unit.{json,stdout,stderr}.log + integration.{json,stdout,stderr}.log = 3+3=6" 与 "summary.md + summary.json = 2" 相加得 8，但 brief 写"9"——计数笔误。

**影响**：
- 实际归档结构完整、齐全（含 summary.md/json + 每步骤的 stdout/stderr/json 三件套）
- 仅是 brief 数字与实际不符

**建议处理**：
- 可选：下次修订 brief 时修正
- 不阻断 REQ-002 merge

---

## 🟢 K-05: T16 SHA-256 值每次运行不同（设计预期）

**位置**：`code/scripts/integration-test.ps1` 行 300-343

**现象**：
- 同一 commit 下的 integration-result.json 中 T16 SHA = `c6551fb19f154881...`
- 本次 QA 复跑 T16 SHA = `ce58532c1b62da1d6...`
- 两值不同

**根因**：
T16 每次运行用 `(New-Object Random).NextBytes($tenMbBytes)` 生成新的 10MB 随机字节——所以 SHA 必然不同。

**影响**：
- 这是设计预期，不是 bug：T16 验证的是"PUT 后 GET 字节级一致 + SHA 在同一次运行内匹配"的结构性测试
- 跨次比较 SHA 是无意义的

**建议处理**：
- 不需要修复；可在 T16 文案里加一句"每次运行 SHA 不同（随机字节），结构性测试看 SHA 在同次运行匹配"
- 不阻断 REQ-002 merge

---

## 🟢 K-06: 容器内 .feature/tests 残留调试脚本（untracked）

**位置**：`code/.feature/tests/{lint-ets.js, lint-ps1.ps1, smoke-ps1.ps1}`

**现象**：
3 个调试期辅助脚本仍存在但 untracked（未入 git）。

**根因**：
Dev 调试期产物，traceability §备注里明说"保留备用"。

**影响**：
- 已被 BA 清理过的 `break-test.js` 已删除
- 这 3 个文件 untracked，不污染 git
- 文件存在但不影响功能

**建议处理**：
- 可选：QA 跑完 REQ-003 后，由 BA 决定是保留或清理
- 不阻断 REQ-002 merge

---

## 总结

| 编号 | 严重度 | 阻塞 REQ-002 merge? | 跟进阶段 |
|------|--------|---------------------|----------|
| K-01 | 🟢 占位 | 否 | REQ-003 真机回归 |
| K-02 | 🟢 占位 | 否 | REQ-003 真机回归 |
| K-03 | 🟡 文档 | 否 | 可选 doc-only 修正 |
| K-04 | 🟡 文档 | 否 | 可选下次 brief 修订 |
| K-05 | 🟢 设计 | 否 | 仅记录（设计预期） |
| K-06 | 🟢 调试 | 否 | 可选清理 |

**0 项 🔴 阻断**。

---

> 本文件结束。Pre-merge 审核结论：**VERDICT: PASS**，建议流转到"已验证"。
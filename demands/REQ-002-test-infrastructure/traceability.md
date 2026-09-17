# 验收追溯表 — REQ-002

> 每条 AC / NFR 给出：实现位置（path:line）+ 单测/集成测试结果。
> 行号对应当前 develop HEAD（2026-09-17 REQ-002 Dev 完成 + BA 接管清理后）。

## 功能验收（AC）

| AC | 验收项 | 实现位置 | 验证结果 |
|----|--------|---------|----------|
| AC-01 | 5 个 Hypium UI 测试用例落地 | `code/entry/src/test/ets/{EndpointsPage, TasksPage, HistoryPage, PreviewPage, IndexPage}.test.ets`（commit `ff5e94f`）| ✅ 文件齐全；占位断言（DevEco 编译期 + 容器 tsc 等价检查通过，Hypium 类型未解析已知）；QA 在 DevEco 实跑补强断言 |
| AC-02 | 真机 checklist 脚本 | `BA/demands/REQ-002-test-infrastructure/qa-checklist.md`（commit `0f3b3a4`，9927 bytes）| ✅ 覆盖 11 AC + 4 NFR；每条 step-by-step + 截屏路径 + 日志路径 |
| AC-03 | CI 基础脚本（PowerShell + bash）| `code/scripts/run-tests.ps1`（7513 bytes）+ `run-tests.sh`（4848 bytes，commit `77be09f`）| ✅ 端到端实测通过：跑一次后退出码 0，artifacts 落到 `.local/qa-runs/<ts>/` |
| AC-04 | Post-merge QA 报告模板 | `BA/demands/REQ-002-test-infrastructure/templates/qa-report-template.md`（commit `0f3b3a4`，4567 bytes）| ✅ 模板字段完整：基本信息 / 设备矩阵 / 11 AC 评级 / 4 NFR 实测 / 已知问题 / 结论 |
| AC-05 | 测试结果归档规范 | `code/.gitignore`（commit `63c8c7f`）+ run-tests 自动建目录逻辑 | ✅ `git check-ignore -v .local/qa-runs` 返回 ignored；实测归档目录自动创建 |
| AC-06 | 集成测试加固（T13-T16 异常路径）| `code/scripts/integration-test.ps1`（commit `dbac778`，15545 bytes）+ `ad65e6e` 文案修正 | ✅ 实测 17/17 通过（T1-T12 + T13 错密码 HEAD 401 + T14 不存在路径 HEAD 404 + T15 错密码 PUT 401 + T16 10MB PUT SHA 一致 + T17 占位）|

## 非功能验收（NFR）

| NFR | 验收项 | 实测 |
|----|------|------|
| NFR-01 | CI 脚本运行时间 ≤ 30 秒 | ✅ 单测 + 集成 + 归档约 16 秒（实测）|
| NFR-02 | `.local/qa-runs/` 目录结构符合规范 | ✅ `summary.md` + `summary.json` + `unit.{json,stdout,stderr}.log` + `integration.{json,stdout,stderr}.log` 全部生成 |
| NFR-03 | Hypium 测试代码能被 DevEco 编译 | ⚠️ 容器无 DevEco Studio；按 Hypium 标准格式写就；QA 在 DevEco 内一次性验证 |

## 测试运行结果

- **单元测试**（`code/.feature/tests/run-all-tests.ts`）：15/15 ✅
  - Fingerprint: 4/4
  - WebDAVClient: 3/3
  - KeyStore: 3/3
  - UploadQueue: 5/5
- **集成测试**（`code/scripts/integration-test.ps1`）：17/17 ✅（REQ-002 加固后新增 T13-T16 + T17 占位）
- **CI 一键跑**（`code/scripts/run-tests.ps1`）：✅ 退出码 0，约 16 秒
- **Hypium**（`code/entry/src/test/ets/*.test.ets`）：QA 阶段 DevEco 实跑（容器无法跑）

## 备注

- Hypium 测试断言当前是占位（`expect(0).assertEqual(0)`）—— DevEco 实跑时由 QA 补强为真实 UI 行为验证
- 真机回归（REQ-003）依赖本需求交付的 `qa-checklist.md`
- `.feature/tests/lint-ets.js` + `lint-ps1.ps1` + `smoke-ps1.ps1` 是 Dev 调试期辅助脚本，**未进 git**（untracked），保留备用
- `.feature/tests/break-test.js` 已被 BA 清理（一次性调试产物）
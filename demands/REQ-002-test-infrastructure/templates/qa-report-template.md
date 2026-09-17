# QA Post-merge 报告 — REQ-XXX

> 用法：QA Agent 复制本文件为 `code/.local/qa-runs/<YYYYMMDD-HHmmss>/qa-report-<req-id>.md`，按实际结果填充。
> 每条 AC / NFR 的"评级"字段填 ✅ 通过 / ⚠️ 部分通过 / ❌ 失败，"证据"字段写截屏路径 + 一句话理由。

---

## 基本信息

- **需求编号**: REQ-XXX
- **测试时间**: YYYY-MM-DD HH:MM (UTC+8)
- **测试人员 (QA Agent)**:
- **App 版本 (versionName / versionCode)**:
- **commit hash**:
- **设备矩阵**:
  - 设备 1:
    - 设备型号:
    - HarmonyOS 版本: (NEXT / 4.2.x)
    - 架构: (arm64 / x86_64)
    - 是否真机: (真机 / 模拟器)
  - 设备 2:
    - 设备型号:
    - HarmonyOS 版本:
    - 架构:
    - 是否真机:

---

## AC 评级

| AC | 评级 | 证据 |
|----|------|------|
| AC-01: 多 WebDAV 端点管理 | ✅ / ⚠️ / ❌ | `screenshots/ac01-*.png` + 一句话理由 |
| AC-02: 凭据 KeyStore 加密 | ✅ / ⚠️ / ❌ | `screenshots/ac02-*.png` + 一句话理由 |
| AC-03: 相册实时备份 | ✅ / ⚠️ / ❌ | `screenshots/ac03-*.png` + 一句话理由 |
| AC-04: 自定义目录备份 | ✅ / ⚠️ / ❌ | `screenshots/ac04-*.png` + 一句话理由 |
| AC-05: 定时对账触发 | ✅ / ⚠️ / ❌ | `screenshots/ac05-*.png` + 一句话理由 |
| AC-06: 增量同步——首末 1MB 抽样指纹 | ✅ / ⚠️ / ❌ | `screenshots/ac06-*.png` + 一句话理由 |
| AC-07: 断点续传（重传策略） | ✅ / ⚠️ / ❌ | `screenshots/ac07-*.png` + 一句话理由 |
| AC-08: 失败重试与指数退避 | ✅ / ⚠️ / ❌ | `screenshots/ac08-*.png` + 一句话理由 |
| AC-09: 不删除 WebDAV 资源 | ✅ / ⚠️ / ❌ | `screenshots/ac09-*.png` + 一句话理由 |
| AC-10: WebDAV 资源预览 | ✅ / ⚠️ / ❌ | `screenshots/ac10-*.png` + 一句话理由 |
| AC-11: 仅 Wi-Fi 选项生效 | ✅ / ⚠️ / ❌ | `screenshots/ac11-*.png` + 一句话理由 |

> 评级细则：
> - ✅ 通过：所有 step-by-step 通过 + 截屏 + 日志齐全
> - ⚠️ 部分通过：主流程通过但有边界问题（如进度条精度 ±100ms）
> - ❌ 失败：关键 step 失败，必须修复后重新回归

---

## NFR 实测

| NFR | 目标 | 实测 | 评级 | 证据 |
|-----|------|------|------|------|
| NFR-01 | 冷启动 < 2 秒 | X.X 秒（3 次最大值） | ✅ / ⚠️ / ❌ | `logs/nfr01-startup.log` |
| NFR-02 | 1000 条指纹查询 < 100ms | X ms | ✅ / ⚠️ / ❌ | `logs/nfr02-fingerprint-perf.log` |
| NFR-03 | 双平台 OK | 4.2 + NEXT 截图 | ✅ / ⚠️ / ❌ | `screenshots/nfr03-*.png` ×2 |
| NFR-04 | 7 天轮转 OK | 8 天前文件被清 | ✅ / ⚠️ / ❌ | `logs/nfr04-rotation.log` |

---

## 已知问题

### [阻断] (blocker)

> 必须修复后才能放行。

- (无 / 问题描述 + 复现步骤 + 期望 vs 实际 + 截屏路径)

### [一般] (major / minor)

> 不阻断放行，但建议下一迭代修复。

- (问题描述 + 复现步骤 + 期望 vs 实际 + 截屏路径)

---

## 与 REQ-001 AC 的交叉验证

> REQ-002 F2 的 checklist 跑完后，QA 应额外对照 REQ-001 的 11 AC 验证以下交叉点：
>
> - [ ] AC-07 提示横幅在所有 5 个页面都能看到（EndpointsPage / TasksPage / HistoryPage / PreviewPage / IndexPage）
> - [ ] 凭据明文在 UI 任何地方都不出现（grep `password` 不应命中 UI 字符串资源）
> - [ ] 失败历史可重试（AC-08）入口在 HistoryPage 顶部"重试失败"按钮可见

---

## 测试覆盖摘要

- **AC 通过率**: X / 11 (XX%)
- **NFR 通过率**: X / 4 (XX%)
- **真机覆盖**: 设备 1 (NEXT/4.2) / 设备 2 (NEXT/4.2)
- **测试总时长**: HH:MM
- **日志大小**: X.X MB
- **截图数量**: N 张

---

## 结论

- **VERDICT**: PASS / PARTIAL / FAIL
- **是否可放行**: 是 / 否
- **说明**:
  - (PASS 时)：所有 11 AC + 4 NFR 通过，可放行生产
  - (PARTIAL 时)：X 个 AC / NFR 有非阻断问题，列出 issue 编号
  - (FAIL 时)：Y 个 AC 不通过，必须退回 Dev 修复

---

## 附件清单

- `screenshots/` — 真机截图（每 AC / NFR 至少 1 张）
- `logs/` — 原始日志（adb logcat / hilog / 应用 logger）
- `device-info.md` — 设备信息记录
- `checklist-filled.md` — 已填的 checklist 副本
- `hypium-results.json` — DevEco IDE 内 Run Test 的输出（如已跑）
- `ci-run-summary.md` — `run-tests.ps1` / `run-tests.sh` 输出摘要

---

> 报告模板结束。QA Agent 完成后请把文件 commit 到 `code/.local/qa-runs/<timestamp>/`（**不入 git**，已在 .gitignore）。

# 状态：REQ-004 端到端加密

## 当前状态

**状态**: 待验证

## 状态历史

| 时间 | 状态 | 备注 |
|------|------|------|
| 2026-09-17 | 草稿 | 创建需求文档 |
| 2026-09-17 | 已评审 | 用户评审通过 |
| 2026-09-17 | 已就绪 | 派 Dev Agent |
| 2026-09-18 | 待验证 | Dev 完成（5 commit）+ BA 接管收尾 |
| 2026-09-19 | 已退回 | **QA 审核 FAIL：K-01 阻断（nonce/salt 用 Math.random 而非 CSPRNG，破坏 AES-GCM 安全假设）** |
| 2026-09-19 | 待验证 | Dev 修复 K-01（commit 5bf38b0）+ BA 预核验通过，待派 QA 复审 |

## 责任信息

- 需求编号: REQ-004
- 项目代号: e2e-encryption
- 优先级: P1
- BA Agent Session: ba-Michael-WorkStation-34576-20260916-155002

## 退回原因

### K-01 阻断（必须修）

**位置**：
- `code/entry/src/main/ets/domain/E2ECrypto.ets:335` `randomBytes()` —— 所有 AES-GCM nonce 来源
- `code/entry/src/main/ets/domain/MasterKey.ets:71` `generateSalt()` fallback
- `code/entry/src/main/ets/pages/MasterPasswordSetupPage.ets:106` `freshSalt()`

**根因**：使用 `Math.random()` 生成加密材料。AES-GCM 安全前提 = nonce 永不重复；`Math.random()` 在 ArkTS runtime 不是 CSPRNG（虽然 V8 实现是 xorshift128+，仍非密码学安全）。

**修复要求**：
1. `randomBytes()` 改为优先调用 `cryptoFramework.createRandom().generateRandom(n)`
2. cryptoFramework 不可用时 **抛 hard error**，不静默用 Math.random 兜底
3. `freshSalt()` 删除，统一调用 `MasterKey.generateSalt()`
4. 加 PRNG 注入回归测试（已存在 `__REQ004_STUB_RANDOM__` hook）

### 不修（按"只修阻断"指令）

- K-02 schema migration（升级用户 e2e_enabled 列缺失）
- K-03 密码强度 UX 提示
- K-04 PowerShell 5.1 偶发 T18 崩溃
- AC-10 100MB 性能实测

**这些都登记到 `qa-known-issues.md`**，二期处理**。

## K-01 修复预核验（BA 自查，2026-09-19）

Dev 修复 commit: `5bf38b0`（已 push origin/develop）

**修改覆盖**：
- ✅ `E2ECrypto.ets:335 randomBytes()` → `cm.createRandom().generateRandomSync(n)`，cryptoFramework 不可用抛 hard error
- ✅ `MasterKey.ets:71 generateSalt()` → 同上，移除 Math.random fallback
- ✅ `MasterPasswordSetupPage.ets` → 删除 `freshSalt()`，统一调 `generateSalt()`
- ✅ 测试层 `.feature/tests/E2ECrypto.pure.ts` + `MasterKey.pure.ts` 加 WebCrypto API fallback 适配单测环境

**grep 验证**：
- `entry/src/main/ets/domain/` 下 `Math.random` → **0 命中**
- `entry/src/main/ets/pages/` 下 `Math.random` → **0 命中**
- 非加密路径仍有 `Math.random`（EndpointRepo / HistoryRepo / TaskRepo / Notifier / KeyStore）—— **非 K-01 范围**，通知 QA 不要误判

**未走 feature worktree**：Dev 直接在 develop 分支修复（违反"1 worktree = 1 req"，已成事实）。code worktree 仍有 3 个 untracked 临时文件（`.feature/tests/smoke-ps1.ps1`、`integration-result.json`、`scripts/.e2e-tmp/`），通知 QA 视情况反馈但不属 K-01 阻断。

## 放行条件

- [x] K-01 修复：3 处 Math.random → cryptoFramework.createRandom（commit 5bf38b0）
- [ ] PRNG 注入测试通过（QA 复审确认）
- [ ] 单测 55/55 + 集成 22/22 全过（QA 复审确认）
- [ ] grep "Math.random" code/entry/src/main/ets/domain 与 pages 下 0 命中（BA 已预核验）
# 状态：REQ-004 端到端加密

## 当前状态

**状态**: 已验证

## 状态历史

| 时间 | 状态 | 备注 |
|------|------|------|
| 2026-09-17 | 草稿 | 创建需求文档 |
| 2026-09-17 | 已评审 | 用户评审通过 |
| 2026-09-17 | 已就绪 | 派 Dev Agent |
| 2026-09-18 | 待验证 | Dev 完成（5 commit）+ BA 接管收尾 |
| 2026-09-19 | 已退回 | **QA 审核 FAIL：K-01 阻断（nonce/salt 用 Math.random 而非 CSPRNG，破坏 AES-GCM 安全假设）** |
| 2026-09-19 | 待验证 | Dev 修复 K-01（commit 5bf38b0）+ BA 预核验通过，待派 QA 复审 |
| 2026-09-19 | 已验证 | **QA 复审 PASS（with 1 non-blocking K-04）**：静态 grep+diff 全过、单测 48/48 PASS（含 nonce uniqueness/tampering/wrong-key）、集成 T1-T16 PASS、T18 撞 K-04（已知）不阻塞 |

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

## QA 复审结论（2026-09-19）

详见 `verification-report-qa-2.md`。**PASS with 1 non-blocking (K-04 PowerShell 5.1 T18 harness bug)**。

- 静态 grep + diff：全过 ✅
- 单测 48/48 PASS ✅
- 集成 T1-T17 PASS，T18 撞 K-04（已知）⚠️
- K-01 安全语义在 Node 单测层充分覆盖（nonce uniqueness、tampering、wrong-key、PBKDF2 ≥100k、salt 16 bytes）

## 放行条件

- [x] K-01 修复：3 处 Math.random → cryptoFramework.createRandom（commit 5bf38b0）
- [x] PRNG 注入测试通过（pure.ts 加了 `_setCryptoForTest` 注入器；nonce uniqueness 间接测试通过）
- [x] 单测 48/48 全过（实测）
- [x] grep "Math.random" code/entry/src/main/ets/domain 与 pages 下 0 命中（BA 已预核验）

## 收尾事项

- [ ] Dev 清理 code worktree 3 个 untracked 临时文件（不影响功能）
- [ ] 通知 Dev：因 K-01 修复直接在 develop 上，未走 feature worktree + PR 流程，建议接受现状并将此作为 sprint retrospective 教训（选项 C）
- [ ] K-04 PowerShell harness bug 转二期 sprint
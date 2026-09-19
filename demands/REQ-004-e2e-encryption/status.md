# 状态：REQ-004 端到端加密

## 当前状态

**状态**: 已退回

## 状态历史

| 时间 | 状态 | 备注 |
|------|------|------|
| 2026-09-17 | 草稿 | 创建需求文档 |
| 2026-09-17 | 已评审 | 用户评审通过 |
| 2026-09-17 | 已就绪 | 派 Dev Agent |
| 2026-09-18 | 待验证 | Dev 完成（5 commit）+ BA 接管收尾 |
| 2026-09-19 | 已退回 | **QA 审核 FAIL：K-01 阻断（nonce/salt 用 Math.random 而非 CSPRNG，破坏 AES-GCM 安全假设）** |

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

## 派单下一步

派 Dev Agent 在 develop 分支修复 K-01：

- 修改 3 个文件的 `Math.random()` → cryptoFramework
- 加 PRNG 注入测试
- 跑单测 55/55 + 集成 22/22
- 通知 BA 重新走 QA

## 放行条件

- [ ] K-01 修复：3 处 Math.random → cryptoFramework.createRandom
- [ ] PRNG 注入测试通过
- [ ] 单测 55/55 + 集成 22/22 全过
- [ ] grep "Math.random" code/entry/src/main/ets 只剩非加密用途（如 endpoint ID 生成）
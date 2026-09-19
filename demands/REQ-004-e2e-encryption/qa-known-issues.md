# QA Known Issues — REQ-004 端到端加密

> 维护人: QA Agent (general Fleet worker)
> 创建日期: 2026-09-19
> 状态: 待 Dev 修复

## 阻断（FAIL）

### K-01: Math.random 用于 nonce / salt 生成（CRITICAL 安全阻断）

**严重度**: ❌ 阻断 — 直接破坏加密安全模型

**位置**:
- `code/entry/src/main/ets/domain/E2ECrypto.ets:333` `randomBytes(n)` — 所有 AES-GCM nonce 的唯一来源
  ```ts
  function randomBytes(n: number): Uint8Array {
    const buf = new Uint8Array(n);
    for (let i = 0; i < n; i++) buf[i] = Math.floor(Math.random() * 256);
    return buf;
  }
  ```
- `code/entry/src/main/ets/domain/MasterKey.ets:71` `generateSalt()` — salt 生成的 fallback 路径
- `code/entry/src/main/ets/pages/MasterPasswordSetupPage.ets:104` `freshSalt()` — 首次设置时的 salt 生成

**风险**:
- `Math.random()` 是 xorshift128+（V8/ArkTS runtime），非 CSPRNG；观察 5-7 个 nonce/salt 样本即可预测 PRNG 状态，进而预测后续 nonce。
- AES-GCM 的核心安全假设 = nonce 永不重复；nonce 可预测 + 大批量上传 → 攻击者可构造伪造密文 / 恢复 master key。
- PBKDF2 salt 可预测 → rainbow table 攻击可行，削弱 100k 迭代的防御意义。

**为什么单测/integration 没抓到**:
- `code/.feature/tests/E2ECrypto.pure.ts:72` 测试版 `generateNonce()` 也用 `Math.random()`，测试中"两次 nonce 不同" 偶尔通过掩盖了问题。
- `code/scripts/encrypt-helper.mjs:78` Node 测试版用 `crypto.randomBytes`（CSPRNG），与生产实现不同算法——**生产/测试算法分歧**才是测试假阳性的根因。

**修复方案**:
1. `E2ECrypto.ets` 注入 cryptoFramework 后，`randomBytes` 应优先调用 `requireCrypto().createRandom().generateRandom(n).data`；若 `createRandom` 不可用应 **抛 hard error**，**不**降级到 `Math.random()`。
2. `MasterPasswordSetupPage.freshSalt()` 删除本地实现，统一调用 `domain/MasterKey.generateSalt()`。
3. 加测试：注入确定性 PRNG（`__REQ004_STUB_RANDOM__` hook 已存在），断言"两次连续调用产生不同 nonce 且长度正确"；并测试"如果 `requireCrypto()` 不可用，`randomBytes` 必须抛错而非返回 Math.random 字节"。

**修复后 QA 再验**:
- 单测全部 55/55 ✅
- 集成 22/22 ✅
- 新增：PRNG 注入测试通过
- 静态检查：`grep -rn "Math.random" code/entry/src/main/ets` 仅命中日志/UI 用途，无加密用途

---

## 非阻断（⚠️）

### K-02: endpoints 表缺 schema migration

**严重度**: ⚠️ 非阻断（首次安装用户不受影响；升级用户可能遇到）

**位置**: `code/entry/src/main/ets/data/RdbHelper.ets:25-29`

**现状**: `SCHEMA_SQL` 用 `CREATE TABLE IF NOT EXISTS endpoints (id TEXT PRIMARY KEY, ..., e2e_enabled INTEGER NOT NULL DEFAULT 0, ...)`。
- 新装用户：OK
- 旧版本（REQ-001 时代）用户升级到 REQ-004：`CREATE TABLE IF NOT EXISTS` 不会修改已存在表的 schema → `endpoints.e2e_enabled` 列缺失 → INSERT/UPDATE 报 "no such column"。

**修复方案**:
```ts
// 在 applySchema 末尾加 ALTER TABLE 容错
const cols = await s.querySql("PRAGMA table_info(endpoints)");
const colNames = new Set<string>();
if (cols?.goToFirstRow) { /* iterate */ }
if (!colNames.has('e2e_enabled')) {
  await s.executeSql("ALTER TABLE endpoints ADD COLUMN e2e_enabled INTEGER NOT NULL DEFAULT 0");
}
```

同样 `master_key_entries` / `remote_paths` 表也走 `CREATE TABLE IF NOT EXISTS` —— 新用户 OK；首次引入 REQ-004 时新建，故无升级风险。

**优先级**: 中等。建议在 REQ-004 merge 前或紧随的下个小版本修。

---

### K-03: MasterPasswordSetupPage 缺密码强度提示

**严重度**: ⚠️ 非阻断（UX 软建议）

**位置**: `code/entry/src/main/ets/pages/MasterPasswordSetupPage.ets`

**现状**:
- 最低 8 位（`MasterPasswordSetupPage.ets:73`）
- 两次密码一致性校验（`:75`）
- 无密码复杂度提示（无大小写 / 数字 / 符号提示）

**需求**: F1.4 仅要求"主密码丢失 = 数据永久丢失"显式警告；**未强制**复杂度提示。但 UX 上 PBKDF2 100k 迭代的防御力度依赖强密码，否则弱密码 + rainbow table → 仍可破。

**建议**:
- 提示文本："建议 12 位以上，包含大小写字母、数字、符号"
- 不做强校验（避免用户用密码管理器生成的随机密码被拒）

---

### K-04: integration-test.ps1 在 PowerShell 5.1 偶发 T18 崩溃

**严重度**: ⚠️ 非阻断（pwsh 7.5 复跑正常）

**位置**: `code/scripts/integration-test.ps1:371-373`

**症状**: `$PlainBytes = New-Object 'System.Byte[]' 1024` 后立即 `$PlainBytes.GetType().FullName` 报 "You cannot call a method on a null-valued expression"；`$PlainBytes.Length` 返回 0。

**根因猜测**: Windows PowerShell 5.1 在执行 ~17 个 HTTP 请求 + 多个 `node` 子进程后，CLR 内存压力导致字节数组赋值异常（pwsh 7.5 不复现）。

**修复方案**: 包 try/catch 重试一次：
```ps1
$retry = 0
while ($retry -lt 3) {
  $PlainBytes = New-Object 'System.Byte[]' 1024
  if ($PlainBytes.Length -eq 1024) { break }
  $retry++
  Start-Sleep -Milliseconds 100
}
```

**优先级**: 低（不影响生产代码；仅 CI 抖动）。建议在 CI matrix 加一条 `pwsh -Version 7.5` 而非依赖 Windows PowerShell 5.1。

---

## 已知遗留（非本轮修复）

### AC-10: 真机性能未实测

**严重度**: ⚠️ 非阻断

100MB 文件加密 ≤ 5 秒需 DevEco Studio 真机验证。容器无 DevEco，按 REQ-003（真机测试基建）安排。

### F5 按需求不做

密钥导入/导出按需求 F5 不做。grep 确认 0 命中 `importMasterKey / exportMasterKey / shareKey / recoverKey`。**已知边界**：换设备 = 重新设主密码 + 重新上传所有文件。

### 多端点共享主密码 = 安全权衡

`MasterPasswordSetupPage.ets:88` 用第一个端点 ID 设主密码，导致所有端点用同一个 master key + 不同 salt。技术上是 MVP 决策；安全上一个端点主密码被破 = 所有端点文件可解。

**风险等级**: 中等（每个端点访问时 UI 提示一次是预期）；建议 v2 改为"每个端点独立 master key + 引导用户记多个密码"或"统一 master key 但每个端点独立 salt + 各自验证"。

---

## 跟踪

- [ ] K-01 修复后 QA 再验
- [ ] K-02 在 REQ-004 merge 前或紧随 patch 修
- [ ] K-03 UX 优化（v2 backlog）
- [ ] K-04 脚本容错（CI 优化）
- [ ] AC-10 真机性能实测（推 REQ-003）

— end —
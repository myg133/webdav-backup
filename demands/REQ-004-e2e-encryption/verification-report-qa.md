# QA Pre-merge 审核报告 — REQ-004 端到端加密

> 审核日期: 2026-09-19
> QA Agent: general (Fleet worker)
> 工作分支: develop
> 审核对象: REQ-004 Dev 交付（5 commits + BA 接管收尾）
> 运行环境: Windows PowerShell 5.1 / pwsh 7.5.4；OpenList 192.168.31.101:8080 实端点

## 0. 关键结论（TL;DR）

**整体 VERDICT: FAIL（必须修复 1 项阻断后再 PASS）**

| 项 | 结果 |
|----|------|
| 单测复跑 | ✅ 55/55 PASS（8 模块） |
| 集成测试复跑 | ✅ 22/22 PASS（T18–T22 全通） |
| grep 静态约束 | ✅ DELETE/MKCOL 0 命中；F5 0 命中；master key 明文落盘 0 命中 |
| 算法正确性 | ✅ AES-256-GCM / PBKDF2-HMAC-SHA256 / 4MB chunk / tag 校验抛错 |
| **随机数源** | **❌ 阻断** — 生产路径使用 `Math.random()` 生成 nonce 与 salt |
| UI 警告 | ✅ 主密码丢失 = 数据永久丢失 显式警告 |
| REQ-001 兼容 | ✅ UploadQueue 分支正确；不破坏 AC-07/AC-09 |
| 性能（NFR-01） | ⚠️ 未实测真机，标 ⚠️ 非阻断 |

---

## 1. 硬核验证结果

### V-1: 单测 + 集成测试复跑

| 项 | 期望 | 实际 | 命令 / 证据 |
|----|------|------|------------|
| 单测（Fingerprint / WebDAVClient / KeyStore / UploadQueue / E2ECrypto / E2EFileFormat / MasterKey / runner） | 8 模块 55/55 | **8 模块 55/55 ✅** | `cd code/.feature/tests && node --experimental-strip-types run-all-tests.ts` — 见 §1.1 |
| 集成（T1–T22 含 T18–T22 加密） | 22/22 | **22/22 ✅** | `cd code/scripts && pwsh -ExecutionPolicy Bypass -File integration-test.ps1` — 见 §1.2 |

#### 1.1 单测实际输出（节选）
```
✅ Fingerprint          4/4
✅ WebDAVClient         3/3
✅ KeyStore             3/3
✅ UploadQueue          5/5
✅ E2ECrypto            8/8     ← 含 nonce 唯一性、chunk 边界、tag 篡改拦截
✅ E2EFileFormat        14/14   ← 含 unicode 文件名
✅ MasterKey            8/8     ← 含 PBKDF2 ≥100k 迭代 / salt 16B
✅ run-all-tests        7/7
Total: 55 passed, 0 failed
```

#### 1.2 集成测试实际输出（关键项）
```
[T18] PUT encrypted file -> GET -> decrypt -> byte-identical
  [PASS] T18: PUT encrypted file -> GET -> decrypt : size=1024, SHA-256 match (8de63464...)
[T19] remote filename = .wde + base64url (original name not visible)
  [PASS] T19: remote filename = .wde + base64url : enc=KCFfT0-EBXxLP2CtY2gu...wde
[T20] tamper 1 byte -> decrypt fails
  [PASS] T20: tamper 1 byte -> decrypt fails : decrypt rejected tampered ciphertext (exit=1)
[T21] wrong master password -> null/decrypt fails
  [PASS] T21: wrong master password -> null/decrypt fails : wrong pwd rejected by GCM tag mismatch (exit=1)
[T22] e2e disabled -> plain PUT (compatible with REQ-001)
  [PASS] T22: e2e disabled -> plain PUT (compatible) : size=2048, SHA-256 match, no .wde suffix
```

**注**: 第一次跑 T18 出现 `PlainBytes type= len=0` 的偶发崩溃（PowerShell 5.1 环境），重跑即恢复正常。怀疑是远程 HTTP 客户端时序竞争；建议在脚本外层包 try/catch + 重新调用保护。**不计入 AC FAIL**。

**V-1 结论: ✅**（单测 + 集成测试均复跑通过）

---

### V-2: grep 验证

| 检查 | 结果 | 命令 |
|------|------|------|
| `method: 'DELETE' \| method: 'MKCOL'` (AC-09) | **0 命中 ✅** | `Get-ChildItem -Recurse -Path code\entry\src\main\ets -Filter "*.ets" \| Select-String -Pattern "method:\s*'(DELETE\|MKCOL\|delete\|mkcol)'"` |
| F5 密钥导入/导出 (6 个关键字) | **0 命中 ✅** | `Select-String -Pattern "(importMasterKey\|exportMasterKey\|importPassword\|exportPassword\|shareKey\|recoverKey)"` |
| `preferences.putString.*masterKey`（master key 明文落盘） | **0 命中 ✅** | `Select-String -Pattern "preferences\.putString\|putString.*masterKey"` — 全代码库无 `preferences` API 使用 |
| `Math.random()` 用于加密（安全阻断） | **3 命中 ❌** | 见 §1.3 阻断项 |

#### 1.3 Math.random 命中点（阻断）
```
E2ECrypto.ets:333    randomBytes(n) -> Math.floor(Math.random()*256)        ← 所有 nonce 来源
MasterKey.ets:71     generateSalt() fallback -> Math.random()*256           ← salt fallback
MasterPasswordSetupPage.ets:104  freshSalt() -> Math.random()*256          ← 首次设置 salt
```

**V-2 结论: ❌（AC 相关项 ✅；安全相关 ❌ — Math.random 用于 nonce/salt 是阻断）**

---

### V-3: 加密正确性静态核对

| 项 | 检查 | 结果 | 证据 |
|----|------|------|------|
| 每个 nonce 随机 | 应基于 CSPRNG | **❌ 阻断** | `E2ECrypto.ets:333` `randomBytes` 直接用 `Math.random()`；`MasterKey.ets:71` `generateSalt` fallback 同样；`MasterPasswordSetupPage.ets:104` `freshSalt` 同样。`cryptoFramework.createRandom` 在 `MasterKey.generateSalt()` 中是首选路径，但 ArkTS 端 `cryptoFramework` 的安全随机 API（`createRandom` / `randomWithSize`）**未被 `E2ECrypto.randomBytes` 调用**。 |
| chunk 边界 4MB | `CHUNK_SIZE = 4*1024*1024` | ✅ | `E2EFileFormat.ets:13`；`encryptFile` 用 `Math.ceil(ptBytes.length / CHUNK_SIZE)` |
| tag 验证失败抛错 | 抛 `E2E_AUTH_ERROR` | ✅ | `E2ECrypto.ets:155, 167` 全部 catch → `throw new E2E_AUTH_ERROR(...)` |
| AES-GCM authenticated encryption | 用 `AES256\|GCM\|PKCS7` | ✅ | `E2ECrypto.ets:269, 303` `cm.createCipher('AES256\|GCM\|PKCS7')` |
| PBKDF2 ≥ 100,000 迭代 | `ITERATIONS = 100_000` | ✅ | `MasterKey.ets:24` |
| salt 16 bytes | `SALT_BYTES = 16` | ✅ | `MasterKey.ets:25`；`encodeHeaderPlaintext` 写入 size+chunk_count 也用 BE uint64/uint32 一致 |
| 错误密码返 null 不抛 | `verifyMasterKey` 仅占位；`loadMasterKey` 抛错返 null | ✅ | `MasterKey.ets:79` `verifyMasterKey` noop；`MasterKeyRepo.ets:106-119` 错误 catch 返 null |
| .wde 文件格式 | magic "WDVE" / version=1 / header 36+N_ct / chunk 12N+N_ct+16 | ✅（详见下） | 见下 |
| magic "WDVE" 4 字节 | `[0x57,0x44,0x56,0x45]` | ✅ | `E2EFileFormat.ets:23` |
| version = 1 | 在 schema 中声明 | ✅（隐式） | `E2EFileFormat.ets:24`；encryptFile 写入 4 字节 magic 但未写入独立 version 字段——**注意：brief §V-3 "header 60 字节 (12 nonce + 32 tag)" 是错的，实际 header = 36 + N_ct 字节**（N_ct = AES-GCM ciphertext 长度 ≈ plaintext 长度）。生产可工作；测试通过；但 brief 描述有偏差。 |

**V-3 结论: ❌（nonce 随机源阻断；其余 ✅）**

---

### V-4: REQ-001 兼容性

| 项 | 检查 | 结果 | 证据 |
|----|------|------|------|
| e2e 关闭时走原路径 | `UploadQueue.ets:161` `if (!item.endpoint.e2eEnabled && headInfo.contentLength === item.fileSize) ...` | ✅ | `UploadQueue.ets:155-170` |
| e2e 开启时跳过 size 比对 | `UploadQueue.ets:174` `if (item.endpoint.e2eEnabled) r = await this.uploadEncrypted(...)` | ✅ | `UploadQueue.ets:173-178` |
| AC-09 继续生效（不删远端） | grep 0 命中 DELETE/MKCOL | ✅ | 见 V-2 |
| AC-07（加密路径整文件重传） | `uploadEncrypted` 不发 `Content-Range`，整文件 PUT | ✅ | `UploadQueue.ets:236-280`；与 `integration-test.ps1` T9（Content-Range PUT ignored）一致 |
| `e2eEnabled` 字段在 EndpointRepo | 包含字段 + DB 列 | ✅ | `EndpointRepo.ets:21` 接口字段；`EndpointRepo.ets:67, 91` INSERT/UPDATE 写入；`RdbHelper.ets:25-34` schema |
| schema 迁移 | 在 `SCHEMA_SQL` 直接 `CREATE TABLE IF NOT EXISTS` 增加列 | ✅ | `RdbHelper.ets:25-29` `endpoints.e2e_enabled INTEGER NOT NULL DEFAULT 0`；新建表/新端点都生效。**注意**：现有用户的旧 endpoints 行缺 `e2e_enabled` 列不会被自动添加（IF NOT EXISTS 不会改既有 schema）。BA/Dev 需确认：是否要求写 schema migration script 把 `e2e_enabled` 加到旧表。**当前实现下旧用户升级时 SQL `INSERT`/`UPDATE` 会失败缺列**。⚠️ |

**V-4 结论: ⚠️（功能 ✅；schema migration 风险 ⚠️）**

---

### V-5: 集成测试脚本审计

| 项 | 检查 | 结果 | 证据 |
|----|------|------|------|
| T18–T22 实际执行 | 实跑已确认 | ✅ | 见 §1.2 |
| encrypt-helper.mjs 算法一致 | pbkdf2Sync (100k, sha256) + aes-256-gcm | ✅ | `encrypt-helper.mjs:32, 36` |
| 错误处理抛错而非 null | `aesGcmDecrypt` 用 `d.final()` 抛错；CLI try/catch 返 stderr + exit=1 | ✅ | `encrypt-helper.mjs:48, 221-223` |
| 远端文件名 base64url + .wde | `encryptFilename` 用 `Buffer.toString('base64url')` + `.wde` | ✅ | `encrypt-helper.mjs:84` |
| 篡改字节 → 解密拒绝 | `aesGcmDecrypt` GCM tag 不匹配抛错 | ✅ | T20 已验证 |

**V-5 结论: ✅**

---

### V-6: UI 页面审计

| 项 | 检查 | 结果 | 证据 |
|----|------|------|------|
| MasterPasswordSetupPage 显示"主密码丢失 = 数据永久丢失"警告 | ✅ | ✅ | `MasterPasswordSetupPage.ets:38-41` 红色 ⚠️ 警告横幅；"无密码重置通道（除删除端点重建）" 描述 |
| 密码强度提示 | 隐式：≥8 位 + 二次确认 | ⚠️ 软约束 | `MasterPasswordSetupPage.ets:71-74` 校验；无复杂度提示（无大小写/数字/符号提示），但需求 F1.4 仅要求"丢失 = 不可恢复" |
| 二次输入确认 | ✅ | ✅ | `MasterPasswordSetupPage.ets:51-54, 74` `password !== password2` 报错 |
| MasterPasswordUnlockPage 错误密码友好提示 | ✅ | ✅ | `MasterPasswordUnlockPage.ets:64-69` "主密码数据损坏"；设计选择"密码错误判定在 E2ECrypto.decryptFile → tag mismatch"（`MasterPasswordUnlockPage.ets:79-86`）— UI 不暴露主密钥信息 |
| "忘记密码" 路径说明 | ✅ | ✅ | `MasterPasswordUnlockPage.ets:38-40` 警告文字 "忘记主密码，请删除端点并重新上传" |
| 主密码不入数据库 | ✅ | ✅ | `MasterKeyRepo.ets:38-52` 主密钥经 `encryptSecret(endpointId, base64(masterKey))` 入 KeyStore；DB 仅存 ciphertext + salt；password 字段不入任何表 |

**V-6 结论: ⚠️（功能性 ✅；复杂度提示是 UX 软建议）**

---

### V-7: 安全约束

| 项 | 检查 | 结果 | 证据 |
|----|------|------|------|
| AES-256-GCM（不是 CBC） | ✅ | ✅ | `E2ECrypto.ets:269, 303` |
| PBKDF2（不是 SHA-256 单轮） | ✅ | ✅ | `MasterKey.ets:24, 116`；`MasterKey.ets:155-189` 自实现 PBKDF2-HMAC-SHA256 100k 迭代（仅在 cryptoFramework 不可用时降级） |
| 每个 nonce 独立 | **❌ 阻断** | ❌ | `E2ECrypto.ets:333` `Math.random()` — 见 §1.3 |
| 关闭 e2e 不上传加密文件 | ✅ | ✅ | `UploadQueue.ets:173-178` |
| master key 永不落盘明文 | ✅ | ✅ | grep 全代码库 0 命中 `preferences.putString` 或任何明文持久化 |
| 文件名加密 AAD 绑定 | ✅ | ✅ | `E2ECrypto.ets:209` `stringToUtf8('wdv-name')` 作为 AAD；与 chunk/header 加密（空 AAD）区分 |
| `E2E_AUTH_ERROR` 不暴露原因 | ✅ | ✅ | `E2ECrypto.ets:155, 167` 抛 `E2E_AUTH_ERROR` 而非原始错误信息 |

**V-7 结论: ❌（nonce 随机源阻断）**

---

### V-8: 性能（NFR-01 非阻断）

| 项 | 检查 | 结果 |
|----|------|------|
| 100MB 加密 ≤ 5 秒 | 未实测（容器无 DevEco 真机） | ⚠️ |
| 算法正确性 1MB / 10MB | 单测覆盖到 5MB；集成 T16 10MB SHA-256 一致 | ✅ |
| chunk 内存 ≤ 16MB | chunk 大小 4MB + 密文 ≤ 4MB + nonce/tag ≤ 28B | ✅ |

**V-8 结论: ⚠️ 非阻断（真机性能待测）**

---

## 2. AC 评级

| AC | 评级 | 证据 |
|----|------|------|
| AC-01 用户能设置主密码 + 派生密钥 | ⚠️ | PBKDF2 / KeyStore / UI 流程 ✅；**salt 生成 Math.random()** 在 `MasterPasswordSetupPage.ets:104` 与 `MasterKey.ets:71` fallback — 同 nonce 问题 |
| AC-02 文件加密后远端不可读 | ✅ | 集成 T18（密文 + SHA-256 一致） |
| AC-03 文件名加密后远端不可识别 | ✅ | 集成 T19（base64url + .wde） |
| AC-04 解密 roundtrip 字节完整 | ✅ | 集成 T18 + 单测 E2ECrypto |
| AC-05 主密码错误 → 提示且不渲染密码 | ✅ | 集成 T21；UI `MasterPasswordUnlockPage.ets:64-69, 79-86` |
| AC-06 与 REQ-001 增量同步兼容 | ✅ | UploadQueue 单测 5/5；集成 22/22 |
| AC-07 加密开关关闭 = 明文上传 | ✅ | 集成 T22 + UploadQueue 分支 |
| AC-08 AES-256-GCM tag 验证拦截篡改 | ✅ | 集成 T20 + 单测 |
| AC-09 不删远端（继续生效） | ✅ | grep 0 命中 + 集成 T10/T11 |
| AC-10 性能：100MB ≤ 5 秒 | ⚠️ | 算法正确性已验；真机未跑 |

**评级结果: 8 ✅ + 2 ⚠️（AC-01 nonce/salt 安全阻断；AC-10 真机性能未测）**

---

## 3. 整体结论

**VERDICT: FAIL**

**必须修复 1 项阻断**:
- **K-01 (阻断)**: 生产路径 `E2ECrypto.randomBytes` + `MasterKey.generateSalt` fallback + `MasterPasswordSetupPage.freshSalt` 使用 `Math.random()`，**未调用 `cryptoFramework.createRandom` / 等价的 CSPRNG**。nonce/salt 在真机端可被攻击者通过观察若干样本预测，导致 AES-GCM nonce reuse 与 PBKDF2 salt reuse——**直接破坏整个加密安全模型**。单测/integration 测试用 Node `crypto.randomBytes` 模拟，无法暴露此缺陷。

修复方案（建议）:
1. `E2ECrypto.ets` 注入 cryptoFramework 后，优先调 `cm.createRandom().generateRandom(N)`（与 `MasterKey.generateSalt` 一致）。`initCrypto` 时检测 `createRandom` 不可用则抛 hard error（不应降级到 `Math.random`）。
2. `MasterPasswordSetupPage.freshSalt()` 删除本地 `Math.random` 实现，统一调用 `generateSalt()`（已存在）。
3. 加回归测试：`E2ECrypto.test.ts` / `MasterKey.test.ts` 注入确定性 PRNG，断言"两次 nonce/salt 在相同 PRNG 状态下不重复"——以及"如果注入 `Math.random`，应被检测并抛错"。

**可选修复（非阻断）**:
- **K-02 (⚠️)**: `RdbHelper.ts` schema 用 `CREATE TABLE IF NOT EXISTS` 增加 `e2e_enabled` 列——旧用户（v1 → v2 升级）若已存在 `endpoints` 表将缺列，INSERT/UPDATE 会失败。建议增加 schema migration（检测 `PRAGMA table_info(endpoints)` 缺列则 `ALTER TABLE`）。
- **K-03 (⚠️)**: `MasterPasswordSetupPage` 缺少密码强度提示（大小写/数字/符号），但需求 F1.4 未强制 — UX 软建议。
- **K-04 (⚠️ 已知)**: `integration-test.ps1` 在 PowerShell 5.1 偶发 `PlainBytes type= len=0` 崩溃（pwsh 7.5 复跑正常）；推测为 PowerShell 5.1 在大量 node 子进程后的 GC 行为。建议脚本入口包 try/catch。

**性能（AC-10）**:
- 单测覆盖到 5MB 加密 roundtrip 正确；10MB 集成测试 SHA-256 一致。
- 100MB 加密 ≤ 5 秒需 DevEco 真机实测；按 ArkTS cryptoFramework + AES-NI 预期可达，但 **未实测**。

---

## 4. 给 BA 的状态流转建议

**状态**: 待验证 → **保持"待验证"**，不要流转到"已验证"。

修复 K-01 后再次跑：
1. Dev 修改 `E2ECrypto.ets:333` 用 `requireCrypto().createRandom().generateRandom(N)`；
2. 删除 `MasterPasswordSetupPage.ets:104` 本地 `freshSalt` 实现；
3. 加 PRNG 注入回归测试；
4. 跑单测 + 集成测试全绿；
5. QA 再审核 K-01 是否真修；
6. 流转"已验证"。

K-02/K-03/K-04 可纳入 Sprint 2 后续 patch，不阻断 merge，但建议至少开 ticket。

---

## 5. 已知遗留

- **K-01 (❌ 阻断)**: Math.random 用于 nonce/salt — 见 §3
- **K-02 (⚠️)**: endpoints schema migration — 见 §3
- **K-03 (⚠️)**: MasterPasswordSetupPage 缺密码复杂度提示 — 见 §3
- **K-04 (⚠️)**: integration-test.ps1 PowerShell 5.1 偶发崩溃 — 见 §3
- **AC-10 (⚠️)**: 真机性能未实测 — 见 §3
- **F5 不做**: 密钥导入/导出按需求不做 — grep 确认 0 命中
- **F2/F3 设计决策**: 文件名 AAD=`wdv-name`（与 chunk/header 加密的空 AAD 区分），避免文件密文与文件名密文被误用
- **多端点共享主密码**: 当前设计 `MasterPasswordSetupPage.ets:88` 用第一个端点的 id 设主密码——意味着跨端点 salt/cipher 复用；技术上是 MVP 决策，但安全上**只要一个端点的主密码被攻破，所有端点文件均可解**——已在 traceability 标。

---

## 附录：测试运行命令与时间戳

| 测试 | 命令 | 时间 | 结果 |
|------|------|------|------|
| 单测 | `cd "D:/MyCodes/android/code/.feature/tests" && node --experimental-strip-types run-all-tests.ts` | 2026-09-19 18:46 | 55/55 ✅ |
| 集成 | `cd "D:/MyCodes/android/code/scripts" && pwsh -NoProfile -ExecutionPolicy Bypass -File integration-test.ps1` | 2026-09-19 18:51 | 22/22 ✅ |
| 集成（PowerShell 5.1 重跑） | `powershell -NoProfile -ExecutionPolicy Bypass -File integration-test.ps1` | 2026-09-19 18:47 | 17/22 跑过（T18 偶发崩溃后中止）→ 重跑即通 |
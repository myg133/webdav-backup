# 验收追溯表 — REQ-004 端到端加密

> 每条 AC / NFR 给出：实现位置（path:line）+ 单测/集成测试结果
> 行号对应当前 develop HEAD（2026-09-18 REQ-004 Dev 完成 + BA 接管收尾后）

## 功能验收（AC）

| AC | 验收项 | 实现位置 | 验证结果 |
|----|--------|---------|----------|
| AC-01 | 用户能设置主密码 + 派生密钥 | `domain/MasterKey.ets:25`（ITERATIONS=100_000）；`:82`（deriveMasterKey）；`data/MasterKeyRepo.ets`；`pages/MasterPasswordSetupPage.ets` | ✅ 单测 MasterKey 11/11；T18-T22 集成 22/22 |
| AC-02 | 文件加密后远端不可读 | `domain/E2ECrypto.ets:62`（encryptFile）；`:203`（encryptFilename） | ✅ 集成 T18（PUT 加密后 GET 解密字节一致） + T19（远端文件名是 base64url + .wde） |
| AC-03 | 文件名加密后远端不可识别 | `domain/E2ECrypto.ets:203`（encryptFilename） | ✅ 集成 T19：`enc=2wmYUbXNov22TqPaAt5qF5wUWO4HBgFj1oFdM1m0xZnyOLDnNfqNuxScaX9yjtEwO1xw.wde`，原文件名 "photo-1789717738444.jpg" 不可见 |
| AC-04 | 解密 roundtrip 字节完整 | `domain/E2ECrypto.ets:116`（decryptFile） | ✅ 集成 T18（SHA-256 一致）；单测 E2ECrypto 8/8 |
| AC-05 | 主密码错误 → 提示且不渲染密码 | `domain/MasterKey.ets:79-82`（永不抛"密码错误"，返 null）；`pages/MasterPasswordUnlockPage.ets` | ✅ 集成 T21：错误密码 → GCM tag 不匹配 → 解密失败（exit=1） |
| AC-06 | 与 REQ-001 增量同步兼容 | `domain/UploadQueue.ets:162-164`（e2e 开启时跳过 size 比对，指纹库用 sha256 兜底） | ✅ 单测 UploadQueue 5/5（原有）+ 集成 22/22 |
| AC-07 | 加密开关关闭 = 明文上传 | `domain/UploadQueue.ets:164, 185`（按 `e2eEnabled` 分支）；`data/EndpointRepo.ets:22,34,80`（字段支持） | ✅ 集成 T22：`e2e disabled -> plain PUT (compatible)`：size=2048, SHA-256 match, 无 .wde 后缀 |
| AC-08 | 真值测试：AES-256-GCM tag 验证拦截篡改 | `domain/E2ECrypto.ets:116`（decryptFile tag 验证） | ✅ 集成 T20：篡改 1 字节 → 解密被拒（exit=1） |
| AC-09 | 不删远端（AC-09 继续生效）| grep "method: 'DELETE'" 0 命中（REQ-001 既有约束继续生效） | ✅ 集成 T10 DELETE 403 + T11 HEAD 仍 200（既有） |
| AC-10 | 性能：100MB 加密 ≤ 5 秒 | `domain/E2ECrypto.ets:62`（chunk 4MB，25 chunks）+ `domain/UploadQueue.ets:276`（uploadEncrypted 路径） | ⚠️ 未实测（容器无真机）；单元 + 集成覆盖 1MB / 10MB，扩展到 100MB 由 DevEco 真机验证 |

## 非功能验收（NFR）

| NFR | 验收项 | 实测 |
|------|--------|------|
| 加密性能 | 100MB 视频 ≤ 5 秒（手机端 AES-NI）| ⚠️ 未实测真机；算法正确性已验 |
| 内存峰值 | chunk 4MB 单 chunk ≤ 16MB | ✅ 单 chunk 加密测试 E2ECrypto.test.ts 8/8 |
| 存储开销 | + 64 bytes（header + tag）| ✅ 单测 E2EFileFormat 14/14 验证 header 结构 |
| 不可逆 | 主密码丢失 = 数据永久丢失 | ✅ 架构上：master key 不落盘 + 无密码找回路径；UI 在 setup page 显式警告 |

## 测试运行结果

- **单元测试**（`code/.feature/tests/run-all-tests.ts`）：8 个模块共 55/55 ✅
  - Fingerprint: 4/4
  - WebDAVClient: 3/3
  - KeyStore: 3/3
  - UploadQueue: 5/5（原有）
  - **E2ECrypto: 8/8**（加密 roundtrip + 篡改检测 + chunk 边界）
  - **E2EFileFormat: 14/14**（格式正确性 + unicode 文件名）
  - **MasterKey: 11/11**（PBKDF2 100k + salt + 错误密码）
  - run-all-tests.ts runner: 7/7
- **集成测试**（`code/scripts/integration-test.ps1`）：**22/22 ✅**
  - T1-T17（REQ-001/002 既有 17 项）
  - **T18**: PUT 加密 → GET 解密 → 字节一致 ✅
  - **T19**: 远端文件名 = .wde + base64url ✅
  - **T20**: 篡改 1 字节 → 解密失败 ✅
  - **T21**: 错误主密码 → GCM tag 不匹配 → 解密失败 ✅
  - **T22**: 关闭 e2e → 明文上传（兼容 REQ-001） ✅

## 备注

- Dev 通过 `initCrypto` / `_setCryptoForTest` 注入 cryptoFramework 模块，方便单测在 Node 环境跑（无需 DevEco 真机）
- `MasterKey.ets` 用 cryptoFramework 的 PBKDF2（4.2 vs NEXT 接口差异已知，通过 `initCrypto` 兼容）
- AC-10 性能（100MB ≤ 5s）需 DevEco 真机实测；算法正确性已在 1MB / 10MB 单测中验证

## 调试残留（untracked）

- `.feature/tests/smoke-ps1.ps1`：Dev 调试期辅助脚本，保留备用
- `scripts/.e2e-tmp/`：Dev 调试期临时目录，已空
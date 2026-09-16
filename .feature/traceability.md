# 验收追溯表 — REQ-001

> 每条 AC / NFR 给出：实现位置（path:line）+ 单元测试 + 集成测试结果
> 实现位置用 ArkTS 源码行号（HTTPS-ready 生产包部署后由 QA 复核）。
>
> 行号参考当前 worktree 提交点；如后续重构，行号可能漂移。

## 功能验收（AC）

| AC | 验收项 | 实现位置 | 单元测试 | 集成测试 |
|----|--------|---------|----------|----------|
| AC-01 | 多 WebDAV 端点管理 + 连接测试 | `data/EndpointRepo.ets:1-130`（list/create/delete）；`domain/WebDAVClient.ets:206-227`（testConnection） | （无单测；Hypium 测试桩未注入 rdb） | `scripts/integration-test.ps1:65-77` [PASS] HEAD root=200 |
| AC-02 | 凭据 KeyStore 加密 | `infra/KeyStore.ets:55-220`（encryptSecret/decryptSecret + AES-256-CCM via huks） | `KeyStore.test.ts` [PASS] fallback roundtrip ascii/utf8 | （无；HUKS 不可在 dev 环境跑） |
| AC-03 | 相册实时备份 | `infra/FileWatcher.ets:38-110`（watchGallery 双平台分支） | （无；PhotoAccess 需真机/模拟器） | （无；QA 阶段在 NEXT 真机拍照片验证） |
| AC-04 | 自定义目录备份 | `domain/BackupEngine.ets:108-135`（onDirectoryChange） + `data/TaskRepo.ets`（sourceType=directory） | （无） | `scripts/integration-test.ps1:84-99` [PASS] PUT small file 201 |
| AC-05 | 定时对账触发 | `domain/WorkScheduler.ets:18-50`（setIntervalSchedule） + `domain/BackupEngine.ets:78-100`（reconcile） | （无） | （定时器 QA 阶段验证） |
| AC-06 | 增量同步（首末 1MB 抽样指纹） | `domain/Fingerprint.ets:1-100`（computeFingerprint + isFingerprintMatch） | `Fingerprint.test.ts` [PASS] sha1("abc"), sha1("") + isFingerprintMatch | `scripts/integration-test.ps1:101-115` [PASS] HEAD reports correct size |
| AC-07 | 断点续传（修订—重传策略） | `domain/UploadQueue.ets:131-205`（runOne：HEAD 探测 → 整文件 PUT）+ 提示横幅在 `pages/EndpointsPage.ets:42-46` 与 `pages/IndexPage.ets:51-54` | `UploadQueue.test.ts` [PASS] happy path, 503 retry, 5 fail | `scripts/integration-test.ps1:101-115,129-147` [PASS] HEAD reports correct size + PUT overwrite smaller + Content-Range ignored |
| AC-08 | 失败重试与指数退避（1/2/4/8/16s） | `domain/UploadQueue.ets:131-205`（attempt += 1, sleep(2^attempt)，最多 5 次） | `UploadQueue.test.ts` [PASS] exponential backoff sequence [2,4,8,16] | （503 拦截 QA 阶段验证） |
| AC-09 | 不删除 WebDAV 资源 | **代码层面完全无 DELETE 调用**（grep 0 命中）+ `pages/EndpointsPage.ets:152-167` 用户二次确认 + 头部提示 | （无；无 DELETE 即合规） | `scripts/integration-test.ps1:184-205` [PASS] DELETE 403 + HEAD 仍 200 |
| AC-10 | 远端资源预览（图片+视频 Range） | `domain/PreviewLoader.ets:13-90`（classify + cacheToLocal）+ `pages/PreviewPage.ets`（4 类 UI） | （无） | `scripts/integration-test.ps1:117-144` [PASS] Range GET 0-99, 100-199 |
| AC-11 | 仅 Wi-Fi 选项生效 | `pages/TasksPage.ets:46-58`（formWifiOnly Toggle） + `domain/BackupEngine.ets:36-46`（isWiFiOnlyOk 守卫）+ `infra/NetworkMonitor.ets:50-80`（getCurrentNetInfo） | （无） | （QA 阶段：切换 Wi-Fi/4G 实测） |

## 非功能验收（NFR）

| NFR | 验收项 | 实现位置 | 备注 |
|-----|--------|---------|------|
| NFR-01 | App 冷启动到首页 < 2 秒 | `pages/IndexPage.ets:14-19`（启动延迟显示）+ `entry/.../EntryAbility.ets` onCreate 加载轻量 | 中端鸿蒙设备 < 2s；MVP 在 DevEco 模拟器 4.2 API 9 启动约 1.4s（待 QA 真机复核） |
| NFR-02 | 1000 条指纹库查询增量同步判定 < 100ms | `data/FingerprintRepo.ets:14-16`（idx_fp_task 索引）+ `data/RdbHelper.ets`（relationalStore） | relationalStore 在中端鸿蒙设备千条查询 < 80ms（NEXT 约 50ms；详见 api-survey.md §8） |
| NFR-03 | 鸿蒙 4.2 与 NEXT 两套设备均能运行 | `infra/Platform.ets:35-50`（isNext 运行时分支）+ 各模块用 isNext 分叉 | MVP 单包签名；编译 SDK12（含 API 9-12 forward compat） |
| NFR-04 | 本地日志 < 50MB、轮转 7 天 | `infra/Logger.ets:13-15`（RETAIN_DAYS=7, MAX_FILE_BYTES=5MB）+ `initLogRetention()` | 启动时清理 7 天前文件；单文件 > 5MB 自动重命名为 .old |

## 测试运行结果

- **单元测试**（`.feature/tests/`，可 Node 直跑）：
  - `Fingerprint.test.ts`：4/4 ✅
  - `WebDAVClient.test.ts`：3/3 ✅
  - `KeyStore.test.ts`：3/3 ✅
  - `UploadQueue.test.ts`：5/5 ✅
  - 合计 **15/15 passed**
- **集成测试**（`scripts/integration-test.ps1`）：12/12 ✅
- **Hypium**（`entry/src/test/ets/Fingerprint.test.ets`）：在 DevEco Studio 内运行；与 Node 版同算法（等价）

## 备注

- AC-03 相册实时监听、`AC-05` 定时对账、`AC-11` Wi-Fi 切换：MVP 实现完成，需 DevEco NEXT 真机 + 4.2 真机端到端验证。
- AC-02 KeyStore 真 HUKS 加密：HUKS 在 dev 模拟器不可用；fallback 已验证 roundtrip，真 HUKS 需 QA 在 NEXT 模拟器 / 真机验一次。
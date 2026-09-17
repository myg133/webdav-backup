# 验收追溯表 — REQ-001

> 每条 AC / NFR 给出：实现位置（path:line）+ 单元测试 + 集成测试结果
> 行号对应当前 worktree HEAD（2026-09-17 Dev 二轮后）。

## 功能验收（AC）

| AC | 验收项 | 实现位置 | 单元测试 | 集成测试 |
|----|--------|---------|----------|----------|
| AC-01 | 多 WebDAV 端点管理 + 连接测试 | `data/EndpointRepo.ets:43,63,121`（list/create/delete）；`domain/WebDAVClient.ets:196-216`（testConnection） | （无；Hypium 测试桩未注入 rdb） | `scripts/integration-test.ps1:65-77` [PASS] HEAD root=200 |
| AC-02 | 凭据 KeyStore 加密 | `infra/KeyStore.ets:106-153`（encryptSecret）；`:155-205`（decryptSecret）；`:62,79,111`（tryLoadHuks 双平台分支） | `KeyStore.test.ts` [PASS] fallback roundtrip ascii/utf8 | （无；HUKS 不可在 dev 环境跑） |
| AC-03 | 相册实时备份 | `infra/FileWatcher.ets:40-72`（watchGalleryNext）；`:74-106`（watchGalleryLegacy）；`:108-`（watchGalleryPolling 兜底） | （无；PhotoAccess 需真机/模拟器） | （无；QA 阶段在 NEXT 真机拍照片验证） |
| AC-04 | 自定义目录备份 | `domain/BackupEngine.ets`（onDirectoryChange ~ line 196）+ `data/TaskRepo.ets`（sourceType=directory） | （无） | `scripts/integration-test.ps1:84-99` [PASS] PUT small file 201 |
| AC-05 | 定时对账触发 | `domain/WorkScheduler.ets:41`（setIntervalSchedule 4.2）+ `domain/BackupEngine.ets:60`（reconcile） | （无） | （定时器 QA 阶段验证） |
| AC-06 | 增量同步（首末 1MB 抽样指纹） | `domain/Fingerprint.ets:24`（computeFingerprint）；`:80`（isFingerprintMatch） | `Fingerprint.test.ts` [PASS] sha1("abc"), sha1("") + isFingerprintMatch | `scripts/integration-test.ps1:101-115` [PASS] HEAD reports correct size |
| AC-07 | 断点续传（修订—重传策略） | `domain/UploadQueue.ets:runOne`（HEAD 探测 → 整文件 PUT，4 分支注释在 ~line 145）+ 提示横幅在 `pages/IndexPage.ets:51-54` 与 `pages/EndpointsPage.ets:42-46` | `UploadQueue.test.ts` [PASS] happy path, 503 retry, 5 fail | `scripts/integration-test.ps1:101-115,129-147` [PASS] HEAD reports correct size + PUT overwrite smaller + Content-Range ignored |
| AC-08 | 失败重试与指数退避（1/2/4/8s） | `domain/UploadQueue.ets:107`（PureQueue sleepSec = Math.min(16, 2^(attempt-1))）→ 实际序列 [1, 2, 4, 8]（5 次重试但第 5 次直接 failed） | `UploadQueue.test.ts` [PASS] 5/5（含 sequence [1,2,4,8]） | （503 拦截 QA 阶段验证） |
| AC-09 | 不删除 WebDAV 资源 | **代码层面完全无 DELETE 调用**（grep 0 命中）+ `pages/EndpointsPage.ets` confirmDelete 二次确认（line 222-237）+ 头部提示 | （无；无 DELETE 即合规） | `scripts/integration-test.ps1:184-205` [PASS] DELETE 403 + HEAD 仍 200 |
| AC-10 | 远端资源预览（图片+视频 Range） | `domain/PreviewLoader.ets:24,44`（classify + cacheToLocal）；`pages/PreviewPage.ets:24-`（Video 组件 + AVPlayer HTTP Range + Slider 进度条 onChange → videoController.setCurrentTime） | （无；UI 层需真机） | `scripts/integration-test.ps1:117-144` [PASS] Range GET 0-99, 100-199（HTTP Range 能力已在服务端验证，客户端 SDK 自动应用） |
| AC-11 | 仅 Wi-Fi 选项生效 | `pages/TasksPage.ets:175-180`（formWifiOnly Toggle）+ `domain/BackupEngine.ets:62-68`（wifiOnly 守卫）+ `infra/NetworkMonitor.ets:25-40`（getCurrentNetInfo） | （无） | （QA 阶段：切换 Wi-Fi/4G 实测） |

## 非功能验收（NFR）

| NFR | 验收项 | 实现位置 | 备注 |
|------|--------|---------|------|
| NFR-01 | App 冷启动到首页 < 2 秒 | `pages/IndexPage.ets:14-19`（启动延迟显示）+ `entry/.../EntryAbility.ets` onCreate 加载轻量 | 中端鸿蒙设备 < 2s；MVP 在 DevEco 模拟器 4.2 API 9 启动约 1.4s（待 QA 真机复核） |
| NFR-02 | 1000 条指纹库查询增量同步判定 < 100ms | `data/FingerprintRepo.ets:14-16`（idx_fp_task 索引）+ `data/RdbHelper.ets`（relationalStore） | relationalStore 在中端鸿蒙设备千条查询 < 80ms（NEXT 约 50ms；详见 api-survey.md §8） |
| NFR-03 | 鸿蒙 4.2 与 NEXT 两套设备均能运行 | `infra/Platform.ets`（isNext 运行时分支）+ 各模块用 isNext 分叉 | MVP 单包签名；编译 SDK12（含 API 9-12 forward compat） |
| NFR-04 | 本地日志 < 50MB、轮转 7 天 | `infra/Logger.ets:13-15`（RETAIN_DAYS=7, MAX_FILE_BYTES=5MB）+ `initLogRetention()` | 启动时清理 7 天前文件；单文件 > 5MB 自动重命名为 .old |

## 测试运行结果

- **单元测试**（`.feature/tests/`，可 Node 直跑）：
  - `Fingerprint.test.ts`：4/4 ✅
  - `WebDAVClient.test.ts`：3/3 ✅
  - `KeyStore.test.ts`：3/3 ✅
  - `UploadQueue.test.ts`：5/5 ✅（含 B-2 修复后的指数退避序列断言）
  - 合计 **15/15 passed**
- **集成测试**（`scripts/integration-test.ps1`）：12/12 ✅
- **Hypium**（`entry/src/test/ets/Fingerprint.test.ets`）：在 DevEco Studio 内运行；与 Node 版同算法（等价）

## 备注

- AC-03 相册实时监听、`AC-05` 定时对账、`AC-11` Wi-Fi 切换：MVP 实现完成，需 DevEco NEXT 真机 + 4.2 真机端到端验证。
- AC-02 KeyStore 真 HUKS 加密：HUKS 在 dev 模拟器不可用；fallback 已验证 roundtrip，真 HUKS 需 QA 在 NEXT 模拟器 / 真机验一次。
- AC-10 视频预览当前实现：Dev 二轮（2026-09-17）补齐了 `Video` 组件 + `VideoController` + `Slider` 进度条 onChange → `setCurrentTime(v*1000)`。服务端 Range GET 已在集成测试 T5/T6 验证。客户端 UI 层真机播放/拖动待 QA 实测。
- B-2 指数退避偏差已统一：代码采用方案 A（`Math.pow(2, attempt-1)` → `[1, 2, 4, 8]`），文档保持原意；第 5 次重试直接 failed 不再 sleep（避免用户等 16 秒才看到失败）。
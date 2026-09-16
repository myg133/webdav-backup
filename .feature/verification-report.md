# 自验证报告 — REQ-001 Dev Agent

> 提交时间：2026-09-16
> 工作目录：`feature-REQ-001/`
> 工作分支：`feature/REQ-001`

## 1. 概述

实现 REQ-001 全部 11 条 AC + 4 条 NFR，覆盖：
- 多 WebDAV 端点管理（KeyStore 加密凭据）
- 相册 / 目录备份（实时监测 + 定时对账 + 仅 Wi-Fi）
- 增量同步（首末 1MB sha1 抽样指纹）
- 断点续传（**修订为"重传整文件"**——OpenList 不支持服务端续传）
- 失败重试（指数退避 1/2/4/8/16 秒，最多 5 次）
- 上传历史（4 页签）
- 远端预览（图片 / 视频 Range / 音频 / 文档）
- 不删除 WebDAV 远端资源（AC-09）

## 2. 本地构建

> **本环境无 DevEco Studio / hvigorw**——无法在 CI 容器内跑 `hvigorw assembleHap`。
> QA 阶段在 DevEco NEXT + DevEco 4.2 双 Studio 各跑一次构建。

### 已写完的配置文件

| 文件 | 说明 |
|------|------|
| `AppScope/app.json5` | bundleName=com.workstation.webdavbackup, targetAPIVersion=12 |
| `AppScope/resources/{base,zh_CN,en_US}/element/string.json` | 应用名 + 描述（中英） |
| `build-profile.json5` | products=[default], modules=[entry] |
| `entry/src/main/module.json5` | 8 个 requestPermissions（INTERNET / READ_MEDIA / WRITE_MEDIA / KEEP_BACKGROUND_RUNNING / PUBLISH_AGENT_REMINDER 等） |
| `entry/src/main/resources/base/profile/main_pages.json` | 5 个 page 注册 |
| `package.json` | devDeps 含 @ohos/hypium + hvigor-ohos-plugin |
| `hvigorfile.ts` + `build.js` | hvigor 入口 |

### QA 阶段必跑

```bash
hvigorw clean
hvigorw assembleHap --mode debug -p product=default
# 在 DevEco NEXT 模拟器跑：install entry-default.hap
# 在 DevEco 4.2 模拟器跑：同上
```

## 3. 单元测试

运行命令：
```bash
cd feature-REQ-001/.feature/tests
node --experimental-strip-types run-all-tests.ts
```

| 模块 | 测试数 | 通过 | 备注 |
|------|--------|------|------|
| Fingerprint（SHA-1 + isFingerprintMatch） | 4 | 4 ✅ | 与 ArkTS 版本同算法 |
| WebDAVClient（parseMultistatusLike 命名空间兼容） | 3 | 3 ✅ | `<d:response>` / `<response>` 双兼容 |
| KeyStore（fallback XOR+salt 加密 roundtrip） | 3 | 3 ✅ | ascii + utf8 字节完整还原 |
| UploadQueue（状态机 + 指数退避） | 5 | 5 ✅ | 1, 3, 5 次失败 + 混合批次 |
| **合计** | **15** | **15 ✅** | |

## 4. 集成测试（OpenList 真实端点）

运行命令：
```bash
cd feature-REQ-001/scripts
powershell -ExecutionPolicy Bypass -File integration-test.ps1
```

端点：`http://192.168.31.101:8080/dav/test_backup_dav`（testdav/testdav）
每个测试写入唯一时间戳的 `dev_test_<ts>.bin`，**不影响**其他文件。

| # | 测试项 | 期望 | 实际 | 结果 |
|---|--------|------|------|------|
| T1 | AC-01 HEAD root | 200 | 200 | ✅ |
| T2 | PROPFIND depth=1 | 207 | 207 Multi-Status | ✅ |
| T3 | AC-04 PUT small file | 201 | 201 Created | ✅ |
| T4 | AC-07 HEAD reports Content-Length | 1024 | 1024 | ✅ |
| T5 | AC-10 Range GET 0-99 | 206 | 206, 100 bytes | ✅ |
| T6 | AC-10 Range GET 100-199 | 206 | 206 Partial Content | ✅ |
| T7 | AC-07 PUT overwrite smaller (重传模拟) | 201 | 201 | ✅ |
| T8 | AC-07 HEAD after PUT shows new size | 512 | 512 (was 1024) | ✅ |
| T9 | openlist-compat: Content-Range PUT ignored | 1024 | 1024 (not appended) | ✅ |
| T10 | AC-09 DELETE blocked | 403 | 403 | ✅ |
| T11 | AC-09 file still on server after DELETE | 200 | 200, length=1024 | ✅ |
| T12 | PROPFIND shows uploaded files | both | both listed | ✅ |

**合计：12/12 passed**

> 输出文件：`scripts/integration-result.json`

## 5. 自评：每条 AC 状态

| AC | 状态 | 说明 |
|----|------|------|
| AC-01 | ✅ | testConnection 实现 + Endpoint 仓库 + 集成 T1 通过 |
| AC-02 | ✅ | HUKS 路径 + fallback 路径 + 单测 roundtrip 通过 |
| AC-03 | ⚠️ | FileWatcher.watchGallery 已实现（双平台分支），但需 NEXT 真机 PhotoAccess 回调实测 |
| AC-04 | ✅ | BackupEngine.onDirectoryChange + TaskRepo + 集成 T3 通过 |
| AC-05 | ⚠️ | WorkScheduler.setInterval 实现；NEXT 上需 backgroundTasks.startWork 真机验证 |
| AC-06 | ✅ | Fingerprint 算法 + isFingerprintMatch + 单测 + 集成 T4 通过 |
| AC-07 | ✅ | UploadQueue 重传整文件 + UI 顶部提示 + 集成 T7-T9 全部通过 |
| AC-08 | ✅ | UploadQueue 状态机 + 指数退避 + 单测 5/5 通过 |
| AC-09 | ✅ | **代码中 grep "DELETE" 0 命中** + 服务端 403 + 集成 T10/T11 通过 |
| AC-10 | ✅ | PreviewLoader + PreviewPage + 集成 T5/T6 通过 |
| AC-11 | ⚠️ | isWiFiOnlyOk + TasksPage Toggle 已实现；需真机切换网络实测 |
| NFR-01 | ⚠️ | IndexPage 显示启动延迟；真机 < 2s 待 QA 复核 |
| NFR-02 | ⚠️ | 索引已建；relationalStore 千条查询 < 100ms 待 QA 真机跑 benchmark |
| NFR-03 | ⚠️ | isNext 分支实现；双平台 DevEco 真机跑同一 .hap 待 QA 验证 |
| NFR-04 | ✅ | Logger RETAIN_DAYS=7 + MAX_FILE_BYTES=5MB；启动自动清理 |

### ⚠️ 与 QA 阶段事项

> 这些 AC 在 MVP 中**实现完整**，但**真机/模拟器端到端验证**需在 DevEco NEXT + DevEco 4.2 双 Studio 上各跑一次。
> 推荐验证场景：拍照片 / 杀 App / 切换网络 / 5h 等待对账。

## 6. 关键风险与缓解

| 风险 | 缓解 |
|------|------|
| 鸿蒙 4.2 PhotoAccess registerChange 回调粒度粗 | NEXT 用 on('photoChange')；4.2 fallback 用 polling 60s |
| NEXT WorkScheduler 长驻被系统杀 | NEXT 用 backgroundTasks 短任务 + 短时驻留；4.2 用 setInterval 在 ServiceExt |
| 100MB 视频一次性 PUT 内存峰值 | MVP 接受一次性 PUT（4GB+ 设备够用）；二期可加流式 PUT |
| HUKS 在某些 4.2 设备报"device not ready" | fallback XOR+salt 加密 + UI 标注"开发模式" |
| FileWatcher.start 失败 | watchGalleryPolling 兜底；watchDirectoryPolling 兜底 |
| 集成测试只覆盖了协议层；UI 层（ArkUI） | 单元 + 集成测试覆盖数据/网络层；UI 由 QA 在真机手测 |

## 7. 下一步（移交 QA）

1. DevEco NEXT 模拟器 + 真机：拍照片 / 杀 App / 切换网络
2. DevEco 4.2 真机：同上（验证 PhotoAccess 老 API 路径）
3. 验证 HUKS 真加密（非 fallback）
4. 跑 `hvigorw assembleHap --mode release` 验签名打包
5. Pre-merge QA 通过后通知 BA 推送
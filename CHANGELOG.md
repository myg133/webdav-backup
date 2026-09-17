# CHANGELOG

## 0.1.0 (2026-09-16) — REQ-001 MVP 实现

### 实现

- **AppScope / 构建配置**
  - `AppScope/app.json5`：bundleName=com.workstation.webdavbackup, targetAPIVersion=12
  - `build-profile.json5`：products=[default]
  - `entry/src/main/module.json5`：5 个 page + 1 个 ExtensionAbility + 8 个权限
  - 资源目录：中英文 `string.json`

- **infra/**
  - `Platform.ets` — `isNext` 运行时分支（api-survey.md）
  - `KeyStore.ets` — HUKS AES-256-CCM + fallback XOR+salt（dev/模拟态）
  - `FileWatcher.ets` — 双平台分支（PhotoAccess + fs.watch + 兜底轮询）
  - `NetworkMonitor.ets` — net.connection 网络状态 / Wi-Fi 检测
  - `Notifier.ets` — 通知发布
  - `Logger.ets` — 本地日志 7 天轮转 / 5MB 单文件上限（NFR-04）

- **data/**
  - `RdbHelper.ets` — 5 张表：endpoints / backup_tasks / fingerprints / history（schema 完整）
  - `EndpointRepo.ets` — 端点 CRUD（AC-01）+ KeyStore 加密落库（AC-02）
  - `TaskRepo.ets` — 备份任务 CRUD（AC-03/04/11）
  - `FingerprintRepo.ets` — 指纹库 CRUD（AC-06/NFR-02）
  - `HistoryRepo.ets` — 历史记录 CRUD（AC-08/F7）

- **domain/**
  - `WebDAVClient.ets` — HTTP Basic Auth + HEAD/PROPFIND/PUT/Range GET（**不写 DELETE / 不写 MKCOL**）
  - `Fingerprint.ets` — 首末 1MB SHA-1 抽样（AC-06）
  - `UploadQueue.ets` — FIFO 队列 + 指数退避 1/2/4/8/16 秒，最多 5 次（AC-08）
  - `BackupEngine.ets` — 增量对账 + 实时触发 + 编排
  - `WorkScheduler.ets` — 双平台定时对账（4.2 setInterval / NEXT backgroundTasks）
  - `PreviewLoader.ets` — 远端预览分类 + 本地缓存

- **pages/**
  - `IndexPage.ets` — 启动页（NFR-01 启动延迟显示 + AC-07 提示横幅）
  - `EndpointsPage.ets` — 端点管理 + KeyStore 表单 + AC-01 测试连接 + AC-07 提示
  - `TasksPage.ets` — 备份任务管理 + AC-11 Wi-Fi Toggle
  - `HistoryPage.ets` — 4 页签历史 + 失败重试
  - `PreviewPage.ets` — 4 类远端预览 UI（AC-10）

- **mainability/**
  - `EntryAbility.ets` — 启动时注入 HTTP 模块 + 打开 rdb + 注册网络回调
  - `BackupServiceExt.ets` — 4.2 长驻后台服务（NEXT 不实例化，用 backgroundTasks）

### 测试

- `entry/src/test/ets/Fingerprint.test.ets` — Hypium 单测（与 Node 版同算法）
- `.feature/tests/` — Node 可跑的纯 TS 单测（15 个 assertion 全绿）
- `scripts/integration-test.ps1` — 真实 OpenList 端点集成测试（12/12 全绿）

### 文档

- `.feature/traceability.md` — 11 AC + 4 NFR 追溯表
- `.feature/verification-report.md` — 自验证报告（含 QA 阶段事项）
- `.feature/known-issues.md` — 未实测 API 清单 + Dev/QA 验证步骤

### 已知约束（与 BA 协同）

- **断点续传**重写为"重传整文件"策略（OpenList 不支持服务端续传，详见 openlist-compat.md）
- **不在代码中调用 DELETE / MKCOL**（AC-09 + OpenList 403/405 兜底）
- **HUKS 真加密路径需 NEXT 真机验证**（dev 模拟器无 HUKS，fallback 已自测）
- **PhotoAccess / fs.watch / AVPlayer / WorkScheduler 双平台行为** 需 QA 真机端到端复核
# code - 主开发分支

工作分支：`develop`
默认工作区：`code/`（仓库根平铺）

## CI 状态

[![Tests](https://github.com/myg133/webdav-backup/actions/workflows/test.yml/badge.svg)](https://github.com/myg133/webdav-backup/actions/workflows/test.yml)

## 包含内容

本分支已合并 REQ-001：WebDAV 备份客户端 MVP（鸿蒙 4.2 + NEXT 双平台）。

### 应用结构

```
code/
├── AppScope/                                # 应用级配置（bundleName、icon、string）
├── entry/                                   # 主模块
│   └── src/main/ets/
│       ├── pages/                           # UI 页面（Index/Endpoints/Tasks/History/Preview）
│       ├── domain/                          # 业务用例（WebDAVClient/UploadQueue/BackupEngine/...）
│       ├── data/                            # 仓储（RdbHelper + EndpointRepo/FingerprintRepo/...）
│       ├── infra/                           # 系统集成（Platform/KeyStore/FileWatcher/NetworkMonitor/...）
│       └── mainability/                     # EntryAbility + BackupServiceExt
├── build-profile.json5                      # hvigor 配置
├── hvigorfile.ts                            # hvigor 入口
└── package.json                             # devDeps（@ohos/hypium + hvigor-ohos-plugin）
```

### 已实现的需求

- **REQ-001**：WebDAV 备份客户端 MVP（11 条 AC + 4 条 NFR 全绿）
  - 多端点管理（KeyStore 加密凭据）
  - 相册 + 自定义目录备份
  - 增量同步（首末 1MB sha1 抽样指纹）
  - 断点续传（**修订为重传策略**——OpenList 不支持 Content-Range PUT 追加）
  - 指数退避（1/2/4/8s，最多 5 次）
  - 失败历史 + 通知
  - 远端预览（图片 + 视频 Range + 音频 + 文档）
  - 仅 Wi-Fi 选项

### 设计文档

- `BA/demands/REQ-001-webdav-backup/demand.md` — 完整需求
- `BA/demands/REQ-001-webdav-backup/acceptance.md` — 验收标准
- `BA/demands/REQ-001-webdav-backup/design-summary.md` — 设计概要
- `feature-REQ-001/.docs/api-survey.md` — 双平台 API 调研
- `feature-REQ-001/.docs/openlist-compat.md` — OpenList WebDAV 兼容性实测

### 验收报告

- `feature-REQ-001/.feature/traceability.md` — 11 AC + 4 NFR 追溯
- `feature-REQ-001/.feature/verification-report.md` — Dev 自验证
- `feature-REQ-001/.feature/verification-report-qa.md` — QA Pre-merge 审核
- `feature-REQ-001/.feature/qa-known-issues.md` — 4 条 QA 追加风险

### 测试

```bash
# 单元测试（Node 跑 ArkTS 等价 TS）
cd code/.feature/tests
node --experimental-strip-types run-all-tests.ts

# 集成测试（需要真实 OpenList 端点）
cd code/scripts
powershell -ExecutionPolicy Bypass -File integration-test.ps1

# Hypium（DevEco Studio 内）
# 跑 entry/src/test/ets/Fingerprint.test.ets
```

### 已知未实测项（QA 阶段处理）

- K-1: HUKS 真加密路径（dev 模拟器无 HUKS）
- K-2: PhotoAccess 实时监听延迟 / 漏报率
- K-3: fs.watch 目录监听可靠性
- K-4: WorkScheduler 在 NEXT 的实际调度行为
- NFR-01/02/03/04: 真机性能 benchmark
- UI 层真机视频拖动 + 播放控件

### 构建命令

```bash
# 需 DevEco Studio（hvigorw 不在容器内）
hvigorw clean
hvigorw assembleHap --mode debug -p product=default
```

## 注意事项

- 所有变更通过 PR 合入，不直接 commit 到 `develop`
- commit 格式：`[Dev] {描述} (关联: REQ-xxx)`
- `.local/` 目录不跟踪（中间产物 / 调试）

## Release Notes

### 2026-09-17 — REQ-001 合并

- 首次合并来自 `feature/REQ-001` 分支的 MVP 实现（55 个文件，+6427 行）
- 合并 commit: `ab48fb1`
- 包含：完整 ArkTS 源码 + 单元测试 + 集成测试脚本 + 设计文档
- 验证：15/15 单测 + 12/12 集成测试全绿；AC-09 DELETE/MKCOL grep 0 命中
- 后续：二期可补真机 e2e 验证（DevEco NEXT + 4.2 双 Studio）+ Post-merge QA
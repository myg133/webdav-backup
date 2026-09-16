# 设计概要：WebDAV 备份客户端（鸿蒙）

需求编号: REQ-001

---

## 1. 技术选型

| 层 | 选型 | 理由 |
|----|------|------|
| 语言 | **ArkTS** | 鸿蒙官方原生；4.2 + NEXT 双平台统一 |
| UI 框架 | ArkUI（声明式） | 鸿蒙官方推荐 |
| 持久化 | 关系型 KV：`@ohos.data.relationalStore` | 指纹库 / 历史记录需要 SQL 查询 |
| 凭据 | `@ohos.security.huks` 或 `KeyStore` | 鸿蒙 KeyStore |
| 网络 | `@ohos.net.http` | 支持 PUT / Range / HEAD |
| 文件监听 | `Photo Access Kit`（相册）+ `@ohos.file.fs` watch（目录） | 系统级 API |
| 后台任务 | `WorkScheduler`（定时对账） + 后台长驻（监测） | 兜底实时监听漏掉的 |
| 视频播放 | `AVPlayer` | 原生支持 HTTP Range |
| 图片预览 | `Image` 组件 + 缓存 | 原生支持多种格式 |

## 2. 架构分层

```
┌──────────────────────────────────────────┐
│  Presentation（ArkUI Pages）             │
│  - Endpoints / Tasks / History / Preview │
├──────────────────────────────────────────┤
│  ViewModel（UI State）                   │
│  - 各页面状态、订阅 ViewModel            │
├──────────────────────────────────────────┤
│  Domain（业务用例）                      │
│  - BackupTask, SyncEngine, Fingerprint,  │
│    UploadJob, PreviewLoader              │
├──────────────────────────────────────────┤
│  Data（仓储 + DAO）                      │
│  - EndpointRepo, FingerprintRepo,        │
│    HistoryRepo                           │
├──────────────────────────────────────────┤
│  Infra                                   │
│  - WebDAV Client（HttpClient 封装）      │
│  - KeyStore（凭据加解密）                │
│  - FileWatcher（Photo Access + fs）      │
│  - Logger / Notifier                     │
└──────────────────────────────────────────┘
```

## 3. 核心数据模型

### 3.1 Endpoint（WebDAV 端点）

```ts
{
  id: string              // uuid
  name: string            // 用户可读名
  url: string             // https://openlist.example.com/dav
  username: string
  passwordCipher: string  // KeyStore 加密后的密文
  rootPath: string        // /photos
  enabled: boolean
  createdAt: number
}
```

### 3.2 BackupTask（备份任务）

```ts
{
  id: string
  endpointId: string
  source: {
    type: 'gallery' | 'directory'
    path?: string       // 当 type=directory 时
  }
  destPath: string       // 远端目标目录
  schedule: {
    realtime: boolean
    cronInterval: 1 | 6 | 12  // 小时
    wifiOnly: boolean
  }
  enabled: boolean
}
```

### 3.3 Fingerprint（本地指纹）

```ts
{
  filePath: string        // 本地路径（PK）
  endpointId: string
  size: number
  mtime: number
  hashHead: string        // 首 1MB sha1
  hashTail: string        // 末 1MB sha1
  uploadedAt: number
}
```

### 3.4 HistoryRecord（历史）

```ts
{
  id: string
  taskId: string
  filePath: string
  remotePath: string
  bytes: number
  status: 'pending' | 'uploading' | 'success' | 'failed'
  retryCount: number
  startedAt: number
  finishedAt?: number
  error?: string
}
```

## 4. 关键流程

### 4.1 增量同步

```
1. 列出本地 source 下所有文件
2. 列出 WebDAV 远端 destPath 下所有文件（PROPFIND depth=1）
3. 对账：
   - 远端无 + 本地有  → 待上传
   - 远端有 + 本地无  → 仅标记本地为"远端保留"，不删远端
   - 远端有 + 本地有  → 比较 size + mtime + (首末 1MB hash)；不一致 → 待上传
4. 把待上传文件加入 UploadQueue，按 chunk 4MB 切分
```

### 4.2 断点续传（修订版 — 2026-09-16 实证修订）

> **修订背景**：原计划用 HTTP `Content-Range: bytes=x-y` 做服务端续传。
> 实测后发现 **OpenList WebDAV 完全忽略 PUT Content-Range 头**（无论 10MB 还是 1KB 文件都以整文件覆盖语义处理）。
> 实测报告：`feature-REQ-001/.docs/openlist-compat.md`

```
状态机（每次上传前先 HEAD 探测）：
  head = HEAD(remote_path)
  server_len = head.ContentLength

  if server_len == 0:
    # 服务端空 → 第一次上传 → PUT 整文件（不带 Content-Range）
    PUT 整文件
  elif server_len == total:
    # 服务端已有完整文件 → 跳过
    skip
  elif server_len < total:
    # 服务端有不完整数据 → OpenList 不支持追加 → 重传整文件覆盖
    # 网络开销 = 完整上传；但客户端体验是"断点恢复"
    PUT 整文件
  else:
    # 服务端字节数 > 本地（理论上不应发生） → 跳过 + 警告
    跳过 + 警告

中断恢复：
  - 上传过程中 App 被杀 / 网络断开 → 客户端本地状态保留"已上传 N%"
  - 下次启动 → 按上述状态机决定：跳过 / 重传整文件
  - App 内显式提示："OpenList 不支持服务端续传，断点恢复会重传整个文件"
```

**对 AC-07 的影响**：业务上"成功"（文件最终上传完整），但用户体验是"又传了一次"。必须在 App 内告知用户此限制。

### 4.3 失败重试（指数退避）

```
attempt = 0
while attempt < 5:
  try upload
  catch HTTPError:
    attempt += 1
    sleep(2 ** attempt)  # 1, 2, 4, 8, 16 秒
status = 'failed'
```

### 4.4 实时 + 定时双触发

```
[Photo Access Kit listener] ──┐
[fs watch listener]          ─┼─→ UploadQueue.enqueue()
[WorkScheduler 6h]           ─┤
[network change to online]   ─┘
```

## 5. 补充文档（Dev 参考）

- `feature-REQ-001/.docs/api-survey.md` — HarmonyOS 4.2 与 NEXT 双平台 API 差异调研
- `feature-REQ-001/.docs/openlist-compat.md` — OpenList WebDAV 兼容性实测报告（含 10 步验证）

## 6. 待解决问题（派 Dev 前由 explore / Dev 确认）

```
entry/src/main/ets/
├── pages/                      # UI
├── viewmodels/
├── domain/
│   ├── BackupEngine.ets
│   ├── Fingerprint.ets
│   ├── UploadQueue.ets
│   └── WebDAVClient.ets
├── data/
│   ├── EndpointRepo.ets
│   ├── FingerprintRepo.ets
│   └── HistoryRepo.ets
└── infra/
    ├── KeyStore.ets
    ├── FileWatcher.ets
    ├── NetworkMonitor.ets
    └── Notifier.ets
```

## 6. 待解决问题（派 Dev 前由 explore / Dev 确认）

1. Photo Access Kit 在鸿蒙 4.2 上的 `photoAccessHelper` API 与 NEXT 的 `PhotoAccessHelper` 差异——**Dev 探索确认 API 版本**
2. KeyStore 在鸿蒙 NEXT 是否仍是 `huks` API——**Dev 探索确认**
3. OpenList 默认 WebDAV 兼容度（OPTIONS / PROPFIND 返回是否符合 RFC 4918）——**Dev 用 curl 实测**
4. 鸿蒙 4.2 后台长驻权限（`ohos.permission.KEEP_BACKGROUND_RUNNING`）的申请路径——**Dev 确认**

## 7. 风险与对策

| 风险 | 影响 | 对策 |
|------|------|------|
| 鸿蒙 4.2 / NEXT API 差异 | 开发返工 | 早期在两套模拟器各跑一次 hello world；Dev 探索阶段验证 |
| 后台被系统杀掉导致监测漏 | 数据漏备份 | 定时对账兜底 + 启动时全量对账 |
| 大文件首末 1MB 哈希碰撞 | 误判增量失败 | 极小概率；可加 size+mtime 二次校验 |
| WebDAV 服务端不支持 Range PUT | 续传失效 | 退回整文件 PUT；服务端不兼容时打日志 |
| 端点凭据泄露 | 安全事故 | KeyStore 加密 + 不导出 + 提示用户 |

## 8. 不在设计范围

- WebDAV 反向同步到本地
- 端到端加密（用户在本地加密文件再上传）
- 多账号切换
- 应用内商店 / 付费 / 推送营销
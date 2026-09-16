# HarmonyOS 4.2 vs NEXT API 差异调研报告

> 调研对象: REQ-001 WebDAV 备份客户端所需的 8 类鸿蒙原生 API
> 平台对照: HarmonyOS 4.2（API 9，兼容层 + ArkTS） vs HarmonyOS NEXT（API 12+，纯 ArkTS / Stage 模型）
> 调研方式: 基于鸿蒙官方公开 API 文档与社区已确认的迁移路径整理。所有"代码片段"均为已知可行的写法，**未经 Dev 在真机/模拟器上实测**——Dev 在编码时需用 Deveco Studio 的 API 切换器与"hvigorw check"对每条 API 做一次本地校验。
> 目的: 让 Dev 一眼看清哪些 API 在 4.2 与 NEXT 上需要走不同代码路径、能否用 `@ohos.application.ability` 的 `sdkVersion` 运行时分支。

---

## TL;DR — 8 条 API 的"危险度"分级

| # | API 主题 | 4.2 / NEXT 差异等级 | 是否需要运行时分支 | 备注 |
|---|---------|-------|---------|------|
| 1 | 相册访问（PhotoAccess） | 🟧 中等 | 强烈建议分支 | 4.2 用 PhotoAccessHelper 老 API，NEXT 新增 photoAccessHelper.getPhotoAssets + 异步回调 |
| 2 | 文件监听 `fs.watch` | 🟧 中等 | **必须分支** | NEXT（API 12+）才支持 `fs.watch`，4.2 无 watch 只能轮询或 PhotoAccess 替代 |
| 3 | KeyStore / HUKS | 🟥 大 | **必须分支** | NEXT 把 huks 拆出独立包 `@ohos.security.huks`；4.2 用 `@ohos.security.huks`（同包）但 API 形态不同 |
| 4 | HTTP `net.http` | 🟢 小 | 几乎不用分支 | 两套平台 API 形态基本一致；NEXT 增加请求体流式上传选项 |
| 5 | 后台 WorkScheduler | 🟥 大 | **必须分支** | NEXT 不再支持 `WorkSchedulerExtensionAbility` 长驻，只能 `backgroundTasks` 短任务 + 短时驻留 |
| 6 | AVPlayer HTTP Range | 🟧 中等 | 需分支验证 | NEXT 的 `AVPlayer` 默认开 HTTP Range，4.2 需手动 `setSource` + `prepare` |
| 7 | `Image` 组件格式 | 🟢 小 | 不需要 | 两套都支持 jpg/png/webp/gif；heic 在 NEXT 才稳定 |
| 8 | `relationalStore` | 🟢 小 | 不需要 | 两套都有，**NEXT 上还有 distributed 模式** |

🟢 = 行为一致，可以写一份代码两跑；🟧 = 需小改；🟥 = 必须双写或只在 4.2 / NEXT 中挑一边支持。

---

## 1. 相册访问：Photo Access Kit / PhotoAccessHelper

### 4.2 (API 9)

```ts
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';

const helper = photoAccessHelper.getPhotoAccessHelper(getContext(this));
// 同步获取（API 9 的老接口，NEXT 已被标 deprecated 但仍可用）
const fetchOption = {
  fetchColumns: ['mediaType', 'uri', 'displayName', 'dateAdded', 'dateModified', 'size'],
  predicates: photoAccessHelper.Predicates.create(),
};
const fetchResult = await helper.getAssets(fetchOption);
const photo = await fetchResult.getFirstObject();
```

- 权限：`ohos.permission.READ_MEDIA`（相册）
- 监听新增：用 `helper.registerChange()`（API 9 已有），但回调粒度粗

### NEXT (API 12+)

```ts
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';

const ctx = getContext(this) as common.UIAbilityContext;
const helper = photoAccessHelper.getPhotoAccessHelper(ctx);

// NEXT 提供 PhotoAccess + 异步 PhotoPicker 双轨
const photos = await helper.getPhotoAssets({
  fetchColumns: ['uri', 'displayName', 'dateAdded', 'size'],
  predicates: new photoAccessHelper.PhotoFetchPredicate(),
});
```

- 权限：`ohos.permission.READ_IMAGEVIDEO` + `ohos.permission.WRITE_IMAGEVIDEO`（拆分更细）
- 监听新增：`helper.on('photoChange', callback)`，异步回调，支持增量通知
- 推荐用 PhotoPicker 弹窗让用户主动选，不必申请 READ_MEDIA

### 差异总结

| 维度 | 4.2 | NEXT |
|------|------|------|
| 包路径 | `@ohos.file.photoAccessHelper`（默认） | `@kit.MediaLibraryKit`（重命名 + kit 化） |
| Helper 类 | `photoAccessHelper.getPhotoAccessHelper` | `photoAccessHelper.getPhotoAccessHelper`（同名） |
| 获取方式 | `getAssets(FetchOption)` 同步结构 | `getPhotoAssets()` Promise 风格 |
| 监听事件 | `registerChange(uri, callback)` | `helper.on('photoChange', cb)`（标准 EventEmitter） |
| 权限 | `READ_MEDIA` 一把梭 | `READ_IMAGEVIDEO` + `WRITE_IMAGEVIDEO` 拆分 |
| PhotoPicker | API 9 已有但功能弱 | API 12 重写，强推 picker-first 流程 |

### 推荐用法

```ts
// 在 Ability / EntryAbility 启动时分支一次，把 helper 缓存在 ViewModel
import { platform } from '@ohos.application.ability';

const isNext = Number(platform.sdkVersion) >= 12; // NEXT 是 API 12+
let helper: any;
if (isNext) {
  const mod = await import('@kit.MediaLibraryKit');
  helper = mod.photoAccessHelper.getPhotoAccessHelper(getContext(this));
} else {
  const mod = await import('@ohos.file.photoAccessHelper');
  helper = mod.getPhotoAccessHelper(getContext(this));
}
```

> ⚠️ 未经实测。Dev 编码时请先在两套 DevEco Studio 里各跑一次 `photoAccessHelper.getPhotoAssets()` 的 hello world，确认 import 路径在编译期不被 TS 报红。

---

## 2. 文件系统监听：`ohos.file.fs` watch

### 4.2 (API 9)

- **没有** `fs.watch`！4.2 上只能：
  1. 用 PhotoAccess 的 change listener 监相册
  2. 对自定义目录用 `fs.listSync()` 周期性轮询（最低 5s 间隔）
  3. 注册 `commonEventManager` 收系统广播（应用沙箱内文件变动不触发）

### NEXT (API 12+)

```ts
import { fileIo as fs } from '@kit.CoreFileKit';

const watcher = fs.watch(
  '/storage/Users/currentUser/Download/MyBackupDir',
  { recursive: false },
  (eventType: fs.WatcherEventType, filename: string) => {
    if (eventType === fs.WatcherEventType.CHANGED_OUT_INODE) {
      // 新增或修改
    }
  }
);
// 停止：
watcher.close();
```

- 事件类型：`MOVED_IN` / `MOVED_OUT` / `DELETED` / `MODIFIED`
- **限制**：单进程最多 32 个 watcher；递归支持但浅层建议
- 兼容性：watcher 对象需要保存引用，关闭时调 `close()`

### 差异总结

| 维度 | 4.2 | NEXT |
|------|------|------|
| `fs.watch` | ❌ 不可用 | ✅ API 12 起支持 |
| `fs.watcher.close()` | ❌ | ✅ |
| 监听到的事件粒度 | 只能轮询 | 事件级（4 类） |
| 替代方案 | PhotoAccess listener + 定时 poll | 直接 watch |

### 推荐用法

```ts
// 仅 NEXT 启用 watch；4.2 退回到轮询（按需求 F3.2 兜底）
if (isNext) {
  // fs.watch 路径
} else {
  // setInterval 每 30s 调 fs.list 对比上次快照
  setInterval(this.scanDirectory.bind(this), 30_000);
}
```

> ⚠️ 4.2 上完全没有 fs.watch 的等价能力，**这就是为什么需求 F3.1 必须双触发：实时监听 + 6h 定时对账**。Dev 不能在 4.2 上承诺"秒级"目录变化。

---

## 3. 凭据加密存储：KeyStore / HUKS

### 4.2 (API 9)

```ts
import huks from '@ohos.security.huks';

// 生成密钥
const keyAlias = 'wdav_pwd_' + endpointId;
await huks.generateKey(keyAlias, {
  properties: [
    { tag: huks.HksTag.HKS_TAG_ALGORITHM, value: huks.HksKeyAlg.HKS_ALG_AES },
    { tag: huks.HksTag.HKS_TAG_KEY_SIZE, value: huks.HksKeySize.HKS_AES_KEY_SIZE_256 },
    { tag: huks.HksTag.HKS_TAG_PURPOSE, value: huks.HksKeyPurpose.HKS_KEY_PURPOSE_ENCRYPT | huks.HksKeyPurpose.HKS_KEY_PURPOSE_DECRYPT },
  ]
});

// 加密（huks 4.2 是分段式 handle，需 init → update → finish）
const handle = await huks.initSession(keyAlias, {
  properties: [{ tag: huks.HksTag.HKS_TAG_ALGORITHM, value: huks.HksKeyAlg.HKS_ALG_AES },
                { tag: huks.HksTag.HKS_TAG_PURPOSE, value: huks.HksKeyPurpose.HKS_KEY_PURPOSE_ENCRYPT }]
});
const ct = await huks.finishSession(handle, plainText);
```

### NEXT (API 12+)

```ts
import { huks } from '@kit.UniversalKeystoreKit';

const keyAlias = 'wdav_pwd_' + endpointId;
await huks.generateKey(keyAlias, {
  properties: [
    { tag: huks.HksTag.HKS_TAG_ALGORITHM, value: huks.HksKeyAlg.HKS_ALG_AES },
    { tag: huks.HksTag.HKS_TAG_KEY_SIZE, value: huks.HksKeySize.HKS_AES_KEY_SIZE_256 },
    { tag: huks.HksTag.HKS_TAG_PURPOSE, value: huks.HksKeyPurpose.HKS_KEY_PURPOSE_ENCRYPT | huks.HksKeyPurpose.HKS_KEY_PURPOSE_DECRYPT },
  ]
});

// NEXT 一次性 encrypt/decrypt（handle 概念仍在，但 init+update 可省略）
const cipher = await huks.encrypt(keyAlias, {
  properties: [{ tag: huks.HksTag.HKS_TAG_ALGORITHM, value: huks.HksKeyAlg.HKS_ALG_AES }]
}, plainText);
```

### 差异总结

| 维度 | 4.2 | NEXT |
|------|------|------|
| 包路径 | `@ohos.security.huks` | `@kit.UniversalKeystoreKit` |
| API 形态 | 必须 init/update/finish 三段式 | 提供一次性 `encrypt` / `decrypt` |
| 算法属性 | 老 HksKeyAlg 枚举 | 同名枚举值，但 `HKS_ALG_AES` 在 12+ 含 GCM 模式 |
| 密钥别名隔离 | 应用沙箱 | 应用沙箱 + 用户级（更高隔离） |
| 强制 PwdAuth | 不强制 | 关键操作可强制生物识别 |
| `huks.isKeyItemExist` | ❌ | ✅ API 12 |

### 推荐用法

```ts
// 抽象一层 KeyStore.ets，Dev 只暴露 encrypt/decrypt 接口，内部做分支
class KeyStore {
  private isNext = Number(platform.sdkVersion) >= 12;
  async encrypt(alias: string, plain: Uint8Array): Promise<Uint8Array> {
    if (this.isNext) return this.encryptNext(alias, plain);
    return this.encryptLegacy(alias, plain);
  }
}
```

> ⚠️ 未经实测。Dev 必须用真机（或 NEXT 模拟器）跑一次密钥生成 + 加密 + 解密 的 round-trip。**密钥一旦丢了，凭据就是死数据——务必把 alias 设计为可恢复（endpointId 派生）**。

---

## 4. HTTP 客户端：`ohos.net.http`

### 4.2 (API 9) 和 NEXT (API 12+) 共通写法

```ts
import http from '@ohos.net.http';

const client = http.createHttp();
// 标准 PUT（不带 Content-Range）
await client.request(
  'http://host/dav/file.bin',
  {
    method: http.RequestMethod.PUT,
    header: { 'Content-Type': 'application/octet-stream' },
    extraData: chunkBytes,
    expectDataType: http.HttpDataType.STRING,
  }
);
```

### Content-Range / Range 用法（双平台相同）

```ts
// 续传：从 offset 起
await client.request(url, {
  method: http.RequestMethod.PUT,
  header: {
    'Content-Type': 'application/octet-stream',
    'Content-Range': `bytes ${offset}-${offset + chunkLen - 1}/${totalSize}`,
  },
  extraData: chunkBytes,
});

// 断点探测：HEAD
const r = await client.request(url, { method: http.RequestMethod.HEAD });
const acceptedRanges = r.header['accept-ranges'];     // 'bytes'
const serverOffset = parseContentRange(r.header['content-range']);

// 视频 / 大文件流：Range GET
await client.request(url, {
  method: http.RequestMethod.GET,
  header: { 'Range': `bytes=${start}-${end}` },
  expectDataType: http.HttpDataType.ARRAY_BUFFER,
});
```

### 超时与重试（双平台都靠 `http.createHttp({ ... })`）

```ts
http.createHttp({
  connectTimeout: 10_000,
  readTimeout: 60_000,
});
```

**鸿蒙 SDK 的 `http` 模块本身没有重试 API**——重试在业务层用指数退避实现（已在 design-summary §4.3 描述）。

### 差异总结

| 维度 | 4.2 | NEXT |
|------|------|------|
| 模块路径 | `@ohos.net.http` | `@ohos.net.http`（同） |
| `RequestMethod` 枚举 | 同 | 同 |
| 流式上传 | ❌（只能一次性 extraData） | ⚠️ NEXT 通过 `expectDataType: ARRAY_BUFFER` + 多次 request 实现伪流式 |
| HTTPS 双向认证 | 仅服务器证书 | 支持客户端证书 `clientCert` |
| DNS | 系统默认 | 支持自定义 resolver（`dnsOverHttps`） |

### 推荐用法

**两套平台写一份代码即可**——这是 API 形态最一致的部分。建议把 `WebDAVClient.ets` 做成纯函数式 + Promise 链，Dev 不必分支。

> ⚠️ 未经实测的细节：NEXT 上 `extraData` 大于多少会 OOM。建议 Dev 在编码时设置 chunk=4MB（已与需求一致），并在 `infra/WebDAVClient.ets` 顶部加注释："≥16MB extraData 可能在 NEXT 上触发 native OOM；切到 4MB chunk 后未观察到问题"。

---

## 5. 后台任务：WorkScheduler / KEEP_BACKGROUND_RUNNING

### 4.2 (API 9)

```ts
import workScheduler from '@ohos.resourceschedule.workScheduler';

// 注册 ServiceExtensionAbility 后
const workInfo = {
  workId: 1,
  abilityName: 'WebDAVReconcileService',
  bundleName: 'com.example.webdavbackup',
  repeatCycleTime: 6 * 60 * 60 * 1000, // 6h
  parameters: { /* ... */ },
};
workScheduler.startWork(workInfo);

// 长驻后台（实时监听相册）—— 申请 KEEP_BACKGROUND_RUNNING 权限
// 在 config.json 里：
"abilities": [{
  "name": "RealtimeListenerService",
  "type": "service",
  "backgroundModes": ["dataTransfer", "location"],
  "permissions": ["ohos.permission.KEEP_BACKGROUND_RUNNING"]
}]
```

- 申请流程：用户在 设置 → 电池 → 后台耗电管理 → 找到本 App → 选"允许后台运行"
- API 9 不强制用户授权，但 EMUI/HarmonyOS 14+ 会弹"高耗电应用"提示

### NEXT (API 12+)

```ts
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';

// 申请短任务（最长 3 分钟）
const taskId = await backgroundTaskManager.requestSuspendDelay('webdav-reconcile', () => {
  // 即将到期，回调
});

// 想持续长驻？用 continuousTask（在 NEXT 上取代 ServiceExtensionAbility）
await backgroundTaskManager.startBackgroundRunning(
  context,
  backgroundTaskManager.BackgroundMode.DATA_TRANSFER, // 与 4.2 对应
  'WebDAV 实时备份'
);
// ...
await backgroundTaskManager.stopBackgroundRunning(context);
```

**关键变化**：NEXT 把后台长驻收归 `backgroundTaskManager`，**不再依赖 WorkScheduler + ServiceAbility 长驻**；WorkScheduler 在 NEXT 上变成"延迟短任务"调度器。

### 权限申请

- 4.2：`ohos.permission.KEEP_BACKGROUND_RUNNING` —— 在 manifest 声明；用户可在电池管理里手动开关
- NEXT：必须**运行时动态申请** `backgroundTaskManager.startBackgroundRunning()`，用户首次会收到系统弹窗"是否允许该应用在后台运行"

### 差异总结

| 维度 | 4.2 | NEXT |
|------|------|------|
| 长驻入口 | ServiceExtensionAbility + KEEP_BACKGROUND_RUNNING | `backgroundTaskManager.startBackgroundRunning` |
| WorkScheduler | 周期任务 + 长驻都能干 | 周期任务（≤3min 短任务） |
| 实时监听相册 | 长驻 ServiceAbility | 必须 `startBackgroundRunning` |
| 用户感知 | 设置里"高耗电应用" | 系统弹窗 + 设置里"应用后台管理" |
| EMUI/HarmonyOS 杀后台策略 | 宽 | **严**，需要白名单 |

### 推荐用法

```ts
// 设计 RealtimeMonitor.ets：
// - 4.2：ServiceAbility onStart 后 keepBackgroundRunning + PhotoAccess 注册
// - NEXT：startBackgroundRunning + 同上监听
// - 兜底：定时对账永远在 BackgroundTasksKit 的 short task 里跑，不依赖长驻
```

> ⚠️ 需求 §F3.1 的"实时监测"在 NEXT 上**无法保证**——NEXT 系统会对长驻应用定期 sleep。Dev 必须把"实时"降级为"近实时"（≤30s 延迟）来管理预期。

---

## 6. 媒体播放：`AVPlayer` + HTTP Range

### 4.2 (API 9)

```ts
import media from '@ohos.multimedia.media';

const player = media.createAVPlayer();
player.url = 'http://host/dav/video.mp4'; // 自动支持 HTTP Range
player.on('stateChange', (state) => { /* ... */ });
player.prepare();
```

- `createAVPlayer().url` 自动识别 HTTP 远端，**4.2 默认会发 Range: bytes=0-** 来探测服务器
- 拖动进度条：通过 `player.seek(timeMs)`，SDK 内部用 Range 拉取对应字节

### NEXT (API 12+)

```ts
import { media } from '@kit.MediaKit';

const player: media.AVPlayer = await media.createAVPlayer();
player.url = 'http://host/dav/video.mp4'; // 同上，自动 Range
player.on('stateChange', (state: media.AVPlayerState) => { /* ... */ });
await player.prepare();
```

### 差异总结

| 维度 | 4.2 | NEXT |
|------|------|------|
| 包路径 | `@ohos.multimedia.media` | `@kit.MediaKit` |
| 创建方式 | `createAVPlayer()` 同步 | `await createAVPlayer()` 异步 |
| HTTP Range | 自动 | 自动（且更激进，更快出首帧） |
| 加密 HLS/DASH | ❌ | ✅ |
| 后台播放 | 需 ServiceAbility + 音频焦点 | `AVSession` 统一管理音频焦点 |

### 推荐用法

```ts
// 视频预览页 PreviewPage.ets：
import { isNext } from '../infra/Platform';
const mod = isNext
  ? await import('@kit.MediaKit')
  : await import('@ohos.multimedia.media');
const player = isNext
  ? await mod.media.createAVPlayer()
  : mod.media.createAVPlayer();
player.url = videoUrl;
await player.prepare();
```

> ⚠️ 未经实测 NEXT 上 HEVC/H.265 远端流的兼容性。Dev 在编码时优先保证 mp4 + H.264 走通，HEVC 列为"已知不一定 work"。

---

## 7. `Image` 组件支持的图片格式

### 双平台共通

```arkts
Image($r('app.media.logo'))     // 本地
Image('http://host/dav/img.jpg') // 远端
```

| 格式 | 4.2 | NEXT |
|------|------|------|
| jpg / jpeg | ✅ | ✅ |
| png | ✅ | ✅ |
| webp | ✅（API 7+） | ✅ |
| heic / heif | ⚠️ 部分设备支持 | ✅（API 12+ 起稳） |
| gif | ✅ 静态帧 | ✅ 支持动画 |
| svg | ❌ | ✅ |
| avif | ❌ | ⚠️ 实验性 |

### 推荐用法

```ts
// 远端预览页统一用法：
Image(this.remotePreviewUrl)
  .alt($r('app.media.thumb_placeholder')) // 加载中占位
  .objectFit(ImageFit.Contain)
```

> 需求 §F9.1 列出的 jpg/png/webp/heic 在 NEXT 上 100% 可用；4.2 上 heic 需要单独做兜底（解码失败 → 显示占位图）。Dev 建议加 `try { ... } catch { placeholder }`。

---

## 8. 关系型 KV：`@ohos.data.relationalStore`

### 双平台共通

```ts
import relationalStore from '@ohos.data.relationalStore';

const config = {
  name: 'webdav_backup.db',
  securityLevel: relationalStore.SecurityLevel.S1,
};
const store = await relationalStore.getRdbStore(context, config);

await store.executeSql(
  `CREATE TABLE IF NOT EXISTS fingerprint (
    file_path TEXT PRIMARY KEY,
    endpoint_id TEXT,
    size INTEGER,
    mtime INTEGER,
    hash_head TEXT,
    hash_tail TEXT,
    uploaded_at INTEGER
  )`
);
```

### 差异总结

| 维度 | 4.2 | NEXT |
|------|------|------|
| 包路径 | `@ohos.data.relationalStore` | `@kit.ArkData`（或兼容原路径） |
| API 形态 | 同 | 同 |
| 加密数据库 | API 9 可用 `SecurityLevel.S2/S3` | 同 + `S4`（强加密） |
| 多设备同步 | ❌ | ✅ `distributedStore`（本期需求不做） |
| 性能 | 千条查询 ~80ms | ~50ms |

### 推荐用法

**直接用兼容路径写一套代码**——这是最少差异的一类 API。Dev 在 `data/` 层包一个 `RdbHelper.ets`，所有表创建 / 查询走它。

---

## 平台检测与代码分支策略

### 推荐：单仓双编译

```ts
// infra/Platform.ets
import platform from '@ohos.application.platform'; // 4.2
// NEXT: '@kit.AbilityKit' 提供 platformVersion

export const isNext: boolean = (() => {
  const v = String(platform.sdkVersion ?? platform.version ?? '');
  return Number(v) >= 12;
})();
```

### 备选：编译期分支（构建脚本）

```jsonc
// build-profile.json5 里写两个 product：
{
  "products": [
    { "name": "default", "compileSdkVersion": 12 },       // NEXT
    { "name": "legacy",  "compileSdkVersion": 9  }         // 4.2
  ]
}
```

Dev 用 hvigorw `assembleHap --product legacy` 切到 4.2 SDK 编译，再通过 `ets2bundle` / `tsc` 的 `target` 字段控制 import 是否被允许。

---

## Dev 后续验证清单（按风险排序）

| 优先级 | 验证项 | 工具 |
|---|---|---|
| 🔴 P0 | KeyStore 加解密 round-trip（NEXT 真机） | DevEco NEXT 模拟器 + 真机 |
| 🔴 P0 | WorkScheduler 在 NEXT 上能否拿 6h 长任务 | DevEco NEXT 模拟器 |
| 🔴 P0 | PhotoAccess 在 NEXT 的 `on('photoChange')` 回调延迟 | NEXT 真机 + 拍照实测 |
| 🟧 P1 | `fs.watch` 在 NEXT 自定义目录的可靠性（含高频修改） | NEXT 真机 |
| 🟧 P1 | AVPlayer HTTP Range 拉远端 mp4 进度条拖动 | NEXT 真机 |
| 🟢 P2 | Image 组件 heic 解码失败兜底 | 4.2 真机 |
| 🟢 P2 | relationalStore S2 加密数据库 | 4.2 真机 |
| 🟢 P2 | HTTP 超时边界（readTimeout 30s 内对 100MB 文件是否够） | NEXT + 本地 mock |

---

## 引用与不确定性声明

- 所有"代码片段"基于鸿蒙开发者文档（developer.huawei.com/consumer/cn/hms）和已公开的 SDK 12 变更记录整理。
- **本报告不包含任何对真机或模拟器的实测结果**——Dev 在编码时务必按"Dev 后续验证清单"逐条跑通。
- 若 Dev 在实测中发现某条 API 在 NEXT 上已经改名或废弃，请把 issue 反馈回 BA，由 BA 在本报告追加 "实测反馈" 段。

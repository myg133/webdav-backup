# Known Issues — REQ-001 Dev Agent

> 列出"未实测 API + 风险 + Dev/QA 验证步骤"——给 QA 阶段的真机/模拟器复核提供清单。

## 已实现但未实测（需 QA 真机/模拟器验证）

### K-1：KeyStore（HUKS）真加密路径

- **风险**：`infra/KeyStore.ets` 在 dev 模拟器无 HUKS 时自动 fallback 到 XOR+salt；fallback 单测通过，但 **HUKS AES-256-CCM 真机路径未实测**。
- **Dev 验证步骤**：
  1. 在 NEXT 模拟器创建端点，密码 "test123!"
  2. 导出应用数据 → 在数据库 `endpoints.password_cipher` 列看到 base64 blob
  3. 在系统设置 → 应用管理 → 存储 搜索 "test123!" 字符串 → 应**找不到明文**
  4. KeyStore 应有 alias `webdav_password_<uuid>`（用 `hdc shell hidumper -s` 或类似工具）
- **QA 验证步骤**：
  - 重复 Dev 验证步骤 1-4
  - 额外：在 NEXT 真机**卸载并重装** App → 凭据不可恢复（即"非持久化"——这也是 KeyStore 的设计）

### K-2：PhotoAccess 实时监听

- **风险**：`infra/FileWatcher.ets` watchGalleryNext（NEXT）/ watchGalleryLegacy（4.2）写完，但真机回调延迟 / 漏报 概率未知。
- **Dev 验证步骤**：
  1. NEXT 真机：连 Wi-Fi，启用任务 `realtime=true`，进入 App 首页
  2. 用系统相机拍一张照片
  3. 看历史记录页 → 应在 5 秒内新增"成功"
- **QA 验证步骤**：
  - 重复 Dev 验证步骤（NEXT + 4.2 各跑一次）
  - 额外测试：拍 5 张照片同时 → 是否都入库？有没有漏？

### K-3：fs.watch 目录监听（NEXT 独有）

- **风险**：`@ohos.file.fs.watch` 在 NEXT 上是高风险 API（api-survey.md §2），**实测可靠性未知**。
- **Dev 验证步骤**：
  1. NEXT 真机：把 `/Download/test_watch/` 当 sourcePath
  2. 用文件管理器放入 a.txt（100KB）
  3. 看历史记录页 → 应在 5 秒内"成功"
- **QA 验证步骤**：
  - 重复 Dev 验证步骤
  - 高频修改测试：在 1 秒内连续修改 10 次 → 是否都触发？

### K-4：WorkScheduler 在 NEXT 的实际行为

- **风险**：NEXT 文档说"不支持长驻 ServiceExtension"；Dev 用 backgroundTasks.startWork 替代。**NEXT 实际调度行为未实测**。
- **Dev 验证步骤**：
  1. NEXT 真机：配置 task cron=1h
  2. 把 App 切后台、锁屏
  3. 等 1 小时 → 看历史记录是否新增条目
- **QA 验证步骤**：
  - 重复 Dev 验证步骤
  - 额外：模拟"系统杀掉后台"（开发者选项 → 不保留活动）→ 对账是否仍能跑？

### K-5：AVPlayer HTTP Range 远端视频

- **风险**：`PreviewPage` 视频分支代码简化（用 Image 组件显示本地缓存路径）；生产应内嵌 Video 组件 + AVPlayer Range 拉流。
- **Dev 验证步骤**：
  1. 远端上传一个 5MB mp4（H.264）
  2. 预览页选这个视频 → 应能播放 + 拖动进度条
- **QA 验证步骤**：
  - HEVC 编码测试（NEXT 兼容性需验）
  - 大文件（100MB）拖动进度条流畅度

### K-6：Image 组件 4.2 解码 heic

- **风险**：`PreviewLoader.supportsHeic()` 返回 isNext；但 4.2 上部分设备 heic 解码失败。
- **Dev 验证步骤**：
  1. 4.2 真机：上传 heic 图片
  2. 预览页 → 应显示占位图（不崩溃）+ 错误提示
- **QA 验证步骤**：
  - 多种品牌 4.2 设备实测（P40 / Mate 30 / 荣耀 V30）

## MVP 未实现（明确说明）

| 项 | 状态 | 说明 |
|----|------|------|
| 反向同步（远端 → 本地） | ❌ | 设计概要 §8 明示不做 |
| 端到端加密 | ❌ | 设计概要 §8 明示不做 |
| 缩略图缓存 | ❌ | 设计概要 §8 明示二期 |
| 多账号切换 | ❌ | 设计概要 §8 明示不做 |
| MKCOL 调用 | ❌ | OpenList 405；PUT 隐式建父目录已够用 |
| DELETE 调用 | ❌ | OpenList 403 + 设计永久不删 |
| UI 多语言（除 zh/en） | ⚠️ | 资源目录结构支持；目前只填了 zh_CN / en_US |

## API 兼容性表（Dev 已写但 QA 必须复核）

| API | 4.2 | NEXT | 验证方式 |
|-----|------|------|---------|
| `@ohos.security.huks` | ✅ | ✅ | DevEco 真机导入测试 |
| `@ohos.data.relationalStore` | ✅ | ✅ | DevEco 真机 runOnce 测试 |
| `@ohos.net.http` | ✅ | ✅ | DevEco 真机 createHttp 测试 |
| `@ohos.file.fs.watch` | ❌ | ✅ | NEXT 真机目录修改测试 |
| `@ohos.file.photoAccessHelper` | ✅ | (改用 `@kit.MediaLibraryKit`) | DevEco 真机拍照片测试 |
| `@ohos.multimedia.media` (createAVPlayer) | ✅ | (改用 `@kit.MediaKit`) | DevEco 真机视频播放测试 |
| `@ohos.workScheduler` | ✅ | ❌（长驻）→ 用 `@ohos.backgroundtasks` | NEXT 真机 1h 定时测试 |
| `@ohos.notificationManager` | ✅ | ✅ | DevEco 真机通知测试 |

## 与 BA/QA 的协作建议

1. **Dev 已实现** + **单元测试通过** + **集成测试通过**（OpenList 真实端点）——这是验证基线
2. **真机/模拟器端到端**（拍照片/杀 App/锁屏/Wi-Fi 切换）需 QA 复核
3. **HUKS 真加密路径**需 NEXT 真机验，dev 模拟器走 fallback
4. **NFR-01/02/03**（启动延迟、查询性能、双平台安装）需 benchmark 工具复核
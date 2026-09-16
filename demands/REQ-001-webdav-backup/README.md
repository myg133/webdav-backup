# REQ-001: WebDAV 备份客户端（鸿蒙）

需求编号: REQ-001
项目代号: webdav-backup
优先级: P0
当前状态: 草稿

## 目录

- `demand.md` — 需求描述
- `acceptance.md` — 验收标准（11 条 AC + 4 条 NFR）
- `design-summary.md` — 设计概要（架构、数据模型、关键流程）
- `status.md` — 状态卡
- `test-cases/` — 测试用例（QA 阶段生成）

## 关键决策

- 平台: HarmonyOS 4.2 + NEXT 双平台
- 语言: ArkTS（鸿蒙原生）
- 增量同步: 指纹库（path/size/mtime/首末 1MB sha1）+ WebDAV LIST 对账
- 续传: HTTP `PUT` + `Content-Range`，chunk 4MB
- 释放资源: **只标记，不删**
- 端点管理: 多 WebDAV 端点 + KeyStore 加密凭据
- 触发: 实时监测 + 定时对账（默认 6h）+ 仅 Wi-Fi 选项

## 范围

### MVP（11 条 AC）

- F1~F10 全部功能纳入验收

### 二期 / 不做

- 反向同步、端到端加密、缩略图缓存、多账号
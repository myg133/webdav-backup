# REQ-001: WebDAV 备份客户端（鸿蒙）

## 任务上下文

- 需求文档：`BA/demands/REQ-001-webdav-backup/demand.md`
- 验收标准：`BA/demands/REQ-001-webdav-backup/acceptance.md`（11 条 AC + 4 条 NFR）
- 设计概要：`BA/demands/REQ-001-webdav-backup/design-summary.md`
- 当前状态：已就绪
- 已验证 WebDAV 端点：见 `BA/demands/REQ-001-webdav-backup/status.md`

## 任务分工

- Phase 1: explore 子 agent — 摸清鸿蒙 4.2/NEXT API 差异 + OpenList 大文件行为
- Phase 2: Dev 子 agent — 实现全部 AC
- Phase 3: QA 子 agent — Pre-merge 审核

## 开发约束

- 工作分支：`feature/REQ-001`
- 工作目录：`feature-REQ-001/`（仓库根平铺）
- commit 格式：`[Dev] {描述} (关联: REQ-001)`
- 完成后通知 BA，等待 QA 审核

## 开发原则

- 不主动删除 WebDAV 远端资源
- 端点续传必须用 HTTP Content-Range
- 凭据必须用 KeyStore 加密
- MVP 边界：见 design-summary.md §8
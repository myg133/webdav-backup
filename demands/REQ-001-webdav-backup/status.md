# 状态：REQ-001 WebDAV 备份客户端（鸿蒙）

## 当前状态

**状态**: 进行中

## 状态历史

| 时间 | 状态 | 备注 |
|------|------|------|
| 2026-09-16 | 草稿 | 创建需求文档与验收标准 |
| 2026-09-16 | 已评审 | WebDAV 端点验证通过；push 到 origin |
| 2026-09-16 | 已就绪 | 创建 feature-REQ-001 worktree；派 explore 子 agent |
| 2026-09-16 | 进行中 | explore 完成；AC-07 与 §4.2 已根据 OpenList 实测修订；等 Dev Agent 接单 |

## 责任信息

- 需求编号: REQ-001
- 项目代号: webdav-backup
- 优先级: P0
- BA Agent Session: ba-Michael-WorkStation-34576-20260916-155002

## 关键发现（来自 explore 报告）

### OpenList 兼容性实测结论

- ✅ 整文件 PUT：完全正常
- ✅ Range GET：完全正常（视频预览可用）
- ❌ **PUT + Content-Range：服务端完全忽略** —— 必须改为"重传整文件"策略
- ❌ MKCOL：405（PUT 会隐式建父目录，无需 MKCOL）
- ❌ DELETE：403（**正好对齐"永久不删远端"原则**）

### 鸿蒙 API 风险矩阵

- 🔴 P0：KeyStore（HUKS）、WorkScheduler、PhotoAccess
- 🟧 P1：`fs.watch`（4.2 无）、AVPlayer Range、HEIC 解码
- 🟢 P2：relationalStore、Image 组件

## 文档位置

- 设计概要修订：`BA/demands/REQ-001-webdav-backup/design-summary.md` §4.2 + §5
- AC-07 修订：`BA/demands/REQ-001-webdav-backup/acceptance.md`
- Dev 参考文档（feature worktree）：`feature-REQ-001/.docs/`

## 派单下一步

Dev Agent 接单任务清单：
1. 在 `feature-REQ-001/` 实现 REQ-001 全部 11 条 AC + 4 条 NFR
2. 重点：依据 `.docs/api-survey.md` 的 `isNext` 分支策略；依据 `.docs/openlist-compat.md` 重写断点续传
3. 完成后：`.feature/traceability.md` + `.feature/verification-report.md` + CHANGELOG.md
4. 通知 BA：进入待验证状态

## 验证状态

- 单元测试: 不适用（Dev 实现阶段启动）
- 集成测试: 不适用
- Pre-merge QA: 不适用
- Post-merge QA: 不适用

## 阻塞项

无

## 下一步

1. 派 Dev Agent 启动编码
2. Dev 完成后通知 BA → 流转到"待验证"
3. 派 QA 子 agent 做 Pre-merge 审核
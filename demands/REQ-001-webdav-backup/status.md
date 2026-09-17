# 状态：REQ-001 WebDAV 备份客户端（鸿蒙）

## 当前状态

**状态**: 已退回

## 状态历史

| 时间 | 状态 | 备注 |
|------|------|------|
| 2026-09-16 | 草稿 | 创建需求文档与验收标准 |
| 2026-09-16 | 已评审 | WebDAV 端点验证通过；push 到 origin |
| 2026-09-16 | 已就绪 | 创建 feature-REQ-001 worktree；派 explore |
| 2026-09-16 | 进行中 | explore 完成；AC-07 修订；Dev Agent 接单 |
| 2026-09-16 | 待验证 | Dev 完成；BA 独立验证 15/15 单测 + 12/12 集成测试全绿 |
| 2026-09-17 | 已退回 | QA 审核 FAIL：AC-10 视频预览未实现（阻断）；AC-08 序列偏差；traceability 行号偏差 |

## 责任信息

- 需求编号: REQ-001
- 项目代号: webdav-backup
- 优先级: P0
- BA Agent Session: ba-Michael-WorkStation-34576-20260916-155002

## 退回原因（来自 QA 报告）

详见 `feature-REQ-001/.feature/verification-report-qa.md`。

### 阻断项

| # | 阻断内容 | 必须修复 |
|---|---------|---------|
| B-1 | **AC-10 视频预览进度条拖动未实现** | PreviewPage.ets:75-82 用 `Image()` 而非 `Video()` 组件，AC-10 明文要求"进度条可拖动" |

### 建议修复（可一并处理）

| # | 内容 | 选择 |
|---|------|------|
| B-2 | **AC-08 指数退避序列偏差** | Dev 选一个：(a) 改代码 `Math.pow(2, attempt-1)` 对齐文档 [1,2,4,8,16]；或 (b) 更新 design-summary §4.3 + AC-08 接受代码现状 [2,4,8,16,16] |
| B-3 | traceability.md 多处行号偏差 + 1 处越界 | Dev 重跑 wc -l 刷新 path:line |

### 放行条件（Dev 修复后可流转到"已验证"）

- [ ] B-1 修复（AC-10 视频预览）
- [ ] B-2 决策（Dev 选 a 或 b）
- [ ] B-3 traceability 行号刷新

### QA 追加 known-issues（已写入 `qa-known-issues.md`）

- Q-1: PreviewPage 视频分支未实现 Video 组件（同 B-1）
- Q-2: `@ohos.net.http` 双平台 createHttp 行为未实测
- Q-3: 指数退避序列偏差（同 B-2）
- Q-4: traceability.md 行号偏差（同 B-3）

## 派单下一步

派 Dev Agent（**第二轮**）修复上述问题，重点：
1. 用鸿蒙 `Video` 组件 + AVPlayer 实现 AC-10 视频预览（参考 api-survey.md §6 模板）
2. 同步修复 AC-08 序列 + traceability 行号

Dev 完成后重新走 Pre-merge QA 流程。

## 备注

- Dev 第一轮整体质量很高（15/15 单测 + 12/12 集成测试全绿 + AC-09 0 命中）
- 主要问题集中在 UI 层组件使用不当（Image vs Video）+ 文档/代码一致性
- 真机 e2e（AC-03/05/11 + NFR-01/02/03）暂无法验证，需 DevEco NEXT + 4.2 双真机，本轮不动
# 状态：REQ-003 真机回归

## 当前状态

**状态**: 草稿

## 状态历史

| 时间 | 状态 | 备注 |
|------|------|------|
| 2026-09-17 | 草稿 | 创建需求文档（BA 独立完成；真机执行需你本环境跑） |

## 责任信息

- 需求编号: REQ-003
- 项目代号: real-device-regression
- 优先级: P1
- BA Agent Session: ba-Michael-WorkStation-34576-20260916-155002

## 关键事实

- **执行主体**：人类（你）在 DevEco Studio 内跑，容器跑不了 DevEco
- **范围**：复用 REQ-002 交付的 qa-checklist.md（9927 bytes）+ qa-report-template.md
- **设备**：DevEco NEXT 真机 + DevEco 4.2 真机
- **只修阻断级**（与 Sprint 1 retrospective 一致）

## 下一步

1. 流转到"已评审"（你拍板）
2. 流转到"已就绪"
3. 你在真机上跑 qa-checklist
4. 回传报告 → BA 流转到"待验证"→ 派 QA 子 agent
5. QA 审核（关键看实测数据真实性）
6. 流转到"已验证" / "已退回"
# 状态：REQ-003 真机回归

## 当前状态

**状态**: 已评审

## 状态历史

| 时间 | 状态 | 备注 |
|------|------|------|
| 2026-09-17 | 草稿 | 创建需求文档 |
| 2026-09-17 | 已评审 | 用户评审通过；范围 F1-F5；只修阻断级 |

## 责任信息

- 需求编号: REQ-003
- 项目代号: real-device-regression
- 优先级: P1
- BA Agent Session: ba-Michael-WorkStation-34576-20260916-155002

## 派单策略

- **不派 Dev 子 agent**（容器跑不了 DevEco）
- **执行主体**：人类（你）
- **QA 子 agent**：你跑完回传报告后，BA 派 QA 审核报告真实性
- **修复触发**：若发现阻断级问题 → 派 Dev Agent 修

## 下一步

1. 流转到"已就绪"
2. 你在 DevEco NEXT + 4.2 双真机跑 qa-checklist
3. 回传报告到 `BA/demands/REQ-003-real-device-regression/qa-report-<device>.md`
4. BA 流转到"待验证" → 派 QA 审核
5. QA 通过 → "已验证"
# 状态：REQ-003 真机回归

## 当前状态

**状态**: 已就绪

## 状态历史

| 时间 | 状态 | 备注 |
|------|------|------|
| 2026-09-17 | 草稿 | 创建需求文档 |
| 2026-09-17 | 已评审 | 用户评审通过 |
| 2026-09-17 | 已就绪 | 等你在 DevEco NEXT + 4.2 双真机执行 |

## 责任信息

- 需求编号: REQ-003
- 项目代号: real-device-regression
- 优先级: P1
- BA Agent Session: ba-Michael-WorkStation-34576-20260916-155002

## 执行准备（BA 已完成）

- ✅ `BA/demands/REQ-002-test-infrastructure/qa-checklist.md`（9927 bytes，覆盖 11 AC + 4 NFR）
- ✅ `BA/demands/REQ-002-test-infrastructure/templates/qa-report-template.md`（4567 bytes）
- ✅ OpenList 测试端点：`http://192.168.31.101:8080/dav/test_backup_dav`（testdav / testdav）

## 你需要做的（执行）

1. 安装 DevEco NEXT + DevEco 4.2 双 Studio
2. 拉取 develop 分支最新代码
3. 在每个真机上：
   - 构建 .hap
   - 安装
   - 跑 qa-checklist 全部 15 节
   - 截屏 + 日志保存到 `.local/qa-runs/<timestamp>/screenshots/` + `logs/`
4. 填写 qa-report-template.md → 写到 `BA/demands/REQ-003-real-device-regression/qa-report-<device>.md`
5. 回报给 BA：截屏路径 + 报告 + 发现的阻断级问题（如有）

## 派单下一步

- 不派 Dev Agent
- 你执行 → 报告回传 → BA 流转到"待验证" → 派 QA 子 agent 审核报告真实性
- QA 审核 PASS → 流转到"已验证"
- 若发现阻断级问题 → 派 Dev Agent 修
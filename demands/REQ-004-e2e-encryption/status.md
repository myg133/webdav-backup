# 状态：REQ-004 端到端加密

## 当前状态

**状态**: 已就绪

## 状态历史

| 时间 | 状态 | 备注 |
|------|------|------|
| 2026-09-17 | 草稿 | 创建需求文档 |
| 2026-09-17 | 已评审 | 用户评审通过 |
| 2026-09-17 | 已就绪 | 准备派 Dev Agent（排在 REQ-005 之后）|

## 责任信息

- 需求编号: REQ-004
- 项目代号: e2e-encryption
- 优先级: P1
- BA Agent Session: ba-Michael-WorkStation-34576-20260916-155002

## 派单计划

- **派单顺序**：排在 REQ-005 之后（让 CI 先稳定，不阻塞并行）
- **Dev Agent 工作区**：`code/` worktree（develop 分支）
- **写权限**：仅 `code/` + 涉及 EndpointsRepo 等小范围数据层扩展
- **预估工作量**：5-7 天
- **关键技术风险**：加密正确性（PBKDF2 迭代 / GCM tag 验证 / nonce 唯一性）

## 关键设计要点（已写入 demand.md）

- **算法**：AES-256-GCM（认证加密）+ PBKDF2 100k 迭代（密钥派生）
- **格式**：远端 `.wde` 文件 = header(60 bytes) + chunk_data(N × (4MB + 12B nonce + 16B tag))
- **密钥**：master key 仅运行时持有，存 KeyStore 不落盘
- **不可逆**：主密码丢失 = 数据永久丢失
- **兼容 REQ-001**：端点配置开关，关闭时 = 明文上传（兼容旧行为）

## 下一步

1. 派 Dev Agent（先派 REQ-005 CI，结束后立即派本）
2. Dev 完成后 → Pre-merge QA
3. QA 重点：加密 roundtrip + 远端不可读 + GCM tag 拦截篡改 + 主密码错误提示
4. QA 通过 → "已验证"
# REQ-004: 端到端加密

需求编号: REQ-004
项目代号: e2e-encryption
优先级: P1
当前状态: 草稿

## 目录

- `demand.md` — 需求描述
- `acceptance.md` — 验收标准（待 Dev 完成后细化）
- `design-summary.md` — 设计概要
- `status.md` — 状态卡
- `test-cases/` — 测试用例

## 关键决策

- **算法**：AES-256-GCM（认证加密）+ PBKDF2 100k 迭代（密钥派生）
- **格式**：远端存储 `.wde` 文件，header 包含原文件名 / 大小 / chunk count（加密）
- **密钥管理**：master key 仅存 KeyStore，运行时持有，**不**落盘
- **不可逆**：主密码丢失 = 数据永久丢失
- **范围限制**：MVP 不做密钥导入/导出（换设备 = 重传）

## 范围

### MVP（F1-F8）

- F1 密钥派生（PBKDF2）
- F2 文件加密（AES-256-GCM 分块）
- F3 文件名加密
- F4 加密/解密流程
- F6 与 REQ-001 集成
- F7 配置开关
- F8 错误处理

### 不做

- F5 密钥导出/导入
- 多端点共享主密码
- 主密码找回
- 加密算法可配置
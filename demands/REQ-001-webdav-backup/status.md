# 状态：REQ-001 WebDAV 备份客户端（鸿蒙）

## 当前状态

**状态**: 已就绪

## 状态历史

| 时间 | 状态 | 备注 |
|------|------|------|
| 2026-09-16 | 草稿 | 创建需求文档与验收标准 |
| 2026-09-16 | 已评审 | WebDAV 测试端点验证通过；push 到 origin；评审通过 |
| 2026-09-16 | 已就绪 | 准备派 Dev：先 explore 后编码 |

## 责任信息

- 需求编号: REQ-001
- 项目代号: webdav-backup
- 优先级: P0
- BA Agent Session: ba-Michael-WorkStation-34576-20260916-155002

## WebDAV 测试端点（已验证可用）

- URL: http://192.168.31.101:8080/dav/test_backup_dav
- 用户: testdav / testdav
- 验证项:
  - ✅ Basic 鉴权
  - ✅ PROPFIND depth=1
  - ✅ PUT 新建/覆盖（201 Created）
  - ✅ MKCOL 创建目录（201 Created）
  - ✅ OPTIONS 暴露完整 WebDAV 能力
  - ⚠️ 大文件 Content-Range PUT + Range GET 由 Dev 在 feature-REQ-001 内验证

## Worktree 分配

- 即将创建: `feature-REQ-001` (在仓库根平铺)

## 派单计划

按"派单前规则"先派 explore 子 agent 摸鸿蒙 4.2/NEXT API 与 OpenList 大文件行为：

1. explore 子 agent：
   - 输入：当前已知的 OpenList 小文件 PUT 行为
   - 输出：Photo Access Kit / KeyStore / AVPlayer / 后台长驻 API 在 4.2 与 NEXT 上的差异
   - 输出：建议在 feature-REQ-001 用哪一套 API 版本
2. Dev Agent：
   - 在 `feature-REQ-001/` worktree 内实现完整需求
   - 完成后通知 BA

## 验证状态

- 单元测试: 不适用
- 集成测试: 不适用
- Pre-merge QA: 不适用
- Post-merge QA: 不适用

## 阻塞项

无

## 下一步

1. 在仓库根创建 feature-REQ-001 worktree（基于 develop）
2. 派 explore 子 agent
3. 探索报告入档后流转到"进行中"
4. 派 Dev 子 agent
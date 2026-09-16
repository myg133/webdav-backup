# code - 主开发分支

工作分支：`develop`
默认工作区：`code/`（仓库根平铺）

## 核心职责

1. 业务代码开发
2. 单元测试 / 集成测试
3. CI 构建（push 后自动触发）
4. 合并到 main 的 PR 来源（经 release）

## 注意事项

- 所有变更通过 PR 合入，不直接 commit 到 `develop`
- `.local/` 目录不跟踪（中间产物 / 调试）
- 提交格式：`[Dev] {描述} (关联: REQ-xxx)`
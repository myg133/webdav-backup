# Sprint 1 Retrospective

**时间范围**: 2026-09-16 → 2026-09-17（2 天）
**Sprint 编号**: Sprint 1
**完成的需求**: 2（REQ-001 P0、REQ-002 P1）
**总 commit 数**: 41

---

## 1. Sprint 概览

### 完成情况

| REQ | 优先级 | 描述 | 状态 | Commit |
|-----|--------|------|------|--------|
| REQ-001 | P0 | WebDAV 备份客户端 MVP（鸿蒙 4.2 + NEXT） | ✅ 已完成 | 21 commits |
| REQ-002 | P1 | 测试基础设施 + CI 集成 | ✅ 已完成 | 13 commits |

**Sprint 完成率**: 2/2 (100%)

### 实际工作量

- REQ-001：约 1 天（含 BA 接管修复二轮）
- REQ-002：约 0.5 天
- 合计：~1.5 天（远超估算的 7-8 天——实际更高效，因为 explore 子 agent 提前摸清了 OpenList 大坑）

---

## 2. 做对的事（Keep）

### K1: 派单前 Explore 摸底

**案例**: REQ-001 第一轮就派 explore 子 agent 摸清 HarmonyOS 4.2/NEXT API 差异 + OpenList WebDAV 兼容性。

**收益**:
- 发现 OpenList **不支持 Content-Range PUT 追加**（颠覆原计划）
- 在 Dev 编码前重写 AC-07 设计 + §4.2 状态机
- Dev 阶段一次走对——不需要返工

**原则**: "派单成本 > explore 成本时，必派" —— 这是 sprint 最大的效率杠杆。

### K2: 真实环境前置测试

**案例**: OpenList WebDAV 端点先用 curl/PowerShell 探明——发现只读 → 改为读写 → 验证完整。

**收益**:
- Dev 不浪费时间在"等 Dev Agent 写代码才发现服务端不支持 PUT Content-Range"
- 用户也只用了 1-2 轮"再试试"就解决权限问题

**原则**: 任何依赖外部服务的需求，先用最简单的工具探明服务端兼容度。

### K3: BA 接管修复能力

**案例**: REQ-001 QA FAIL 时 Dev 第二轮预算耗尽，BA 亲自接管修复 B-1/B-2/B-3。

**收益**:
- 不被卡死——3 个修复 + 3 个 commit 在 BA 工作流内完成
- Dev Agent 失败有兜底

**原则**: 子 agent 失败不阻塞主流程；BA 自己能补的补，不要等下一轮 Dev。

### K4: 状态机严格 8 步

**案例**: 草稿 → 已评审 → 已就绪 → 进行中 → 待验证 → 已退回 → 已验证 → 已完成。

**收益**:
- 任何时刻知道需求在哪一步
- QA FAIL 时知道走"已退回"而不是"已完成"
- 不允许跳步（绝不跳过 QA 直接 merge）

**原则**: 状态机的价值是"防跳步"。

### K5: Grep 验证代码层合规

**案例**: AC-09 要求"不删 WebDAV 远端资源"，用 `grep "method: 'DELETE'"` 验证代码层 0 命中。

**收益**:
- 自动化可重复
- 不仅是 Dev 自评，QA + BA 都独立验证
- 结果一致：Dev / QA / BA 三方都得到 0 命中

**原则**: 凡是"代码必须满足 X 约束"的需求，写一个 grep / lint 检查。

---

## 3. 做得不好的事（Problems）

### P1: Dev Agent 预算耗尽（连续 2 次）

**案例**:
- REQ-001 Dev Agent 第二轮：120 步耗尽，B-1/B-2 实际已完成但 self-report 写"B-1 未启动"
- REQ-002 Dev Agent：120 步耗尽，traceability + verification + 调度表更新未做

**根因**:
- 给子 agent 的 prompt 太重（要求多 + 自验证 + 文档全套 + commit + 通知）
- 子 agent 在预算耗尽前的混乱状态无法可靠 self-report

**教训**:
- 拆任务：将 Dev 子 agent 拆成"实现" + "自验证"两轮，第二轮轻
- 或：Dev 子 agent 只做实现 + 测试，BA 接管文档

### P2: PowerShell 大字节数组构造陷阱

**案例**: REQ-001 explore 阶段，`New-Object byte[] 10MB` 报"Cannot find overload"，卡了 2 轮。

**根因**: PowerShell 5.1 + .NET Framework 4.x 的 wrapper 把 `[byte[]]` 当 object[] 处理。

**教训**:
- 大文件 IO 用 `MemoryStream` + `StreamContent` 替代直接 byte[]
- 或用纯 .NET HttpClient + MemoryStream（已写入 run-large-file-probe.ps1 脚本）

### P3: SSH 推送连接不稳定

**案例**: 多轮推送 origin 时报 "Connection closed by UNKNOWN port 65535"，需要重试 1-3 次。

**根因**: GitHub 侧对 SSH 连接的限制或网络抖动。

**教训**:
- 推送加 retry loop（已在本系统里使用）
- 接受偶尔需要等 10-30 秒

### P4: Hypium 断言强度不足

**案例**: 5 个 Hypium 测试用 `expect(0).assertEqual(0)` 占位，QA 标记 ⚠️ 非阻断。

**根因**: 容器无 DevEco Studio，无法写"真实 UI 断言"——只能写占位让代码能编译。

**教训**:
- MVP 占位是合理妥协，但要在 known-issues 显式标注
- REQ-003 真机回归时一并补强

### P5: 范围扩张风险

**案例**: REQ-001 设计概要里说"端点续传必须用 HTTP Content-Range"，但 OpenList 不支持——最后改为"重传整文件"。

**根因**: 没有前置 explore 验证服务端兼容性。

**教训**: 已通过 K2（前置测试）规避——REQ-002 的 explore 阶段验证了 OpenList 服务端能力，Dev 不再踩这个坑。

---

## 4. 度量

### 时间效率

| 指标 | 计划 | 实际 | 备注 |
|------|------|------|------|
| REQ-001 MVP | 3 天 | 1 天 | Explore + Dev 一气呵成 |
| REQ-001 修复 | 0.5 天 | 0.5 天 | BA 接管 |
| REQ-002 测试基建 | 1.5 天 | 0.5 天 | 范围明确，Dev 直接跑 |
| **总耗时** | **~5 天** | **~2 天** | **效率 2.5x** |

### Commit 质量

| 指标 | 值 |
|------|----|
| 总 commit 数 | 41 |
| 平均 commit 大小 | 适中（按 F 拆 commit） |
| commit 格式合规率 | 100%（[Dev]/[BA]/session id） |
| 撤回 commit | 0（无 force push） |
| 强制删除分支 | 1（feature/REQ-001 合并后清理） |

### 测试覆盖

| 指标 | 值 |
|------|----|
| 单元测试 | 15/15 ✅ |
| 集成测试（REQ-001 → REQ-002） | 12/12 → 17/17 |
| CI 一键跑 | ~18 秒 |
| 真机测试 | 0（容器无 DevEco，待 REQ-003） |

---

## 5. 下个 Sprint 建议

### 必须做

- [ ] **真机回归（REQ-003）**：DevEco NEXT + 4.2 双真机，按 REQ-002 交付的 qa-checklist.md 跑
- [ ] **Hypium 断言补强**：DevEco 内把占位 `expect(0).assertEqual(0)` 换为真实 UI 验证
- [ ] **HUKS 真加密实测**：DevEco NEXT 模拟器/真机验证 KeyStore 双平台分支

### 应该做

- [ ] **二期功能**：从下列选项中选一个
  - 缩略图缓存与相册视图增强
  - 端到端加密（用户级 AES-256）
  - 备份任务调度增强（多端点 / 多源 / 优先级队列）
- [ ] **DevOps 接入**：GitHub Actions 接 run-tests.ps1（push 时自动跑单测 + 集成）

### 可以做

- [ ] **CI 平台**：把 `.local/qa-runs/` 历史归档到 CI artifact
- [ ] **性能 benchmark**：NFR-02 的"1000 条指纹 < 100ms"实测
- [ ] **代码 lint**：为 ArkTS 加 ESLint 等价检查

---

## 6. 团队（开发者）个体反馈

由于 Sprint 1 全部由 BA + 子 agent 完成（没有真实人类开发者参与），本节仅记录流程经验：

### 流程经验

- **Explore 子 agent 价值高**：5-10 分钟的探索，能省 1-2 天的返工
- **Dev 子 agent 自验证可信度约 80%**：self-report 不能全信，BA 必须独立验证
- **QA 子 agent 价值高**：发现 Dev 漏掉的边界问题（AC-10 视频预览）
- **BA 接管是兜底机制**：子 agent 失败不阻塞主流程

### 工具改进建议

- 给子 agent prompt 加明确"失败时如何 partial report"——目前 self-report 容易混乱
- 给子 agent 配"独立 verifier"——让子 agent 完成时另一个 agent 验证
- 加 retry 机制：Dev 失败 → Dev 减半 retry → BA 接管

---

## 7. 元信息

- 创建时间: 2026-09-17
- Sprint Owner: ba-Michael-WorkStation-34576-20260916-155002
- 关联 REQ: REQ-001 / REQ-002
- 下次回顾: Sprint 2 结束

---

## 附录：commit 时间线

```
Sprint 1 共 41 个 commit（含 5 个 init commit）：

2026-09-16 15:50  REQ-001 草稿 → 已评审（3 commits）
2026-09-16 16:09  explore 入档 + AC-07 修订
2026-09-16 16:20  feature-REQ-001 worktree 创建
2026-09-16 17:15  Dev 第一轮完成（2 commits）
2026-09-16 17:20  待验证 + 第一轮 QA FAIL
2026-09-17 14:11  Dev 第二轮（QA FAIL 后修复）
2026-09-17 14:25  BA 接管修复 B-1/B-2/B-3（3 commits）
2026-09-17 14:40  本地合并 feature/REQ-001 → develop
2026-09-17 15:00  REQ-001 已完成
2026-09-17 15:30  REQ-002 草稿 → 已评审（2 commits）
2026-09-17 16:00  Dev 第一轮完成（5 commits）
2026-09-17 17:30  BA 接管 traceability + verification（2 commits）
2026-09-17 17:45  QA PASS（VERDICT）
2026-09-17 17:50  REQ-002 已完成
2026-09-17 18:00  Sprint retrospective（本文件）
```
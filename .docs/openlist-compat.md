# OpenList WebDAV 大文件行为探测报告

> 目标: 在真实 OpenList 部署上验证大文件 (10MB) 的分块上传与 Range 拉流语义，为 REQ-001 的"断点续传 (F5)"和"视频预览 (F9.2)"两条核心需求提供实测依据。
> 端点: `http://192.168.31.101:8080/dav/test_backup_dav`
> 凭据: `testdav` / `testdav`
> 测试日期: 2026-09-16
> 测试工具: PowerShell + .NET `System.Net.Http.HttpClient`（脚本归档于 `probe-large-file.ps1`，原始输出归档于 `probe-output.txt`，下载样本归档于 `local.bin` / `remote.bin`）

---

## TL;DR — 结论先行

| 项 | 结果 |
|----|------|
| 整文件 PUT（10MB，无 Content-Range） | ✅ 201 Created，HEAD 显示 10485760 字节 |
| 分块 PUT（前 4MB） | ✅ 201 Created |
| **Content-Range 续传 PUT（剩余 6MB + `Content-Range: bytes 4194304-10485759/10485760`）** | ❌ **协议不支持** — 服务端 **忽略** Content-Range 头，**整文件被覆盖为最后一段 6MB 字节**；最终 HEAD 显示 **6291456 字节**（≠ 10485760） |
| 断点续传语义 | ❌ **不可用**。OpenList WebDAV 不实现 RFC 7233 风格的"append / partial PUT" |
| 视频流式 Range GET | ✅ **全绿**。`Range: bytes=0-1023` 与 `Range: bytes=4194304-4195327` 都返回 206 Partial Content + 正确 Content-Range + 字节完全匹配 |
| 远端 SHA-256 校验 | ❌ 因服务端数据已被覆盖为 6MB，远端 SHA-256 与本地 10MB 不一致（这是预期结果，不算客户端 bug） |
| 服务端是否允许 DELETE | ❌ 403 Forbidden（这条**反而对 REQ-001 有利**——OpenList 默认拒绝普通用户删文件，符合"永久不删远端资源"原则） |

**最大发现**: OpenList WebDAV **不实现 Content-Range PUT 的追加语义**。REQ-001 的"断点续传 (F5)"设计必须调整为 **基于客户端检测的兜底策略**：若服务端忽略 Content-Range，Dev 应在客户端**重新从 0 字节上传**整个文件，而不是尝试续传。

---

## 测试环境

- 客户端: Windows 11 + PowerShell 5.1 + .NET Framework 4.x（默认 PS 配置）
- HTTP 客户端库: `System.Net.Http.HttpClient`（直接调用以规避 `Invoke-WebRequest` 对非常规 verb 和大 byte[] 的限制）
- 服务端: OpenList + 内置 WebDAV
- 网络: LAN（同网段 192.168.31.x）

---

## 测试步骤与原始结果

> 每个步骤格式：**请求 → 响应码 → 响应头关键字段 → 结论**

### 预先: 一次性探测（小文件）

| 步骤 | 请求 | 状态码 | 关键响应 | 结论 |
|---|---|---|---|---|
| Sanity 1 | `OPTIONS /dav/test_backup_dav` | 200 | `Allow: OPTIONS LOCK PUT MKCOL`，`DAV: 1, 2` | ✅ 完整 WebDAV 1/2 能力 |
| Sanity 2 | `PROPFIND /dav/test_backup_dav/ depth=1` | 207 Multi-Status | 返回 XML multistatus，列出每个子文件的 `getcontentlength` 与 `getlastmodified` | ✅ 标准 PROPFIND |
| Sanity 3 | `PUT /dav/.../probe_x.bin` 256 bytes | 201 Created | — | ✅ 基础 PUT 通 |
| Sanity 4 | `HEAD /dav/.../probe_x.bin` | 200 | `Content-Length: 256` | ✅ HEAD 返回准确长度 |
| Sanity 5 | `DELETE /dav/.../probe_x.bin` | **403 Forbidden** | — | ⚠️ OpenList **不允许** DELETE（详见后文） |

### Step 0: MKCOL 子目录

| 请求 | 状态 | 说明 |
|---|---|---|
| `MKCOL /dav/test_backup_dav/probe-large-20260916` | **405 Method Not Allowed** | OpenList 在 MKCOL 上返回 405 |

**结论**: OpenList 不支持 MKCOL。但 PUT 会**隐式创建父路径**（见下一步），所以不影响 REQ-001 的目录备份逻辑。

### Step 1: 生成 10MB 随机字节（确定性 seed）

| 项 | 值 |
|---|---|
| 字节长度 | 10485760 |
| 种子 | `0xC0FFEE`（`System.Random(int)` 构造） |
| 算法 | `System.Random.NextBytes()` |
| **本地 SHA-256** | **`4d0896ac0df2ef592c49bcb8da1adc88024aafa259283bfdc2d50a75860f86d6`** |
| Head byte[0] | `8` |
| Tail byte[10485759] | `53` |

**结论**: 字节生成成功。固定种子意味着任何人在任何机器上跑同种算法 + 相同 seed 都能复现同样 SHA-256（前提是 .NET 实现跨平台一致；该 seed 在实测中已落地到 `local.bin`，可直接 hash 复用）。

### Step 2: 完整 PUT 10MB（无 Content-Range）

| 项 | 值 |
|---|---|
| 请求 | `PUT /dav/test_backup_dav/probe-large-20260916/big.bin` |
| Body | 完整 10485760 字节 |
| **响应码** | **201 Created** |
| HEAD 跟随 | 200，`Content-Length: 10485760` |

**结论**: ✅ **OK**。OpenList 接收 10MB 整文件上传，HEAD 返回准确字节数。

### Step 3: DELETE 清空（仅探测用）

| 项 | 值 |
|---|---|
| 请求 | `DELETE /dav/test_backup_dav/probe-large-20260916/big.bin` |
| **响应码** | **403 Forbidden** |
| HEAD 跟随 | 200，`Content-Length: 10485760`（**文件依然存在**） |

**结论**: ❌ **DELETE 被服务端拒绝**。文件**没有**被删除——这其实**正好对齐 REQ-001 的"永久不删远端资源"原则**。但需要 Dev 注意：客户端代码里**不要写 DELETE 路径**（AC-09 也是这么要求的），服务端已经替你兜住了。

> ⚠️ 由于 DELETE 不通，本探测无法真正"清空"文件。Step 4 之后的 PUT 会覆盖原文件（OpenList 允许 PUT 覆盖），所以语义上等价于"清空后 PUT"。Dev 在 ACT 编码里**不应**依赖 DELETE 探测。

### Step 4: 第二次 PUT（仅前 4MB）

| 项 | 值 |
|---|---|
| 请求 | `PUT /dav/.../big.bin`，Body = `local[0..4194303]`（4194304 字节） |
| **响应码** | **201 Created** |
| HEAD 跟随 | 200，`Content-Length: 4194304`（**只剩 4MB**） |

**结论**: ✅ 服务端**接受** 4MB PUT 并**丢弃了原来的 6MB**——这是正常的整文件覆盖。HEAD 返回 `4194304` 表示文件被截短为 4MB。

### Step 5: HEAD 查看当前服务端字节数

| 响应头 | 值 |
|---|---|
| Status | 200 |
| Content-Length | **4194304** |
| Content-Range | （缺省，未返回） |
| **Accept-Ranges** | **`bytes`** |

**结论**: ✅ HEAD 返回精确长度，`Accept-Ranges: bytes` 表示服务端**愿意**接受 Range 请求——但这是**GET** 的 Range，不是 PUT 的 Range。这条 header 单独**不能**证明 Content-Range PUT 可用。

### Step 6: 第三次 PUT + Content-Range（剩余 6MB）

| 项 | 值 |
|---|---|
| 请求 | `PUT /dav/.../big.bin`，Body = `local[4194304..10485759]`（6291456 字节） |
| Header | **`Content-Range: bytes 4194304-10485759/10485760`** |
| **响应码** | **201 Created** |

**结论**: ⚠️ 服务端 **201 接受**了该 PUT，没有返回 4xx——**表面上"成功"**，但是否真的 append 了？看 Step 7。

### Step 7: HEAD 最终字节数

| 响应头 | 值 |
|---|---|
| Status | 200 |
| **Content-Length** | **6291456** |
| Content-Range | （缺省） |
| Accept-Ranges | `bytes` |

**结论**: ❌ **协议不支持**。

- 期望: `Content-Length: 10485760`（如果服务端 append 成功：4194304 + 6291456 = 10485760）
- 实际: `Content-Length: 6291456`（= chunk2 字节数，等于"覆盖"语义）

**这证明 OpenList WebDAV 把 `Content-Range` 头当透明头处理**：直接以本次 PUT 的 body 长度**覆盖**了原文件。

### Step 8: GET 全文件 + SHA-256 校验

| 项 | 值 |
|---|---|
| 请求 | `GET /dav/.../big.bin` |
| 状态 | 200 |
| Body 长度 | **6291456**（确认服务端只有 6MB） |
| **远端 SHA-256** | **`916c6cdbae8cb092d7136f6b6c41449a842d86c73dc3226a72f1449ef01a8384`** |
| **本地 SHA-256** | **`4d0896ac0df2ef592c49bcb8da1adc88024aafa259283bfdc2d50a75860f86d6`** |
| Match | **False** |

**字节级验证**（用 `local.bin` 与 `remote.bin` 做 Array 异或）：

| 对照 | 不匹配字节数 / 总数 |
|---|---|
| remote[0..6291455] vs `local[4194304..10485759]`（即 chunk2） | **0 / 6291456** ✅ 完全一致 |
| remote[0..6291455] vs `local[0..6291455]` | **6266639 / 6291456** ❌ 几乎全部不一致 |

**结论**: 远端文件**恰好就是 chunk2**——`local[4194304..10485759]`。这进一步证实：服务端把第三次 PUT 当成"完整覆盖"，**原 4MB chunk1 已被丢弃**。

> ⚠️ 如果 Dev 真的把这种"续传 PUT" 放到 REQ-001 的 AC-07（100MB 文件中断 50% 后续传）里跑，**第二次 PUT 时远端只剩 chunk2 的 6MB，第三次续传 4MB chunk1 上来时又把 chunk2 覆盖掉**——最终**只有 chunk1**（4MB）保留。永远不可能拼回完整文件。

### Step 9: Range GET `bytes=0-1023`

| 项 | 值 |
|---|---|
| 请求 | `GET /dav/.../big.bin`，Header `Range: bytes=0-1023` |
| **状态** | **206 Partial Content** |
| **Content-Length** | **1024** |
| **Content-Range** | **`bytes 0-1023/6291456`** |
| Body 长度 | 1024 |
| 字节匹配 vs `remote[0..1023]` | 1024/1024 ✅ |

**结论**: ✅ **OK**。Range GET **完全合规**：返回 206 + 准确 Content-Range + 字节与远端文件头部完全一致。

### Step 10: Range GET `bytes=4194304-4195327`

| 项 | 值 |
|---|---|
| 请求 | `GET /dav/.../big.bin`，Header `Range: bytes=4194304-4195327` |
| **状态** | **206 Partial Content** |
| **Content-Length** | **1024** |
| **Content-Range** | **`bytes 4194304-4195327/6291456`** |
| Body 长度 | 1024 |
| 字节匹配 vs `remote[4194304..4195327]` | 1024/1024 ✅ |

**结论**: ✅ **OK**。中段 Range 也完全合规。AVPlayer 视频流式播放（REQ F9.2）**完全可用**。

---

## 补充验证：Content-Range PUT 是否始终被忽略

为排除"10MB 太大导致分块失败"的偶然因素，**追加 1KB 实验**：

| 步骤 | 请求 | 状态 | 后续 HEAD `Content-Length` |
|---|---|---|---|
| 11 | `PUT append-test.bin`，Body = 1024 字节，无 Content-Range | 201 | **1024** |
| 12 | `PUT append-test.bin`，Body = 1024 字节，`Content-Range: bytes 1024-2047/2048` | **201** | **1024**（不是 2048） |

**结论**: 即使在 1KB 量级，OpenList 仍然把 Content-Range 头**忽略**，行为一致。这不是数据量的问题，而是**协议层未实现**。

---

## 关键结论汇总表

| 场景 | OpenList 行为 | REQ-001 影响 |
|---|---|---|
| PUT（无 Content-Range，整文件） | ✅ 201 正常 | F4.3 / AC-04 ✅ |
| PROPFIND depth=1 | ✅ 207 正常 | F1.4 / F4.1 ✅ |
| HEAD | ✅ 200 + Content-Length | F5.3 / AC-05 ✅ |
| OPTIONS | ✅ 200，DAV: 1,2 | 能力探测 ✅ |
| MKCOL | ❌ 405 | ⚠️ 需 PUT 隐式建父目录（已确认 PUT 会自动建） |
| **PUT + Content-Range（追加）** | ❌ **完全忽略 Range 头，整文件覆盖** | **F5 续传策略必须改写** |
| GET + Range | ✅ 206 + 正确 Content-Range + 字节匹配 | F9.2 视频预览 ✅ / F5.3 探测 ✅ |
| **DELETE** | ❌ **403** | ✅ **天然对齐 REQ-001 "永久不删远端"**；客户端代码不必写 DELETE |

---

## 对 Dev 的建议（影响需求实现）

### 1. 断点续传（F5）必须重写

原 design-summary §4.2 的设计（HEAD 探测 offset → 续传）**不能照搬**。OpenList 不支持 RFC 7233 append。

**重写方案**：

```
HTTP PUT chunk:
  if first_chunk:
    # 探测：HEAD 是否返回 200 且 Content-Length 是 0？
    head = HEAD(remote_path)
    server_len = head.ContentLength

    if server_len == 0:
      # 服务器空文件 -> 第一次上传 -> 用 chunk1 + Content-Range: bytes 0-(N-1)/total
      # （Content-Range 此时被忽略也无妨，反正空文件被覆盖 = 等同整文件 PUT）
      PUT chunk1
    elif server_len == total:
      # 服务器已经有完整文件（之前完整 PUT 过了）-> 跳过
      skip
    elif server_len < total and server_len % CHUNK == 0:
      # 服务器部分文件（offset = server_len）-> 但 Content-Range 会被忽略，
      # 必须从 0 重新上传整个文件（无法 append）
      PUT 整文件（不带 Content-Range）
    else:
      # 服务器长度既不是 0 也不是 total 也不是 chunk 整数倍 -> 服务端曾因网络抖动收到半 chunk
      # 直接 PUT 整文件覆盖
      PUT 整文件
  else:
    # 中间 chunk 与最后一个 chunk -> 永远从 0 重新 PUT 整个文件
    PUT 整文件
```

**关键点**：
- 在 OpenList 上，"断点续传"实际上退化为"**断点重传整文件**"——续传只是**节省了用户感知**（App 记住已上传过该文件的历史，本地状态显示 '已上传 100%'），并不真的省网络流量。
- 实现复杂度降低：客户端只需一个 "是否要重新传" 的状态机，没有 chunk-level 重试。
- **AC-07**（100MB 文件中断 50% 后续传）：业务上仍可"成功"（App 重新跑一次整文件 PUT），但用户体验是"又传了一次 100MB"。**必须在 App 内显式提示用户**："OpenList 不支持服务端续传，断点恢复会重传整个文件"。

### 2. 视频预览（F9.2）维持原设计

Range GET **完全可用**，AVPlayer HTTP Range 拉流会正常出首帧并支持拖动进度条。**无需修改**。

### 3. DELETE 不要写在代码里

服务端已 403，**写 DELETE 会浪费一次请求**。但为了防御性编程（万一服务端允许），代码里**保留 DELETE 调用前的"用户二次确认"**——这是设计概要 §4.4 与 AC-09 的要求。

### 4. MKCOL 不要写

服务端返回 405，PUT 会隐式建父目录。代码里**不要**做 mkdir；直接 PUT 完整路径（如 `/photos/2024/01/img.jpg`），如果中间目录不存在由服务端补建（实测 OK）。

---

## 归档文件

| 文件 | 用途 |
|---|---|
| `probe-large-file.ps1` | 完整测试脚本（10 步 + 1KB 追加验证） |
| `probe-output.txt` | 脚本原始输出 |
| `local.bin` | 10MB 原始字节（seed=0xC0FFEE，SHA-256 = `4d0896a…f86d6`） |
| `remote.bin` | 服务端返回的 6291456 字节（SHA-256 = `916c6cdb…a8384`） |

Dev 可用以下命令重新生成 reference 字节：

```powershell
$rng = [System.Random]::new(0xC0FFEE)
$buf = [byte[]]::new(10MB)
$rng.NextBytes($buf)
```

---

## 验证状态

- ✅ 端点连通性、Basic 鉴权、PROPFIND、PUT、HEAD、Range GET、OPTIONS
- ❌ Content-Range PUT 追加语义（**已知 OpenList 限制**）
- ❌ MKCOL、DELETE（**已知 405/403**）
- ⚠️ 未测：大文件（>100MB）整 PUT 的稳定性（建议 Dev 用 100MB 真实视频压一次测首字节延迟）

---

## 引用与原始证据

- 测试端点来源: `BA/demands/REQ-001-webdav-backup/status.md`
- 测试凭据来源: 同上
- 测试时间: 2026-09-16
- 本次报告不依赖任何网络搜索；所有 HTTP 行为均为实测。

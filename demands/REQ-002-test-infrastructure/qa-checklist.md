# 真机回归 checklist — REQ-001（REQ-002 F2）

> 此 checklist 给 REQ-003 真机回归使用。每条 AC / NFR 列出 step-by-step 操作。
> 跑前：确保 DevEco NEXT + DevEco 4.2 双真机或模拟器各跑一次。
>
> 取证规范：
> - 截屏：保存到 `code/.local/qa-runs/<YYYYMMDD-HHmmss>/screenshots/acNN-<slug>.png`
> - 日志：保存到 `code/.local/qa-runs/<YYYYMMDD-HHmmss>/logs/acNN-<slug>.log`
> - 设备记录：在 `code/.local/qa-runs/<timestamp>/device-info.md` 写明设备型号 / HarmonyOS 版本 / 应用版本号
>
> 测试端点（统一用 BA 验证过的 OpenList 实例）：
> - URL: `http://192.168.31.101:8080/dav/test_backup_dav`
> - 用户名: `testdav` / 密码: `testdav` / 根路径: `/`

---

## AC-01: 多 WebDAV 端点管理

- [ ] 打开 App → 端点设置 → 点击顶部"新增"
- [ ] 名称填 `e2e-A` / URL 填 `http://192.168.31.101:8080/dav/test_backup_dav`
- [ ] 用户名 `testdav` / 密码 `testdav` / 根路径 `/`
- [ ] 点击"保存"
- [ ] **期望**：列表立即出现 `e2e-A` 卡片，状态显示"已启用"
- [ ] 再次点击"新增" → URL 故意拼错为 `http://192.168.31.101:8080/dav/typo_url`
- [ ] 保存后点击该端点的"测试连接"
- [ ] **期望**：弹错误提示（DNS 失败 / 401 / 404），≤3 秒返回
- [ ] **截屏**：`screenshots/ac01-endpoint-list.png` + `screenshots/ac01-bad-connect.png`
- [ ] **日志路径**：`logs/ac01-http.log`（adb logcat | grep WebDAVClient）

---

## AC-02: 凭据 KeyStore 加密

- [ ] 添加端点 `e2e-A` 后，停留在端点列表页
- [ ] 系统设置 → 应用管理 → 该 App → 存储 → 查看占用
- [ ] 导出应用数据（系统设置 → 应用管理 → 存储 → 导出）
- [ ] 在导出包内 grep 密码明文 `testdav`
- [ ] **期望**：明文 `testdav`（作为 password 字段值）**找不到**；
        只能找到 `endpoints.password_cipher` 列下的 base64 blob
- [ ] 用 `hdc shell hilog | grep KeyStore` 确认 KeyStore 中存在对应 alias
- [ ] **截屏**：`screenshots/ac02-storage.png`
- [ ] **日志路径**：`logs/ac02-keystore.log`

---

## AC-03: 相册实时备份

- [ ] 端点 `e2e-A` 已连接；新建任务，源 = 相册，仅 Wi-Fi = 开，实时监测 = 开
- [ ] 设备连入 Wi-Fi
- [ ] 用系统相机拍一张照片
- [ ] 等待 ≤5 秒
- [ ] 进入 App → 上传历史 → "成功" Tab
- [ ] **期望**：新增一条 `success` 记录；远端 `/photos/` 目录能列到该文件
- [ ] **截屏**：`screenshots/ac03-history.png`
- [ ] **日志路径**：`logs/ac03-gallery.log`

---

## AC-04: 自定义目录备份

- [ ] 端点 `e2a-A` 已连接；新建任务，源 = 目录 `/Download/manual_e2e/`，远端 `/manual_e2e/`
- [ ] 用文件管理器在 `/Download/manual_e2e/` 放入 `a.txt`（100KB）+ `b.zip`（2MB）
- [ ] 在任务卡片点击"立即对账"
- [ ] **期望**：对账结束后历史"成功" Tab 新增 2 条
- [ ] **截屏**：`screenshots/ac04-tasks.png` + `screenshots/ac04-history.png`
- [ ] **日志路径**：`logs/ac04-reconcile.log`

---

## AC-05: 定时对账触发

- [ ] 端点 `e2e-A` 已连接；将某任务的"对账间隔"改为 `1 小时`
- [ ] 临时关闭该任务的"实时监测"
- [ ] 开发者选项 → 把 `lastReconcileAt` 改成 2 小时前
- [ ] 拍一张照片（实时监测关闭，应不立即上传）
- [ ] 等待 ≤5 秒，历史 Tab 不应有新条目
- [ ] 完全杀掉 App，重新启动
- [ ] **期望**：启动后触发对账，刚才拍的照片被检测并上传，历史新增成功条目
- [ ] **截屏**：`screenshots/ac05-no-realtime.png` + `screenshots/ac05-after-restart.png`
- [ ] **日志路径**：`logs/ac05-reconcile-on-startup.log`

---

## AC-06: 增量同步——首末 1MB 抽样指纹

- [ ] 端点 `e2e-A` 上传过一个 50MB 视频（AC-03 / AC-04 阶段已经产生）
- [ ] 进入该任务的"立即对账"
- [ ] ssh 到远端记录 mtime：`stat /dav/test_backup_dav/<file>.mp4`
- [ ] 等待对账完成（≤30 秒）
- [ ] ssh 再次 `stat` 同一文件
- [ ] **期望**：mtime **未变**（指纹命中，不重新上传）
- [ ] 历史 Tab 不应新增 `success` 条目
- [ ] **截屏**：`screenshots/ac06-no-mtime-change.png`
- [ ] **日志路径**：`logs/ac06-fingerprint-hit.log`

---

## AC-07: 断点续传（重传策略）

- [ ] 端点 `e2e-A` 已连接；准备上传一份 100MB 文件（可复制一个大视频）
- [ ] 在远端创建 `/e2e-ac07/big.bin` 占位，先 PUT 50% 后用 Fiddler / Charles 中断
- [ ] App 内触发对账；观察上传队列（占位文件被识别为"服务端有不完整数据"）
- [ ] App UI 应显示明确提示："OpenList WebDAV 不支持服务端续传，断点恢复会重传整个文件"
- [ ] 等待完整 PUT 完成
- [ ] **期望**：文件最终 100% 上传成功；远端 SHA-256 与本地一致
- [ ] **截屏**：`screenshots/ac07-banner.png` + `screenshots/ac07-success.png`
- [ ] **日志路径**：`logs/ac07-retransmit.log`（含 SHA-256 输出）

---

## AC-08: 失败重试与指数退避

- [ ] 端点 `e2e-A` 已连接
- [ ] 用网络代理工具（Fiddler / Charles）拦截 WebDAV PUT 请求，返回 503
- [ ] App 内上传一份新文件
- [ ] 观察上传过程 + 历史 Tab
- [ ] **期望**：尝试 5 次，间隔分别为 1s / 2s / 4s / 8s（≈15 秒内结束）
        5 次后进入"失败"Tab，状态"重试次数耗尽"
- [ ] **截屏**：`screenshots/ac08-retry-countdown.png` + `screenshots/ac08-failed.png`
- [ ] **日志路径**：`logs/ac08-backoff.log`（含 4 次重试的时间戳）

---

## AC-09: 不删除 WebDAV 资源

- [ ] 端点 `e2e-A` 已上传过 3 个文件
- [ ] 用 ssh 列出远端 `/photos/`，记下 3 个文件名 + 大小
- [ ] 在本地删除其中一个文件（任意一个）
- [ ] 在 App 内触发"立即对账"
- [ ] ssh 再次列出 `/photos/`
- [ ] **期望**：远端 3 个文件**全部仍然存在**（App 不发 DELETE）
- [ ] App 历史 Tab：被本地删除的文件状态显示"本地已删除，远端保留"
- [ ] **截屏**：`screenshots/ac09-remote-listing.png` + `screenshots/ac09-history-state.png`
- [ ] **日志路径**：`logs/ac09-no-delete.log`

---

## AC-10: WebDAV 资源预览

- [ ] 端点 `e2e-A` 上传过至少 1 张图片（jpg）+ 1 个 mp4 视频
- [ ] 进入 App → 上传历史 → 成功 Tab → 点击某条图片记录 → 打开图片预览
- [ ] **期望**：Image 组件渲染图片（jpg / png / heic / webp）
- [ ] 点击某条视频记录 → 打开视频播放器
- [ ] **期望**：视频开始播放，进度条可拖动（拖动后视频跳到对应位置）
- [ ] **截屏**：`screenshots/ac10-image.png` + `screenshots/ac10-video.png`
- [ ] **日志路径**：`logs/ac10-range-get.log`（观察 HTTP Range 请求）

---

## AC-11: 仅 Wi-Fi 选项生效

- [ ] 端点 `e2e-A`；某任务的"仅 Wi-Fi"= 开
- [ ] 关闭 Wi-Fi，确认 4G 在线
- [ ] 拍一张照片
- [ ] 等待 30 秒
- [ ] **期望**：历史 Tab **不**新增条目（4G 期间不触发上传）
- [ ] 打开 Wi-Fi
- [ ] 等待 ≤5 秒
- [ ] **期望**：历史 Tab 新增一条 `success`（Wi-Fi 恢复后立即上传）
- [ ] **截屏**：`screenshots/ac11-4g-no-upload.png` + `screenshots/ac11-wifi-upload.png`
- [ ] **日志路径**：`logs/ac11-network-switch.log`

---

## NFR-01: App 冷启动 < 2 秒

- [ ] 完全杀掉 App（adb shell am force-stop + 上滑清除）
- [ ] 启动 App（adb shell am start -n com.example.webdavbackup/.EntryAbility）
- [ ] 立即读取首页 `IndexPage.ets` 顶部 `启动 Xms` 文字
- [ ] **期望**：`< 2000 ms`（中端鸿蒙设备）
- [ ] 重复 3 次取最大值
- [ ] **截屏**：`screenshots/nfr01-startup.png`
- [ ] **日志路径**：`logs/nfr01-startup.log`（含 3 次测量值）

---

## NFR-02: 1000 条指纹库查询增量同步判定 < 100ms

- [ ] 准备 1000 条假指纹（脚本生成：随机 filePath / size / mtime / hashHead / hashTail）
- [ ] 用 REQ-001 提供的指纹纯函数 `isFingerprintMatch(a, b)` 跑 1000 次查询
- [ ] 用 Node 测：`node -e "const t0=Date.now(); for(let i=0;i<1000;i++) isFingerprintMatch(a,b); console.log(Date.now()-t0,'ms')"`
- [ ] **期望**：`< 100ms`
- [ ] **截屏**：`screenshots/nfr02-bench.png`
- [ ] **日志路径**：`logs/nfr02-fingerprint-perf.log`

---

## NFR-03: 鸿蒙 4.2 与 NEXT 双平台均能安装运行

- [ ] 在 4.2 真机（或模拟器）侧载 HAP 包
- [ ] 启动 App，能进入首页 + 端点 / 任务 / 历史 / 预览 4 个菜单
- [ ] 在 NEXT 真机（或模拟器）侧载**同一**包（同一签名）
- [ ] 启动 App，4 个菜单都能进入
- [ ] **期望**：两台设备功能无差异（仅双平台分支代码路径不同）
- [ ] **截屏**：`screenshots/nfr03-hmos42.png` + `screenshots/nfr03-next.png`
- [ ] **日志路径**：`logs/nfr03-platform.log`

---

## NFR-04: 应用本地日志 ≤ 50MB，自动轮转 7 天

- [ ] 用脚本生成 60MB 日志条目写入 App 日志目录（`files/logs/app.log`）
- [ ] 等待 App 下一次写入触发轮转
- [ ] 检查日志目录：
  - [ ] 当前 `app.log` ≤ 50MB
  - [ ] 轮转文件 `app.log.YYYY-MM-DD` 存在
- [ ] 修改系统时间到 8 天前，重启 App
- [ ] 触发一次日志写入
- [ ] **期望**：8 天前的轮转文件被自动清理
- [ ] **截屏**：`screenshots/nfr04-log-rotation.png`
- [ ] **日志路径**：`logs/nfr04-rotation.log`

---

## 跑完后的归档

完成后由 QA 在 `code/.local/qa-runs/<YYYYMMDD-HHmmss>/` 目录下：
1. 复制此 checklist 为 `checklist-filled.md`，每条 step 后追加 `[x]`，并在 `[ ]` 后加 ✅ / ⚠️ / ❌ + 一句话说明
2. 填 `code/.local/qa-runs/<timestamp>/device-info.md`（设备型号 / OS 版本 / 应用版本）
3. 用 `BA/demands/REQ-002-test-infrastructure/templates/qa-report-template.md` 写最终报告
4. 上传截图与日志到 `screenshots/` 和 `logs/` 子目录

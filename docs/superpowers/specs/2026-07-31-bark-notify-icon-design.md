# 移除 SSH/iMessage、改用 Bark 提醒、新增 App 图标 — 设计 spec

日期：2026-07-31（2026-08-03 增补：吸收交接文档三项未决问题）
状态：已获用户批准

## 背景与目标

1. **删除**整套「iPhone 通过 SSH 远程让 Mac 睡眠」功能（用户不用了）。
2. **长时间合盖提醒**的通知通道从 iMessage 换成 **Bark**（iOS 推送 App，官方服务器 `api.day.app`，仅配 device key）。
3. 给 Clamshell Mode.app 做一个**贝壳母题的 App 图标**（当前没有图标）。
4. **（增补）收编两处孤本改动进 main**：光标/WindowServer 修复（原存于旧克隆未推分支 `fix/menubar-refresh-window-storm` @3f14aa2 与部署版 lua）；Bark 发送骨架（原只存在于部署版 lua，字段 `barkURL`，但用户 config 从未配置过该键——**无数据迁移负担**）。
5. **（增补）部署同步**：main 完成后用 install.sh 重新部署 `~/.hammerspoon/`，消灭「仓库 ≠ 运行时」分裂（现场已有备份 `~/.hammerspoon/backup-20260803-052548/`）。
6. 全部完成后 commit + push GitHub。**朋友机器（tsc@100.100.15.127）这轮不动**，以后 git pull + install.sh 自行升级。

## 1. 删除 SSH 远程切换

- `SetupView.swift`：删「Mac 快捷指令」卡片（`macShortcutCard`）、「iPhone 远程触发设置」卡片（`iphoneSetupCard`）、状态卡中 Remote Login (SSH) 行、`sshOn` / `addresses` state 及 `refresh()` 中对应读取。Setup 页保留：Hammerspoon 运行状态、pmset 免密 sudo 状态。
- `SystemInfo.swift`：删除仅为 SSH 功能服务的成员——`isSshEnabled`、`localHostname`、`networkAddresses`、`friendlyLabel`、`openShortcutsApp`、`username`；`copyToClipboard` 与 `CodeBlock`（SetupView 底部 struct）若 grep 确认无其他引用一并删除。保留 `runShell`、`isHammerspoonRunning`、`isSudoersConfigured`、`reloadHammerspoon`；`sleepDisabled` 同样按 grep 结果决定去留。
- README 中英文：「iPhone 远程切回睡眠」/「iPhone remote sleep」整节删除；功能列表、组件表中相关行删除。

## 2. iMessage → Bark

### 配置（`clamshell-config.json`）

- 删 `phone`；新增 `barkKey: String = ""`（空 = 不推送）。`notifyEnabled` / `notifyDelaySec` 语义不变。
- **迁移安全**：`ClamshellConfig` 增加自定义 `init(from decoder:)`，**所有字段** `decodeIfPresent` + 默认值兜底——现有 JSON 缺 `barkKey` 时不得整体解码失败（否则 GUI 全部设置回退默认）。encode 用编译器合成版本（`phone` 字段已删，保存后旧键自然消失）。lua 侧 loadConfig 本就容忍多余/缺失键，无需迁移逻辑。
- `install.sh` 第 5 步默认 config JSON：`"phone": ""` → `"barkKey": ""`。

### 发送（`clamshell.lua`）

- `sendIMessage(text)` → `sendBark(body)`：`hs.http.asyncGet` 请求
  `https://api.day.app/<barkKey>/<title>/<body>`，title 固定 `Clamshell Mode`，title/body 用 `hs.http.encodeForQuery` 逐段 URL 编码；回调里 status ≠ 200 仅 `print` 日志，不打扰用户（沿用部署版 sendBark 的骨架，把 barkURL 拼接改为 barkKey + 官方服务器 + 标题段）。
- 触发逻辑不变：唤醒模式合盖超过 `notifyDelaySec` 发一条；提醒文案沿用原中文（"…已合盖 N 分钟…"）。
- 守卫从 `phone == ""` 改为 `barkKey == ""`。cfg 默认表删 `phone`、加 `barkKey = ""`。

### （增补）光标/WindowServer 修复转正（`clamshell.lua`）

把部署版 / 旧克隆 3f14aa2 的修复原样收进 main（部署版已验证多日）：

- `lastSleepDisabled` 状态缓存；`refreshMenu(force)` 在 `not force and disabled == lastSleepDisabled` 时直接 return——无条件每秒重设菜单栏项会让 macOS 反复重排整条菜单栏，macOS 27 上表现为 WindowServer 刷 `_CGXPackagesSetWindowConstraints: Invalid window`（约 120 次/分钟），偶发 `set_cursor_surface` 失败、光标不变形。
- `toggleClamshell` 内改调 `refreshMenu(true)`（点击/热键路径强制重绘）。
- 菜单栏刷新定时器与盖子轮询解耦：`menuInterval = cfg.menuRefreshInterval or 15`（原来跟 `pollInterval` 共用 1 秒，每秒 fork `pmset -g | awk` 子进程是残余 Invalid window 的来源）。`menuRefreshInterval` 仅作为 lua 侧可选配置键，**不进 GUI**（YAGNI）。
- 保留部署版里解释这两处的注释。

### GUI（`SettingsView.swift`）

- 「iMessage 长时间合盖提醒」分区 → 「**Bark 长时间合盖提醒**」：
  - 启用开关（`notifyEnabled`，原样）
  - device key 输入框（monospaced；caption：*「App Store 安装 Bark → 首页复制 device key」*）
  - 延时阈值滑块（原样，1–120 分钟）
  - 「**发送测试推送**」按钮：用 `URLSession` GET 同一 URL（body = "测试推送 ✓"），结果就地显示（✓ 已发送 / ✗ HTTP 状态码或错误），按钮在 key 为空时禁用。

## 3. App 图标（贝壳母题）

- 视觉：合起的贝壳，开缝处透出一线亮光（呼应"合盖但醒着"），macOS Big Sur+ 圆角方块（squircle）风格，深色渐变背景。
- 资产管线：`app/AppIcon.svg`（母版，进仓库）→ 无头 Chrome 渲染 1024×1024 PNG → `sips` 缩出 16/32/64/128/256/512/1024 → `iconutil -c icns` → `app/AppIcon.icns`（进仓库）。
- 选稿流程：先做 2–3 个配色/构图变体，渲染 PNG 后 `open` 进 Preview，用户挑一版定稿再产 icns。
- `app/build-app.sh`：把 `AppIcon.icns` 拷入 `Contents/Resources/`，Info.plist 加 `<key>CFBundleIconFile</key><string>AppIcon</string>`。
- `AboutView`（ContentView.swift 内）：`Image(systemName: "laptopcomputer")` → `Image(nsImage: NSApp.applicationIconImage)`。
- 菜单栏 icon-sleep/icon-awake 不动。

## 4. 测试与验证

- 新增单测（`ConfigTests.swift`）：
  1. 旧格式 JSON（含 `phone`、无 `barkKey`）解码成功且其余字段值保留；
  2. 空 JSON `{}` 解码 = 全默认值；
  3. encode 后不含 `phone` 键。
- 既有 15 个 ScreenTimers 单测保持全绿。
- E2E：`build-app.sh` 装好 → GUI 填真实 key → 点测试推送 → 用户 iPhone 收到即通过；图标在 Dock/Finder/About 页显示正确。合盖超时链路复用原 timer 逻辑，不专门实测。

## 5. 非目标

- 不做多通知通道抽象、自建 Bark 服务器支持、推送加密（Bark 支持但 YAGNI）。
- 不动系统亮屏时间分区、亮度渐变、快捷键、菜单栏图标等既有功能。

## 交付

- **部署同步**：main 验证通过后跑 `./install.sh` 重新部署 `~/.hammerspoon/`（脚本对已存在的 config JSON 不覆盖；用户现有 config 里残留的 `phone` 键无害，GUI 首次保存后自动消失），reload 后确认菜单栏图标 + 盖子轮询正常。
- **DEV_NOTES 修正**：删除两处过期的「本目录当前不是 git 仓库」表述（自 2026-07-31 commit 464c0d3 起已是 git 仓库且有 origin），并按 /sync 惯例补记本轮改动；SESSION_LOG 追加条目。
- commit、push `origin/main`（连同此前未推的 spec commit 一起）。
- 旧克隆 `~/clamshell-mode-mac` 与其分支 `fix/menubar-refresh-window-storm` 在修复收编进 main 后即无孤本价值，本轮不删除、不合并，仅在 DEV_NOTES 记一句"可清理"。

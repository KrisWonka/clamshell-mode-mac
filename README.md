# clamshell-mode-mac

macOS 「合盖不睡眠」一键切换 + 合盖自动调暗 / 开盖渐亮。无需外接显示器。

- **菜单栏图标**（SF Symbol 渲染）一键切换
- **唤醒模式下** 合盖：系统继续运行（程序、下载、训练全部不中断），屏幕亮度归 0 省电护屏
- **开盖瞬间** 用 60fps 小数精度过渡平滑升回原亮度，无突兀闪烁
- **iPhone 远程切回** 通过 Shortcuts SSH 一键关闭唤醒并立即睡眠
- **长时间合盖 iMessage 提醒**（可选），方便包里跑着别忘了

> Apple Silicon Mac 验证通过。Intel Mac 理论也可用，但 `setbrightness` 工具未测试。

## 工作原理

绕开 macOS 在没有外接显示器时强制睡眠的限制：用 `pmset disablesleep 1` 在系统层关掉合盖触发的睡眠。盖子开关状态用 `ioreg AppleClamshellState` 轮询；亮度通过私有框架 `DisplayServices` 直接调用，达到比公开 API 更细的小数级精度。

| 组件 | 作用 |
|------|------|
| `clamshell.lua` | Hammerspoon 主逻辑：菜单栏、轮询、亮度协调 |
| `setbrightness` (Swift) | 调 `DisplayServicesSetBrightness` 私有 API，60fps 内置 fade |
| `Clamshell Mode.app` (SwiftUI) | 配置 GUI：状态检查、网络识别、所有可调项 |
| `~/.hammerspoon/clamshell-config.json` | 单一配置源，App 写入，lua 读取 |
| `/etc/sudoers.d/clamshell-mode-pmset` | 让 `pmset` 免密 sudo |

## 安装

依赖：[Hammerspoon](https://www.hammerspoon.org/)、Xcode Command Line Tools (`xcode-select --install`)。

```bash
git clone https://github.com/KrisWonka/clamshell-mode-mac.git
cd clamshell-mode-mac
./install.sh
```

安装脚本会：
1. 编译 `setbrightness` 到 `~/.hammerspoon/`
2. 在 `/etc/sudoers.d/` 写一条仅放行 `pmset` 的免密规则（要你输一次密码）
3. 拷贝 `clamshell.lua` + 默认菜单栏图标到 `~/.hammerspoon/`
4. 在 `~/.hammerspoon/init.lua` 里追加 `require("clamshell")`
5. 写入默认 `clamshell-config.json`（已存在就不动）
6. 编译 `Clamshell Mode.app` 装到 `/Applications/`
7. 重载 Hammerspoon

完成后右上角菜单栏出现 SF Symbol 图标，Spotlight 搜「Clamshell」打开 GUI 配置面板。

## 使用

### 菜单栏 / 快捷键
- 点菜单栏图标切换睡眠/唤醒模式
- 默认快捷键 **`⌃⌥⌘ + 6`**（在 GUI Settings 里可改）
- 唤醒模式下合盖：屏幕亮度归 0；开盖：1.5s 平滑升回

### 配置 GUI（**Clamshell Mode.app**）
Spotlight 搜「Clamshell」打开。三个标签：

- **Setup**：实时检测 Hammerspoon / SSH / sudoers 状态；列出所有网络接口的 IP（自动识别 iPhone 热点 / Tailscale / WiFi）；展示 Mac 端 Shortcut 脚本供复制
- **Settings**：手机号、提醒延时（1–120 分钟）、亮度过渡时长、快捷键、菜单栏图标（任意 SF Symbol）、各功能独立开关。**保存后自动重载**
- **About**：仓库链接

### iPhone 远程切回睡眠

1. Mac 端开 Remote Login（系统设置 → 通用 → 共享 → 远程登录）
2. 用 GUI 的 Setup 页查 IP（推荐 Tailscale，跨网络稳定；同 WiFi 用 Bonjour 名）
3. iPhone Shortcuts 新建 → 加「**通过 SSH 运行脚本**」→ 填 GUI 显示的 Host / User / Port，脚本：
   ```
   /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0 && /usr/bin/pmset sleepnow
   ```

> ⚠️ 合盖不睡时机器在包里散热受限，电池也消耗更快。长时间不用记得切回。

## 手动改配置

不开 GUI 也能改 —— 编辑 `~/.hammerspoon/clamshell-config.json`，然后 reload Hammerspoon。

```json
{
  "fadeEnabled": true,
  "fadeDuration": 1.5,
  "pollInterval": 1,
  "hotkeyEnabled": true,
  "hotkeyMods": ["ctrl", "alt", "cmd"],
  "hotkeyKey": "6",
  "notifyEnabled": false,
  "phone": "+8613...",
  "notifyDelaySec": 900,
  "iconSleep": "zzz",
  "iconAwake": "cup.and.saucer.fill"
}
```

## 卸载

```bash
./uninstall.sh
```

或手动：

```bash
rm ~/.hammerspoon/{setbrightness,clamshell.lua,clamshell-config.json,icon-sleep.png,icon-awake.png}
rm -rf "/Applications/Clamshell Mode.app"
sudo rm -f /etc/sudoers.d/clamshell-mode-pmset
# 编辑 ~/.hammerspoon/init.lua，删掉 require("clamshell") 那两行
# 然后 reload Hammerspoon
```

## 致谢

- [Hammerspoon](https://www.hammerspoon.org/) — macOS 自动化框架
- `DisplayServices` 私有框架的用法参考社区多年积累

## License

MIT

# clamshell-mode-mac

macOS 「合盖不睡眠」一键切换 + 合盖自动调暗 / 开盖渐亮。无需外接显示器。

- **菜单栏图标** 💤 / ☕️ 一键切换
- **☕️ 模式下** 合盖：系统继续运行（程序、下载、训练全部不中断），屏幕亮度归 0 省电护屏
- **开盖瞬间** 用 60fps 小数精度的过渡平滑升回合盖前亮度，无突兀闪烁

> Apple Silicon Mac 验证通过。Intel Mac 理论也可用，但 `setbrightness` 工具未测试。

## 工作原理

绕开 macOS 在没有外接显示器时强制睡眠的限制：用 `pmset disablesleep 1` 在系统层关掉合盖触发的睡眠。盖子开关状态用 `ioreg AppleClamshellState` 轮询检测；亮度通过私有框架 `DisplayServices` 直接调用，做到比公开 API 更细的小数级精度。

| 组件 | 作用 |
|------|------|
| `clamshell.lua` | Hammerspoon 主逻辑：菜单栏、轮询、亮度协调 |
| `setbrightness` (Swift) | 调 `DisplayServicesSetBrightness` 私有 API，支持 60fps 内置 fade |
| `/etc/sudoers.d/clamshell-mode-pmset` | 让 `pmset` 免密 sudo，菜单栏点击无需弹密码 |

## 安装

依赖：[Hammerspoon](https://www.hammerspoon.org/)、Xcode Command Line Tools (`xcode-select --install`)。

```bash
git clone https://github.com/KrisWonka/clamshell-mode-mac.git
cd clamshell-mode-mac
./install.sh
```

安装脚本会：
1. 编译 `setbrightness` 到 `~/.hammerspoon/`
2. 在 `/etc/sudoers.d/` 写一条仅放行 `pmset` 的免密规则（会要你的密码一次）
3. 把 `clamshell.lua` 拷到 `~/.hammerspoon/` 并在 `init.lua` 里 `require("clamshell")`
4. 重载 Hammerspoon

完成后右上角菜单栏会出现 💤。

## 使用

- **点击 💤** → 切到 ☕️：合盖不睡模式开启
- **再点 ☕️** → 切回 💤：恢复默认（合盖正常睡眠）
- **快捷键** `⌃⌥⌘ + F6` 也能切换（在 `clamshell.lua` 里改 `HOTKEY_MODS` / `HOTKEY_KEY` 自定义）
- ☕️ 模式下：合盖时屏幕亮度归 0；开盖时 1.5 秒平滑升回

> ⚠️ 合盖不睡时机器在包里散热受限，电池也消耗更快。长时间不用记得切回 💤。

## 自定义

编辑 `~/.hammerspoon/clamshell.lua` 顶部的常量：

```lua
local POLL_INTERVAL = 1                       -- 盖子状态轮询间隔（秒）
local FADE_DURATION = 1.5                     -- 开盖渐亮时长（秒）
local HOTKEY_MODS = { "ctrl", "alt", "cmd" }  -- 切换快捷键修饰
local HOTKEY_KEY  = "f6"                       -- 切换快捷键主键
```

改完点 Hammerspoon 菜单 → Reload Config。

## 卸载

```bash
rm ~/.hammerspoon/setbrightness ~/.hammerspoon/clamshell.lua
sudo rm -f /etc/sudoers.d/clamshell-mode-pmset
# 编辑 ~/.hammerspoon/init.lua，删掉 require("clamshell") 那两行
# 然后 reload Hammerspoon
```

## 致谢

- [Hammerspoon](https://www.hammerspoon.org/) — macOS 自动化框架
- `DisplayServices` 私有框架的用法参考社区多年积累

## License

MIT

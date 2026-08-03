# clamshell-mode-mac

[English](README.md) | [中文](README.zh.md)

macOS 「合盖不睡眠」一键切换 + 合盖自动调暗 / 开盖渐亮。无需外接显示器。

- **菜单栏图标**（SF Symbol 渲染）一键切换
- **唤醒模式下** 合盖：系统继续运行（程序、下载、训练全部不中断），屏幕亮度归 0 省电护屏
- **开盖瞬间** 用 60fps 小数精度过渡平滑升回原亮度，无突兀闪烁
- **长时间合盖 Bark 推送提醒**（可选），方便包里跑着别忘了

> Apple Silicon Mac 验证通过。Intel Mac 理论也可用，但 `setbrightness` 工具未测试。

## 工作原理

绕开 macOS 在没有外接显示器时强制睡眠的限制：用 `pmset disablesleep 1` 在系统层关掉合盖触发的睡眠。盖子开关状态用 `ioreg AppleClamshellState` 轮询；亮度通过私有框架 `DisplayServices` 直接调用，达到比公开 API 更细的小数级精度。

| 组件 | 作用 |
|------|------|
| `clamshell.lua` | Hammerspoon 主逻辑：菜单栏、轮询、亮度协调 |
| `setbrightness` (Swift) | 调 `DisplayServicesSetBrightness` 私有 API，60fps 内置 fade |
| `Clamshell Mode.app` (SwiftUI) | 配置 GUI：状态检查、所有可调项 |
| `~/.hammerspoon/clamshell-config.json` | 单一配置源，App 写入，lua 读取 |
| `/etc/sudoers.d/clamshell-mode-pmset` | 让 `pmset` 免密 sudo |

## 安装

### 全新 Mac 一键装

把本项目需要的 Xcode CLT、Homebrew、Hammerspoon 和项目本身一次性装好：

```bash
curl -fsSL https://raw.githubusercontent.com/KrisWonka/clamshell-mode-mac/main/bootstrap.sh | bash
```

### 手动

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

> ⚠️ 合盖不睡时机器在包里散热受限，电池也消耗更快。长时间不用记得切回。

### 配置 GUI（**Clamshell Mode.app**）
Spotlight 搜「Clamshell」打开。三个标签：

- **Setup**：实时检测 Hammerspoon / sudoers 状态
- **Settings**：系统亮屏时间（屏保启动 / 电池关屏 / 电源关屏，直接读写系统设置）、Bark 提醒（device key + 延时阈值 + 测试推送）、亮度过渡时长、快捷键、菜单栏图标（任意 SF Symbol）、各功能独立开关。**保存后自动重载**
- **About**：仓库链接

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
  "barkKey": "your-bark-device-key",
  "notifyDelaySec": 900,
  "iconSleep": "zzz",
  "iconAwake": "cup.and.saucer.fill"
}
```

另有 lua-only 可选键 `menuRefreshInterval`（菜单栏状态自刷新间隔秒数，默认 15）。

## 常见问题 / 踩过的坑

### 菜单栏没有月亮图标

1. **菜单栏挤爆了，图标被刘海吞了。** 有刘海的 MacBook 上状态栏图标从右往左排，排不下的会落到刘海底下——**不是没生成，是看不见**。装的时候加 `HIDE_HS_MENUICON=1` 可隐藏 Hammerspoon 自己的锤子腾出约 30px：

   ```bash
   HIDE_HS_MENUICON=1 ./install.sh
   ```

   再不够就精简别的常驻图标。注意 Hammerspoon 报的 `frame` 坐标**不反映刘海遮挡**，被盖住的图标照样有正常坐标，不能靠坐标判断可见性。

2. **Hammerspoon 没开机自启。** 重启后 HS 没启动 = 图标和快捷键全没，很容易误判成装失败。新版 `install.sh` 会自动加登录项。

3. **改完配置没真正重载。** 对已在运行的 Hammerspoon 执行 `open` 只是激活它，**不会重新加载 init.lua**：

   ```bash
   osascript -e 'quit app "Hammerspoon"'; sleep 1; pkill -x Hammerspoon; open -ga Hammerspoon
   ```

### 图标出现了一会儿又消失

`hs.menubar` / `hs.timer` 对象存在 `local` 变量里，chunk 执行完没有强引用就会被 Lua GC 回收——表现为图标先出现后消失、合盖轮询悄悄停掉。本项目已改成全局变量（`lidMenu` / `menuTimer` / `lidPoller`）。

### 点图标切换没反应 / 提示要密码

一键切换靠 `sudo -n pmset -a disablesleep`，需要 `/etc/sudoers.d/clamshell-mode-pmset` 放行。检查：

```bash
sudo -n /usr/bin/pmset -g >/dev/null && echo "免密 OK" || echo "sudoers 没配好，重跑 ./install.sh"
```

### 合盖后没调暗 / 开盖没渐亮

`setbrightness` 用的是 `DisplayServices` 私有框架，只对内置屏有效，外接显示器不管用。确认二进制在且可执行：

```bash
ls -l ~/.hammerspoon/setbrightness && ~/.hammerspoon/setbrightness fade 0.5 1
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

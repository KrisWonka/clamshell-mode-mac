# clamshell-mode-mac

[English](README.md) | [中文](README.zh.md)

One-click macOS "lid-closed without sleep" toggle, with automatic dim-on-close and smooth fade-in on lid open. **No external display required.**

- **Menu bar icon** (rendered with SF Symbols) — one-click toggle
- **Awake mode** keeps the system fully running on lid close (programs, downloads, training jobs all uninterrupted), while the screen brightness drops to 0 to save power and protect the panel
- **Lid-open** triggers a 60fps sub-percent brightness fade back to your previous level — no jarring flash
- **Remote sleep from iPhone** via a Shortcuts SSH command — disable awake-mode and sleep instantly
- **Optional iMessage reminder** when the lid has been closed for a long time, so you don't forget the laptop is still running in your bag

> Verified on Apple Silicon Mac. Should work on Intel Macs too, but the `setbrightness` helper has not been tested there.

## How it works

Bypasses macOS's "force sleep when no external display" behavior by using `pmset disablesleep 1` to disable the lid-close sleep trigger at the system level. Lid state is polled via `ioreg AppleClamshellState`. Brightness is driven through the private `DisplayServices` framework for sub-percent precision that the public API doesn't expose.

| Component | Role |
|------|------|
| `clamshell.lua` | Hammerspoon main logic: menu bar, polling, brightness coordination |
| `setbrightness` (Swift) | Calls `DisplayServicesSetBrightness` private API with a built-in 60fps fade |
| `Clamshell Mode.app` (SwiftUI) | Configurator GUI: status checks, network detection, all tunable options |
| `~/.hammerspoon/clamshell-config.json` | Single source of truth — app writes, lua reads |
| `/etc/sudoers.d/clamshell-mode-pmset` | Passwordless sudo for `pmset` only |

## Install

Requires: [Hammerspoon](https://www.hammerspoon.org/) and Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/KrisWonka/clamshell-mode-mac.git
cd clamshell-mode-mac
./install.sh
```

The installer will:
1. Build `setbrightness` and place it in `~/.hammerspoon/`
2. Add a sudoers rule in `/etc/sudoers.d/` allowing only `pmset` without a password (you'll be asked once)
3. Copy `clamshell.lua` and the default menu bar icons into `~/.hammerspoon/`
4. Append `require("clamshell")` to `~/.hammerspoon/init.lua`
5. Write a default `clamshell-config.json` (skipped if one already exists)
6. Build `Clamshell Mode.app` and install it to `/Applications/`
7. Reload Hammerspoon

Once done, an SF Symbol icon appears in the menu bar — open the GUI from Spotlight by searching "Clamshell".

Or grab the prebuilt `.dmg` from [Releases](https://github.com/KrisWonka/clamshell-mode-mac/releases) and drag the app into Applications, then run `./install.sh` to wire up the Hammerspoon side.

## Usage

### Menu bar / hotkey
- Click the menu bar icon to toggle sleep / awake mode
- Default hotkey **`⌃⌥⌘ + 6`** (rebindable in GUI Settings)
- Awake-mode lid close → brightness to 0; lid open → 1.5s smooth fade back

### Configurator (`Clamshell Mode.app`)
Open via Spotlight. Three tabs:

- **Setup**: live status of Hammerspoon / SSH / sudoers; lists every network interface IP (auto-labels iPhone hotspot / Tailscale / WiFi); shows the Mac-side Shortcut script ready to copy
- **Settings**: phone number, reminder delay (1–120 min), brightness fade duration, hotkey, menu bar icon (any SF Symbol), and per-feature toggles. **Auto-reloads Hammerspoon on save**
- **About**: repo link

### Remote sleep from iPhone

1. Enable Remote Login on the Mac (System Settings → General → Sharing → Remote Login)
2. Pick an IP from the GUI Setup tab (Tailscale recommended for cross-network reliability; same-WiFi users can use the Bonjour `.local` name)
3. iPhone Shortcuts → new shortcut → add **Run Script Over SSH** → fill in the Host / User / Port shown in the GUI, with this script:
   ```
   /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0 && /usr/bin/pmset sleepnow
   ```

> ⚠️ Closed-lid awake mode means the chassis is in a bag with limited cooling, and battery drains faster. Remember to switch back when you're not using it.

## Manual config

You can edit the config file directly without the GUI — `~/.hammerspoon/clamshell-config.json`, then reload Hammerspoon.

```json
{
  "fadeEnabled": true,
  "fadeDuration": 1.5,
  "pollInterval": 1,
  "hotkeyEnabled": true,
  "hotkeyMods": ["ctrl", "alt", "cmd"],
  "hotkeyKey": "6",
  "notifyEnabled": false,
  "phone": "+1...",
  "notifyDelaySec": 900,
  "iconSleep": "zzz",
  "iconAwake": "cup.and.saucer.fill"
}
```

## Uninstall

```bash
./uninstall.sh
```

Or manually:

```bash
rm ~/.hammerspoon/{setbrightness,clamshell.lua,clamshell-config.json,icon-sleep.png,icon-awake.png}
rm -rf "/Applications/Clamshell Mode.app"
sudo rm -f /etc/sudoers.d/clamshell-mode-pmset
# Edit ~/.hammerspoon/init.lua and remove the two lines for require("clamshell")
# Then reload Hammerspoon
```

## Acknowledgements

- [Hammerspoon](https://www.hammerspoon.org/) — macOS automation framework
- `DisplayServices` private API usage builds on years of community reverse-engineering

## License

MIT

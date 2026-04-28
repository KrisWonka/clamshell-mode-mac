-- ===== clamshell-mode-mac =====
-- 菜单栏一键切换「合盖不睡眠」+ 合盖自动调暗 / 开盖渐亮
-- https://github.com/KrisWonka/clamshell-mode-mac

local M = {}

local HS_DIR = os.getenv("HOME") .. "/.hammerspoon"
local SETBRIGHTNESS_BIN = HS_DIR .. "/setbrightness"
local CONFIG_PATH = HS_DIR .. "/clamshell-config.json"

-- 默认配置（被 clamshell-config.json 覆盖；JSON 是 ClamshellModeApp.app 写的）
local cfg = {
  fadeEnabled = true,
  fadeDuration = 1.5,
  pollInterval = 1,
  hotkeyEnabled = true,
  hotkeyMods = { "ctrl", "alt", "cmd" },
  hotkeyKey = "6",
  notifyEnabled = false,
  phone = "",
  notifyDelaySec = 15 * 60,
  iconSleep = "zzz",
  iconAwake = "cup.and.saucer.fill",
}

local function loadConfig()
  local f = io.open(CONFIG_PATH, "r")
  if not f then return end
  local raw = f:read("*a"); f:close()
  local ok, parsed = pcall(hs.json.decode, raw)
  if not ok or type(parsed) ~= "table" then return end
  for k, v in pairs(parsed) do cfg[k] = v end
end
loadConfig()

local lidMenu = hs.menubar.new(true, "clamshellModeIndicator")
if lidMenu and lidMenu.setPriority then
  lidMenu:setPriority(hs.menubar.priorities.system or 2147483647)
end

local iconSleep = hs.image.imageFromPath(HS_DIR .. "/icon-sleep.png")
local iconAwake = hs.image.imageFromPath(HS_DIR .. "/icon-awake.png")
if iconSleep then iconSleep:setSize({ w = 18, h = 18 }):template(true) end
if iconAwake then iconAwake:setSize({ w = 18, h = 18 }):template(true) end

local function getSleepDisabled()
  local out = hs.execute("/usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/{print $2}'")
  return (out and out:match("1")) ~= nil
end

local function refreshMenu()
  if not lidMenu then return end
  if getSleepDisabled() then
    if iconAwake then lidMenu:setIcon(iconAwake, true); lidMenu:setTitle(nil)
    else lidMenu:setTitle("☕") end
    lidMenu:setTooltip("合盖不睡眠（程序继续跑）— 点击切回默认")
  else
    if iconSleep then lidMenu:setIcon(iconSleep, true); lidMenu:setTitle(nil)
    else lidMenu:setTitle("☾") end
    lidMenu:setTooltip("合盖会睡眠（默认）— 点击保持唤醒")
  end
end

local function toggleClamshell()
  local target = getSleepDisabled() and "0" or "1"
  hs.execute("/usr/bin/sudo -n /usr/bin/pmset -a disablesleep " .. target)
  refreshMenu()
  hs.notify.new({
    title = "合盖模式",
    informativeText = target == "1" and "合盖不睡眠 — 程序继续跑" or "合盖会睡眠 — 已恢复默认",
    withdrawAfter = 2,
  }):send()
end

if lidMenu then
  lidMenu:setClickCallback(toggleClamshell)
  refreshMenu()
end

if cfg.hotkeyEnabled and cfg.hotkeyKey and #cfg.hotkeyMods > 0 then
  hs.hotkey.bind(cfg.hotkeyMods, cfg.hotkeyKey, toggleClamshell)
end

local menuTimer = hs.timer.doEvery(cfg.pollInterval, refreshMenu)
menuTimer:start()

local savedBrightness = nil
local fadeTask = nil
local lidPoller
local notifyTimer = nil

local function sendIMessage(text)
  if not cfg.notifyEnabled or not cfg.phone or cfg.phone == "" then return end
  local script = string.format(
    'tell application "Messages" to send %q to buddy %q of (1st service whose service type = iMessage)',
    text, cfg.phone
  )
  hs.task.new("/usr/bin/osascript", nil, { "-e", script }):start()
end

local function fadeBrightnessTo(targetInt, durationSec)
  if fadeTask then fadeTask:terminate(); fadeTask = nil end
  if lidPoller then lidPoller:stop() end
  fadeTask = hs.task.new(
    SETBRIGHTNESS_BIN,
    function()
      if lidPoller then lidPoller:start() end
      fadeTask = nil
    end,
    { "fade", string.format("%.4f", targetInt / 100), tostring(durationSec) }
  )
  fadeTask:start()
end

local function isLidClosed()
  local out = hs.execute("/usr/sbin/ioreg -r -k AppleClamshellState | /usr/bin/grep -m1 '\"AppleClamshellState\"'")
  return out and out:match("Yes") ~= nil
end

local lidWasClosed = false
lidPoller = hs.timer.doEvery(cfg.pollInterval, function()
  local closed = isLidClosed()
  if closed and not lidWasClosed then
    if getSleepDisabled() then
      if cfg.fadeEnabled then
        savedBrightness = hs.brightness.get()
        hs.brightness.set(0)
      end
      if cfg.notifyEnabled and cfg.phone and cfg.phone ~= "" then
        if notifyTimer then notifyTimer:stop() end
        notifyTimer = hs.timer.doAfter(cfg.notifyDelaySec, function()
          sendIMessage(string.format(
            "📌 你的 Mac 在「合盖不睡眠」模式下已合盖 %d 分钟，记得检查一下",
            math.floor(cfg.notifyDelaySec / 60)
          ))
          notifyTimer = nil
        end)
      end
    end
  elseif (not closed) and lidWasClosed then
    if notifyTimer then notifyTimer:stop(); notifyTimer = nil end
    if cfg.fadeEnabled and savedBrightness then
      fadeBrightnessTo(savedBrightness, cfg.fadeDuration)
      savedBrightness = nil
    end
  end
  lidWasClosed = closed
end)
lidPoller:start()

return M

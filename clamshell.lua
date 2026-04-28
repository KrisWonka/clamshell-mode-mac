-- ===== clamshell-mode-mac =====
-- 菜单栏一键切换「合盖不睡眠」+ 合盖自动调暗 / 开盖渐亮
-- https://github.com/KrisWonka/clamshell-mode-mac

local M = {}

local SETBRIGHTNESS_BIN = os.getenv("HOME") .. "/.hammerspoon/setbrightness"
local POLL_INTERVAL = 1       -- 秒，盖子状态 + 菜单栏刷新频率
local FADE_DURATION = 1.5     -- 秒，开盖渐亮时长
local HOTKEY_MODS = { "ctrl", "alt", "cmd" }  -- 切换模式的快捷键修饰
local HOTKEY_KEY  = "6"                        -- 切换模式的主键

-- 合盖不睡 + 长时间未开盖时给你 iPhone 推 iMessage 提醒
-- 留 nil 关闭功能；填你的号码（带国家码）启用，例如 "+8613812345678"
local NOTIFY_PHONE = nil
local LID_CLOSED_NOTIFY_AFTER = 15 * 60        -- 秒，超过此时长仍合盖则推送

local lidMenu = hs.menubar.new(true, "clamshellModeIndicator")
if lidMenu and lidMenu.setPriority then
  lidMenu:setPriority(hs.menubar.priorities.system or 2147483647)
end

local function getSleepDisabled()
  local out = hs.execute("/usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/{print $2}'")
  return (out and out:match("1")) ~= nil
end

local function refreshMenu()
  if not lidMenu then return end
  if getSleepDisabled() then
    lidMenu:setTitle("☕️")
    lidMenu:setTooltip("合盖不睡眠（程序继续跑）— 点击切回默认")
  else
    lidMenu:setTitle("💤")
    lidMenu:setTooltip("合盖会睡眠（默认）— 点击保持唤醒")
  end
end

local function toggleClamshell()
  local target = getSleepDisabled() and "0" or "1"
  hs.execute("/usr/bin/sudo -n /usr/bin/pmset -a disablesleep " .. target)
  refreshMenu()
  hs.notify.new({
    title = "合盖模式",
    informativeText = target == "1" and "☕️ 合盖不睡眠" or "💤 合盖会睡眠",
    withdrawAfter = 2,
  }):send()
end

if lidMenu then
  lidMenu:setClickCallback(toggleClamshell)
  refreshMenu()
end

-- 全局快捷键
if HOTKEY_KEY and #HOTKEY_MODS > 0 then
  hs.hotkey.bind(HOTKEY_MODS, HOTKEY_KEY, toggleClamshell)
end

local menuTimer = hs.timer.doEvery(POLL_INTERVAL, refreshMenu)
menuTimer:start()

-- 合盖自动调暗 / 开盖渐亮
local savedBrightness = nil
local fadeTask = nil
local lidPoller -- 前向声明，fade 时暂停以避免子进程干扰
local notifyTimer = nil

local function sendIMessage(text)
  if not NOTIFY_PHONE then return end
  local script = string.format(
    'tell application "Messages" to send %q to buddy %q of (1st service whose service type = iMessage)',
    text, NOTIFY_PHONE
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
lidPoller = hs.timer.doEvery(POLL_INTERVAL, function()
  local closed = isLidClosed()
  if closed and not lidWasClosed then
    if getSleepDisabled() then
      savedBrightness = hs.brightness.get()
      hs.brightness.set(0)
      if NOTIFY_PHONE then
        if notifyTimer then notifyTimer:stop() end
        notifyTimer = hs.timer.doAfter(LID_CLOSED_NOTIFY_AFTER, function()
          sendIMessage(string.format(
            "📌 你的 Mac 在「合盖不睡眠」模式下已合盖 %d 分钟，记得检查一下",
            math.floor(LID_CLOSED_NOTIFY_AFTER / 60)
          ))
          notifyTimer = nil
        end)
      end
    end
  elseif (not closed) and lidWasClosed then
    if notifyTimer then notifyTimer:stop(); notifyTimer = nil end
    if savedBrightness then
      fadeBrightnessTo(savedBrightness, FADE_DURATION)
      savedBrightness = nil
    end
  end
  lidWasClosed = closed
end)
lidPoller:start()

return M

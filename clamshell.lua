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
  barkKey = "",
  notifyDelaySec = 15 * 60,
  iconSleep = "zzz",
  iconAwake = "cup.and.saucer.fill",
  alertSleep = "Clam Sleep",
  alertAwake = "Clam Awake",
  lidCloseDisplaySleep = false,
  lidCloseLowPower = false,
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

-- 注意：菜单栏对象和定时器必须是全局的。存成 local 的话 chunk 执行完就没有强引用，
-- Lua GC 随时可能回收它们 —— 表现为图标先出现后消失、轮询悄悄停掉。
lidMenu = hs.menubar.new(true, "clamshellModeIndicator")
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

-- 只在状态真正变化时才重设菜单栏项。无条件每秒重设会让 macOS 反复重排整条
-- 菜单栏，在 macOS 27 上表现为 WindowServer 刷 _CGXPackagesSetWindowConstraints:
-- Invalid window（约 120 次/分钟），进而偶发 set_cursor_surface 失败、光标不变形。
local lastSleepDisabled = nil

local function refreshMenu(force)
  if not lidMenu then return end
  local disabled = getSleepDisabled()
  if not force and disabled == lastSleepDisabled then return end
  lastSleepDisabled = disabled
  if disabled then
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
  refreshMenu(true)
  hs.alert.show(target == "1" and cfg.alertAwake or cfg.alertSleep, 1.5)
end

if lidMenu then
  lidMenu:setClickCallback(toggleClamshell)
  refreshMenu(true)
end

if cfg.hotkeyEnabled and cfg.hotkeyKey and #cfg.hotkeyMods > 0 then
  hs.hotkey.bind(cfg.hotkeyMods, cfg.hotkeyKey, toggleClamshell)
end

-- 菜单栏指示器只反映 SleepDisabled 状态，而它只会被本模块的热键/点击改动（那两条
-- 路径已经主动调 refreshMenu(true)）。外部改动极罕见，所以这里不需要 1 秒轮询——
-- 每次轮询都要 fork 一个 `pmset -g | awk` 子进程，是剩余 Invalid window 的来源。
local menuInterval = cfg.menuRefreshInterval or 15
menuTimer = hs.timer.doEvery(menuInterval, refreshMenu)  -- 全局：防 GC
menuTimer:start()

local fadeTask = nil
-- lidPoller 同样是全局（防 GC），不要加 local
local notifyTimer = nil

-- 合盖时保存的现场（亮度、能耗模式），开盖时据此恢复。落盘是因为 Hammerspoon 可能在
-- 合盖期间重载或崩溃：只存内存的话，低电量模式会一直留在系统里，亮度会被「恢复」成 0。
local LID_STATE_PATH = HS_DIR .. "/clamshell-lid-state.json"

local function readLidState()
  local f = io.open(LID_STATE_PATH, "r")
  if not f then return nil end
  local raw = f:read("*a"); f:close()
  local ok, parsed = pcall(hs.json.decode, raw)
  if ok and type(parsed) == "table" then return parsed end
  return nil
end

local function writeLidState(state)
  local ok, encoded = pcall(hs.json.encode, state)
  if not ok or not encoded then return end
  local f = io.open(LID_STATE_PATH, "w")
  if not f then return end
  f:write(encoded); f:close()
end

local lidState = readLidState()   -- 非 nil = 有一次合盖的现场还没恢复

-- 读电池 / 电源两段各自的能耗模式。键名因机型而异：MacBook Pro 是 powermode
-- （0 自动 / 1 低电量 / 2 高性能），其他机型是 lowpowermode（0 / 1）。
local function readPowerModes()
  local out = hs.execute("/usr/bin/pmset -g custom") or ""
  local modes, section = {}, nil
  for line in out:gmatch("[^\n]+") do
    if line:match("^Battery Power:") then section = "b"
    elseif line:match("^AC Power:") then section = "c"
    elseif section then
      local key, value = line:match("^%s*(%a+)%s+(%d+)%s*$")
      if key == "powermode" or key == "lowpowermode" then
        modes.key = key
        modes[section] = tonumber(value)
      end
    end
  end
  return modes
end

local function setPowerMode(key, sourceFlag, value)
  hs.execute(string.format("/usr/bin/sudo -n /usr/bin/pmset -%s %s %d", sourceFlag, key, value))
end

local function sleepDisplayNow()
  hs.execute("/usr/bin/pmset displaysleepnow")
end

local function sendBark(text)
  if not cfg.notifyEnabled or not cfg.barkKey or cfg.barkKey == "" then return end
  local url = "https://api.day.app/" .. cfg.barkKey
    .. "/" .. hs.http.encodeForQuery("Clamshell Mode")
    .. "/" .. hs.http.encodeForQuery(text)
  hs.http.asyncGet(url, nil, function(status, body, _)
    if status ~= 200 then
      print("[clamshell] Bark notify failed: " .. tostring(status) .. " " .. tostring(body))
    end
  end)
end

local function fadeBrightnessTo(targetInt, durationSec)
  if fadeTask then fadeTask:terminate(); fadeTask = nil end
  -- fade 期间暂停所有会 spawn 子进程的轮询，避免抢 CPU 打断 60fps 节奏
  if lidPoller then lidPoller:stop() end
  if menuTimer then menuTimer:stop() end
  fadeTask = hs.task.new(
    SETBRIGHTNESS_BIN,
    function()
      if lidPoller then lidPoller:start() end
      if menuTimer then menuTimer:start() end
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
local resleepTimer = nil

local function stopResleepTimer()
  if resleepTimer then resleepTimer:stop(); resleepTimer = nil end
end

local function enterLidClosed()
  -- 已有未恢复的现场（合盖期间重载）就沿用，不能用此刻的亮度 0 / 低电量模式覆盖它
  if not lidState then
    lidState = {}
    if cfg.fadeEnabled then lidState.brightness = hs.brightness.get() end
    if cfg.lidCloseLowPower then
      local modes = readPowerModes()
      lidState.powerKey, lidState.powerB, lidState.powerC = modes.key, modes.b, modes.c
    end
    writeLidState(lidState)
  end
  if cfg.fadeEnabled then hs.brightness.set(0) end
  if lidState.powerKey then
    if lidState.powerB then setPowerMode(lidState.powerKey, "b", 1) end
    if lidState.powerC then setPowerMode(lidState.powerKey, "c", 1) end
  end
  if cfg.lidCloseDisplaySleep then sleepDisplayNow() end
  if cfg.notifyEnabled and cfg.barkKey and cfg.barkKey ~= "" then
    if notifyTimer then notifyTimer:stop() end
    notifyTimer = hs.timer.doAfter(cfg.notifyDelaySec, function()
      sendBark(string.format(
        "📌 你的 Mac 在「合盖不睡眠」模式下已合盖 %d 分钟，记得检查一下",
        math.floor(cfg.notifyDelaySec / 60)
      ))
      notifyTimer = nil
    end)
  end
end

local function exitLidClosed()
  if notifyTimer then notifyTimer:stop(); notifyTimer = nil end
  stopResleepTimer()
  if not lidState then return end
  if lidState.powerKey then
    if lidState.powerB then setPowerMode(lidState.powerKey, "b", lidState.powerB) end
    if lidState.powerC then setPowerMode(lidState.powerKey, "c", lidState.powerC) end
  end
  if cfg.fadeEnabled and lidState.brightness then
    fadeBrightnessTo(lidState.brightness, cfg.fadeDuration)
  end
  lidState = nil
  os.remove(LID_STATE_PATH)
end

-- 合盖期间屏幕被唤醒（远程桌面连入、合成输入等）后，等输入空闲满 60 秒再关一次。
-- 接电源时系统的关屏计时可能是「永不」，不补这一步屏幕会一直亮到开盖。
if cfg.lidCloseDisplaySleep then
  lidDisplayWatcher = hs.caffeinate.watcher.new(function(event)  -- 全局：防 GC
    if event == hs.caffeinate.watcher.screensDidWake then
      if lidWasClosed and lidState then
        stopResleepTimer()
        resleepTimer = hs.timer.doEvery(30, function()
          if not lidWasClosed then stopResleepTimer(); return end
          if hs.host.idleTime() >= 60 then sleepDisplayNow() end
        end)
      end
    elseif event == hs.caffeinate.watcher.screensDidSleep then
      stopResleepTimer()
    end
  end)
  lidDisplayWatcher:start()
end

-- 上次合盖的现场没来得及恢复（合盖期间 Hammerspoon 崩溃或机器重启），而现在盖子开着：补恢复
if lidState and not isLidClosed() then exitLidClosed() end

lidPoller = hs.timer.doEvery(cfg.pollInterval, function()
  local closed = isLidClosed()
  if closed and not lidWasClosed then
    if getSleepDisabled() then enterLidClosed() end
  elseif (not closed) and lidWasClosed then
    exitLidClosed()
  end
  lidWasClosed = closed
end)
lidPoller:start()

return M

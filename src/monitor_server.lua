-- QuarryOS base monitor server. It tracks several turtles and sends direct,
-- acknowledged commands only to the selected turtle.
local monitor = peripheral.find("monitor")
if not monitor then error("Attach an Advanced Monitor to this computer.", 0) end

local monitorName = peripheral.getName and peripheral.getName(monitor) or nil
local speaker = peripheral.find("speaker")
local screenWidth, screenHeight = monitor.getSize()
local textScale = monitor.getTextScale and monitor.getTextScale() or nil
local layout = "tiny"
local turtles = {}
local selectedTurtleId = nil
local view = "overview"
local tinyPage = 1
local touchTargets = {}
local alerts = {}
local requestNumber = 0
local pending = nil
local controlNotice = nil

-- A flat, low-noise operations overlay. Advanced Monitors have a character
-- grid rather than true pixels, so avoiding large coloured rectangles makes
-- the display look considerably cleaner at every monitor size.
local THEME = {
  background = colors.black, panel = colors.black, header = colors.black,
  button = colors.gray, divider = colors.gray, accent = colors.cyan,
  text = colors.white, muted = colors.lightGray, safe = colors.lime,
  warning = colors.orange, danger = colors.red, alert = colors.purple,
}

-- A 26-character threshold selects scale 1.0 on a normal 3x3 monitor and
-- scale 1.5 on a normal 5x5 monitor. Narrow monitors use the tiny layout.
local COMPACT_WIDTH, COMPACT_HEIGHT = 26, 10
local TINY_WIDTH, TINY_HEIGHT = 14, 10

local function now()
  return os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
end

local function fits(width, height, neededWidth, neededHeight)
  return width >= neededWidth and height >= neededHeight
end

local function largestScaleFor(neededWidth, neededHeight)
  if not monitor.setTextScale then
    local width, height = monitor.getSize()
    if fits(width, height, neededWidth, neededHeight) then
      return monitor.getTextScale and monitor.getTextScale() or nil, width, height
    end
    return nil
  end

  for scale = 5, 0.5, -0.5 do
    monitor.setTextScale(scale)
    local width, height = monitor.getSize()
    if fits(width, height, neededWidth, neededHeight) then return scale, width, height end
  end
  return nil
end

local function configureDisplay()
  local scale, width, height = largestScaleFor(COMPACT_WIDTH, COMPACT_HEIGHT)
  if scale then
    layout = "compact"
  else
    scale, width, height = largestScaleFor(TINY_WIDTH, TINY_HEIGHT)
    layout = "tiny"
  end
  if not scale then
    if monitor.setTextScale then monitor.setTextScale(0.5) end
    scale = monitor.getTextScale and monitor.getTextScale() or 0.5
    width, height = monitor.getSize()
    layout = "tiny"
  end
  textScale, screenWidth, screenHeight = scale, width, height
end

local function clip(value, maximum)
  local text = tostring(value or "")
  if maximum <= 0 then return "" end
  if #text <= maximum then return text end
  if maximum <= 3 then return text:sub(1, maximum) end
  return text:sub(1, maximum - 3) .. "..."
end

local function writeAt(x, y, value, colour)
  if y < 1 or y > screenHeight or x > screenWidth then return end
  local available = screenWidth - x + 1
  if available <= 0 then return end
  monitor.setCursorPos(math.max(1, x), y)
  if colour then monitor.setTextColor(colour) end
  monitor.write(clip(value, available))
end

local function centerAt(y, value, colour)
  local text = clip(value, screenWidth)
  writeAt(math.max(1, math.floor((screenWidth - #text) / 2) + 1), y, text, colour)
end

local function beginFrame(title)
  monitor.setBackgroundColor(THEME.background)
  monitor.clear()
  monitor.setBackgroundColor(THEME.header)
  monitor.setTextColor(THEME.accent)
  monitor.setCursorPos(1, 1)
  monitor.write(string.rep(" ", screenWidth))
  centerAt(1, title, THEME.accent)
  monitor.setBackgroundColor(THEME.background)
  monitor.setTextColor(THEME.muted)
  monitor.setCursorPos(1, 2)
  monitor.write(string.rep("-", screenWidth))
end

local function fillRect(x, y, width, height, background)
  if width <= 0 or height <= 0 then return end
  local left = math.max(1, x)
  local right = math.min(screenWidth, x + width - 1)
  if left > right then return end
  monitor.setBackgroundColor(background)
  for row = math.max(1, y), math.min(screenHeight, y + height - 1) do
    monitor.setCursorPos(left, row)
    monitor.write(string.rep(" ", right - left + 1))
  end
  monitor.setBackgroundColor(THEME.background)
end

local function writeOn(x, y, value, foreground, background)
  if y < 1 or y > screenHeight or x > screenWidth then return end
  local available = screenWidth - x + 1
  if available <= 0 then return end
  monitor.setCursorPos(math.max(1, x), y)
  monitor.setBackgroundColor(background or THEME.background)
  monitor.setTextColor(foreground or THEME.text)
  monitor.write(clip(value, available))
  monitor.setBackgroundColor(THEME.background)
end

local function drawCard(x, y, width, height, title, titleColour)
  fillRect(x, y, width, height, THEME.panel)
  if title then
    local label = " " .. title .. " "
    writeOn(x, y, label, titleColour or THEME.accent, THEME.header)
    fillRect(x + #label, y, math.max(0, width - #label), 1, THEME.divider)
  end
end

local function addTarget(left, top, right, bottom, action)
  touchTargets[#touchTargets + 1] = {
    left = left, top = top, right = right, bottom = bottom, action = action,
  }
end

local function drawButton(x, y, width, label, foreground, action)
  if y < 1 or y > screenHeight or x > screenWidth or width <= 0 then return end
  width = math.min(width, screenWidth - x + 1)
  local text = " " .. clip(label, math.max(1, width - 2)) .. " "
  text = clip(text, width)
  monitor.setCursorPos(x, y)
  monitor.setBackgroundColor(THEME.button)
  monitor.setTextColor(foreground or THEME.text)
  monitor.write(text .. string.rep(" ", math.max(0, width - #text)))
  monitor.setBackgroundColor(colors.black)
  addTarget(x, y, x + width - 1, y, action)
end

local function drawCenteredButton(y, label, foreground, action)
  local width = math.min(screenWidth, #label + 2)
  local x = math.max(1, math.floor((screenWidth - width) / 2) + 1)
  drawButton(x, y, width, label, foreground, action)
end

local function textOf(value, fallback)
  if value == nil then return fallback or "?" end
  return tostring(value)
end

local function durationText(milliseconds, short)
  local seconds = math.max(0, math.ceil(milliseconds / 1000))
  if seconds < 60 then return short and "<1m" or "<1 min" end
  local minutes = math.floor(seconds / 60)
  if minutes < 60 then return tostring(minutes) .. (short and "m" or " min") end
  local hours = math.floor(minutes / 60)
  minutes = minutes % 60
  if hours < 24 then return tostring(hours) .. "h" .. string.format("%02d", minutes) .. "m" end
  return tostring(math.floor(hours / 24)) .. "d" .. tostring(hours % 24) .. "h"
end

local function progressText(data, short)
  local percentage = tonumber(data.progressPercent)
  if not percentage then return short and "P calculating" or "Progress: calculating..." end
  local prefix = data.progressEstimated and "~" or ""
  return (short and "P " or "Progress: ") .. prefix .. tostring(math.floor(percentage)) .. "%"
end

local function etaText(data, short)
  local milliseconds = tonumber(data.estimatedRemainingMs)
  if not milliseconds then return short and "ETA calc" or "ETA: calculating..." end
  return (short and "ETA " or "ETA: ") .. (data.progressEstimated and "~" or "")
    .. durationText(milliseconds, short)
end

local function progressBar(data, width)
  local percentage = math.max(0, math.min(100, math.floor(tonumber(data.progressPercent) or 0)))
  local filled = math.floor(width * percentage / 100)
  return string.rep("=", filled) .. string.rep("-", width - filled)
end

local function statusColour(data)
  if tonumber(data.fuelShortfall) and tonumber(data.fuelShortfall) > 0 then return THEME.danger end
  if data.stopAfterLayerRequested or data.phase == "paused" then return THEME.warning end
  return THEME.muted
end

local function turtleIds()
  local ids = {}
  for id in pairs(turtles) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
  return ids
end

local function selected()
  return selectedTurtleId and turtles[selectedTurtleId] or nil
end

local function turtleName(id, entry)
  local data = entry and entry.data or nil
  return (data and data.turtleName) or ("Turtle " .. tostring(id))
end

local function isStale(entry)
  return not entry or now() - (entry.lastSeen or 0) > 30000
end

local function nextRequestId()
  requestNumber = requestNumber + 1
  return "monitor-" .. tostring(os.getComputerID()) .. "-" .. tostring(now()) .. "-" .. tostring(requestNumber)
end

local function addAlert(sender, payload)
  local entry = turtles[sender]
  local item = {
    sender = sender, name = payload.turtleName or turtleName(sender, entry),
    message = payload.message or tostring(payload), level = payload.level or "info", at = now(),
  }
  table.insert(alerts, 1, item)
  while #alerts > 20 do table.remove(alerts) end
  if speaker and item.level ~= "info" then pcall(speaker.playSound, "block.note_block.pling", 1, 1) end
  print("Quarry alert [" .. item.level .. "] " .. item.name .. ": " .. item.message)
end

local function alertColour(level)
  if level == "success" then return THEME.safe end
  if level == "warning" then return THEME.warning end
  if level == "error" then return THEME.danger end
  return THEME.accent
end

local function fuelText(data, short)
  local fuel = textOf(data.fuel)
  local required = tonumber(data.fuelRequired)
  local missing = tonumber(data.fuelShortfall)
  if not required then return (short and "F " or "Fuel: ") .. fuel end
  if missing and missing > 0 then
    return (short and "F " or "Fuel: ") .. fuel .. "/" .. required .. " -" .. missing
  end
  return (short and "F " or "Fuel: ") .. fuel .. "/" .. required .. " OK"
end

local function statusText(data)
  return controlNotice or textOf(data.message, "Working...")
end

local function drawDetailCompact(entry)
  local data = entry.data
  beginFrame("QUARRYOS // CONTROL")
  addTarget(1, 1, screenWidth, 1, "overview")
  drawCard(1, 3, screenWidth, 3, " ACTIVE UNIT", THEME.accent)
  writeOn(2, 4, turtleName(selectedTurtleId, entry) .. "  //  L" .. textOf(data.layer), THEME.text, THEME.panel)
  writeOn(2, 5, "[" .. progressBar(data, math.max(6, screenWidth - 13)) .. "] " .. progressText(data, true), THEME.accent, THEME.panel)
  drawCard(1, 6, screenWidth, 2, " LIVE METRICS", THEME.accent)
  writeOn(2, 7, fuelText(data, true) .. "  " .. etaText(data, true),
    tonumber(data.fuelShortfall) and tonumber(data.fuelShortfall) > 0 and THEME.danger or THEME.safe, THEME.panel)
  fillRect(1, 8, screenWidth, 1, THEME.panel)
  writeOn(2, 8, statusText(data), statusColour(data), THEME.panel)
  drawButton(1, 9, 5, "SVC", THEME.danger, "service_pause")
  drawButton(7, 9, 6, "STOP", THEME.warning, "stop_after_layer")
  drawButton(14, 9, 6, "FUEL", THEME.accent, "fuel_check")
  drawButton(21, 9, 6, "LIST", THEME.muted, "overview")
  local alarmWidth = math.max(10, math.floor((screenWidth - 1) / 2))
  drawButton(1, 10, alarmWidth, "ALARMS " .. #alerts, THEME.alert, "alerts")
  drawButton(alarmWidth + 2, 10, screenWidth - alarmWidth - 1, "UPDATE", THEME.safe, "monitor_update")
end

local function drawDetailTiny(entry)
  local data = entry.data
  beginFrame("QOS // P" .. tinyPage)
  addTarget(1, 1, screenWidth, 1, "tiny_next")
  writeAt(1, 3, clip(turtleName(selectedTurtleId, entry), screenWidth), THEME.text)
  writeAt(1, 4, "[" .. progressBar(data, 7) .. "] " .. progressText(data, true), THEME.accent)
  writeAt(1, 5, etaText(data, true) .. " L" .. textOf(data.layer), THEME.muted)
  writeAt(1, 6, fuelText(data, true), tonumber(data.fuelShortfall) and tonumber(data.fuelShortfall) > 0 and THEME.danger or THEME.safe)
  writeAt(1, 7, "BLOCKS " .. textOf(data.blocks), THEME.muted)
  writeAt(1, 8, statusText(data), statusColour(data))
  writeAt(1, 9, "Tap title: next", THEME.muted)
  local pages = {
    { "SERVICE", THEME.danger, "service_pause" },
    { "STOP LAYER", THEME.warning, "stop_after_layer" },
    { "FUEL CHECK", THEME.accent, "fuel_check" },
    { "TURTLES", THEME.muted, "overview" },
    { "ALARMS " .. #alerts, THEME.alert, "alerts" },
    { "UPDATE", THEME.safe, "monitor_update" },
  }
  local page = pages[tinyPage]
  drawCenteredButton(10, page[1], page[2], page[3])
end

local function drawOverview()
  local ids = turtleIds()
  beginFrame("QUARRYOS // FLEET " .. #ids)
  if #ids == 0 then
    writeAt(1, 3, "NO ACTIVE UNITS", THEME.warning)
    writeAt(1, 5, "Check Ender/Wireless", THEME.muted)
    writeAt(1, 6, "Modems on both ends.", THEME.muted)
  else
    local maximum = layout == "compact" and 5 or 5
    for index = 1, math.min(#ids, maximum) do
      local id = ids[index]
      local entry = turtles[id]
      local data = entry.data
      local label = turtleName(id, entry)
      local percent = tonumber(data.progressPercent)
      local status = isStale(entry) and "OFF" or ((percent and math.floor(percent) .. "%") or "...")
      local line = layout == "compact"
        and ("[" .. status .. "] " .. label .. "  F" .. textOf(data.fuel))
        or (clip(label, 7) .. " " .. status)
      local colour = isStale(entry) and THEME.danger or THEME.text
      writeAt(1, index + 2, line, colour)
      addTarget(1, index + 2, screenWidth, index + 2, "select:" .. tostring(id))
    end
    if #ids > maximum then writeAt(1, 8, "+" .. (#ids - maximum) .. " more units", THEME.muted) end
    writeAt(1, 9, "Select a unit for controls", THEME.muted)
  end
  drawCenteredButton(10, "ALARMS " .. #alerts, THEME.alert, "alerts")
end

local function drawAlerts()
  beginFrame("QUARRYOS // ALERTS " .. #alerts)
  addTarget(1, 1, screenWidth, 1, "overview")
  if #alerts == 0 then
    writeAt(1, 4, "SYSTEM CLEAR", THEME.safe)
  else
    for index = 1, math.min(#alerts, 6) do
      local alert = alerts[index]
      writeAt(1, index + 2, alert.name .. ": " .. alert.message, alertColour(alert.level))
    end
  end
  drawCenteredButton(10, "BACK", THEME.muted, "overview")
end

local function render()
  touchTargets = {}
  if view == "alerts" then
    drawAlerts()
    return
  end
  local entry = selected()
  if view == "detail" and entry then
    if layout == "compact" then drawDetailCompact(entry) else drawDetailTiny(entry) end
  else
    view = "overview"
    drawOverview()
  end
end

local function sendCommand(commandName)
  if pending then
    local sent = rednet.send(pending.turtleId, pending.serialized, "quarryos-control")
    controlNotice = sent and "Request resent - waiting" or "Retry could not send"
    render()
    return
  end
  local entry = selected()
  if not entry or not entry.data or not entry.data.jobId then
    controlNotice = "No active Turtle selected"
    render()
    return
  end
  local requestId = nextRequestId()
  local serialized = textutils.serialize({ command = commandName, jobId = entry.data.jobId, requestId = requestId })
  local sent = rednet.send(selectedTurtleId, serialized, "quarryos-control")
  if sent then
    pending = { turtleId = selectedTurtleId, jobId = entry.data.jobId, requestId = requestId,
      command = commandName, serialized = serialized }
  end
  controlNotice = sent and "Request sent - waiting" or "Request could not send"
  render()
end

-- This function only exists in the monitor program. It installs the current
-- release on this computer, then reboots this monitor computer alone. Turtle
-- computers never receive an update or reboot command from this button.
local function updateThisMonitor()
  if pending then
    controlNotice = "Wait for the active request before updating"
    render()
    return
  end
  controlNotice = "Updating this monitor - rebooting shortly..."
  render()
  local updated = shell.run("/quarryos/update.lua")
  if updated then
    controlNotice = "Update complete - rebooting monitor..."
    render()
    sleep(1)
    os.reboot()
  end
  controlNotice = "Monitor update failed - see this computer's terminal"
  render()
end

local function handleAction(action)
  if action == "overview" then
    view = "overview"
    controlNotice = nil
  elseif action == "alerts" then
    view = "alerts"
  elseif action == "tiny_next" then
    tinyPage = tinyPage % 6 + 1
  elseif action:sub(1, 7) == "select:" then
    selectedTurtleId = tonumber(action:sub(8)) or action:sub(8)
    view = "detail"
    controlNotice = nil
  elseif action == "service_pause" or action == "stop_after_layer" or action == "fuel_check" then
    sendCommand(action)
    return
  elseif action == "monitor_update" then
    updateThisMonitor()
    return
  end
  render()
end

configureDisplay()

local hasWirelessModem = false
for _, side in ipairs(peripheral.getNames()) do
  if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
    rednet.open(side)
    hasWirelessModem = true
  end
end
if not hasWirelessModem then error("Attach an Ender or Wireless Modem to this computer.", 0) end

render()
print("QuarryOS monitor control ready (" .. layout .. ", text scale " .. textOf(textScale) .. ").")
local refreshTimer = os.startTimer(5)

while true do
  local event, first, second, third = os.pullEvent()
  if event == "rednet_message" then
    local sender, message, protocol = first, second, third
    if protocol == "quarryos-monitor" then
      local data = textutils.unserialize(message)
      if data then
        turtles[sender] = { data = data, lastSeen = now() }
        if not selectedTurtleId then
          selectedTurtleId = sender
          view = "detail"
        end
        if pending and sender == pending.turtleId and data.jobId ~= pending.jobId then pending = nil end
        render()
      end
    elseif protocol == "quarryos-control-ack" then
      local ack = textutils.unserialize(message)
      if ack and pending and sender == pending.turtleId and ack.jobId == pending.jobId
        and ack.requestId == pending.requestId and ack.command == pending.command .. "_ack" then
        if pending.command == "fuel_check" then
          controlNotice = "Fuel " .. textOf(ack.fuel) .. "/" .. textOf(ack.requiredFuel)
            .. (tonumber(ack.fuelShortfall) and ack.fuelShortfall > 0 and (" missing " .. ack.fuelShortfall) or " OK")
        else
          controlNotice = pending.command == "stop_after_layer" and "Stop after layer confirmed" or "Service pause confirmed"
        end
        pending = nil
        render()
        print("Monitor request confirmed by Turtle " .. tostring(sender) .. ".")
      end
    elseif protocol == "quarryos-notify" then
      local payload = textutils.unserialize(message)
      if type(payload) ~= "table" then payload = { message = message, level = "info" } end
      addAlert(sender, payload)
      render()
    end
  elseif event == "monitor_touch" and (not monitorName or first == monitorName) then
    local x, y = second, third
    for index = #touchTargets, 1, -1 do
      local target = touchTargets[index]
      if x >= target.left and x <= target.right and y >= target.top and y <= target.bottom then
        handleAction(target.action)
        break
      end
    end
  elseif event == "monitor_resize" and (not monitorName or first == monitorName) then
    local width, height = monitor.getSize()
    if width ~= screenWidth or height ~= screenHeight then
      configureDisplay()
      render()
      print("Monitor resized: " .. layout .. ", " .. screenWidth .. "x" .. screenHeight .. ".")
    end
  elseif event == "timer" and first == refreshTimer then
    refreshTimer = os.startTimer(5)
    render()
  end
end

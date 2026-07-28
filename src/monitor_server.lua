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
  monitor.setBackgroundColor(colors.black)
  monitor.clear()
  monitor.setBackgroundColor(colors.blue)
  monitor.setTextColor(colors.white)
  monitor.setCursorPos(1, 1)
  monitor.write(string.rep(" ", screenWidth))
  centerAt(1, title, colors.white)
  monitor.setBackgroundColor(colors.black)
end

local function addTarget(left, top, right, bottom, action)
  touchTargets[#touchTargets + 1] = {
    left = left, top = top, right = right, bottom = bottom, action = action,
  }
end

local function drawButton(x, y, width, label, background, action)
  if y < 1 or y > screenHeight or x > screenWidth or width <= 0 then return end
  width = math.min(width, screenWidth - x + 1)
  local text = " " .. clip(label, math.max(1, width - 2)) .. " "
  text = clip(text, width)
  monitor.setCursorPos(x, y)
  monitor.setBackgroundColor(background)
  monitor.setTextColor(colors.white)
  monitor.write(text .. string.rep(" ", math.max(0, width - #text)))
  monitor.setBackgroundColor(colors.black)
  addTarget(x, y, x + width - 1, y, action)
end

local function drawCenteredButton(y, label, background, action)
  local width = math.min(screenWidth, #label + 2)
  local x = math.max(1, math.floor((screenWidth - width) / 2) + 1)
  drawButton(x, y, width, label, background, action)
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
  if level == "success" then return colors.lime end
  if level == "warning" then return colors.orange end
  if level == "error" then return colors.red end
  return colors.lightBlue
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
  beginFrame("QUARRYOS | " .. turtleName(selectedTurtleId, entry))
  addTarget(1, 1, screenWidth, 1, "overview")
  writeAt(1, 3, "Area " .. textOf(data.width) .. "x" .. textOf(data.length) .. "  Layer " .. textOf(data.layer), colors.cyan)
  writeAt(1, 4, progressText(data, false), colors.lightGray)
  writeAt(1, 5, etaText(data, false), colors.yellow)
  writeAt(1, 6, fuelText(data, false), tonumber(data.fuelShortfall) and tonumber(data.fuelShortfall) > 0 and colors.red or colors.lime)
  writeAt(1, 7, "Blocks: " .. textOf(data.blocks) .. (data.stopAfterLayerRequested and "  Stop pending" or ""), colors.lightGray)
  writeAt(1, 8, statusText(data), colors.yellow)
  drawButton(1, 9, 5, "SVC", colors.red, "service_pause")
  drawButton(7, 9, 6, "STOP", colors.orange, "stop_after_layer")
  drawButton(14, 9, 6, "FUEL", colors.blue, "fuel_check")
  drawButton(21, 9, 6, "LIST", colors.gray, "overview")
  drawCenteredButton(10, "ALARMS " .. #alerts, colors.purple, "alerts")
end

local function drawDetailTiny(entry)
  local data = entry.data
  beginFrame("QOS " .. turtleName(selectedTurtleId, entry) .. " P" .. tinyPage)
  addTarget(1, 1, screenWidth, 1, "tiny_next")
  writeAt(1, 3, "L " .. textOf(data.layer) .. " " .. (data.stopAfterLayerRequested and "STOP" or ""), colors.cyan)
  writeAt(1, 4, progressText(data, true), colors.lightGray)
  writeAt(1, 5, etaText(data, true), colors.yellow)
  writeAt(1, 6, fuelText(data, true), tonumber(data.fuelShortfall) and tonumber(data.fuelShortfall) > 0 and colors.red or colors.lime)
  writeAt(1, 7, "B " .. textOf(data.blocks), colors.lightGray)
  writeAt(1, 8, statusText(data), colors.yellow)
  writeAt(1, 9, "Tap title: next", colors.lightGray)
  local pages = {
    { "SERVICE", colors.red, "service_pause" },
    { "STOP LAYER", colors.orange, "stop_after_layer" },
    { "FUEL CHECK", colors.blue, "fuel_check" },
    { "TURTLES", colors.gray, "overview" },
    { "ALARMS " .. #alerts, colors.purple, "alerts" },
  }
  local page = pages[tinyPage]
  drawCenteredButton(10, page[1], page[2], page[3])
end

local function drawOverview()
  local ids = turtleIds()
  beginFrame("TURTLES " .. #ids)
  if #ids == 0 then
    writeAt(1, 3, "Waiting for Turtle", colors.yellow)
    writeAt(1, 5, "Check Ender/Wireless", colors.lightGray)
    writeAt(1, 6, "Modems on both ends.", colors.lightGray)
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
        and (label .. " " .. status .. " F" .. textOf(data.fuel))
        or (clip(label, 7) .. " " .. status)
      local colour = isStale(entry) and colors.red or colors.white
      writeAt(1, index + 2, line, colour)
      addTarget(1, index + 2, screenWidth, index + 2, "select:" .. tostring(id))
    end
    if #ids > maximum then writeAt(1, 8, "+" .. (#ids - maximum) .. " more turtles", colors.lightGray) end
    writeAt(1, 9, "Tap a Turtle for controls", colors.lightGray)
  end
  drawCenteredButton(10, "ALARMS " .. #alerts, colors.purple, "alerts")
end

local function drawAlerts()
  beginFrame("ALARMS " .. #alerts)
  addTarget(1, 1, screenWidth, 1, "overview")
  if #alerts == 0 then
    writeAt(1, 4, "No alerts yet.", colors.lime)
  else
    for index = 1, math.min(#alerts, 6) do
      local alert = alerts[index]
      writeAt(1, index + 2, alert.name .. ": " .. alert.message, alertColour(alert.level))
    end
  end
  drawCenteredButton(10, "BACK", colors.gray, "overview")
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

local function handleAction(action)
  if action == "overview" then
    view = "overview"
    controlNotice = nil
  elseif action == "alerts" then
    view = "alerts"
  elseif action == "tiny_next" then
    tinyPage = tinyPage % 5 + 1
  elseif action:sub(1, 7) == "select:" then
    selectedTurtleId = tonumber(action:sub(8)) or action:sub(8)
    view = "detail"
    controlNotice = nil
  elseif action == "service_pause" or action == "stop_after_layer" or action == "fuel_check" then
    sendCommand(action)
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

-- QuarryOS base monitor server. Run this on a base computer with an Advanced
-- Monitor and an Ender Modem. It receives live updates from the turtle.
local monitor = peripheral.find("monitor")
if not monitor then error("Attach an Advanced Monitor to this computer.", 0) end

local monitorName = peripheral.getName and peripheral.getName(monitor) or nil
local screenWidth, screenHeight = monitor.getSize()
local textScale = monitor.getTextScale and monitor.getTextScale() or nil
local layout = "tiny"
local lastData = nil
local lastTurtleId = nil
local controlNotice = nil
local controlButton = nil
local requestNumber = 0
local pendingRequestId = nil
local pendingJobId = nil
local pendingTurtleId = nil
local pendingControl = nil

-- A 26-character threshold selects scale 1.0 on a normal 3x3 monitor and
-- scale 1.5 on a normal 5x5 monitor. Narrow monitors use the tiny layout
-- instead, rather than clipping the normal dashboard.
local COMPACT_WIDTH, COMPACT_HEIGHT = 26, 10
local TINY_WIDTH, TINY_HEIGHT = 14, 10

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
    if fits(width, height, neededWidth, neededHeight) then
      return scale, width, height
    end
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

  -- Every standard monitor supports the tiny layout at scale 0.5. Keep a
  -- defensive fallback in case a server changes monitor terminal sizes.
  if not scale then
    if monitor.setTextScale then monitor.setTextScale(0.5) end
    scale = monitor.getTextScale and monitor.getTextScale() or 0.5
    width, height = monitor.getSize()
    layout = "tiny"
  end

  textScale = scale
  screenWidth, screenHeight = width, height
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
  local x = math.max(1, math.floor((screenWidth - #text) / 2) + 1)
  writeAt(x, y, text, colour)
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

local function drawControlButton(y, label)
  local text = " " .. label .. " "
  text = clip(text, screenWidth)
  local x = math.max(1, math.floor((screenWidth - #text) / 2) + 1)

  monitor.setCursorPos(x, y)
  monitor.setBackgroundColor(colors.red)
  monitor.setTextColor(colors.white)
  monitor.write(text)
  monitor.setBackgroundColor(colors.black)

  controlButton = { left = x, right = x + #text - 1, top = y, bottom = y }
end

local function textOf(input, fallback)
  if input == nil then return fallback or "?" end
  return tostring(input)
end

local function nextRequestId()
  requestNumber = requestNumber + 1
  local timestamp = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
  return "monitor-" .. tostring(os.getComputerID()) .. "-" .. tostring(timestamp) .. "-" .. tostring(requestNumber)
end

local function statusLine(data, fallback)
  return controlNotice or textOf(data.message, fallback)
end

local function oneBased(input)
  local number = tonumber(input)
  if number then return tostring(math.floor(number) + 1) end
  return textOf(input)
end

local function fraction(index, maximum)
  return oneBased(index) .. "/" .. textOf(maximum)
end

local function depthLine(data, short)
  if data.layer ~= nil then
    return (short and "L " or "Layer: ") .. textOf(data.layer)
  end
  return (short and "D " or "Depth: ") .. textOf(data.current) .. "/" .. textOf(data.mined)
end

local function stepLine(data, short)
  if data.layerProgress ~= nil and data.totalCells ~= nil then
    return (short and "Done " or "Done: ") .. textOf(data.layerProgress) .. "/" .. textOf(data.totalCells)
  end
  if data.positionStep == nil and data.progressStep == nil then return nil end
  return (short and "S " or "Step: ") .. textOf(data.positionStep) .. "/" .. textOf(data.progressStep)
end

local function durationText(milliseconds, short)
  local seconds = math.max(0, math.ceil(milliseconds / 1000))
  if seconds < 60 then return short and "<1m" or "<1 min" end
  local minutes = math.floor(seconds / 60)
  if minutes < 60 then return tostring(minutes) .. (short and "m" or " min") end
  local hours = math.floor(minutes / 60)
  minutes = minutes % 60
  if hours < 24 then return tostring(hours) .. "h" .. string.format("%02d", minutes) .. "m" end
  local days = math.floor(hours / 24)
  hours = hours % 24
  return tostring(days) .. "d" .. tostring(hours) .. "h"
end

local function progressLine(data, short)
  local percentage = tonumber(data.progressPercent)
  if not percentage then return stepLine(data, short) or (short and "P calculating" or "Progress: calculating...") end
  local prefix = data.progressEstimated and "~" or ""
  local cells = not data.progressEstimated and data.completedCells ~= nil and data.plannedCells ~= nil
    and (textOf(data.completedCells) .. "/" .. textOf(data.plannedCells)) or nil
  if short then
    return "P " .. prefix .. tostring(math.floor(percentage)) .. "%" .. (cells and (" " .. cells) or "")
  end
  return "Progress: " .. prefix .. tostring(math.floor(percentage)) .. "%" .. (cells and (" " .. cells) or "")
end

local function etaLine(data, short)
  local milliseconds = tonumber(data.estimatedRemainingMs)
  if not milliseconds then return short and "E calculating" or "ETA: calculating..." end
  local prefix = data.progressEstimated and "~" or ""
  return (short and "E " or "ETA: ") .. prefix .. durationText(milliseconds, short)
end

local function drawCompact(data)
  beginFrame("QUARRYOS LIVE")
  writeAt(1, 3, "Area: " .. textOf(data.width) .. "x" .. textOf(data.length), colors.cyan)
  writeAt(1, 4, "X " .. fraction(data.columnX, data.width) .. " Z " .. fraction(data.columnZ, data.length), colors.lightGray)
  writeAt(1, 5, depthLine(data, false), colors.lightGray)
  writeAt(1, 6, progressLine(data, false), colors.lightGray)
  writeAt(1, 7, etaLine(data, false), colors.yellow)
  writeAt(1, 8, "Fuel: " .. textOf(data.fuel) .. " B: " .. textOf(data.blocks), colors.lime)
  writeAt(1, 9, statusLine(data, "Working..."), colors.yellow)
  drawControlButton(10, "SERVICE & PAUSE")
end

local function drawTiny(data)
  beginFrame("QUARRYOS")
  writeAt(1, 3, "A " .. textOf(data.width) .. "x" .. textOf(data.length), colors.cyan)
  writeAt(1, 4, depthLine(data, true), colors.lightGray)
  writeAt(1, 5, progressLine(data, true), colors.lightGray)
  writeAt(1, 6, etaLine(data, true), colors.yellow)
  writeAt(1, 7, "F " .. textOf(data.fuel) .. " B " .. textOf(data.blocks), colors.lime)
  writeAt(1, 8, "X " .. fraction(data.columnX, data.width) .. " Z " .. fraction(data.columnZ, data.length), colors.lightGray)
  writeAt(1, 9, statusLine(data, "Working..."), colors.yellow)
  drawControlButton(10, "SVC & PAUSE")
end

local function draw(data)
  if layout == "compact" then
    drawCompact(data)
  else
    drawTiny(data)
  end
end

local function drawWaiting()
  if layout == "compact" then
    beginFrame("QUARRYOS LIVE")
    writeAt(1, 3, "Waiting for Turtle", colors.yellow)
    writeAt(1, 5, "No signal received.", colors.lightGray)
    writeAt(1, 7, "Check Ender/Wireless", colors.lightGray)
    writeAt(1, 8, "Modems on both ends.", colors.lightGray)
    writeAt(1, 9, controlNotice or ("Scale " .. textOf(textScale)), colors.cyan)
    drawControlButton(10, "SERVICE & PAUSE")
  else
    beginFrame("QUARRYOS")
    writeAt(1, 3, "Waiting for", colors.yellow)
    writeAt(1, 4, "Turtle", colors.yellow)
    writeAt(1, 6, "Check modems", colors.lightGray)
    writeAt(1, 8, "Scale " .. textOf(textScale), colors.cyan)
    writeAt(1, 9, controlNotice or "", colors.yellow)
    drawControlButton(10, "SVC & PAUSE")
  end
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

drawWaiting()
print("QuarryOS monitor server ready (" .. layout .. ", text scale " .. textOf(textScale) .. ", " .. screenWidth .. "x" .. screenHeight .. ").")
if monitorName then print("Using monitor: " .. monitorName) end

while true do
  local event, first, second, third = os.pullEvent()
  if event == "rednet_message" then
    local message, protocol = second, third
    if protocol == "quarryos-monitor" then
      local data = textutils.unserialize(message)
      if data then
        controlNotice = nil
        lastData = data
        lastTurtleId = first
        if pendingJobId and data.jobId ~= pendingJobId then
          pendingRequestId = nil
          pendingJobId = nil
          pendingTurtleId = nil
          pendingControl = nil
        end
        draw(data)
      end
    elseif protocol == "quarryos-control-ack" then
      local ack = textutils.unserialize(message)
      if ack and ack.command == "service_pause_ack" and first == pendingTurtleId
        and ack.requestId == pendingRequestId and ack.jobId == pendingJobId then
        pendingRequestId = nil
        pendingJobId = nil
        pendingTurtleId = nil
        pendingControl = nil
        controlNotice = layout == "compact" and "Request confirmed" or "REQ confirmed"
        if lastData then draw(lastData) else drawWaiting() end
        print("Service & pause request confirmed by Turtle " .. tostring(first) .. ".")
      end
    elseif protocol == "quarryos-notify" then
      print("Quarry notification: " .. message)
    end
  elseif event == "monitor_touch" and (not monitorName or first == monitorName) then
    local x, y = second, third
    if controlButton and x >= controlButton.left and x <= controlButton.right and y >= controlButton.top and y <= controlButton.bottom then
      if pendingRequestId then
        local resent = pendingTurtleId and pendingControl
          and rednet.send(pendingTurtleId, pendingControl, "quarryos-control")
        controlNotice = resent and (layout == "compact" and "Request resent - waiting" or "REQ resent")
          or (layout == "compact" and "Retry could not send" or "Retry failed")
        if lastData then draw(lastData) else drawWaiting() end
        if resent then
          print("Service & pause request resent to Turtle " .. tostring(pendingTurtleId) .. ".")
        else
          print("Could not resend the pending service & pause request.")
        end
      elseif not lastTurtleId or not lastData or not lastData.jobId then
        controlNotice = layout == "compact" and "No active quarry signal" or "No quarry signal"
        if lastData then draw(lastData) else drawWaiting() end
        print("Cannot send service request: no active quarry status with a job ID.")
      else
        local requestId = nextRequestId()
        local control = textutils.serialize({
          command = "service_pause",
          jobId = lastData.jobId,
          requestId = requestId,
        })
        local sent = rednet.send(lastTurtleId, control, "quarryos-control")
        if sent then
          pendingRequestId = requestId
          pendingJobId = lastData.jobId
          pendingTurtleId = lastTurtleId
          pendingControl = control
        end
        controlNotice = sent and (layout == "compact" and "Request sent - waiting" or "REQ sent; wait") or "Request could not send"
        if lastData then draw(lastData) else drawWaiting() end
        if sent then
          print("Service & pause request sent to Turtle " .. tostring(lastTurtleId) .. ". Waiting for confirmation.")
        else
          print("Could not send service & pause request to Turtle " .. tostring(lastTurtleId) .. ".")
        end
      end
    end
  elseif event == "monitor_resize" and (not monitorName or first == monitorName) then
    -- setTextScale queues this event too. Only recalculate when the terminal
    -- dimensions really changed, so the event does not cause a loop.
    local width, height = monitor.getSize()
    if width ~= screenWidth or height ~= screenHeight then
      configureDisplay()
      if lastData then draw(lastData) else drawWaiting() end
      print("Monitor resized: " .. layout .. ", text scale " .. textOf(textScale) .. ", " .. screenWidth .. "x" .. screenHeight .. ".")
    end
  end
end

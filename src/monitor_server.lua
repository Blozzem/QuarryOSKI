-- QuarryOS base monitor server. Run this on a base computer with an Advanced
-- Monitor and an Ender Modem. It receives live updates from the turtle.
local monitor = peripheral.find("monitor")
if not monitor then error("Attach an Advanced Monitor to this computer.", 0) end

local monitorName = peripheral.getName and peripheral.getName(monitor) or nil
local screenWidth, screenHeight = monitor.getSize()
local textScale = monitor.getTextScale and monitor.getTextScale() or nil
local layout = "tiny"
local lastData = nil

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

local function textOf(input, fallback)
  if input == nil then return fallback or "?" end
  return tostring(input)
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
  if data.positionStep == nil and data.progressStep == nil then return nil end
  return (short and "S " or "Step: ") .. textOf(data.positionStep) .. "/" .. textOf(data.progressStep)
end

local function drawCompact(data)
  beginFrame("QUARRYOS LIVE")
  writeAt(1, 3, "Area: " .. textOf(data.width) .. "x" .. textOf(data.length), colors.cyan)
  writeAt(1, 4, "X " .. fraction(data.columnX, data.width) .. " Z " .. fraction(data.columnZ, data.length), colors.lightGray)
  writeAt(1, 5, depthLine(data, false), colors.lightGray)

  local step = stepLine(data, false)
  if step then writeAt(1, 6, step, colors.lightGray) end
  writeAt(1, 7, "Fuel: " .. textOf(data.fuel), colors.lime)
  writeAt(1, 8, "Blocks: " .. textOf(data.blocks), colors.lightGray)
  writeAt(1, 10, textOf(data.message, "Working..."), colors.yellow)
end

local function drawTiny(data)
  beginFrame("QUARRYOS")
  writeAt(1, 3, "A " .. textOf(data.width) .. "x" .. textOf(data.length), colors.cyan)
  writeAt(1, 4, "X " .. fraction(data.columnX, data.width), colors.lightGray)
  writeAt(1, 5, "Z " .. fraction(data.columnZ, data.length), colors.lightGray)
  writeAt(1, 6, depthLine(data, true), colors.lightGray)

  local step = stepLine(data, true)
  if step then writeAt(1, 7, step, colors.lightGray) end
  writeAt(1, 8, "F " .. textOf(data.fuel), colors.lime)
  writeAt(1, 9, "B " .. textOf(data.blocks), colors.lightGray)
  writeAt(1, 10, textOf(data.message, "Working..."), colors.yellow)
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
    writeAt(1, 10, "Scale " .. textOf(textScale), colors.cyan)
  else
    beginFrame("QUARRYOS")
    writeAt(1, 3, "Waiting for", colors.yellow)
    writeAt(1, 4, "Turtle", colors.yellow)
    writeAt(1, 6, "Check modems", colors.lightGray)
    writeAt(1, 8, "Scale " .. textOf(textScale), colors.cyan)
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
        lastData = data
        draw(data)
      end
    elseif protocol == "quarryos-notify" then
      print("Quarry notification: " .. message)
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

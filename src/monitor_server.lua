-- QuarryOS base monitor server. Run this on a base computer with an Advanced
-- Monitor and an Ender Modem. It receives live updates from the turtle.
local monitor = peripheral.find("monitor")
if not monitor then error("Attach an Advanced Monitor to this computer.", 0) end

local hasWirelessModem = false
for _, side in ipairs(peripheral.getNames()) do
  if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
    rednet.open(side)
    hasWirelessModem = true
  end
end
if not hasWirelessModem then error("Attach an Ender or Wireless Modem to this computer.", 0) end

local function draw(data)
  if monitor.setTextScale then monitor.setTextScale(0.5) end
  monitor.setBackgroundColor(colors.black)
  monitor.clear()
  monitor.setCursorPos(1, 1)
  monitor.setBackgroundColor(colors.blue)
  monitor.setTextColor(colors.white)
  monitor.write(" QuarryOS LIVE QUARRY ")
  monitor.setBackgroundColor(colors.black)
  monitor.setCursorPos(2, 3)
  monitor.setTextColor(colors.cyan)
  monitor.write("AREA: " .. data.width .. " x " .. data.length)
  monitor.setCursorPos(2, 5)
  monitor.setTextColor(colors.lightGray)
  monitor.write("Column: " .. (data.columnX + 1) .. "/" .. data.width .. "  " .. (data.columnZ + 1) .. "/" .. data.length)
  monitor.setCursorPos(2, 6)
  monitor.write("Depth: " .. data.current .. " / " .. data.mined)
  monitor.setCursorPos(2, 7)
  monitor.write("Fuel: ")
  monitor.setTextColor(colors.lime)
  monitor.write(tostring(data.fuel))
  monitor.setCursorPos(2, 8)
  monitor.setTextColor(colors.lightGray)
  monitor.write("Blocks: " .. data.blocks)
  monitor.setCursorPos(2, 10)
  monitor.setTextColor(colors.yellow)
  monitor.write(data.message or "Working...")
end

print("QuarryOS monitor server ready.")
while true do
  local _, message = rednet.receive("quarryos-monitor")
  local data = textutils.unserialize(message)
  if data then draw(data) end
end

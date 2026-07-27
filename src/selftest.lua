local function result(label, ok, extra)
  term.setTextColor(ok and colors.lime or colors.red)
  print((ok and "OK   " or "FAIL ") .. label .. (extra and " - " .. extra or ""))
  term.setTextColor(colors.white)
end

print("QuarryOS self-test")
result("Advanced Turtle", turtle ~= nil and term.isColor())
result("Fuel chest (top)", peripheral.isPresent("top"))
result("Ore chest (left)", peripheral.isPresent("left"))
result("Block chest (right)", peripheral.isPresent("right"))
local x = gps.locate(3)
result("GPS", x ~= nil)
local modem = false
for _, side in ipairs(peripheral.getNames()) do
  if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then modem = true end
end
result("Ender/Wireless modem", modem)
result("Fuel available", turtle and turtle.getFuelLevel() ~= 0)

local function result(label, ok, extra)
  term.setTextColor(ok and colors.lime or colors.red)
  print((ok and "OK   " or "FAIL ") .. label .. (extra and " - " .. extra or ""))
  term.setTextColor(colors.white)
end

local function isStorage(detail)
  if not detail or not detail.name then return false end
  local name = detail.name:lower()
  return name:find("chest") or name:find("barrel") or name:find("shulker")
    or name:find("crate") or name:find("drawer")
end

local function storageAt(side)
  if not turtle then return false, "not a turtle" end
  local present, detail
  if side == "top" then
    present, detail = turtle.inspectUp()
  elseif side == "left" then
    turtle.turnLeft()
    present, detail = turtle.inspect()
    turtle.turnRight()
  else
    turtle.turnRight()
    present, detail = turtle.inspect()
    turtle.turnLeft()
  end
  return present and isStorage(detail), detail and detail.name or "air"
end

print("QuarryOS self-test")
result("Advanced Turtle", turtle ~= nil and term.isColor())
if turtle then
  local fuelChest, fuelName = storageAt("top")
  local oreChest, oreName = storageAt("left")
  local blockChest, blockName = storageAt("right")
  result("Fuel chest (top)", fuelChest, fuelName)
  result("Ore chest (left)", oreChest, oreName)
  result("Block chest (right)", blockChest, blockName)
end
local x = gps and gps.locate and gps.locate(3)
if x then
  result("GPS (optional)", true)
else
  term.setTextColor(colors.lightGray)
  print("INFO GPS (optional) - not configured")
  term.setTextColor(colors.white)
end
local modem = false
for _, side in ipairs(peripheral.getNames()) do
  if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then modem = true end
end
result("Ender/Wireless modem", modem)
result("Fuel available", turtle and turtle.getFuelLevel() ~= 0)

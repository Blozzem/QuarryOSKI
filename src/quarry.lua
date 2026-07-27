-- QuarryOS Advanced Turtle quarry. A service chest with fuel belongs directly
-- above the starting position. Progress is stored after every vertical move.
local requestedDepth = tonumber(({ ... })[1])
local stateFile = "/quarryos/quarry-state"

if not turtle then
  printError("This program must run on a turtle.")
  return
end

if not term.isColor() then
  printError("QuarryOS requires an Advanced Turtle with a colour display.")
  return
end

local function loadState()
  if not fs.exists(stateFile) then return { current = 0, mined = 0 } end
  local handle = fs.open(stateFile, "r")
  local state = textutils.unserialize(handle.readAll())
  handle.close()
  return state or { current = 0, mined = 0 }
end

local state = loadState()
requestedDepth = requestedDepth or state.maximum

local fuelLevel
local function paint(colour) term.setTextColor(colour) end

local function dashboard(message)
  local width = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setBackgroundColor(colors.blue)
  paint(colors.white)
  write(" QuarryOS  |  ADVANCED TURTLE")
  write(string.rep(" ", math.max(0, width - 30)))
  term.setBackgroundColor(colors.black)

  term.setCursorPos(2, 3)
  paint(colors.cyan)
  write("VERTICAL QUARRY")
  term.setCursorPos(2, 5)
  paint(colors.lightGray)
  write("Current depth: ")
  paint(colors.white)
  write(tostring(state.current))
  term.setCursorPos(2, 6)
  paint(colors.lightGray)
  write("Mining depth:  ")
  paint(colors.white)
  write(tostring(state.mined))
  term.setCursorPos(2, 7)
  paint(colors.lightGray)
  write("Target depth:  ")
  paint(colors.white)
  write(requestedDepth and tostring(requestedDepth) or "Bedrock")
  term.setCursorPos(2, 9)
  paint(colors.lightGray)
  write("Fuel: ")
  paint(colors.lime)
  write(tostring(fuelLevel()))
  term.setCursorPos(2, 10)
  paint(colors.lightGray)
  write("Inventory: ")
  local used = 0
  for slot = 1, 16 do if turtle.getItemCount(slot) > 0 then used = used + 1 end end
  paint(used == 16 and colors.red or colors.lime)
  write(used .. "/16 slots")
  term.setCursorPos(2, 12)
  paint(colors.yellow)
  print(message or "Mining...")
  paint(colors.white)
end

local function saveState()
  local handle = fs.open(stateFile, "w")
  handle.write(textutils.serialize(state))
  handle.close()
end

fuelLevel = function()
  local value = turtle.getFuelLevel()
  return value == "unlimited" and math.huge or value
end

local function inventoryFull()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then return false end
  end
  return true
end

local function moveUp()
  while not turtle.up() do
    if turtle.detectUp() then turtle.digUp() else sleep(0.2) end
  end
  state.current = state.current - 1
  saveState()
  dashboard("Returning to service chest...")
end

local function moveDown()
  while not turtle.down() do sleep(0.2) end
  state.current = state.current + 1
  saveState()
  dashboard("Resuming quarry...")
end

local function returnToSurface()
  while state.current > 0 do moveUp() end
end

local function resumeMiningDepth()
  while state.current < state.mined do moveDown() end
end

local function serviceAtSurface()
  returnToSurface()
  dashboard("Unloading all items...")
  print("Unloading everything to the chest above the turtle...")
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.getItemCount(slot) > 0 and not turtle.dropUp() then
      printError("The service chest is full. Empty it and run the program again.")
      return false
    end
  end

  -- Loot and fuel may share the chest. Non-fuel items are returned to it.
  local targetFuel = (state.mined + 20) * 2
  local attempts = 0
  while fuelLevel() < targetFuel and attempts < 128 do
    turtle.select(16)
    if not turtle.suckUp(1) then break end
    if turtle.refuel(0) then turtle.refuel(1) else turtle.dropUp() end
    attempts = attempts + 1
  end
  if fuelLevel() < targetFuel then
    printError("No usable fuel in the service chest. Add coal or another fuel.")
    return false
  end

  print("Refuelled. Returning to depth " .. state.mined .. "...")
  dashboard("Refuelled - returning to quarry...")
  resumeMiningDepth()
  return true
end

if state.finished then
  print("Previous quarry finished; returning to the surface.")
  returnToSurface()
  fs.delete(stateFile)
  return
end

state.maximum = requestedDepth
saveState()
print("QuarryOS vertical quarry started.")
dashboard("Starting quarry...")
if state.current > 0 then
  print("Resuming from depth " .. state.current .. ".")
end

-- A restart can happen while the turtle was returning for service. Resume its
-- previous mining depth, servicing first when it cannot safely make the trip.
if state.current < state.mined then
  if state.current == 0 and fuelLevel() < (state.mined + 20) * 2 then
    if not serviceAtSurface() then return end
  else
    resumeMiningDepth()
  end
end

while not requestedDepth or state.mined < requestedDepth do
  if inventoryFull() or fuelLevel() < (state.mined + 20) * 2 then
    if not serviceAtSurface() then return end
  end

  if turtle.down() then
    state.current = state.current + 1
    state.mined = state.current
    saveState()
    dashboard("Mining...")
  elseif turtle.detectDown() and turtle.digDown() then
    -- Move into the mined block during the next iteration.
  else
    print("Stopped at an unbreakable block after " .. state.mined .. " layers.")
    break
  end
end

state.finished = true
saveState()
dashboard("Quarry complete - returning home...")
returnToSurface()
fs.delete(stateFile)
print("Quarry complete. The turtle is back at the surface.")

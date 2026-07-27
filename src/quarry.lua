-- QuarryOS Advanced Turtle quarry. The service chest belongs directly above
-- the turtle's starting corner. Width, length and depth are chosen in-game.
local stateFile = "/quarryos/quarry-state"

if not turtle then printError("This program must run on an Advanced Turtle.") return end
if not term.isColor() then printError("QuarryOS requires an Advanced Turtle.") return end

local function loadState()
  if not fs.exists(stateFile) then return nil end
  local handle = fs.open(stateFile, "r")
  local value = textutils.unserialize(handle.readAll())
  handle.close()
  return value
end

local state = loadState()

-- Preserve an unfinished shaft from older QuarryOS releases instead of trying
-- to interpret it as an area-quarry plan.
if state and not state.width then
  fs.move(stateFile, stateFile .. ".legacy")
  state = nil
  print("Old quarry state backed up to /quarryos/quarry-state.legacy")
end

if state and not state.stats then
  state.stats = { blocks = 0, surfaceMoves = 0, verticalMoves = 0, services = 0 }
end

if state and not state.origin then
  printError("This old quarry has no GPS position record and cannot resume safely.")
  print("Start a new quarry after moving the turtle back to its start corner.")
  return
end

local function saveState()
  local handle = fs.open(stateFile, "w")
  handle.write(textutils.serialize(state))
  handle.close()
end

local function fuelLevel()
  local fuel = turtle.getFuelLevel()
  return fuel == "unlimited" and math.huge or fuel
end

local function paint(colour) term.setTextColor(colour) end

local function broadcastMonitor(message)
  local payload = {
    width = state.width, length = state.length, maximum = state.maximum,
    columnX = state.targetX, columnZ = state.targetZ,
    current = state.current, mined = state.mined,
    fuel = fuelLevel(), blocks = state.stats.blocks, message = message,
  }
  pcall(rednet.broadcast, textutils.serialize(payload), "quarryos-monitor")
end

local function notify(message)
  pcall(rednet.broadcast, message, "quarryos-notify")
  broadcastMonitor("NOTICE: " .. message)
end

local function dashboard(message)
  local width = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setBackgroundColor(colors.blue)
  paint(colors.white)
  write(" QuarryOS | ADVANCED QUARRY")
  write(string.rep(" ", math.max(0, width - 28)))
  term.setBackgroundColor(colors.black)
  term.setCursorPos(2, 3)
  paint(colors.cyan)
  write("AREA  " .. state.width .. " x " .. state.length .. "  |  ")
  write(state.maximum == 0 and "BEDROCK" or ("DEPTH " .. state.maximum))
  term.setCursorPos(2, 5)
  paint(colors.lightGray)
  write("Column: ")
  paint(colors.white)
  write((state.targetX + 1) .. "/" .. state.width .. "  " .. (state.targetZ + 1) .. "/" .. state.length)
  term.setCursorPos(2, 6)
  paint(colors.lightGray)
  write("Depth: ")
  paint(colors.white)
  write(state.current .. " / " .. state.mined)
  term.setCursorPos(2, 8)
  paint(colors.lightGray)
  write("Fuel: ")
  paint(colors.lime)
  write(tostring(fuelLevel()))
  local used = 0
  for slot = 1, 16 do if turtle.getItemCount(slot) > 0 then used = used + 1 end end
  term.setCursorPos(2, 9)
  paint(colors.lightGray)
  write("Inventory: ")
  paint(used == 16 and colors.red or colors.lime)
  write(used .. "/16")
  term.setCursorPos(2, 11)
  paint(colors.lightGray)
  write("Blocks mined: ")
  paint(colors.white)
  write(tostring(state.stats.blocks))
  term.setCursorPos(2, 12)
  paint(colors.yellow)
  print(message or "Working...")
  paint(colors.white)
  broadcastMonitor(message)
end

local function menuNumber(label, minimum, allowZero)
  while true do
    term.setCursorPos(2, 1)
    term.clearLine()
    paint(colors.cyan)
    write(label)
    paint(colors.white)
    write(": ")
    local value = tonumber(read())
    if value and (value >= minimum or (allowZero and value == 0)) then return math.floor(value) end
    paint(colors.red)
    print("Please enter a valid whole number.")
  end
end

local function isInventory(side)
  if not peripheral.isPresent(side) then return false end
  if peripheral.hasType then return peripheral.hasType(side, "inventory") end
  return peripheral.wrap(side) ~= nil
end

local function preflightCheck(showHeader)
  if showHeader then
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    paint(colors.white)
    print(" QuarryOS | SERVICE CHEST CHECK ")
    term.setBackgroundColor(colors.black)
  end

  local checks = {
    { side = "top", label = "Fuel chest (top)" },
    { side = "left", label = "Ore chest (left)" },
    { side = "right", label = "Block chest (right)" },
  }
  local ok = true
  for index, check in ipairs(checks) do
    term.setCursorPos(2, index + 2)
    paint(colors.lightGray)
    write(check.label .. ": ")
    if isInventory(check.side) then
      paint(colors.lime)
      print("OK")
    else
      paint(colors.red)
      print("MISSING OR NOT AN INVENTORY")
      ok = false
    end
  end

  if ok then
    local fuelChest = peripheral.wrap("top")
    local contents = fuelChest and fuelChest.list and fuelChest.list() or {}
    if next(contents) == nil then
      term.setCursorPos(2, 7)
      paint(colors.red)
      print("Fuel chest is empty. Add fuel before starting.")
      ok = false
    end
  end
  paint(colors.white)
  return ok
end

local function setupMenu()
  if not preflightCheck(true) then
    paint(colors.white)
    print("Fix the service chests, then run QuarryOS again.")
    return nil
  end
  term.setCursorPos(2, 9)
  paint(colors.lightGray)
  print("Checking GPS position and facing direction...")
  local originX, originY, originZ = gps.locate(5)
  if not originX then
    paint(colors.red)
    print("GPS is required. Set up GPS host computers, then run again.")
    return nil
  end
  if not turtle.forward() then
    paint(colors.red)
    print("The block in front must be clear for the GPS direction check.")
    return nil
  end
  local forwardX, _, forwardZ = gps.locate(5)
  turtle.back()
  if not forwardX then
    paint(colors.red)
    print("GPS direction check failed. Run again near GPS coverage.")
    return nil
  end
  print("")
  print("Select quarry plan:")
  print("  1) Small  8 x 8  to bedrock")
  print("  2) Medium 16 x 16 to bedrock")
  print("  3) Large  32 x 32 to bedrock")
  print("  4) Custom size")
  local choice = menuNumber("Plan", 1, false)
  local width, length, maximum
  if choice == 1 then width, length, maximum = 8, 8, 0
  elseif choice == 2 then width, length, maximum = 16, 16, 0
  elseif choice == 3 then width, length, maximum = 32, 32, 0
  elseif choice == 4 then
    width = menuNumber("Width (blocks)", 1, false)
    length = menuNumber("Length (blocks)", 1, false)
    maximum = menuNumber("Depth (0 = bedrock)", 1, true)
  else
    printError("Unknown plan.")
    return nil
  end
  local estimateDepth = maximum == 0 and 320 or maximum
  local estimatedBlocks = width * length * estimateDepth
  local estimatedFuel = estimatedBlocks * 2 + width * length * 8 + 200
  print("Estimated blocks: " .. estimatedBlocks)
  print("Estimated fuel:  " .. estimatedFuel)
  write("Start this quarry? [Y/n] ")
  if read():lower() == "n" then return nil end
  return {
    width = width, length = length, maximum = maximum,
    targetX = 0, targetZ = 0, x = 0, z = 0, heading = 0,
    current = 0, mined = 0, phase = "ready",
    stats = { blocks = 0, surfaceMoves = 0, verticalMoves = 0, services = 0 },
    origin = { x = originX, y = originY, z = originZ, forwardX = forwardX - originX, forwardZ = forwardZ - originZ },
    started = os.epoch("utc"), plan = choice,
  }
end

if not state then
  state = setupMenu()
  if not state then return end
  saveState()
  notify("Quarry started: " .. state.width .. "x" .. state.length)
elseif not preflightCheck(true) then
  paint(colors.white)
  print("Fix the service chests before resuming this quarry.")
  return
end

local function verifySavedPosition()
  local x, y, z = gps.locate(5)
  if not x then
    printError("GPS is unavailable. QuarryOS will not resume without a position check.")
    return false
  end
  local origin = state.origin
  local rightX, rightZ = -origin.forwardZ, origin.forwardX
  local expectedX = origin.x + origin.forwardX * state.x + rightX * state.z
  local expectedY = origin.y - state.current
  local expectedZ = origin.z + origin.forwardZ * state.x + rightZ * state.z
  if x ~= expectedX or y ~= expectedY or z ~= expectedZ then
    printError("Turtle position does not match the saved quarry position.")
    print("Expected: " .. expectedX .. ", " .. expectedY .. ", " .. expectedZ)
    print("Found:    " .. x .. ", " .. y .. ", " .. z)
    return false
  end
  return true
end

if not verifySavedPosition() then return end

-- Heading: 0=east, 1=south, 2=west, 3=north. Coordinates are saved after
-- every surface move, so a restart while travelling can safely return home.
local vectors = { [0] = { 1, 0 }, [1] = { 0, 1 }, [2] = { -1, 0 }, [3] = { 0, -1 } }
local function turnRight()
  turtle.turnRight()
  state.heading = (state.heading + 1) % 4
  saveState()
end
local function face(direction)
  while state.heading ~= direction do turnRight() end
end
local function surfaceForward()
  while not turtle.forward() do
    if turtle.detect() then
      if turtle.dig() then state.stats.blocks = state.stats.blocks + 1 end
    else sleep(0.2) end
  end
  local vector = vectors[state.heading]
  state.x = state.x + vector[1]
  state.z = state.z + vector[2]
  state.stats.surfaceMoves = state.stats.surfaceMoves + 1
  saveState()
end
local function moveTo(x, z)
  if state.x ~= x then
    face(x > state.x and 0 or 2)
    while state.x ~= x do surfaceForward() end
  end
  if state.z ~= z then
    face(z > state.z and 1 or 3)
    while state.z ~= z do surfaceForward() end
  end
  face(0)
end
local function moveUp()
  while not turtle.up() do
    if turtle.detectUp() then if turtle.digUp() then state.stats.blocks = state.stats.blocks + 1 end else sleep(0.2) end
  end
  state.current = state.current - 1
  state.stats.verticalMoves = state.stats.verticalMoves + 1
  saveState()
end
local function moveDown()
  while not turtle.down() do sleep(0.2) end
  state.current = state.current + 1
  state.stats.verticalMoves = state.stats.verticalMoves + 1
  saveState()
end
local function returnToSurface()
  while state.current > 0 do moveUp() end
end

local function serviceChest()
  dashboard("Unloading into service chest...")
  state.stats.services = state.stats.services + 1
  saveState()
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.getItemCount(slot) > 0 then
      local detail = turtle.getItemDetail(slot)
      local name = detail and detail.name or ""
      local valuable = name:find("ore") or name:find("raw_") or name:find("diamond") or name:find("emerald") or name:find("lapis") or name:find("redstone") or name:find("quartz") or name:find("ancient_debris")
      if valuable then turnRight(); turnRight(); turnRight() else turnRight() end
      local dropped = turtle.drop()
      if valuable then turnRight() else turnRight(); turnRight(); turnRight() end
      if not dropped then
        printError("Output chest is full. Empty it and restart the quarry.")
        return false
      end
    end
  end
  local depthBudget = state.maximum == 0 and 1024 or state.maximum * 2 + 80
  local attempts = 0
  while fuelLevel() < depthBudget and attempts < 256 do
    turtle.select(16)
    if not turtle.suckUp(1) then break end
    if turtle.refuel(0) then turtle.refuel(1) else turtle.dropUp() end
    attempts = attempts + 1
  end
  if fuelLevel() < depthBudget then
    printError("Add more fuel to the service chest, then restart the quarry.")
    return false
  end
  return true
end

local function goHomeAndService()
  returnToSurface()
  moveTo(0, 0)
  return serviceChest()
end

local function mineColumn()
  state.phase = "mining"
  saveState()
  while state.current < state.mined do moveDown() end
  while state.maximum == 0 or state.mined < state.maximum do
    if fuelLevel() < (state.current + 20) * 2 then
      state.phase = "returning"
      saveState()
      return false
    end
    if turtle.down() then
      state.current = state.current + 1
      state.mined = state.current
      saveState()
      dashboard("Mining column...")
    elseif turtle.detectDown() and turtle.digDown() then
      state.stats.blocks = state.stats.blocks + 1
      -- Step into the mined block on the next iteration.
    else
      return true
    end
  end
  return true
end

local function advanceColumn()
  state.mined = 0
  state.current = 0
  state.targetX = state.targetX + 1
  if state.targetX >= state.width then
    state.targetX = 0
    state.targetZ = state.targetZ + 1
  end
  state.phase = "ready"
  saveState()
end

-- Recover from a restart during a return trip before deciding the next action.
if state.phase == "returning" then
  dashboard("Resuming return to service chest...")
  if not goHomeAndService() then return end
  state.phase = "ready"
  saveState()
end

while state.targetZ < state.length do
  dashboard("Travelling to next column...")
  if state.current > 0 then
    -- A restart while mining: continue exactly at the recorded depth.
    local finished = mineColumn()
    if not finished then
      if not goHomeAndService() then return end
    else
      returnToSurface()
      if not goHomeAndService() then return end
      advanceColumn()
    end
  else
    if state.x ~= 0 or state.z ~= 0 then moveTo(0, 0) end
    if not serviceChest() then return end
    moveTo(state.targetX, state.targetZ)
    local finished = mineColumn()
    if not finished then
      if not goHomeAndService() then return end
    else
      returnToSurface()
      if not goHomeAndService() then return end
      advanceColumn()
    end
  end
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
paint(colors.lime)
print("Quarry complete. All columns were delivered to the service chest.")
paint(colors.white)
notify("Quarry complete: " .. state.stats.blocks .. " blocks mined")
local statsHandle = fs.open("/quarryos/quarry-last-stats", "w")
statsHandle.write(textutils.serialize(state.stats))
statsHandle.close()
local history = fs.open("/quarryos/quarry-history", "a")
history.writeLine(textutils.serialize({
  width = state.width, length = state.length, maximum = state.maximum,
  blocks = state.stats.blocks, started = state.started, finished = os.epoch("utc"),
}))
history.close()
fs.delete(stateFile)

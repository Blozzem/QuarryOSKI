-- QuarryOS Advanced Turtle layer quarry.
-- The turtle starts at the top corner, mines one full horizontal layer below
-- itself in a zig-zag path, then descends to the next layer.
local arguments = { ... }
local stateFile = "/quarryos/quarry-state"
local stateBackupFile = stateFile .. ".bak"
local stateTemporaryFile = stateFile .. ".tmp"
-- Keep the route format explicit. A saved plan from another quarry layout must
-- never be resumed with this route, even if its other fields look compatible.
local stateLayout = "layer-zigzag-v1"

if not turtle then printError("This program must run on an Advanced Turtle.") return end
if not term.isColor() then printError("QuarryOS requires an Advanced Turtle.") return end

local function readState(path)
  if not fs.exists(path) then return nil end
  local handle = fs.open(path, "r")
  if not handle then return nil end
  local content = handle.readAll()
  handle.close()
  local ok, value = pcall(textutils.unserialize, content)
  return ok and value or nil
end

local function loadState()
  local primary = readState(stateFile)
  if primary then return primary, false end
  local backup = readState(stateBackupFile)
  if backup then return backup, true end
  return nil, false
end

local function archiveState(label)
  local target = stateFile .. "." .. label .. "-" .. tostring(os.epoch("utc"))
  local suffix = 1
  while fs.exists(target) do
    target = stateFile .. "." .. label .. "-" .. tostring(os.epoch("utc")) .. "-" .. suffix
    suffix = suffix + 1
  end
  if fs.exists(stateFile) then
    fs.move(stateFile, target)
  elseif fs.exists(stateBackupFile) then
    fs.move(stateBackupFile, target)
  end
  if fs.exists(stateBackupFile) then fs.move(stateBackupFile, target .. ".bak") end
  if fs.exists(stateTemporaryFile) then fs.delete(stateTemporaryFile) end
  return target
end

if arguments[1] and arguments[1] ~= "new" then
  print("Usage: quarry [new]")
  print("  quarry      Resume the saved quarry, or plan one when none exists.")
  print("  quarry new  Archive the saved quarry and plan a new one.")
  return
end

local state, recoveredFromBackup = loadState()
local hasSavedState = fs.exists(stateFile) or fs.exists(stateBackupFile)
if arguments[1] == "new" and hasSavedState then
  local archived = archiveState("cancelled")
  state = nil
  print("Previous quarry progress archived to " .. archived)
end

if hasSavedState and not state and arguments[1] ~= "new" then
  printError("The saved quarry state is damaged. Run 'q new' to archive it and start again.")
  return
end
if recoveredFromBackup and arguments[1] ~= "new" then print("Recovered the last valid quarry state backup.") end

-- A plan from a different route layout cannot be interpreted safely here.
if state and state.layout ~= stateLayout then
  local archived = archiveState("legacy")
  state = nil
  print("Old column-quarry progress was archived to " .. archived)
  print("Layer mode needs a new quarry plan.")
end

if state and not state.origin then
  printError("The saved quarry has no GPS record. Run 'q new' at the starting corner.")
  return
end

if state and not state.stats then
  state.stats = { blocks = 0, surfaceMoves = 0, verticalMoves = 0, services = 0 }
end
if state then
  -- Plans created by the first layer release always travelled forwards. Add
  -- the new direction/progress fields without losing a job which is already
  -- in progress.
  local totalCells = state.width * state.length
  state.nextCell = state.nextCell or 0
  state.routeDirection = state.routeDirection or 1
  if state.layerProgress == nil then
    state.layerProgress = state.layerComplete and totalCells or math.max(0, state.nextCell)
  end
  if state.layerProgress >= totalCells and state.nextCell >= totalCells then
    state.layerProgress = totalCells
    state.nextCell = totalCells - 1
  end
  state.version = math.max(3, state.version or 1)
  state.jobId = state.jobId or (tostring(os.getComputerID()) .. "-" .. tostring(os.epoch("utc")))
  state.bedrockFound = state.bedrockFound or false
  state.layerComplete = state.layerComplete or false
  state.stopAfterLayerRequested = state.stopAfterLayerRequested or false
  -- Estimate the normal Overworld bedrock level for a useful *approximate*
  -- progress display. The actual quarry still stops only when it finds
  -- bedrock, so modded worlds and other dimensions remain safe.
  state.estimatedLayers = state.estimatedLayers or (state.maximum == 0
    and math.max(1, state.origin.y + 64) or state.maximum)
  state.timing = state.timing or {}
  state.timing.lastCompleted = state.timing.lastCompleted
    or ((state.layer - 1) * totalCells + math.min(totalCells, state.layerProgress or 0))
  state.timing.lastEpoch = state.timing.lastEpoch or os.epoch("utc")
end

local function saveState()
  if fs.exists(stateTemporaryFile) then fs.delete(stateTemporaryFile) end
  local handle = fs.open(stateTemporaryFile, "w")
  handle.write(textutils.serialize(state))
  handle.close()
  if fs.exists(stateBackupFile) then fs.delete(stateBackupFile) end
  if fs.exists(stateFile) then
    fs.copy(stateFile, stateBackupFile)
    fs.delete(stateFile)
  end
  fs.move(stateTemporaryFile, stateFile)
end

local function fuelLevel()
  local fuel = turtle.getFuelLevel()
  return fuel == "unlimited" and math.huge or fuel
end

local function fuelCapacity()
  local capacity = turtle.getFuelLimit()
  return capacity == "unlimited" and math.huge or capacity
end

local function completedCells()
  local cellsPerLayer = state.width * state.length
  return math.max(0, (math.max(1, state.layer or 1) - 1) * cellsPerLayer
    + math.min(cellsPerLayer, math.max(0, state.layerProgress or 0)))
end

local function progressTarget()
  local approximate = state.maximum == 0
  local layers = approximate and state.estimatedLayers or state.maximum
  layers = math.max(1, math.floor(tonumber(layers) or 1))
  return state.width * state.length * layers, approximate
end

-- Keep a moving average for one mined cell. This survives restarts and gives
-- a practical ETA; very long interruption gaps are ignored as pauses.
local function recordProgressTiming()
  state.timing = state.timing or {}
  local now = os.epoch("utc")
  local completed = completedCells()
  local previous = tonumber(state.timing.lastCompleted) or completed
  local previousEpoch = tonumber(state.timing.lastEpoch) or now
  local gained = completed - previous
  local elapsed = now - previousEpoch

  if gained > 0 and elapsed >= 0 and elapsed <= 300000 * gained then
    local sample = elapsed / gained
    local average = tonumber(state.timing.averageCellMs)
    state.timing.averageCellMs = average
      and math.floor(average * 0.75 + sample * 0.25 + 0.5)
      or math.floor(sample + 0.5)
  end

  state.timing.lastCompleted = completed
  state.timing.lastEpoch = now
end

local function quarryProgress()
  local plannedCells, approximate = progressTarget()
  local completed = math.min(plannedCells, completedCells())
  local percentage = math.floor((completed / plannedCells) * 100 + 0.5)
  -- A bedrock plan has no fixed depth. Do not promise 100% before bedrock was
  -- really encountered, even when the normal-world estimate is reached.
  if approximate and state.bedrockFound then
    percentage = 100
  elseif approximate then
    percentage = math.min(99, percentage)
  end

  local average = state.timing and tonumber(state.timing.averageCellMs)
  local remaining = state.bedrockFound and 0
    or (average and math.max(0, plannedCells - completed) * average or nil)
  return percentage, remaining, approximate, completed, plannedCells
end

local function formatDuration(milliseconds)
  if not milliseconds then return "calculating..." end
  local seconds = math.max(0, math.ceil(milliseconds / 1000))
  if seconds < 60 then return "<1 min" end
  local minutes = math.floor(seconds / 60)
  if minutes < 60 then return tostring(minutes) .. " min" end
  local hours = math.floor(minutes / 60)
  minutes = minutes % 60
  if hours < 24 then return tostring(hours) .. "h " .. string.format("%02d", minutes) .. "m" end
  local days = math.floor(hours / 24)
  hours = hours % 24
  return tostring(days) .. "d " .. tostring(hours) .. "h"
end

local function fuelRequiredForResume()
  local workDepth = state.layer - 1
  local total = state.width * state.length
  local workChunk = math.min(256, math.max(0, total - (state.layerProgress or 0)))
  return math.max(64, (workDepth + state.nextCell + workChunk + 1) * 2 + 24)
end

-- The direction check moves forward and back once. Load its two movement
-- points from the chest above before the first movement attempt.
local function loadSetupFuel(required)
  if fuelLevel() >= required then return true end

  local selected = turtle.getSelectedSlot()
  while fuelLevel() < required do
    local freeSlot
    for slot = 1, 16 do
      if turtle.getItemCount(slot) == 0 then
        freeSlot = slot
        break
      end
    end
    if not freeSlot then break end

    turtle.select(freeSlot)
    if not turtle.suckUp(1) then break end
    if not turtle.refuel(1) then
      turtle.dropUp()
      break
    end
  end
  turtle.select(selected)
  return fuelLevel() >= required
end

local function paint(colour) term.setTextColor(colour) end

-- Rednet only broadcasts through opened modems. The turtle modem is normally
-- its second upgrade, next to the mining tool.
local monitorNetworkReady = false
local function openMonitorModems()
  local opened = false
  for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "modem" then
      local modem = peripheral.wrap(side)
      if modem and modem.isWireless() then
        local ok = pcall(rednet.open, side)
        if ok then opened = true end
      end
    end
  end
  return opened
end

monitorNetworkReady = openMonitorModems()

local function broadcastMonitor(message)
  local total = state.width * state.length
  local percentage, eta, approximate, completed, planned = quarryProgress()
  local requiredFuel = fuelRequiredForResume()
  local payload = {
    jobId = state.jobId, turtleName = os.getComputerLabel() or ("Turtle " .. os.getComputerID()), phase = state.phase,
    width = state.width, length = state.length, maximum = state.maximum,
    -- The work area begins one block in front of the service corner, so turn
    -- the local X coordinate back into a zero-based in-area monitor position.
    columnX = math.max(0, state.x - 1), columnZ = state.z,
    current = state.depth, mined = state.layer,
    layer = state.layer, nextCell = state.nextCell, totalCells = total,
    positionStep = state.positionStep + 1, progressStep = total,
    layerProgress = state.layerProgress,
    progressPercent = percentage, progressEstimated = approximate,
    estimatedRemainingMs = eta, completedCells = completed, plannedCells = planned,
    fuelRequired = requiredFuel, fuelShortfall = math.max(0, requiredFuel - fuelLevel()),
    stopAfterLayerRequested = state.stopAfterLayerRequested,
    fuel = fuelLevel(), blocks = state.stats.blocks, message = message,
  }
  if not monitorNetworkReady then monitorNetworkReady = openMonitorModems() end
  if monitorNetworkReady then
    rednet.broadcast(textutils.serialize(payload), "quarryos-monitor")
  end
end

local function notify(message, level)
  if not monitorNetworkReady then monitorNetworkReady = openMonitorModems() end
  if monitorNetworkReady then
    rednet.broadcast(textutils.serialize({
      jobId = state.jobId, turtleName = os.getComputerLabel() or ("Turtle " .. os.getComputerID()),
      message = message, level = level or "info",
    }), "quarryos-notify")
  end
  broadcastMonitor("NOTICE: " .. message)
end

local function dashboard(message)
  local screenWidth = term.getSize()
  local total = state.width * state.length
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setBackgroundColor(colors.blue)
  paint(colors.white)
  write(" QuarryOS | LAYER QUARRY")
  write(string.rep(" ", math.max(0, screenWidth - 25)))
  term.setBackgroundColor(colors.black)

  term.setCursorPos(2, 3)
  paint(colors.cyan)
  write("AREA  " .. state.width .. " x " .. state.length .. "  |  ")
  write(state.maximum == 0 and "BEDROCK" or ("DEPTH " .. state.maximum))
  term.setCursorPos(2, 5)
  paint(colors.lightGray)
  write("Layer: ")
  paint(colors.white)
  write(state.layer .. (state.maximum == 0 and " / bedrock" or (" / " .. state.maximum)))
  term.setCursorPos(2, 6)
  paint(colors.lightGray)
  write("Cell: ")
  paint(colors.white)
  write(math.min((state.layerProgress or 0) + 1, total) .. "/" .. total .. "  (" .. state.x .. "," .. state.z .. ")")
  term.setCursorPos(2, 7)
  paint(colors.lightGray)
  write("Work depth: ")
  paint(colors.white)
  write(tostring(state.depth))
  term.setCursorPos(2, 8)
  paint(colors.lightGray)
  write("Progress: ")
  local percentage, eta, approximate = quarryProgress()
  paint(colors.white)
  write((approximate and "~" or "") .. percentage .. "%")
  term.setCursorPos(2, 9)
  paint(colors.lightGray)
  write("ETA: ")
  paint(colors.white)
  write((approximate and "~" or "") .. formatDuration(eta))
  term.setCursorPos(2, 11)
  paint(colors.lightGray)
  write("Fuel: ")
  paint(colors.lime)
  write(tostring(fuelLevel()))
  local used = 0
  for slot = 1, 16 do if turtle.getItemCount(slot) > 0 then used = used + 1 end end
  term.setCursorPos(2, 12)
  paint(colors.lightGray)
  write("Inventory: ")
  paint(used == 16 and colors.red or colors.lime)
  write(used .. "/16")
  term.setCursorPos(2, 14)
  paint(colors.lightGray)
  write("Blocks mined: ")
  paint(colors.white)
  write(tostring(state.stats.blocks))
  term.setCursorPos(2, 16)
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

local function isStorageBlock(detail)
  if not detail then return false end
  local name = detail.name:lower()
  return name:find("chest") or name:find("barrel") or name:find("shulker")
    or name:find("crate") or name:find("drawer")
end

local function storageAt(side)
  local ok, detail
  if side == "top" then
    ok, detail = turtle.inspectUp()
  elseif side == "left" then
    turtle.turnLeft()
    ok, detail = turtle.inspect()
    turtle.turnRight()
  else -- right
    turtle.turnRight()
    ok, detail = turtle.inspect()
    turtle.turnLeft()
  end
  return ok and isStorageBlock(detail), detail and detail.name or "air"
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
    local found, blockName = storageAt(check.side)
    if found then
      paint(colors.lime)
      print("OK (" .. blockName .. ")")
    else
      paint(colors.red)
      print("NOT STORAGE (" .. blockName .. ")")
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
  if fuelLevel() < 2 then
    print("Loading fuel from the top chest for GPS direction check...")
    if not loadSetupFuel(2) then
      paint(colors.red)
      print("Not enough usable fuel in the top fuel chest.")
      return nil
    end
  end

  local moved, moveReason = turtle.forward()
  if not moved then
    local hasBlock, detail = turtle.inspect()
    if hasBlock then
      local dug, digReason = turtle.dig()
      if dug then
        moved, moveReason = turtle.forward()
        if moved then print("Mined the first block for the GPS direction check.") end
      else
        paint(colors.red)
        print("Cannot mine the block in front: " .. (detail.name or "unknown block"))
        print(digReason or "Check the turtle tool and any claim/protection.")
        return nil
      end
    end
    if not moved then
      paint(colors.red)
      print("Cannot move forward for GPS direction check.")
      print(moveReason or "The front may be blocked by an entity or protected area.")
      return nil
    end
  end
  local forwardX, _, forwardZ = gps.locate(5)
  local returned, returnReason = turtle.back()
  if not returned then
    paint(colors.red)
    print("GPS check succeeded, but the turtle cannot return to its start.")
    print(returnReason or "Clear the block or entity behind the turtle, then move it back manually.")
    return nil
  end
  if not forwardX then
    paint(colors.red)
    print("GPS direction check failed. Run again near GPS coverage.")
    return nil
  end

  print("")
  print("Select layer quarry plan:")
  print("  1) Small  16 x 16 to bedrock")
  print("  2) Medium 32 x 32 to bedrock")
  print("  3) Large  64 x 64 to bedrock")
  print("  4) Custom size")
  local choice = menuNumber("Plan", 1, false)
  local width, length, maximum
  if choice == 1 then width, length, maximum = 16, 16, 0
  elseif choice == 2 then width, length, maximum = 32, 32, 0
  elseif choice == 3 then width, length, maximum = 64, 64, 0
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
  print("Mode: every full horizontal layer is mined before descending.")
  print("Estimated blocks: " .. estimatedBlocks)
  print("Estimated fuel:  " .. estimatedFuel)
  write("Start this quarry? [Y/n] ")
  if read():lower() == "n" then return nil end
  return {
    layout = stateLayout, version = 3,
    width = width, length = length, maximum = maximum,
    x = 0, z = 0, heading = 0, depth = 0,
    layer = 1, nextCell = 0, layerProgress = 0, routeDirection = 1, positionStep = -1,
    layerComplete = false, bedrockFound = false, phase = "surface",
    stats = { blocks = 0, surfaceMoves = 0, verticalMoves = 0, services = 0 },
    origin = { x = originX, y = originY, z = originZ, forwardX = forwardX - originX, forwardZ = forwardZ - originZ },
    started = os.epoch("utc"), plan = choice,
    estimatedLayers = maximum == 0 and math.max(1, originY + 64) or maximum,
    timing = { lastCompleted = 0, lastEpoch = os.epoch("utc") },
    jobId = tostring(os.getComputerID()) .. "-" .. tostring(os.epoch("utc")),
  }
end

local function worldPosition(x, z, depth)
  local origin = state.origin
  local rightX, rightZ = -origin.forwardZ, origin.forwardX
  return origin.x + origin.forwardX * x + rightX * z,
    origin.y - depth,
    origin.z + origin.forwardZ * x + rightZ * z
end

local function resolvePendingMove()
  local pending = state.pendingMove
  if not pending then return true end
  local x, y, z = gps.locate(5)
  if not x then
    printError("GPS is unavailable. QuarryOS cannot recover an interrupted move.")
    return false
  end
  local fromX, fromY, fromZ = worldPosition(pending.fromX, pending.fromZ, pending.fromDepth)
  local toX, toY, toZ = worldPosition(pending.x, pending.z, pending.depth)
  if x == toX and y == toY and z == toZ then
    state.x, state.z, state.depth = pending.x, pending.z, pending.depth
    if pending.positionStep ~= nil then state.positionStep = pending.positionStep end
    if pending.action == "forward" then
      state.stats.surfaceMoves = state.stats.surfaceMoves + 1
    else
      state.stats.verticalMoves = state.stats.verticalMoves + 1
    end
    state.pendingMove = nil
    saveState()
    print("Recovered an interrupted " .. pending.action .. " movement.")
    return true
  end
  if x == fromX and y == fromY and z == fromZ then
    state.pendingMove = nil
    saveState()
    return true
  end
  printError("Turtle position does not match the interrupted movement record.")
  return false
end

local function verifySavedPosition()
  local x, y, z = gps.locate(5)
  if not x then
    printError("GPS is unavailable. QuarryOS will not resume without a position check.")
    return false
  end
  local expectedX, expectedY, expectedZ = worldPosition(state.x, state.z, state.depth)
  if x ~= expectedX or y ~= expectedY or z ~= expectedZ then
    printError("Turtle position does not match the saved quarry position.")
    print("Expected: " .. expectedX .. ", " .. expectedY .. ", " .. expectedZ)
    print("Found:    " .. x .. ", " .. y .. ", " .. z)
    return false
  end
  return true
end

local resumePausedQuarry = state and state.phase == "paused"
if not state then
  state = setupMenu()
  if not state then return end
  saveState()
  notify("Layer quarry started: " .. state.width .. "x" .. state.length, "info")
elseif (state.phase == "surface" or resumePausedQuarry) and not preflightCheck(true) then
  paint(colors.white)
  print("Fix the service chests before resuming this quarry.")
  return
end

if not resolvePendingMove() then return end
if not verifySavedPosition() then return end
if resumePausedQuarry then
  state.phase = "surface"
  state.pauseRequested = nil
  state.pauseRequestId = nil
  saveState()
  print("Resuming the quarry from the service station...")
end

-- These are local coordinates: 0 is the start-facing direction, then right,
-- back and left. GPS conversion above uses the recorded start-facing vector.
local vectors = { [0] = { 1, 0 }, [1] = { 0, 1 }, [2] = { -1, 0 }, [3] = { 0, -1 } }

local function turnRight()
  local turned, reason = turtle.turnRight()
  if not turned then
    printError("Cannot turn the turtle: " .. (reason or "unknown reason"))
    return false
  end
  state.heading = (state.heading + 1) % 4
  saveState()
  return true
end

local function turnLeft()
  local turned, reason = turtle.turnLeft()
  if not turned then
    printError("Cannot turn the turtle: " .. (reason or "unknown reason"))
    return false
  end
  state.heading = (state.heading + 3) % 4
  saveState()
  return true
end

local function face(direction)
  local turnCount = (direction - state.heading) % 4
  if turnCount == 0 then return true end
  if turnCount == 1 then return turnRight() end
  if turnCount == 2 then return turnRight() and turnRight() end
  return turnLeft()
end

local function moveForward(allowDig)
  local moved, reason = turtle.forward()
  if not moved and allowDig then
    local hasBlock, detail = turtle.inspect()
    if hasBlock then
      local dug, digReason = turtle.dig()
      if dug then
        state.stats.blocks = state.stats.blocks + 1
        moved, reason = turtle.forward()
      else
        reason = "Cannot mine " .. (detail.name or "front block") .. ": " .. (digReason or "unknown reason")
      end
    end
  end
  if not moved then
    printError("Cannot move forward: " .. (reason or "path blocked"))
    notify("Movement blocked: " .. (reason or "path blocked"), "error")
    return false
  end
  local vector = vectors[state.heading]
  state.x = state.x + vector[1]
  state.z = state.z + vector[2]
  state.stats.surfaceMoves = state.stats.surfaceMoves + 1
  return true
end

local function moveDown(allowDig)
  state.pendingMove = {
    action = "down", fromX = state.x, fromZ = state.z, fromDepth = state.depth,
    x = state.x, z = state.z, depth = state.depth + 1, positionStep = state.positionStep,
  }
  saveState()
  local moved, reason = turtle.down()
  if not moved and allowDig then
    local hasBlock, detail = turtle.inspectDown()
    if hasBlock then
      local dug, digReason = turtle.digDown()
      if dug then
        state.stats.blocks = state.stats.blocks + 1
        moved, reason = turtle.down()
      else
        reason = "Cannot mine " .. (detail.name or "block below") .. ": " .. (digReason or "unknown reason")
      end
    end
  end
  if not moved then
    state.pendingMove = nil
    saveState()
    printError("Cannot move down: " .. (reason or "path blocked"))
    notify("Downward movement blocked: " .. (reason or "path blocked"), "error")
    return false
  end
  state.depth = state.depth + 1
  state.stats.verticalMoves = state.stats.verticalMoves + 1
  state.pendingMove = nil
  saveState()
  return true
end

local function moveUp(allowDig)
  state.pendingMove = {
    action = "up", fromX = state.x, fromZ = state.z, fromDepth = state.depth,
    x = state.x, z = state.z, depth = state.depth - 1, positionStep = state.positionStep,
  }
  saveState()
  local moved, reason = turtle.up()
  if not moved and allowDig then
    local hasBlock, detail = turtle.inspectUp()
    if hasBlock then
      local dug, digReason = turtle.digUp()
      if dug then
        state.stats.blocks = state.stats.blocks + 1
        moved, reason = turtle.up()
      else
        reason = "Cannot mine " .. (detail.name or "block above") .. ": " .. (digReason or "unknown reason")
      end
    end
  end
  if not moved then
    state.pendingMove = nil
    saveState()
    printError("Cannot move up: " .. (reason or "path blocked"))
    notify("Upward movement blocked: " .. (reason or "path blocked"), "error")
    return false
  end
  state.depth = state.depth - 1
  state.stats.verticalMoves = state.stats.verticalMoves + 1
  state.pendingMove = nil
  saveState()
  return true
end

local function cellForStep(step)
  -- Step -1 is the service corner. The actual quarry begins one block ahead,
  -- keeping both side output chests outside the selected area.
  if step == -1 then return 0, 0 end
  local row = math.floor(step / state.width)
  local column = step % state.width
  local x = row % 2 == 0 and (column + 1) or (state.width - column)
  return x, row
end

local function directionTo(x, z)
  local deltaX, deltaZ = x - state.x, z - state.z
  if deltaX == 1 and deltaZ == 0 then return 0 end
  if deltaX == 0 and deltaZ == 1 then return 1 end
  if deltaX == -1 and deltaZ == 0 then return 2 end
  if deltaX == 0 and deltaZ == -1 then return 3 end
  return nil
end

local function moveToRouteStep(step, allowDig)
  local x, z = cellForStep(step)
  local direction = directionTo(x, z)
  if not direction then
    printError("Saved layer path is not adjacent to the turtle position.")
    return false
  end
  if not face(direction) then return false end
  state.pendingMove = {
    action = "forward", fromX = state.x, fromZ = state.z, fromDepth = state.depth,
    x = x, z = z, depth = state.depth, positionStep = step,
  }
  saveState()
  if not moveForward(allowDig) then
    state.pendingMove = nil
    saveState()
    return false
  end
  if state.x ~= x or state.z ~= z then
    state.pendingMove = nil
    saveState()
    printError("Turtle movement did not reach the expected layer cell.")
    return false
  end
  state.positionStep = step
  state.pendingMove = nil
  saveState()
  return true
end

local function inventoryFull()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then return false end
  end
  return true
end

local function fuelForSafeReturn(includeNextMove)
  -- positionStep 0 is the first work cell, one move away from the service
  -- corner. When another move follows, both that move and the longer return
  -- route must be reserved.
  local moves = state.positionStep + state.depth + 13
  if includeNextMove then moves = moves + 2 end
  return moves
end

local function fuelForResume()
  return fuelRequiredForResume()
end

local function serviceChest(requiredFuel)
  dashboard("Unloading into service chests...")
  -- The return path may leave the turtle facing back toward the quarry. The
  -- chest layout is defined relative to its original facing, so restore that
  -- direction before using the left/right output chests.
  if not face(0) then return false end
  local hasFuelChest, fuelChestDetail = turtle.inspectUp()
  if not hasFuelChest or not isStorageBlock(fuelChestDetail) then
    printError("Fuel chest above the turtle is missing or is not storage.")
    return false
  end
  state.stats.services = state.stats.services + 1
  saveState()
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.getItemCount(slot) > 0 then
      local detail = turtle.getItemDetail(slot)
      local name = detail and detail.name or ""
      local valuable = name:find("ore") or name:find("raw_") or name:find("diamond")
        or name:find("emerald") or name:find("lapis") or name:find("redstone")
        or name:find("quartz") or name:find("ancient_debris")
      local chestDirection = valuable and 3 or 1
      if not face(chestDirection) then return false end
      local hasOutputChest, outputChestDetail = turtle.inspect()
      if not hasOutputChest or not isStorageBlock(outputChestDetail) then
        face(0)
        printError("Output chest is missing or is not storage. Nothing was dropped.")
        return false
      end
      while turtle.getItemCount(slot) > 0 do
        local stillStorage, currentOutputDetail = turtle.inspect()
        if not stillStorage or not isStorageBlock(currentOutputDetail) then
          face(0)
          printError("Output chest disappeared. Nothing else was dropped.")
          return false
        end
        local before = turtle.getItemCount(slot)
        local dropped = turtle.drop()
        if not dropped or turtle.getItemCount(slot) >= before then
          face(0)
          printError("Output chest is full. Empty it and restart the quarry.")
          return false
        end
      end
      if not face(0) then return false end
    end
  end

  requiredFuel = requiredFuel or 0
  if requiredFuel > fuelCapacity() then
    printError("This resume needs " .. requiredFuel .. " fuel, above this turtle's capacity.")
    print("Use a smaller quarry plan or start a new quarry.")
    return false
  end
  local attempts = 0
  while fuelLevel() < requiredFuel and attempts < 1024 do
    turtle.select(16)
    if not turtle.suckUp(1) then break end
    if turtle.refuel(0) then
      turtle.refuel(1)
    else
      turtle.dropUp()
      break
    end
    attempts = attempts + 1
  end
  if fuelLevel() < requiredFuel then
    printError("Add more usable fuel to the top fuel chest, then restart the quarry.")
    print("Need " .. requiredFuel .. ", have " .. fuelLevel() .. ".")
    return false
  end
  return true
end

local function returnToBase()
  state.phase = "returning"
  saveState()
  dashboard("Returning to service chests...")
  while state.positionStep > 0 do
    if not moveToRouteStep(state.positionStep - 1) then return false end
  end
  while state.depth > 0 do
    if not moveUp(false) then return false end
  end
  if state.positionStep == 0 then
    if not moveToRouteStep(-1) then return false end
  end
  state.phase = "surface"
  saveState()
  return true
end

local function moveAlongRouteTo(targetStep)
  while state.positionStep ~= targetStep do
    if state.pauseRequested then return false, "pause" end
    local nextStep = state.positionStep < targetStep and state.positionStep + 1 or state.positionStep - 1
    if not moveToRouteStep(nextStep) then return false, "blocked" end
  end
  if state.pauseRequested then return false, "pause" end
  return true
end

local function prepareWorkingPosition()
  if state.pauseRequested then return false, "pause" end
  local targetDepth = state.layer - 1
  -- Walk from the protected service corner to the first work cell. This cell
  -- is the vertical access shaft for deeper layers.
  state.phase = "replaying"
  saveState()
  if state.positionStep < 0 then
    if not moveToRouteStep(0) then return false, "blocked" end
    if state.pauseRequested then return false, "pause" end
  end

  state.phase = "descending"
  saveState()
  while state.depth < targetDepth do
    if state.pauseRequested then return false, "pause" end
    if not moveDown(false) then return false, "blocked" end
  end
  if state.depth ~= targetDepth then
    printError("Turtle depth is deeper than the saved layer.")
    return false
  end

  state.phase = "replaying"
  saveState()
  local reached, reason = moveAlongRouteTo(state.nextCell)
  if not reached then
    if reason == "pause" then return false, "pause" end
    printError("Turtle cannot reach the saved layer progress safely.")
    return false, "blocked"
  end
  if state.pauseRequested then return false, "pause" end
  state.phase = "mining"
  saveState()
  return true
end

local function isBedrock(detail)
  local name = detail and detail.name or ""
  return name == "minecraft:bedrock"
end

local function mineCurrentCell()
  local hasBlock, detail = turtle.inspectDown()
  if not hasBlock then return true end
  if isBedrock(detail) then
    state.bedrockFound = true
    return true
  end
  local dug, reason = turtle.digDown()
  if dug then
    state.stats.blocks = state.stats.blocks + 1
    return true
  end
  printError("Cannot mine below at " .. (detail.name or "unknown block") .. ".")
  print(reason or "Check the turtle tool and claim/protection settings.")
  notify("Mining blocked by " .. (detail.name or "unknown block") .. ".", "error")
  return false
end

local function mineLayer()
  local total = state.width * state.length
  -- A restart may happen after a cell was mined and saved, but just before the
  -- turtle moved to the next cell. That path is already clear, so restore the
  -- expected position instead of treating the job as corrupt.
  if (state.layerProgress or 0) >= total then
    state.layerComplete = true
    state.phase = "layer_complete"
    saveState()
    return true, "complete"
  end
  if state.positionStep ~= state.nextCell then
    state.phase = "replaying"
    saveState()
    local replayed, replayReason = moveAlongRouteTo(state.nextCell)
    if not replayed then return false, replayReason or "blocked" end
    state.phase = "mining"
    saveState()
  end

  while state.layerProgress < total do
    if state.positionStep ~= state.nextCell then
      printError("Layer position and saved progress do not match.")
      return false, "blocked"
    end
    if state.pauseRequested then
      dashboard("Service & pause requested - returning safely...")
      return false, "pause"
    end
    if inventoryFull() then
      dashboard("Inventory full - returning to service chests...")
      notify("Inventory full - returning to the service station.", "warning")
      return false, "service"
    end
    local hasNextMove = state.layerProgress < total - 1
    if fuelLevel() < fuelForSafeReturn(hasNextMove) then
      dashboard("Fuel reserve reached - returning to service chests...")
      notify("Fuel reserve reached - returning to the service station.", "warning")
      return false, "service"
    end

    dashboard("Mining layer " .. state.layer .. "...")
    if not mineCurrentCell() then return false, "blocked" end

    state.layerProgress = state.layerProgress + 1
    recordProgressTiming()
    if state.layerProgress < total then
      state.nextCell = state.nextCell + state.routeDirection
      saveState()
      if not moveToRouteStep(state.nextCell) then return false, "blocked" end
    else
      state.layerComplete = true
      state.phase = "layer_complete"
      saveState()
      return true, "complete"
    end
  end
  state.layerComplete = true
  state.phase = "layer_complete"
  saveState()
  return true, "complete"
end

local function completeQuarry()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      printError("Items remain in the turtle. The quarry state was kept safely.")
      return false
    end
  end
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  paint(colors.lime)
  print("Layer quarry complete. All items were delivered to the service chests.")
  paint(colors.white)
  notify("Layer quarry complete: " .. state.stats.blocks .. " blocks mined", "success")
  local statsHandle = fs.open("/quarryos/quarry-last-stats", "w")
  statsHandle.write(textutils.serialize(state.stats))
  statsHandle.close()
  local history = fs.open("/quarryos/quarry-history", "a")
  history.writeLine(textutils.serialize({
    width = state.width, length = state.length, maximum = state.maximum,
    blocks = state.stats.blocks, started = state.started, finished = os.epoch("utc"), layout = "layers",
  }))
  history.close()
  fs.delete(stateFile)
  if fs.exists(stateBackupFile) then fs.delete(stateBackupFile) end
  return true
end

local function atServiceStation()
  return state.positionStep == -1 and state.depth == 0 and state.x == 0 and state.z == 0
end

local function finalLayerReached()
  return state.bedrockFound or (state.maximum > 0 and state.layer >= state.maximum)
end

local function serviceReasonAtLayerBoundary()
  if state.pauseRequested then return "pause" end
  if state.stopAfterLayerRequested then return "pause" end
  if inventoryFull() then return "service" end
  if fuelLevel() < fuelForSafeReturn(true) then return "service" end
  return nil
end

local function beginNextLayer()
  local startStep = state.nextCell
  if startStep < 0 or startStep >= state.width * state.length then
    printError("The completed layer has no valid starting cell for the next layer.")
    return false
  end

  -- Stay at the end of the previous snake path. The next layer uses the same
  -- path in reverse, so it can descend immediately instead of travelling back
  -- to the service station after every completed layer.
  state.phase = "transitioning"
  saveState()
  state.layer = state.layer + 1
  state.nextCell = startStep
  state.layerProgress = 0
  state.routeDirection = -state.routeDirection
  state.layerComplete = false
  state.bedrockFound = false
  state.phase = "descending"
  saveState()
  return prepareWorkingPosition()
end

local function pauseAtServiceStation()
  -- Mark the pause before touching any chest. A full or missing chest must not
  -- make the turtle leave the service station again after a restart.
  state.phase = "paused"
  state.pauseRequested = nil
  state.pauseRequestId = nil
  state.stopAfterLayerRequested = nil
  if state.timing then state.timing.lastEpoch = nil end
  saveState()
  dashboard("Paused at service station. Unloading and refuelling...")
  local serviced = serviceChest(fuelForResume())
  if serviced then
    dashboard("Paused at service station. Run 'q' to continue.")
  else
    dashboard("Paused at service station. Fix service chests/fuel, then run 'q'.")
  end
  notify("Quarry paused at the service station. Run q on the turtle to continue.", "warning")
  return false
end

local function handleCompletedLayer()
  local reason = serviceReasonAtLayerBoundary()
  if finalLayerReached() then
    -- A manual pause wins over automatic completion, so the user can inspect
    -- the last layer before choosing to resume and finish the job.
    if reason == "pause" then
      if not atServiceStation() and not returnToBase() then return false end
      return pauseAtServiceStation()
    end
    if not atServiceStation() and not returnToBase() then return false end
    if state.pauseRequested or state.stopAfterLayerRequested then return pauseAtServiceStation() end
    dashboard(state.bedrockFound and "Bedrock layer reached - final service..." or "Final service visit...")
    if not serviceChest(0) then return false end
    if state.pauseRequested or state.stopAfterLayerRequested then return pauseAtServiceStation() end
    completeQuarry()
    return false
  end

  if reason then
    if not atServiceStation() and not returnToBase() then return false end
    if reason == "pause" then return pauseAtServiceStation() end
    dashboard("Layer complete - service needed before continuing...")
    if not serviceChest(fuelForResume()) then return false end
    if state.pauseRequested then return pauseAtServiceStation() end
  end

  if state.pauseRequested or state.stopAfterLayerRequested then
    if not atServiceStation() and not returnToBase() then return false end
    return pauseAtServiceStation()
  end
  local started, startReason = beginNextLayer()
  if not started and startReason == "pause" then
    if not atServiceStation() and not returnToBase() then return false end
    return pauseAtServiceStation()
  end
  return started
end

local function decodeControl(message)
  if type(message) == "table" then return message end
  if type(message) ~= "string" then return nil end
  local ok, command = pcall(textutils.unserialize, message)
  return ok and command or nil
end

local function acknowledgeControl(sender, command, status, extra)
  if not sender then return end
  local response = {
    command = command.command .. "_ack", jobId = state.jobId,
    requestId = command.requestId, status = status,
  }
  if extra then
    for key, value in pairs(extra) do response[key] = value end
  end
  rednet.send(sender, textutils.serialize(response), "quarryos-control-ack")
end

-- The listener runs beside the mining loop. It only records a request; the
-- worker accepts it at a saved cell boundary and never interrupts a move/dig.
local function controlListener()
  while true do
    local sender, message = rednet.receive("quarryos-control")
    local command = decodeControl(message)
    if command and command.jobId == state.jobId then
      if command.command == "service_pause" then
        if state.phase == "paused" then
          acknowledgeControl(sender, command, "paused")
        elseif state.pauseRequested then
          -- A monitor may retry the same direct message when its ACK was lost.
          -- The desired state is already saved, so just acknowledge it again.
          acknowledgeControl(sender, command, "accepted")
        else
          state.pauseRequested = true
          state.pauseRequestId = command.requestId
          saveState()
          acknowledgeControl(sender, command, "accepted")
          notify("Service & pause requested from the monitor.", "warning")
        end
      elseif command.command == "stop_after_layer" then
        if state.phase == "paused" then
          acknowledgeControl(sender, command, "paused")
        elseif state.stopAfterLayerRequested then
          acknowledgeControl(sender, command, "accepted")
        else
          state.stopAfterLayerRequested = true
          saveState()
          acknowledgeControl(sender, command, "accepted")
          notify("Stop after the current layer requested from the monitor.", "warning")
        end
      elseif command.command == "fuel_check" then
        local required = fuelRequiredForResume()
        acknowledgeControl(sender, command, "reported", {
          fuel = fuelLevel(), requiredFuel = required,
          fuelShortfall = math.max(0, required - fuelLevel()),
        })
      end
    end
  end
end

local function runQuarry()
  -- Recover safely from a restart in the middle of a return trip or a layer
  -- transition before deciding which work action is next.
  if state.phase == "returning" then
    if not returnToBase() then return end
  elseif state.phase == "transitioning" then
    local started, startReason = beginNextLayer()
    if not started then
      if startReason == "pause" and returnToBase() then pauseAtServiceStation() end
      return
    end
  elseif state.phase ~= "surface" and state.phase ~= "mining" and state.phase ~= "descending"
    and state.phase ~= "replaying" and state.phase ~= "layer_complete" then
    printError("Unknown quarry phase: " .. tostring(state.phase))
    return
  end

  while true do
    if state.phase == "surface" then
      if state.pauseRequested then
        pauseAtServiceStation()
        return
      elseif state.layerComplete then
        if not handleCompletedLayer() then return end
      else
        if not serviceChest(fuelForResume()) then return end
        if state.pauseRequested then
          pauseAtServiceStation()
          return
        end
        local prepared, prepareReason = prepareWorkingPosition()
        if not prepared then
          if prepareReason == "pause" and returnToBase() then pauseAtServiceStation() end
          return
        end
      end
    elseif state.phase == "layer_complete" then
      if not handleCompletedLayer() then return end
    elseif state.phase == "descending" or state.phase == "replaying" then
      local prepared, prepareReason = prepareWorkingPosition()
      if not prepared then
        if prepareReason == "pause" and returnToBase() then pauseAtServiceStation() end
        return
      end
    end

    if state.phase == "mining" then
      local _, result = mineLayer()
      if result == "blocked" then return end
      if result == "pause" or result == "service" then
        if not returnToBase() then return end
        if state.pauseRequested then
          pauseAtServiceStation()
          return
        end
      end
      -- A completed layer is deliberately handled on the next loop pass. It
      -- may descend straight into the reverse route without a service visit.
    end
  end
end

if monitorNetworkReady then
  parallel.waitForAny(runQuarry, controlListener)
else
  runQuarry()
end

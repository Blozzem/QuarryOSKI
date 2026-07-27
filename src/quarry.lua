-- QuarryOS Turtle quarry. Place a chest with fuel directly ABOVE the turtle's
-- starting position. It unloads to and refuels from that chest when needed.
local requestedDepth = tonumber(({ ... })[1])

if not turtle then
  printError("This program must run on a turtle.")
  return
end

local function fuelLevel()
  local value = turtle.getFuelLevel()
  return value == "unlimited" and math.huge or value
end

local function inventoryFull()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then return false end
  end
  return true
end

local function returnToSurface(depth)
  while depth > 0 do
    if not turtle.up() then
      if turtle.detectUp() then turtle.digUp() else sleep(0.2) end
    else
      depth = depth - 1
    end
  end
end

local function descendTo(depth)
  for _ = 1, depth do
    while not turtle.down() do sleep(0.2) end
  end
end

local function serviceAtSurface(depth)
  returnToSurface(depth)
  print("Unloading everything to the chest above the turtle...")
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.getItemCount(slot) > 0 and not turtle.dropUp() then
      printError("The service chest is full. Empty it and run the program again.")
      return false
    end
  end

  -- The same chest may contain both loot and fuel. Non-fuel items are put
  -- back immediately; this walks through the chest until usable fuel is found.
  local targetFuel = (depth + 20) * 2
  local attempts = 0
  while fuelLevel() < targetFuel and attempts < 128 do
    turtle.select(16)
    if not turtle.suckUp(1) then break end
    if turtle.refuel(0) then
      turtle.refuel(1)
    elseif not turtle.dropUp() then
      printError("The service chest is full. Empty it and run the program again.")
      return false
    end
    attempts = attempts + 1
  end
  if fuelLevel() < targetFuel then
    printError("No usable fuel in the service chest. Add coal or another fuel.")
    return false
  end

  print("Refuelled. Returning to depth " .. depth .. "...")
  descendTo(depth)
  return true
end

local depth = 0
print("QuarryOS vertical quarry started.")
print("Place one service chest with fuel above the starting position.")

while not requestedDepth or depth < requestedDepth do
  -- Reserve enough fuel to return to the surface, plus a small digging margin.
  if inventoryFull() or fuelLevel() < (depth + 20) * 2 then
    if not serviceAtSurface(depth) then return end
  end

  if turtle.down() then
    depth = depth + 1
  elseif turtle.detectDown() and turtle.digDown() then
    -- The next iteration moves into the just-mined block.
  else
    print("Stopped at an unbreakable block after " .. depth .. " layers.")
    break
  end
end

returnToSurface(depth)
print("Quarry complete. The turtle is back at the surface.")

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

local function refuel(target)
  while fuelLevel() < target do
    local usedFuel = false
    for slot = 1, 16 do
      turtle.select(slot)
      if turtle.refuel(0) then
        turtle.refuel(1)
        usedFuel = true
        break
      end
    end
    if not usedFuel then return false end
  end
  return true
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
  print("Unloading to chest above the turtle...")
  for slot = 1, 16 do
    turtle.select(slot)
    turtle.dropUp()
  end

  -- The chest should contain only fuel. Pull one stack at a time as needed.
  while not refuel((depth + 20) * 2) do
    if not turtle.suckUp() then
      printError("No fuel in the chest above. Add fuel and run the program again.")
      return false
    end
  end

  print("Refuelled. Returning to depth " .. depth .. "...")
  descendTo(depth)
  return true
end

local depth = 0
print("QuarryOS vertical quarry started.")
print("Place an output chest with fuel above the starting position.")

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

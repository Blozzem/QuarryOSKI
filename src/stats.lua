local arguments = { ... }
local file = "/quarryos/quarry-last-stats"
if not fs.exists(file) then
  print("No completed quarry statistics yet.")
  return
end

local handle = fs.open(file, "r")
local stats = textutils.unserialize(handle.readAll())
handle.close()
if type(stats) ~= "table" then
  printError("The saved statistics are damaged.")
  return
end

local function rowsFrom(counts)
  local rows = {}
  if type(counts) ~= "table" then return rows end
  for name, count in pairs(counts) do
    count = tonumber(count) or 0
    if count > 0 then table.insert(rows, { name = tostring(name), count = count }) end
  end
  table.sort(rows, function(left, right)
    if left.count == right.count then return left.name < right.name end
    return left.count > right.count
  end)
  return rows
end

local function shortName(name)
  return name:gsub("^minecraft:", "")
end

local function printRows(title, rows, limit)
  if #rows == 0 then
    print(title .. ": no detailed data (older quarry).")
    return
  end
  print(title .. ":")
  for index, row in ipairs(rows) do
    if limit and index > limit then
      print("  +" .. (#rows - limit) .. " more (run 'stats all')")
      break
    end
    print("  " .. shortName(row.name) .. " x" .. row.count)
  end
end

local showAll = arguments[1] == "all"
local ores = rowsFrom(stats.oreTypes)
local blocks = rowsFrom(stats.blockTypes)

print("QuarryOS statistics")
print("Blocks mined: " .. (stats.blocks or 0))
print("Surface moves: " .. (stats.surfaceMoves or 0))
print("Vertical moves: " .. (stats.verticalMoves or 0))
print("Service visits: " .. (stats.services or 0))
print("Lava fields found: " .. (stats.fluids or 0))
print("Lava walls sealed: " .. (stats.seals or 0))
printRows("Ore blocks mined", ores)
printRows(showAll and "All mined block types" or "Top mined block types", blocks, showAll and nil or 10)

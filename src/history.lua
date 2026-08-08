local file = "/quarryos/quarry-history"
if not fs.exists(file) then print("No completed quarry history yet.") return end

local function topOreSummary(oreTypes)
  if type(oreTypes) ~= "table" then return "" end
  local rows = {}
  for name, count in pairs(oreTypes) do
    count = tonumber(count) or 0
    if count > 0 then table.insert(rows, { name = tostring(name), count = count }) end
  end
  table.sort(rows, function(left, right)
    if left.count == right.count then return left.name < right.name end
    return left.count > right.count
  end)
  if #rows == 0 then return "" end
  local parts = {}
  for index, row in ipairs(rows) do
    if index > 3 then break end
    table.insert(parts, row.name:gsub("^minecraft:", "") .. " " .. row.count)
  end
  if #rows > 3 then table.insert(parts, "+" .. (#rows - 3)) end
  return " - ores: " .. table.concat(parts, ", ")
end

print("QuarryOS history")
local handle = fs.open(file, "r")
local index = 0
while true do
  local line = handle.readLine()
  if not line then break end
  local entry = textutils.unserialize(line)
  if entry then
    index = index + 1
    local depth = entry.maximum == 0 and "bedrock" or entry.maximum
    print(index .. ") " .. entry.width .. "x" .. entry.length .. "x" .. depth .. " - "
      .. entry.blocks .. " blocks" .. topOreSummary(entry.oreTypes))
  end
end
handle.close()

local file = "/quarryos/quarry-history"
if not fs.exists(file) then print("No completed quarry history yet.") return end
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
    print(index .. ") " .. entry.width .. "x" .. entry.length .. "x" .. depth .. " - " .. entry.blocks .. " blocks")
  end
end
handle.close()

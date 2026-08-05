local file = "/quarryos/quarry-last-stats"
if not fs.exists(file) then
  print("No completed quarry statistics yet.")
  return
end
local handle = fs.open(file, "r")
local stats = textutils.unserialize(handle.readAll())
handle.close()
print("QuarryOS statistics")
print("Blocks mined: " .. (stats.blocks or 0))
print("Surface moves: " .. (stats.surfaceMoves or 0))
print("Vertical moves: " .. (stats.verticalMoves or 0))
print("Service visits: " .. (stats.services or 0))
print("Lava fields found: " .. (stats.fluids or 0))
print("Lava walls sealed: " .. (stats.seals or 0))

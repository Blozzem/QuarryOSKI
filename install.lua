-- QuarryOS remote installer for CC:Tweaked.
local owner = "Blozzem"
local repository = "QuarryOSKI"
local branch = "main"
local root = "/quarryos"

local files = {
  ["src/quarryos/kernel.lua"] = root .. "/kernel.lua",
  ["src/quarryos/lib/ui.lua"] = root .. "/ui.lua",
  ["src/quarry.lua"] = root .. "/quarry.lua",
  ["src/update.lua"] = root .. "/update.lua",
  ["src/stats.lua"] = root .. "/stats.lua",
  ["src/monitor_server.lua"] = root .. "/monitor_server.lua",
  ["src/history.lua"] = root .. "/history.lua",
  ["src/selftest.lua"] = root .. "/selftest.lua",
}

if not http.checkURL("https://raw.githubusercontent.com") then
  printError("HTTP access is disabled. Enable http in the CC:Tweaked config first.")
  return
end

if fs.exists("/startup") and not fs.exists("/startup.quarryos-backup") then
  fs.copy("/startup", "/startup.quarryos-backup")
  print("Backed up existing startup to /startup.quarryos-backup")
end

local function writeStartup(program)
  local startup = fs.open("/startup", "w")
  startup.write(program .. "\n")
  startup.close()
end

local function askCoordinate(label)
  while true do
    write(label .. ": ")
    local value = tonumber(read())
    if value then return value end
    printError("Please enter a number.")
  end
end

for source, destination in pairs(files) do
  local directory = fs.getDir(destination)
  if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end

  local url = ("https://raw.githubusercontent.com/%s/%s/%s/%s")
    :format(owner, repository, branch, source)
  write("Downloading " .. source .. "... ")
  local response, message = http.get(url)
  if not response then
    printError("failed")
    printError(message or "Could not download QuarryOS from GitHub.")
    return
  end
  local content = response.readAll()
  response.close()
  if fs.exists(destination) then fs.delete(destination) end
  local output = fs.open(destination, "w")
  output.write(content)
  output.close()
  print("done")
end

if turtle then
  writeStartup('shell.run("/quarryos/kernel.lua")')
  print("QuarryOS Turtle installed. Reboot to start QuarryOS.")
elseif peripheral.find("monitor") then
  writeStartup('shell.run("/quarryos/monitor_server.lua")')
  print("Monitor server installed. Reboot to start the live display.")
else
  print("GPS host setup")
  print("Enter this computer block's coordinates (F3).")
  local x, y, z = gps.locate(2)
  if x then
    print("GPS found this position: " .. x .. ", " .. y .. ", " .. z)
    write("Use it? [Y/n] ")
    local answer = read():lower()
    if answer == "n" then x, y, z = nil, nil, nil end
  end
  x = x or askCoordinate("X")
  y = y or askCoordinate("Y")
  z = z or askCoordinate("Z")
  writeStartup('shell.run("gps", "host", ' .. x .. ", " .. y .. ", " .. z .. ")")
  print("GPS host installed. Reboot to start hosting.")
end

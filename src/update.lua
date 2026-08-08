-- Downloads and executes the current installer without relying on wget run.
-- The installer stages changed files and keeps a recovery journal. The normal
-- Turtle/Monitor startup repairs an interrupted update before QuarryOS starts.
local arguments = { ... }
local mode = arguments[1] or "update"
if mode ~= "update" and mode ~= "check" then
  print("Usage: update [check]")
  return
end

local url = "https://raw.githubusercontent.com/Blozzem/QuarryOSKI/main/install.lua"
local temporaryFile = "/quarryos/.installer-update.lua"

local allowed, checkMessage = http.checkURL(url)
if not allowed then
  printError("HTTP access is disabled. Enable http in the CC:Tweaked config first.")
  if checkMessage then printError(checkMessage) end
  return
end

print(mode == "check" and "Checking QuarryOS files..." or "Checking for a QuarryOS update...")
local response, message = http.get(url)
if not response then
  printError(message or "Could not contact GitHub. Check that HTTP is enabled.")
  return
end

local content = response.readAll()
response.close()
local output = fs.open(temporaryFile, "w")
if not output then
  printError("Could not create the temporary updater file.")
  return
end
output.write(content)
output.close()

local ok, errorMessage = shell.run(temporaryFile, mode)
if fs.exists(temporaryFile) then fs.delete(temporaryFile) end

-- The installer prints the authoritative result itself. A Lua program which
-- reports an expected HTTP or recovery error can still make shell.run return
-- true, so do not add a misleading generic success message here.
if not ok then
  printError(errorMessage or "Update failed.")
end

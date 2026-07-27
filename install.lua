-- QuarryOS remote installer for CC:Tweaked.
local owner = "Blozzem"
local repository = "QuarryOSKI"
local branch = "main"
local root = "/quarryos"

local files = {
  ["startup.lua"] = "/startup",
  ["kernel.lua"] = root .. "/kernel.lua",
  ["ui.lua"] = root .. "/ui.lua",
  ["quarry.lua"] = root .. "/quarry.lua",
}

if not http.checkURL("https://raw.githubusercontent.com") then
  printError("HTTP access is disabled. Enable http in the CC:Tweaked config first.")
  return
end

if fs.exists("/startup") and not fs.exists("/startup.quarryos-backup") then
  fs.copy("/startup", "/startup.quarryos-backup")
  print("Backed up existing startup to /startup.quarryos-backup")
end

for source, destination in pairs(files) do
  local directory = fs.getDir(destination)
  if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end

  local url = ("https://raw.githubusercontent.com/%s/%s/%s/%s")
    :format(owner, repository, branch, source)
  write("Downloading " .. source .. "... ")
  local ok, message = shell.run("wget", "-f", url, destination)
  if not ok then
    printError("failed")
    printError(message or "Could not download QuarryOS.")
    return
  end
  print("done")
end

print("QuarryOS installed. Reboot or run 'startup' to begin.")

-- Downloads and executes the current installer without relying on wget run.
local url = "https://raw.githubusercontent.com/Blozzem/QuarryOSKI/main/install.lua"
local temporaryFile = "/quarryos/.installer-update.lua"

print("Checking for a QuarryOS update...")
local response, message = http.get(url)
if not response then
  printError(message or "Could not contact GitHub. Check that HTTP is enabled.")
  return
end

local content = response.readAll()
response.close()
local output = fs.open(temporaryFile, "w")
output.write(content)
output.close()

local ok, errorMessage = shell.run(temporaryFile)
if fs.exists(temporaryFile) then fs.delete(temporaryFile) end

if ok then
  print("Update complete. Reboot to load the new QuarryOS version.")
else
  printError(errorMessage or "Update failed.")
end

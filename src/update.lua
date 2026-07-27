-- Updates QuarryOS in place. Existing files outside /quarryos are preserved.
local url = "https://raw.githubusercontent.com/Blozzem/QuarryOSKI/main/install.lua"

print("Updating QuarryOS...")
local ok, message = shell.run("wget", "run", url)
if ok then
  print("Update complete. Restart QuarryOS to use the new version.")
else
  printError(message or "Update failed. Check that HTTP is enabled.")
end

-- QuarryOS boot entry point.
if not fs.exists("/quarryos/kernel.lua") then
  printError("QuarryOS is incomplete. Run the installer again.")
  return
end

shell.run("/quarryos/kernel.lua")

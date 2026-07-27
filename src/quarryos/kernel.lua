local ui = dofile("/quarryos/ui.lua")

local VERSION = "0.1.0"
local running = true

local builtins = {}

local function words(line)
  local result = {}
  for word in line:gmatch("%S+") do table.insert(result, word) end
  return result
end

local function printHelp()
  print("Built-in commands:")
  print("  help                 Show this message")
  print("  about                Show QuarryOS details")
  print("  status               Show computer and turtle status")
  print("  clear                Clear the display")
  print("  cd <directory>       Change current directory")
  print("  ls [directory]       List files")
  print("  edit <file>          Open the native editor")
  print("  run <program> [...]  Run a program")
  print("  update               Download the latest QuarryOS version")
  print("  stats                Show the last completed quarry statistics")
  print("  history              Show completed quarry jobs")
  print("  selftest             Check GPS, chests, fuel and modem")
  print("  reboot | shutdown    Power controls")
  print("\nOther commands are passed to the normal ComputerCraft shell.")
end

builtins.help = function() printHelp() end

builtins.about = function()
  print("QuarryOS " .. VERSION)
  print("A ComputerCraft shell for NeoForge worlds.")
  print("Type 'help' to see available commands.")
end

builtins.status = function()
  print("Computer ID: " .. os.getComputerID())
  print("Label: " .. (os.getComputerLabel() or "(unnamed)"))
  print("Directory: " .. shell.dir())
  if turtle then
    print("Turtle fuel: " .. turtle.getFuelLevel() .. " / " .. turtle.getFuelLimit())
  end
end

builtins.clear = function()
  term.clear()
  term.setCursorPos(1, 1)
end

builtins.cd = function(arguments)
  local target = arguments[2]
  if not target then
    print("Usage: cd <directory>")
    return
  end
  local resolved = shell.resolve(target)
  if not fs.isDir(resolved) then
    printError("Not a directory: " .. target)
    return
  end
  shell.setDir(resolved)
end

builtins.ls = function(arguments)
  local target = shell.resolve(arguments[2] or ".")
  if not fs.exists(target) then
    printError("No such file or directory: " .. target)
    return
  end
  if not fs.isDir(target) then
    print(fs.getName(target))
    return
  end
  for _, entry in ipairs(fs.list(target)) do
    local fullPath = fs.combine(target, entry)
    if fs.isDir(fullPath) then
      ui.colour(colors.lightBlue)
      print(entry .. "/")
      ui.reset()
    else
      print(entry)
    end
  end
end

builtins.edit = function(arguments)
  if not arguments[2] then
    print("Usage: edit <file>")
    return
  end
  shell.run("edit", shell.resolve(arguments[2]))
end

builtins.run = function(arguments)
  if not arguments[2] then
    print("Usage: run <program> [arguments]")
    return
  end
  table.remove(arguments, 1)
  shell.run(table.unpack(arguments))
end

builtins.update = function()
  shell.run("/quarryos/update.lua")
end

builtins.stats = function()
  shell.run("/quarryos/stats.lua")
end

builtins.history = function()
  shell.run("/quarryos/history.lua")
end

builtins.selftest = function()
  shell.run("/quarryos/selftest.lua")
end

builtins.reboot = function() os.reboot() end
builtins.shutdown = function() os.shutdown() end

ui.banner("QuarryOS " .. VERSION, "ComputerCraft edition")
print("Type 'help' for commands. Native ComputerCraft commands still work.")

while running do
  ui.prompt(shell.dir())
  local line = read()
  local arguments = words(line)
  local command = arguments[1]

  if command and command ~= "" then
    local builtin = builtins[command]
    if builtin then
      builtin(arguments)
    else
      local ok = shell.run(table.unpack(arguments))
      if not ok then printError("Command failed: " .. command) end
    end
  end
end

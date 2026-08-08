-- QuarryOS remote installer and recoverable in-game updater for CC:Tweaked.
local arguments = { ... }
local mode = arguments[1] or "install"
local owner = "Blozzem"
local repository = "QuarryOSKI"
local branch = "main"
local root = "/quarryos"
local VERSION
local versionFile = root .. "/.version"
local stagingRoot = root .. "/.update-staging"
local journalFile = stagingRoot .. "/journal"
local journalPendingFile = stagingRoot .. "/journal.pending"
local applyingFile = stagingRoot .. "/applying"
local commitFile = stagingRoot .. "/commit"
local rolledBackFile = stagingRoot .. "/rolledback"

if mode ~= "install" and mode ~= "update" and mode ~= "check" then
  print("Usage: install.lua [install|update|check]")
  return
end

local files = {
  { source = "src/quarryos/kernel.lua", destination = root .. "/kernel.lua" },
  { source = "src/quarryos/lib/ui.lua", destination = root .. "/ui.lua" },
  { source = "src/quarry.lua", destination = root .. "/quarry.lua" },
  { source = "src/update.lua", destination = root .. "/update.lua" },
  { source = "src/stats.lua", destination = root .. "/stats.lua" },
  { source = "src/monitor_server.lua", destination = root .. "/monitor_server.lua" },
  { source = "src/history.lua", destination = root .. "/history.lua" },
  { source = "src/selftest.lua", destination = root .. "/selftest.lua" },
  { source = "src/web_gateway.lua", destination = root .. "/web_gateway.lua" },
}
local allowedDestinations = { [versionFile] = true }
for _, file in ipairs(files) do allowedDestinations[file.destination] = true end

local function readFile(path)
  if not fs.exists(path) then return nil end
  local handle = fs.open(path, "r")
  if not handle then return nil end
  local content = handle.readAll()
  handle.close()
  return content
end

local function writeFile(path, content)
  local handle = fs.open(path, "w")
  if not handle then return false, "Could not open " .. path end
  handle.write(content)
  handle.close()
  return true
end

local function trim(value)
  return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function fetch(source)
  local url = "https://raw.githubusercontent.com/" .. owner .. "/" .. repository
    .. "/" .. branch .. "/" .. source
  local response, message = http.get(url)
  if not response then return nil, message or ("Could not download " .. url) end
  local content = response.readAll()
  response.close()
  return content
end

local bootMarker = "-- QuarryOS stable recovery boot loader (API v1)."
local legacyTurtleStartup = 'shell.run("/quarryos/kernel.lua")'
local legacyMonitorStartup = 'shell.run("/quarryos/monitor_server.lua")'

local function replaceFile(path, temporaryFile, content)
  if fs.exists(temporaryFile) then fs.delete(temporaryFile) end
  local wrote, written, writeMessage = pcall(writeFile, temporaryFile, content)
  if not wrote then return false, tostring(written) end
  if not written then return false, tostring(writeMessage) end
  if readFile(temporaryFile) ~= content then
    if fs.exists(temporaryFile) then fs.delete(temporaryFile) end
    return false, "Could not verify " .. temporaryFile
  end
  local moved, moveMessage = pcall(function()
    if fs.exists(path) then fs.delete(path) end
    fs.move(temporaryFile, path)
  end)
  if not moved or not fs.exists(path) then
    return false, tostring(moveMessage)
  end
  return true
end

local function writeStartup(program)
  if fs.exists("/startup") and fs.isDir("/startup") then
    return false, "/startup is a directory"
  end
  return replaceFile("/startup", "/startup.quarryos-new", program .. "\n")
end

local function installStableBootLoader()
  if fs.exists("/startup") and fs.isDir("/startup") then
    return false, "/startup is a directory"
  end
  local content, message = fetch("src/startup.lua")
  if not content then return false, message end
  if not content:find(bootMarker, 1, true) then
    return false, "Downloaded boot loader has an unexpected format"
  end
  return replaceFile("/startup", "/startup.quarryos-new", content)
end

local function prepareStartupRecovery()
  if not turtle and not peripheral.find("monitor") then return true end
  if fs.exists("/startup") and fs.isDir("/startup") then
    print("Existing /startup directory was left unchanged; update recovery is available through 'update'.")
    return true
  end
  local current = readFile("/startup")
  if current and current:find(bootMarker, 1, true) then return true end
  local trimmed = trim(current)
  if current and trimmed ~= legacyTurtleStartup and trimmed ~= legacyMonitorStartup then
    print("Custom /startup was left unchanged; update recovery is available through 'update'.")
    return true
  end
  if current and not fs.exists("/startup.quarryos-backup") then
    local copied, copyMessage = pcall(fs.copy, "/startup", "/startup.quarryos-backup")
    if not copied then return false, tostring(copyMessage) end
  end
  local installed, message = installStableBootLoader()
  if installed then print("Installed QuarryOS startup recovery.") end
  return installed, message
end

local function clearStaging()
  if fs.exists(stagingRoot) then fs.delete(stagingRoot) end
end

local function clearFinishedStaging(markerFile)
  if not fs.exists(stagingRoot) then return true end
  local markerName = fs.getName(markerFile)
  -- Leave the final marker until every other staging file is gone. A reboot
  -- during cleanup can then never mistake a completed apply or rollback for
  -- an unfinished transaction.
  for _, name in ipairs(fs.list(stagingRoot)) do
    if name ~= markerName then
      local deleted, deleteMessage = pcall(fs.delete, stagingRoot .. "/" .. name)
      if not deleted then return false, tostring(deleteMessage) end
    end
  end
  if fs.exists(markerFile) then
    local deleted, deleteMessage = pcall(fs.delete, markerFile)
    if not deleted then return false, tostring(deleteMessage) end
  end
  if fs.exists(stagingRoot) then
    local deleted, deleteMessage = pcall(fs.delete, stagingRoot)
    if not deleted then return false, tostring(deleteMessage) end
  end
  return true
end

local function restoreEntry(entry)
  -- Keep backups in place while recovering. That makes a second recovery safe
  -- if the computer loses power halfway through the first one.
  if entry.hadOriginal and not fs.exists(entry.backup) then
    return false, "backup is missing"
  end
  local restored, restoreMessage = pcall(function()
    if fs.exists(entry.destination) then fs.delete(entry.destination) end
    if entry.hadOriginal then fs.copy(entry.backup, entry.destination) end
  end)
  if not restored then return false, tostring(restoreMessage) end
  if entry.hadOriginal and not fs.exists(entry.destination) then
    return false, "backup copy did not create the destination"
  end
  return true
end

local function rollback(entries)
  for index = #entries, 1, -1 do
    local restored, restoreMessage = restoreEntry(entries[index])
    if not restored then return false, entries[index].source .. ": " .. tostring(restoreMessage) end
  end
  return true
end

local function validateJournal(journal)
  if type(journal) ~= "table" or journal.schema ~= 1 or type(journal.entries) ~= "table" then
    return false, "unsupported journal format"
  end
  local backupPrefix = stagingRoot .. "/"
  local seen = {}
  local entryCount = 0
  for index in pairs(journal.entries) do
    if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
      return false, "journal has an invalid entry index"
    end
    entryCount = entryCount + 1
  end
  for index = 1, entryCount do
    local entry = journal.entries[index]
    if type(entry) ~= "table" or not allowedDestinations[entry.destination] then
      return false, "journal contains an unsafe destination"
    end
    if seen[entry.destination] then return false, "journal contains a duplicate destination" end
    seen[entry.destination] = true
    if type(entry.backup) ~= "string" or entry.backup:sub(1, #backupPrefix) ~= backupPrefix
      or entry.backup:sub(#backupPrefix + 1):find("/", 1, true) then
      return false, "journal contains an unsafe backup path"
    end
    if entry.hadOriginal ~= true and entry.hadOriginal ~= false then
      return false, "journal has an invalid backup flag"
    end
    if entry.hadOriginal and not fs.exists(entry.backup) then
      return false, "a required backup is missing"
    end
  end
  return true
end

local function recoverInterruptedUpdate()
  if not fs.exists(stagingRoot) then return true end

  -- A commit marker is written only after every replacement succeeded. Keep
  -- the new files and merely clean up remnants from an interrupted cleanup.
  if fs.exists(commitFile) then
    print("Finishing cleanup from a completed QuarryOS update...")
    local cleaned, cleanupMessage = clearFinishedStaging(commitFile)
    if cleaned then return true end
    printError("Could not clean completed update files: " .. tostring(cleanupMessage))
    return false
  end

  if fs.exists(rolledBackFile) then
    print("Finishing cleanup from a recovered QuarryOS update...")
    local cleaned, cleanupMessage = clearFinishedStaging(rolledBackFile)
    if cleaned then return true end
    printError("Could not clean recovered update files: " .. tostring(cleanupMessage))
    return false
  end

  -- Before this marker is written the installer has not touched a live file.
  -- This deliberately discards an incomplete journal write after a power loss.
  if not fs.exists(applyingFile) then
    clearStaging()
    return true
  end

  local journalContent = readFile(journalFile)
  if not journalContent then
    printError("An update was interrupted after it began, but its recovery journal is missing.")
    printError("Keep " .. stagingRoot .. " and run the installer again after making a backup.")
    return false
  end

  local decoded, journal = pcall(textutils.unserialize, journalContent)
  local valid, reason = validateJournal(decoded and journal or nil)
  if not valid then
    printError("An interrupted update journal is damaged: " .. tostring(reason) .. ". Keep " .. stagingRoot
      .. " and run the installer again after making a backup.")
    return false
  end

  print("Recovering files from an interrupted QuarryOS update...")
  local restored, restoreMessage = rollback(journal.entries)
  if not restored then
    printError("Could not restore the previous QuarryOS files: " .. tostring(restoreMessage))
    printError("Keep " .. stagingRoot .. " and run the installer again after making a backup.")
    return false
  end
  local marked, markerMessage = writeFile(rolledBackFile, "restored\n")
  if not marked then
    printError("Files were restored, but the rollback marker could not be written: " .. tostring(markerMessage))
    return false
  end
  local cleaned, cleanupMessage = clearFinishedStaging(rolledBackFile)
  if not cleaned then
    printError("Files were restored, but temporary update files need cleanup: " .. tostring(cleanupMessage))
    return false
  end
  print("Previous QuarryOS files restored safely.")
  return true
end

local allowed, checkMessage = http.checkURL("https://raw.githubusercontent.com")
if not allowed then
  printError("HTTP access is disabled. Enable http in the CC:Tweaked config first.")
  if checkMessage then printError(checkMessage) end
  return
end

if not fs.exists(root) then fs.makeDir(root) end
if not recoverInterruptedUpdate() then return end
if mode == "update" then
  local ready, startupMessage = prepareStartupRecovery()
  if not ready then
    printError("Could not prepare startup update recovery: " .. tostring(startupMessage))
    printError("No QuarryOS files were changed.")
    return
  end
end
local remoteVersion, versionMessage = fetch("VERSION")
VERSION = trim(remoteVersion)
if not remoteVersion or VERSION == "" then
  printError("Could not read the QuarryOS release version: " .. tostring(versionMessage))
  printError("No QuarryOS files were changed.")
  return
end
local installedVersion = trim(readFile(versionFile))
if installedVersion == "" then installedVersion = "unknown (older installation)" end

print("QuarryOS " .. mode .. " check")
print("Installed: " .. installedVersion)
print("Available: " .. VERSION)

if mode ~= "check" then
  clearStaging()
  fs.makeDir(stagingRoot)
end

local checked, unchanged = 0, 0
local changes = {}
for index, file in ipairs(files) do
  write("Checking " .. file.source .. "... ")
  local remoteContent, message = fetch(file.source)
  if not remoteContent then
    print("failed")
    printError(message)
    clearStaging()
    printError("No QuarryOS files were changed.")
    return
  end

  checked = checked + 1
  if readFile(file.destination) == remoteContent then
    unchanged = unchanged + 1
    print("current")
  else
    print("changed")
    local entry = {
      source = file.source, destination = file.destination, index = index,
      stage = stagingRoot .. "/" .. tostring(index) .. ".new",
      backup = stagingRoot .. "/" .. tostring(index) .. ".bak",
    }
    if mode ~= "check" then
      local written, writeMessage = writeFile(entry.stage, remoteContent)
      if not written then
        clearStaging()
        printError(writeMessage)
        printError("No QuarryOS files were changed.")
        return
      end
    end
    table.insert(changes, entry)
  end
end

local versionChanged = installedVersion ~= VERSION
if versionChanged then
  local entry = {
    source = "version metadata", destination = versionFile, index = #files + 1,
    stage = stagingRoot .. "/version.new", backup = stagingRoot .. "/version.bak",
  }
  if mode ~= "check" then
    local written, writeMessage = writeFile(entry.stage, VERSION .. "\n")
    if not written then
      clearStaging()
      printError(writeMessage)
      printError("No QuarryOS files were changed.")
      return
    end
  end
  table.insert(changes, entry)
end

local sourceChanges = #changes - (versionChanged and 1 or 0)
if mode == "check" then
  print("Checked: " .. checked .. " | Changed: " .. sourceChanges .. " | Unchanged: " .. unchanged)
  if versionChanged then print("Version metadata will update to " .. VERSION .. ".") end
  if sourceChanges == 0 and not versionChanged then print("QuarryOS is already up to date.") end
  return
end

-- Make a backup of every target before the transaction journal is written.
-- Until the journal exists no installed QuarryOS file is changed, so failures
-- in this phase can always discard the staging directory safely.
for _, entry in ipairs(changes) do
  entry.hadOriginal = fs.exists(entry.destination)
  if entry.hadOriginal then
    local copied, copyMessage = pcall(fs.copy, entry.destination, entry.backup)
    if not copied or not fs.exists(entry.backup) then
      clearStaging()
      printError("Could not back up " .. entry.source .. ": " .. tostring(copyMessage))
      printError("Update was rolled back.")
      return
    end
  end
end

local serializedJournal = textutils.serialize({ schema = 1, entries = changes })
local journalWritten, journalMessage = writeFile(journalPendingFile, serializedJournal)
if not journalWritten then
  clearStaging()
  printError("Could not stage the update recovery journal: " .. tostring(journalMessage))
  printError("No QuarryOS files were changed.")
  return
end

local decodedPending, pendingJournal = pcall(textutils.unserialize, readFile(journalPendingFile) or "")
local pendingValid = decodedPending and validateJournal(pendingJournal)
if not pendingValid then
  clearStaging()
  printError("Could not verify the update recovery journal.")
  printError("No QuarryOS files were changed.")
  return
end

local movedJournal, moveJournalMessage = pcall(fs.move, journalPendingFile, journalFile)
if not movedJournal or not fs.exists(journalFile) then
  clearStaging()
  printError("Could not prepare the update recovery journal: " .. tostring(moveJournalMessage))
  printError("No QuarryOS files were changed.")
  return
end

local applyingWritten, applyingMessage = writeFile(applyingFile, "apply\n")
if not applyingWritten then
  clearStaging()
  printError("Could not start the safe update transaction: " .. tostring(applyingMessage))
  printError("No QuarryOS files were changed.")
  return
end

for _, entry in ipairs(changes) do

  local moved, moveMessage = pcall(function()
    if fs.exists(entry.destination) then fs.delete(entry.destination) end
    fs.move(entry.stage, entry.destination)
  end)
  if not moved or not fs.exists(entry.destination) then
    local restored, restoreMessage = rollback(changes)
    local marked, markerMessage
    if restored then marked, markerMessage = writeFile(rolledBackFile, "restored\n") end
    local cleaned, cleanupMessage
    if marked then cleaned, cleanupMessage = clearFinishedStaging(rolledBackFile) end
    printError("Could not replace " .. entry.source .. ": " .. tostring(moveMessage))
    if restored and marked and cleaned then
      printError("Update was rolled back.")
    elseif restored then
      printError("Files were restored, but cleanup needs recovery on the next update: "
        .. tostring(markerMessage or cleanupMessage))
    else
      printError("Rollback needs recovery on the next update: " .. tostring(restoreMessage))
    end
    return
  end
end

-- Keep this marker until cleanup is complete. If a reboot happens during the
-- cleanup, the next update knows that the new complete set must be kept.
local committed, commitMessage = writeFile(commitFile, "complete\n")
if not committed then
  printError("All files were replaced, but the commit marker could not be written: " .. tostring(commitMessage))
  printError("Run 'update' again before using QuarryOS.")
  return
end
local cleaned, cleanupMessage = clearFinishedStaging(commitFile)
if not cleaned then
  printError("QuarryOS was updated, but temporary files need cleanup: " .. tostring(cleanupMessage))
  printError("Run 'update' again before using QuarryOS.")
  return
end

print("Checked: " .. checked .. " | Updated: " .. sourceChanges .. " | Unchanged: " .. unchanged)
if sourceChanges == 0 and not versionChanged then print("QuarryOS is already up to date.") end

local function askCoordinate(label)
  while true do
    write(label .. ": ")
    local value = tonumber(read())
    if value then return value end
    printError("Please enter a number.")
  end
end

if mode == "update" then
  if sourceChanges > 0 or versionChanged then
    print("Update complete. Reboot to load the new QuarryOS version.")
  end
  return
end

if fs.exists("/startup") and not fs.isDir("/startup") and not fs.exists("/startup.quarryos-backup") then
  fs.copy("/startup", "/startup.quarryos-backup")
  print("Backed up existing startup to /startup.quarryos-backup")
end

if turtle then
  local installed, startupMessage = installStableBootLoader()
  if not installed then
    printError("Could not create /startup: " .. tostring(startupMessage))
    return
  end
  print("QuarryOS Turtle installed. Reboot to start QuarryOS.")
elseif peripheral.find("monitor") then
  local installed, startupMessage = installStableBootLoader()
  if not installed then
    printError("Could not create /startup: " .. tostring(startupMessage))
    return
  end
  print("Monitor server installed. Reboot to start the live display.")
else
  print("No Turtle or Monitor detected.")
  print("A GPS host is optional and only needed for safe quarry resumes.")
  write("Set up this computer as a GPS host? [y/N] ")
  local answer = read():lower()
  if answer ~= "y" and answer ~= "yes" and answer ~= "j" and answer ~= "ja" then
    print("No GPS host installed.")
    return
  end
  print("GPS host setup")
  print("Enter this computer block's coordinates (F3).")
  local x, y, z = gps.locate(2)
  if x then
    print("GPS found this position: " .. x .. ", " .. y .. ", " .. z)
    write("Use it? [Y/n] ")
    local useAnswer = read():lower()
    if useAnswer == "n" then x, y, z = nil, nil, nil end
  end
  x = x or askCoordinate("X")
  y = y or askCoordinate("Y")
  z = z or askCoordinate("Z")
  local created, startupMessage = writeStartup('shell.run("gps", "host", ' .. x .. ", " .. y .. ", " .. z .. ")")
  if not created then
    printError("Could not create /startup: " .. tostring(startupMessage))
    return
  end
  print("GPS host installed. Reboot to start hosting.")
end

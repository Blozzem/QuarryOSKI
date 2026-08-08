-- QuarryOS stable recovery boot loader (API v1).
-- The installer creates this once and normal updates deliberately leave it in
-- place, so it can repair a program update before starting the main shell.
local root = "/quarryos"
local stagingRoot = root .. "/.update-staging"
local journalFile = stagingRoot .. "/journal"
local applyingFile = stagingRoot .. "/applying"
local commitFile = stagingRoot .. "/commit"
local rolledBackFile = stagingRoot .. "/rolledback"
local allowedDestinations = {
  [root .. "/kernel.lua"] = true,
  [root .. "/ui.lua"] = true,
  [root .. "/quarry.lua"] = true,
  [root .. "/update.lua"] = true,
  [root .. "/stats.lua"] = true,
  [root .. "/monitor_server.lua"] = true,
  [root .. "/history.lua"] = true,
  [root .. "/selftest.lua"] = true,
  [root .. "/web_gateway.lua"] = true,
  [root .. "/.version"] = true,
}

local function readFile(path)
  if not fs.exists(path) then return nil end
  local file = fs.open(path, "r")
  if not file then return nil end
  local content = file.readAll()
  file.close()
  return content
end

local function writeFile(path, content)
  local file = fs.open(path, "w")
  if not file then return false, "Could not open " .. path end
  file.write(content)
  file.close()
  return true
end

local function clearFinishedStaging(markerFile)
  if not fs.exists(stagingRoot) then return true end
  local markerName = fs.getName(markerFile)
  for _, name in ipairs(fs.list(stagingRoot)) do
    if name ~= markerName then
      local deleted, message = pcall(fs.delete, stagingRoot .. "/" .. name)
      if not deleted then return false, tostring(message) end
    end
  end
  if fs.exists(markerFile) then
    local deleted, message = pcall(fs.delete, markerFile)
    if not deleted then return false, tostring(message) end
  end
  if fs.exists(stagingRoot) then
    local deleted, message = pcall(fs.delete, stagingRoot)
    if not deleted then return false, tostring(message) end
  end
  return true
end

local function restoreEntry(entry)
  if entry.hadOriginal and not fs.exists(entry.backup) then
    return false, "backup is missing"
  end
  local restored, message = pcall(function()
    if fs.exists(entry.destination) then fs.delete(entry.destination) end
    if entry.hadOriginal then fs.copy(entry.backup, entry.destination) end
  end)
  if not restored then return false, tostring(message) end
  if entry.hadOriginal and not fs.exists(entry.destination) then
    return false, "backup copy did not create the destination"
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

local function recoverUpdate()
  if not fs.exists(stagingRoot) then return true end
  if fs.exists(commitFile) then
    local cleaned, message = clearFinishedStaging(commitFile)
    if not cleaned then printError("Could not clean completed update: " .. tostring(message)) end
    return true
  end
  if fs.exists(rolledBackFile) then
    local cleaned, message = clearFinishedStaging(rolledBackFile)
    if not cleaned then printError("Could not clean recovered update: " .. tostring(message)) end
    return true
  end
  -- Before this marker exists, no installed program file was replaced.
  if not fs.exists(applyingFile) then
    fs.delete(stagingRoot)
    return true
  end

  local content = readFile(journalFile)
  local decoded, journal = pcall(textutils.unserialize, content or "")
  local valid, reason = validateJournal(decoded and journal or nil)
  if not valid then
    printError("QuarryOS update recovery data is damaged: " .. tostring(reason))
    printError("Run the installer again.")
    return false
  end

  print("Recovering QuarryOS after an interrupted update...")
  for index = #journal.entries, 1, -1 do
    local restored, message = restoreEntry(journal.entries[index])
    if not restored then
      printError("Could not restore " .. tostring(journal.entries[index].source) .. ": " .. tostring(message))
      return false
    end
  end
  local marked, message = writeFile(rolledBackFile, "restored\n")
  if not marked then
    printError("QuarryOS files were restored, but cleanup is pending: " .. tostring(message))
    return false
  end
  local cleaned, cleanupMessage = clearFinishedStaging(rolledBackFile)
  if not cleaned then printError("Recovered files; cleanup is pending: " .. tostring(cleanupMessage)) end
  return true
end

if not recoverUpdate() then return end

local program = turtle and (root .. "/kernel.lua")
  or (peripheral.find("monitor") and (root .. "/monitor_server.lua"))
  or (root .. "/kernel.lua")
if not fs.exists(program) then
  printError("QuarryOS is incomplete. Run the installer again.")
  return
end
shell.run(program)

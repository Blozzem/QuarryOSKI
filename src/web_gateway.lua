-- QuarryOS CC:Tweaked-to-web gateway. Run this on a separate computer with a
-- wireless/Ender modem. It forwards Rednet status and safe control commands.
local CONFIG_PATH = "/quarryos/web-gateway.cfg"
local AUTOSTART_DIR = "/startup"
local AUTOSTART_PATH = AUTOSTART_DIR .. "/quarryos-web-gateway.lua"
local args = { ... }

local function installAutostart()
  if fs.exists(AUTOSTART_DIR) and not fs.isDir(AUTOSTART_DIR) then
    return false, "/startup is an existing file. Add shell.run(\"/quarryos/web_gateway.lua\") to it manually."
  end
  if not fs.exists(AUTOSTART_DIR) then fs.makeDir(AUTOSTART_DIR) end
  local file = fs.open(AUTOSTART_PATH, "w")
  if not file then return false, "Could not write " .. AUTOSTART_PATH end
  file.write('if shell.openTab then\n')
  file.write('  shell.openTab("/quarryos/web_gateway.lua")\n')
  file.write('else\n')
  file.write('  shell.run("/quarryos/web_gateway.lua")\n')
  file.write('end\n')
  file.close()
  return true
end

local function removeAutostart()
  if fs.exists(AUTOSTART_PATH) then fs.delete(AUTOSTART_PATH) end
  print("QuarryOS Web Gateway autostart removed.")
end

local function readConfig()
  if not fs.exists(CONFIG_PATH) then return nil end
  local file = fs.open(CONFIG_PATH, "r")
  if not file then return nil end
  local config = textutils.unserialize(file.readAll())
  file.close()
  return type(config) == "table" and config or nil
end

local function setup()
  print("QuarryOS Web Gateway setup")
  write("API URL (example http://192.168.1.20:8080): ")
  local baseUrl = read():gsub("/+$", "")
  write("API key: ")
  local apiKey = read("*")
  if baseUrl == "" or apiKey == "" then printError("URL and key are required.") return false end
  if not fs.exists("/quarryos") then fs.makeDir("/quarryos") end
  local file = fs.open(CONFIG_PATH, "w")
  file.write(textutils.serialize({ baseUrl = baseUrl, apiKey = apiKey }))
  file.close()
  print("Saved. The key is stored on this Minecraft computer.")
  local installed, reason = installAutostart()
  if installed then
    print("Autostart installed. The gateway will reconnect after a reboot.")
  else
    printError("Autostart was not installed: " .. tostring(reason))
  end
  return true
end

if args[1] == "autostart" then
  local installed, reason = installAutostart()
  if installed then print("QuarryOS Web Gateway autostart installed.") else printError(reason) end
  return
elseif args[1] == "remove-autostart" then
  removeAutostart()
  return
end
if args[1] == "setup" and not setup() then return end
local config = readConfig()
if not config then printError("Run: /quarryos/web_gateway.lua setup") return end
if not http then printError("HTTP is disabled in CC:Tweaked.") return end

local modemReady = false
for _, side in ipairs(peripheral.getNames()) do
  if peripheral.getType(side) == "modem" then
    local modem = peripheral.wrap(side)
    if modem and modem.isWireless() then rednet.open(side) modemReady = true end
  end
end
if not modemReady then printError("Attach a Wireless or Ender Modem.") return end

local headers = { ["Content-Type"] = "application/json", ["X-QuarryOS-Key"] = config.apiKey }
local function request(method, path, body)
  local options = { url = config.baseUrl .. path, headers = headers, timeout = 10 }
  if body then options.body = textutils.serializeJSON(body) end
  local response, reason
  if method == "POST" then response, reason = http.post(options) else response, reason = http.get(options) end
  if not response then return nil, reason end
  local content = response.readAll()
  local code = response.getResponseCode()
  response.close()
  local parsed = content ~= "" and textutils.unserializeJSON(content) or {}
  if code < 200 or code >= 300 then return nil, (parsed and parsed.error) or ("HTTP " .. code) end
  return parsed
end

local function post(path, body) return request("POST", path, body) end
local allowed, reason = http.checkURL(config.baseUrl .. "/api/health")
if not allowed then printError("URL blocked by CC:Tweaked: " .. tostring(reason)) return end

local function rednetLoop()
  while true do
    local sender, message, protocol = rednet.receive()
    if protocol == "quarryos-monitor" then
      local data = type(message) == "table" and message or textutils.unserialize(message)
      if type(data) == "table" then
        local _, problem = post("/api/v1/heartbeat", { turtleId = sender, data = data })
        if problem then printError("Heartbeat: " .. tostring(problem)) end
      end
    elseif protocol == "quarryos-control-ack" then
      local ack = type(message) == "table" and message or textutils.unserialize(message)
      if type(ack) == "table" and ack.requestId then
        ack.turtleId = sender
        local _, problem = post("/api/v1/commands/" .. textutils.urlEncode(ack.requestId) .. "/ack", ack)
        if problem then printError("ACK: " .. tostring(problem)) end
      end
    end
  end
end

local function commandLoop()
  while true do
    local pending, problem = request("GET", "/api/v1/commands")
    if pending then
      for _, command in ipairs(pending) do
        local turtleId = tonumber(command.turtleId)
        if turtleId then rednet.send(turtleId, textutils.serialize(command), "quarryos-control") end
      end
    elseif problem then printError("Commands: " .. tostring(problem)) end
    sleep(2)
  end
end

term.clear() term.setCursorPos(1, 1)
print("QuarryOS Web Gateway")
print("API: " .. config.baseUrl)
print("Listening for turtles...")
parallel.waitForAll(rednetLoop, commandLoop)

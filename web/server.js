"use strict";

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const HOST = process.env.QUARRYOS_HOST || "0.0.0.0";
// Managed hosts such as Hostinger assign their own PORT. QUARRYOS_PORT stays
// available for self-hosted installations and 8080 is the local default.
const PORT = Number(process.env.PORT || process.env.QUARRYOS_PORT || 8080);
const API_KEY = process.env.QUARRYOS_API_KEY || "";
const PUBLIC_DIR = path.join(__dirname, "public");
const BODY_LIMIT = 64 * 1024;
const COMMAND_TTL = 2 * 60 * 1000;
const ALLOWED_COMMANDS = new Set([
  "service_pause", "stop_after_layer", "fuel_check", "emergency_toggle",
]);

const turtles = new Map();
const commands = new Map();

function json(response, status, value) {
  const body = JSON.stringify(value);
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-store",
  });
  response.end(body);
}

function safeEqual(left, right) {
  const a = Buffer.from(left || "");
  const b = Buffer.from(right || "");
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function isAuthorised(request) {
  return API_KEY && safeEqual(request.headers["x-quarryos-key"], API_KEY);
}

async function readJson(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > BODY_LIMIT) throw Object.assign(new Error("Body too large"), { status: 413 });
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
  } catch {
    throw Object.assign(new Error("Invalid JSON"), { status: 400 });
  }
}

function cleanCommands() {
  const cutoff = Date.now() - COMMAND_TTL;
  for (const [id, item] of commands) {
    if (item.createdAt < cutoff || item.ack) commands.delete(id);
  }
}

function serveStatic(request, response, pathname) {
  const names = { "/": "index.html", "/app.js": "app.js", "/style.css": "style.css" };
  const name = names[pathname];
  if (!name) return false;
  const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8" };
  const body = fs.readFileSync(path.join(PUBLIC_DIR, name));
  response.writeHead(200, {
    "Content-Type": types[path.extname(name)],
    "Content-Length": body.length,
    "Cache-Control": "no-store, max-age=0",
    "Pragma": "no-cache",
    "Expires": "0",
  });
  response.end(body);
  return true;
}

async function handle(request, response) {
  const url = new URL(request.url, `http://${request.headers.host || "localhost"}`);
  if (request.method === "GET" && url.pathname === "/api/health") {
    return json(response, 200, { ok: true, service: "quarryos-web" });
  }
  if (!url.pathname.startsWith("/api/")) {
    if (request.method === "GET" && serveStatic(request, response, url.pathname)) return;
    return json(response, 404, { error: "Not found" });
  }
  if (!isAuthorised(request)) return json(response, 401, { error: "Invalid API key" });

  if (request.method === "GET" && url.pathname === "/api/v1/turtles") {
    const now = Date.now();
    return json(response, 200, [...turtles.values()].map(item => ({
      ...item.data, turtleId: item.turtleId, lastSeen: item.lastSeen,
      online: now - item.lastSeen < 30000,
    })).sort((a, b) => String(a.turtleName || a.turtleId).localeCompare(String(b.turtleName || b.turtleId))));
  }

  if (request.method === "POST" && url.pathname === "/api/v1/heartbeat") {
    const body = await readJson(request);
    const turtleId = Number(body.turtleId);
    if (!Number.isInteger(turtleId) || !body.data || typeof body.data !== "object") {
      return json(response, 400, { error: "turtleId and data are required" });
    }
    turtles.set(turtleId, { turtleId, data: body.data, lastSeen: Date.now() });
    return json(response, 202, { ok: true });
  }

  if (request.method === "GET" && url.pathname === "/api/v1/commands") {
    cleanCommands();
    return json(response, 200, [...commands.values()].filter(item => !item.ack).map(item => item.command));
  }

  const commandMatch = url.pathname.match(/^\/api\/v1\/turtles\/(\d+)\/commands$/);
  if (request.method === "POST" && commandMatch) {
    cleanCommands();
    const turtleId = Number(commandMatch[1]);
    const turtle = turtles.get(turtleId);
    const body = await readJson(request);
    if (!turtle) return json(response, 404, { error: "Unknown turtle" });
    if (!ALLOWED_COMMANDS.has(body.command)) return json(response, 400, { error: "Unsupported command" });
    if (!body.jobId || body.jobId !== turtle.data.jobId) return json(response, 409, { error: "Quarry job changed; refresh first" });
    if (body.command === "emergency_toggle" && typeof body.emergencyMode !== "boolean") {
      return json(response, 400, { error: "emergencyMode must be boolean" });
    }
    const requestId = `web-${Date.now()}-${crypto.randomBytes(4).toString("hex")}`;
    const command = { turtleId, command: body.command, jobId: body.jobId, requestId };
    if (body.command === "emergency_toggle") command.emergencyMode = body.emergencyMode;
    commands.set(requestId, { command, createdAt: Date.now(), ack: null });
    return json(response, 202, { ok: true, requestId });
  }

  const ackMatch = url.pathname.match(/^\/api\/v1\/commands\/([^/]+)\/ack$/);
  if (request.method === "POST" && ackMatch) {
    const requestId = decodeURIComponent(ackMatch[1]);
    const item = commands.get(requestId);
    if (!item) return json(response, 404, { error: "Unknown or expired command" });
    const body = await readJson(request);
    item.ack = { ...body, receivedAt: Date.now() };
    return json(response, 200, { ok: true });
  }

  return json(response, 404, { error: "Not found" });
}

function createServer() {
  return http.createServer((request, response) => {
    handle(request, response).catch(error => {
      console.error(error);
      if (!response.headersSent) json(response, error.status || 500, { error: error.status ? error.message : "Internal server error" });
      else response.end();
    });
  });
}

if (!API_KEY) {
  console.error("QUARRYOS_API_KEY is required. Set it to a long random value before starting.");
  process.exit(1);
}

// Hostinger requires the entry file to call listen() directly during module
// evaluation. A require.main guard prevents its runtime from detecting that
// the application has started.
const server = createServer();
server.listen(PORT, HOST, () => {
  const address = server.address();
  console.log(`QuarryOS web: http://${HOST}:${address.port}`);
});

module.exports = { createServer, server };

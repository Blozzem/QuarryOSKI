"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { once } = require("node:events");
process.env.QUARRYOS_API_KEY = "test-secret";
process.env.PORT = "0";
const { server } = require("../server");

test("heartbeat, listing and command round-trip", async () => {
  if (!server.listening) await once(server, "listening");
  const base = `http://127.0.0.1:${server.address().port}`;
  const headers = { "Content-Type": "application/json", "X-QuarryOS-Key": "test-secret" };
  try {
    let response = await fetch(`${base}/`);
    assert.match(response.headers.get("cache-control"), /no-store/);
    const page = await response.text();
    assert.match(page, /style\.css\?v=/);
    assert.match(page, /app\.js\?v=/);
    response = await fetch(`${base}/api/v1/heartbeat`, { method: "POST", headers, body: JSON.stringify({ turtleId: 12, data: { jobId: "job-1", turtleName: "Miner", width: 16, length: 16, inventory: [{ slot: 1, name: "minecraft:diamond", count: 7 }], statistics: { blocks: 42, services: 2, blockTypes: { "minecraft:stone": 30 }, oreTypes: { "minecraft:diamond": 4 } } } }) });
    assert.equal(response.status, 202);
    response = await fetch(`${base}/api/v1/turtles`, { headers });
    const listed = (await response.json())[0]; assert.equal(listed.turtleName, "Miner"); assert.equal(listed.inventory[0].name, "minecraft:diamond"); assert.equal(listed.statistics.oreTypes["minecraft:diamond"], 4);
    response = await fetch(`${base}/api/v1/turtles/12/commands`, { method: "POST", headers, body: JSON.stringify({ command: "fuel_check", jobId: "job-1" }) });
    const accepted = await response.json(); assert.equal(response.status, 202);
    response = await fetch(`${base}/api/v1/commands`, { headers });
    const pending = await response.json(); assert.equal(pending[0].requestId, accepted.requestId); assert.equal(pending[0].turtleId, 12);
    response = await fetch(`${base}/api/v1/commands/${accepted.requestId}/ack`, { method: "POST", headers, body: JSON.stringify({ status: "reported" }) });
    assert.equal(response.status, 200);
    response = await fetch(`${base}/api/v1/commands`, { headers }); assert.deepEqual(await response.json(), []);
  } finally { await new Promise(resolve => server.close(resolve)); }
});

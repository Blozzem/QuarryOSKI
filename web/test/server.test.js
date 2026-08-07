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
    let response = await fetch(`${base}/api/v1/heartbeat`, { method: "POST", headers, body: JSON.stringify({ turtleId: 12, data: { jobId: "job-1", turtleName: "Miner" } }) });
    assert.equal(response.status, 202);
    response = await fetch(`${base}/api/v1/turtles`, { headers });
    assert.deepEqual((await response.json())[0].turtleName, "Miner");
    response = await fetch(`${base}/api/v1/turtles/12/commands`, { method: "POST", headers, body: JSON.stringify({ command: "fuel_check", jobId: "job-1" }) });
    const accepted = await response.json(); assert.equal(response.status, 202);
    response = await fetch(`${base}/api/v1/commands`, { headers });
    const pending = await response.json(); assert.equal(pending[0].requestId, accepted.requestId); assert.equal(pending[0].turtleId, 12);
    response = await fetch(`${base}/api/v1/commands/${accepted.requestId}/ack`, { method: "POST", headers, body: JSON.stringify({ status: "reported" }) });
    assert.equal(response.status, 200);
    response = await fetch(`${base}/api/v1/commands`, { headers }); assert.deepEqual(await response.json(), []);
  } finally { await new Promise(resolve => server.close(resolve)); }
});

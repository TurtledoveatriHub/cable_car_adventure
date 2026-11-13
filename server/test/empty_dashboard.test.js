import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { createApp } from "../src/app.js";
import { openDatabase } from "../src/db.js";

let server;
let db;
let baseUrl;

before(async () => {
  db = openDatabase(":memory:");
  const app = createApp({
    db,
    config: {
      publicDir: "",
      sessionSecret: "test-secret",
      allowedOrigin: "*",
      reviewMode: "mock",
    },
  });
  await new Promise((resolve) => {
    server = app.listen(0, "127.0.0.1", resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  if (server) await new Promise((resolve) => server.close(resolve));
  if (db) db.close();
});

test("dashboard returns a complete zero payload on an empty database", async () => {
  const response = await fetch(`${baseUrl}/api/telemetry/dashboard?days=7`);
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.equal(data.ok, true);
  assert.equal(data.kpis.runs, 0);
  assert.equal(data.kpis.completion_rate, 0);
  assert.equal(data.kpis.total_events, 0);
  assert.deepEqual(data.platforms, []);
  assert.deepEqual(data.main_levels, []);
  assert.equal(data.trend.length, 7);
  assert.equal(data.collisions.progress_bins.length, 20);
  assert.deepEqual(data.ugc.levels, []);
  assert.equal(data.ugc.funnel.churn_rate, 0);
  assert.deepEqual(data.recent_runs, []);
});

test("summary also returns a valid zero payload on an empty database", async () => {
  const response = await fetch(`${baseUrl}/api/telemetry/summary?days=7`);
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.equal(data.ok, true);
  assert.deepEqual(data.by_day, []);
  assert.deepEqual(data.totals, []);
});

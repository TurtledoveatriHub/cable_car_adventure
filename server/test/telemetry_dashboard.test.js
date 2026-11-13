import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { createApp } from "../src/app.js";
import { openDatabase } from "../src/db.js";

let server;
let db;
let baseUrl;

function jsonBody(value) {
  return {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(value),
  };
}

async function request(path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, options);
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : {} };
}

function telemetry(eventType, levelId, payload, overrides = {}) {
  return request("/api/telemetry", jsonBody({
    event_id: `dash_${eventType}_${levelId}_${Math.random().toString(36).slice(2)}`,
    event_type: eventType,
    platform: overrides.platform || "windows",
    level_id: levelId,
    level_name: overrides.levelName || levelId,
    mode: "solo",
    custom: overrides.custom ?? false,
    ts: Date.now() / 1000,
    payload: {
      level_id: levelId,
      player_id: overrides.playerId || "SW-dashboard",
      session_id: overrides.sessionId || "s_dashboard",
      ...payload,
    },
  }));
}

before(async () => {
  db = openDatabase(":memory:");
  const app = createApp({
    db,
    config: {
      publicDir: "",
      appKey: "test",
      sessionSecret: "test-secret",
      allowedOrigin: "*",
      reviewMode: "mock",
      maxLevelsPerAuthor: 20,
    },
  });
  await new Promise((resolve) => {
    server = app.listen(0, "127.0.0.1", resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  if (server) {
    await new Promise((resolve) => server.close(resolve));
  }
  if (db) {
    db.close();
  }
});

test("dashboard aggregates KPI, platforms, main levels, choke points and UGC churn", async () => {
  const level = {
    schema_version: 2,
    name: "看板测试关卡",
    difficulty: 2,
    par_time: 60,
    track: {
      start_angle_deg: 0,
      pieces: [
        { type: "straight", length: 240 },
        { type: "straight", length: 240 },
        { type: "straight", length: 240 },
      ],
      start_s: 60,
      finish_s: 600,
    },
    obstacles: [],
  };
  const upload = await request("/api/ugc/upload", jsonBody({
    name: "看板测试关卡",
    author_name: "数据测试员",
    author_id: "SW-dashboard",
    platform: "wechat",
    level_data: level,
  }));
  assert.equal(upload.status, 201);
  const ugcId = upload.body.id;

  await request(`/api/ugc/${ugcId}/play`, jsonBody({}));
  await request(`/api/ugc/${ugcId}/like`, jsonBody({ player_id: "SW-fan" }));
  await request(`/api/ugc/${ugcId}/favorite`, jsonBody({ player_id: "SW-fan" }));

  // 主线：1 次通关、1 次卡在 35% 的失败。
  await telemetry("run_end", "level_01", {
    completed: true, passengers: 3, starting_passengers: 3, lost_passengers: 0,
    time_seconds: 50, stars: 3, progress: 1, collisions: 2, difficulty: 1,
  }, { platform: "windows", levelName: "晴空初旅", playerId: "SW-a" });
  await telemetry("run_end", "level_01", {
    completed: false, passengers: 0, starting_passengers: 3, lost_passengers: 3,
    time_seconds: 20, stars: 0, progress: 0.35, collisions: 1, difficulty: 1,
  }, { platform: "android", levelName: "晴空初旅", playerId: "SW-b", sessionId: "s_b" });

  // UGC：3 次进入、2 次结算、1 次通关；失败点在 55%。
  for (let index = 0; index < 3; index += 1) {
    await telemetry("enter_custom_level", ugcId, {
      custom: true, level_name: "看板测试关卡", run_id: `r_${index}`,
    }, { platform: "wechat", levelName: "看板测试关卡", custom: true, playerId: `SW-u${index}` });
  }
  await telemetry("run_end", ugcId, {
    completed: true, passengers: 3, starting_passengers: 3, lost_passengers: 0,
    time_seconds: 40, stars: 3, progress: 1, collisions: 0, custom: true,
  }, { platform: "wechat", levelName: "看板测试关卡", custom: true, playerId: "SW-u0" });
  await telemetry("run_end", ugcId, {
    completed: false, passengers: 0, starting_passengers: 3, lost_passengers: 3,
    time_seconds: 22, stars: 0, progress: 0.55, collisions: 1, custom: true,
  }, { platform: "wechat", levelName: "看板测试关卡", custom: true, playerId: "SW-u1" });
  await telemetry("collision", ugcId, {
    obstacle_type: "bird", motion_type: "wave", track_progress: 0.35, s: 400, speed: 300,
  }, { platform: "android", levelName: "看板测试关卡", custom: true, playerId: "SW-a" });
  await telemetry("collision", ugcId, {
    obstacle_type: "crate", motion_type: "static", track_progress: 0.55, s: 600, speed: 280,
  }, { platform: "wechat", levelName: "看板测试关卡", custom: true, playerId: "SW-b" });

  const response = await request("/api/telemetry/dashboard?days=7");
  assert.equal(response.status, 200);
  const data = response.body;
  assert.equal(data.ok, true);
  assert.equal(data.kpis.runs, 4);
  assert.equal(data.kpis.completed, 2);
  assert.equal(data.kpis.completion_rate, 50);
  assert.equal(data.kpis.collisions, 2);
  assert.equal(data.kpis.mainline_runs, 2);
  assert.equal(data.kpis.ugc_runs, 2);
  assert.equal(data.kpis.unique_players, 5);

  assert.equal(data.platforms.length, 3);
  const windows = data.platforms.find((item) => item.id === "windows");
  assert.equal(windows.runs, 1);
  assert.equal(windows.completion_rate, 100);

  assert.equal(data.main_levels.length, 1);
  assert.equal(data.main_levels[0].level_id, "level_01");
  assert.equal(data.main_levels[0].runs, 2);
  assert.equal(data.main_levels[0].completion_rate, 50);

  const progress = data.collisions.progress_bins;
  assert.equal(progress.length, 20);
  assert.equal(progress[7].collisions, 1);
  assert.equal(progress[11].collisions, 1);
  assert.equal(progress[7].failures, 1);
  assert.ok(data.choke_levels.length >= 1);

  assert.equal(data.ugc.funnel.enters, 3);
  assert.equal(data.ugc.funnel.runs, 2);
  assert.equal(data.ugc.funnel.completed, 1);
  assert.equal(data.ugc.totals.churn_rate, 66.67);
  assert.equal(data.ugc.levels[0].name, "看板测试关卡");
  assert.equal(data.ugc.levels[0].plays, 1);
  assert.equal(data.ugc.levels[0].likes, 1);
  assert.equal(data.ugc.levels[0].favorites, 1);
  assert.ok(data.ugc.levels[0].heat_score > 0);
  assert.equal(data.trend.length, 7);

  assert.equal(data.recent_runs.length, 4);
  assert.equal(data.event_counts.run_end, 4);
  assert.equal(data.event_counts.collision, 2);
  assert.equal(data.event_counts.enter_custom_level, 3);
});

test("dashboard survives malformed legacy payload rows", async () => {
  db.prepare(`
    INSERT INTO telemetry_events
    (event_id, event_type, platform, level_id, level_name, mode, custom, client_ts, received_at, payload_json)
    VALUES (?, 'run_end', 'wechat', 'legacy_bad', '坏数据', 'solo', 0, ?, ?, ?)
  `).run("dash_bad_payload", Date.now() / 1000, new Date().toISOString(), "{broken json");
  const response = await request("/api/telemetry/dashboard?days=7");
  assert.equal(response.status, 200);
  assert.equal(response.body.ok, true);
  assert.equal(typeof response.body.kpis.runs, "number");
  assert.equal(response.body.degraded, undefined);
  db.prepare("DELETE FROM telemetry_events WHERE event_id = ?").run("dash_bad_payload");
});

test("dashboard endpoint exposes CORS headers for the Vue dev server", async () => {
  const origin = "http://127.0.0.1:5173";
  const response = await fetch(`${baseUrl}/api/telemetry/dashboard?days=7`, {
    headers: { Origin: origin },
  });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("access-control-allow-origin"), "*");

  const preflight = await fetch(`${baseUrl}/api/telemetry/dashboard?days=7`, {
    method: "OPTIONS",
    headers: {
      Origin: origin,
      "Access-Control-Request-Method": "GET",
      "Access-Control-Request-Headers": "content-type",
    },
  });
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get("access-control-allow-origin"), "*");
  assert.match(String(preflight.headers.get("access-control-allow-methods")), /GET/);
});

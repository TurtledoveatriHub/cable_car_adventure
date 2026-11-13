import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { createApp } from "../src/app.js";
import { openDatabase } from "../src/db.js";

let server;
let db;
let baseUrl;

function makeLevel(overrides = {}) {
  return {
    schema_version: 2,
    id: "client_should_be_replaced",
    name: "测试环线",
    subtitle: "联调关卡",
    description: "API 自动化测试关卡",
    difficulty: 2,
    par_time: 60,
    countdown_seconds: 3,
    time_limit_seconds: 180,
    background_id: "sky",
    custom: true,
    source: "user",
    theme: {
      sky_top: "#68cdf2",
      sky_bottom: "#fff1b8",
      track: "#2f4b68",
      accent: "#ff6b5b",
    },
    camera_bounds: { x: -100, y: -100, w: 900, h: 500 },
    track: {
      start_angle_deg: 0,
      pieces: [
        { type: "straight", length: 240, direction: 1, direction_anchor: true },
        { type: "straight", length: 240, direction: 1 },
        { type: "straight", length: 240, direction: 1 },
      ],
      start_s: 60,
      finish_s: 600,
    },
    obstacles: [
      { prefab: "bird", s: 300, offset: { x: 0, y: -60 }, flip_x: false },
    ],
    analytics_tags: ["测试"],
    ...overrides,
  };
}

async function request(path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, options);
  const text = await response.text();
  const body = text ? JSON.parse(text) : {};
  return { status: response.status, body };
}

function jsonBody(value) {
  return {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(value),
  };
}

before(async () => {
  db = openDatabase(":memory:");
  const app = createApp({
    db,
    config: {
      publicDir: "",
      appId: "wx_test",
      appSecret: "",
      sessionSecret: "test-secret",
      ugcScene: 2,
      allowedOrigin: "*",
      reviewMode: "mock",
      maxLevelsPerAuthor: 20,
    },
  });
  await new Promise((resolve) => {
    server = app.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  baseUrl = `http://127.0.0.1:${address.port}`;
});

after(async () => {
  if (server) {
    await new Promise((resolve) => server.close(resolve));
  }
  if (db) {
    db.close();
  }
});

test("UGC upload/list/detail/play/like/favorite/delete", async (t) => {
  let uploadedId = "";
  await t.test("health reports sqlite", async () => {
    const { status, body } = await request("/health");
    assert.equal(status, 200);
    assert.equal(body.ok, true);
    assert.equal(body.database, "sqlite");
  });

  await t.test("upload validates and stores canonical level", async () => {
    const level = makeLevel();
    const { status, body } = await request("/api/ugc/upload", jsonBody({
      name: "广场测试关卡",
      author_name: "测试玩家",
      author_id: "local_player",
      platform: "windows",
      description: "这是一个测试",
      level_data: level,
    }));
    assert.equal(status, 201);
    assert.equal(body.ok, true);
    assert.equal(body.review_status, "approved");
    assert.match(body.id, /^ugc_/);
    assert.notEqual(body.id, level.id);
    uploadedId = body.id;
  });

  await t.test("list returns摘要 without level_data", async () => {
    const { status, body } = await request("/api/ugc/list?page=1&page_size=10&player_id=local_player");
    assert.equal(status, 200);
    assert.equal(body.ok, true);
    assert.equal(body.total, 1);
    const entry = body.entries[0];
    assert.equal(entry.id, uploadedId);
    assert.equal(entry.name, "广场测试关卡");
    assert.equal(entry.author, "测试玩家");
    assert.equal(entry.platform, "windows");
    assert.equal(entry.played, undefined);
    assert.equal(entry.level_data, undefined);
  });

  await t.test("detail returns full level and preserves editor fields", async () => {
    const { status, body } = await request(`/api/ugc/detail/${uploadedId}?player_id=local_player`);
    assert.equal(status, 200);
    assert.equal(body.ok, true);
    assert.equal(body.entry.id, uploadedId);
    assert.equal(body.entry.level_data.id, uploadedId);
    assert.equal(body.entry.level_data.track.pieces.length, 3);
    assert.equal(body.entry.level_data.obstacles.length, 1);
    assert.deepEqual(body.entry.level_data.obstacles[0].offset, { x: 0, y: -60 });
    assert.equal(body.entry.level_data.camera_bounds.w, 900);
    assert.equal(body.entry.level_data.source, "community");
    assert.equal(body.entry.level_data.custom, true);
  });

  await t.test("play increments count", async () => {
    const { status, body } = await request(`/api/ugc/${uploadedId}/play`, jsonBody({}));
    assert.equal(status, 200);
    assert.equal(body.plays, 1);
    const list = await request("/api/ugc/list?page=1&page_size=1");
    assert.equal(list.body.entries[0].plays, 1);
  });

  await t.test("like and favorite toggle", async () => {
    const like = await request(`/api/ugc/${uploadedId}/like`, jsonBody({ player_id: "local_player" }));
    assert.equal(like.status, 200);
    assert.equal(like.body.liked, true);
    assert.equal(like.body.likes, 1);
    const favorite = await request(`/api/ugc/${uploadedId}/favorite`, jsonBody({ player_id: "local_player" }));
    assert.equal(favorite.status, 200);
    assert.equal(favorite.body.favorited, true);
    const detail = await request(`/api/ugc/detail/${uploadedId}?player_id=local_player`);
    assert.equal(detail.body.entry.liked, true);
    assert.equal(detail.body.entry.favorited, true);
  });

  await t.test("rejects invalid and oversized payloads", async () => {
    const invalid = await request("/api/ugc/upload", jsonBody({
      name: "坏关卡",
      author_name: "测试",
      author_id: "local_player",
      platform: "windows",
      level_data: makeLevel({ track: { pieces: [] } }),
    }));
    assert.equal(invalid.status, 400);
    assert.equal(invalid.body.ok, false);

    const oversizedLevel = makeLevel({ padding: "x".repeat(2 * 1024 * 1024 + 100) });
    const oversized = await request("/api/ugc/upload", jsonBody({
      name: "超大关卡",
      author_name: "测试",
      author_id: "local_player",
      platform: "windows",
      level_data: oversizedLevel,
    }));
    assert.equal(oversized.status, 413);
    assert.equal(oversized.body.error, "payload_too_large");
  });

  await t.test("delete requires the original author", async () => {
    const forbidden = await request(`/api/ugc/${uploadedId}`, {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ author_id: "another_player" }),
    });
    assert.equal(forbidden.status, 403);
    const deleted = await request(`/api/ugc/${uploadedId}`, {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ author_id: "local_player" }),
    });
    assert.equal(deleted.status, 200);
    const detail = await request(`/api/ugc/detail/${uploadedId}`);
    assert.equal(detail.status, 404);
  });
});

test("telemetry accepts run_end and enter_custom_level", async (t) => {
  await t.test("stores telemetry and deduplicates event_id", async () => {
    const event = {
      event_id: "test-event-1",
      event_type: "run_end",
      platform: "android",
      level_id: "ugc_demo",
      level_name: "测试关卡",
      mode: "solo",
      custom: true,
      ts: Date.now() / 1000,
      payload: { completed: true, passengers: 3, time_seconds: 12.3 },
    };
    const first = await request("/api/telemetry", jsonBody(event));
    assert.equal(first.status, 202);
    assert.equal(first.body.ok, true);
    assert.equal(first.body.duplicate, false);

    const duplicate = await request("/api/telemetry", jsonBody(event));
    assert.equal(duplicate.status, 202);
    assert.equal(duplicate.body.duplicate, true);

    const enter = await request("/api/telemetry", jsonBody({
      event_id: "test-event-2",
      event_type: "enter_custom_level",
      platform: "wechat",
      level_id: "ugc_demo",
      level_name: "测试关卡",
      mode: "solo",
      custom: true,
      ts: Date.now() / 1000,
      payload: { level_id: "ugc_demo", custom: true },
    }));
    assert.equal(enter.status, 202);

    const summary = await request("/api/telemetry/summary?days=7");
    assert.equal(summary.status, 200);
    const total = summary.body.totals.find((item) => item.event_type === "run_end");
    assert.equal(total.count, 1);
  });

  await t.test("rejects unsupported telemetry", async () => {
    const response = await request("/api/telemetry", jsonBody({
      event_type: "screen_shot",
      platform: "windows",
      payload: {},
    }));
    assert.equal(response.status, 400);
    assert.equal(response.body.error, "invalid_event_type");
  });
});

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
      appSecret: "",
      sessionSecret: "test-secret",
      allowedOrigin: "*",
      reviewMode: "pending",
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

test("pending review mode keeps uploads out of the public list", async () => {
  const level = {
    schema_version: 2,
    name: "待审核关卡",
    difficulty: 1,
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
  const response = await fetch(`${baseUrl}/api/ugc/upload`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      name: "待审核关卡",
      author_name: "测试",
      author_id: "local_player",
      platform: "wechat",
      level_data: level,
    }),
  });
  assert.equal(response.status, 202);
  const uploaded = await response.json();
  assert.equal(uploaded.review_status, "pending");
  assert.equal(uploaded.entry.name, "待审核关卡");

  const list = await fetch(`${baseUrl}/api/ugc/list`).then((item) => item.json());
  assert.equal(list.total, 0);
  const detail = await fetch(`${baseUrl}/api/ugc/detail/${uploaded.id}`);
  assert.equal(detail.status, 404);
});

import fs from "node:fs";
import path from "node:path";
import { openDatabase } from "../src/db.js";

const dbPath = process.env.UGC_DB_PATH || path.resolve("data", "dashboard_demo.sqlite");
const reset = process.argv.includes("--reset");
if (!dbPath.includes("demo")) {
  console.error("拒绝写入非 demo 数据库。请把 UGC_DB_PATH 指向文件名包含 demo 的路径。");
  process.exit(1);
}
if (fs.existsSync(dbPath) && !reset) {
  const db = openDatabase(dbPath);
  const count = db.prepare("SELECT COUNT(*) AS count FROM telemetry_events").get().count;
  db.close();
  if (count > 0) {
    console.error(`数据库已有 ${count} 条事件；加 --reset 可重建 demo 数据。`);
    process.exit(1);
  }
}
if (reset && fs.existsSync(dbPath)) {
  fs.rmSync(dbPath, { force: true });
  for (const suffix of ["-wal", "-shm"]) {
    fs.rmSync(`${dbPath}${suffix}`, { force: true });
  }
}

const db = openDatabase(dbPath);
const insertEvent = db.prepare(`
  INSERT OR REPLACE INTO telemetry_events
  (event_id, event_type, platform, level_id, level_name, mode, custom, client_ts, received_at, payload_json)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
`);
const insertUgc = db.prepare(`
  INSERT OR REPLACE INTO ugc_levels
  (id, name, author_id, author_name, description, platform, difficulty, schema_version,
   level_bytes, level_json, review_status, review_provider, review_reason, created_at, updated_at,
   plays, likes, favorites)
  VALUES (?, ?, ?, ?, ?, ?, ?, 2, 2, '{}', 'approved', 'mock', 'demo', ?, ?, ?, ?, ?)
`);

let seed = 20261108;
function random() {
  seed = (seed * 1664525 + 1013904223) >>> 0;
  return seed / 0xffffffff;
}
function pick(items) {
  return items[Math.floor(random() * items.length)];
}
function between(min, max) {
  return min + random() * (max - min);
}

const platforms = [
  { id: "windows", weight: 0.25 },
  { id: "android", weight: 0.34 },
  { id: "wechat", weight: 0.41 },
];
function pickPlatform() {
  const value = random();
  let cursor = 0;
  for (const item of platforms) {
    cursor += item.weight;
    if (value <= cursor) return item.id;
  }
  return "wechat";
}

const mainLevels = [
  ["level_01", "晴空初旅", 0.82, 1],
  ["level_02", "风车草坡", 0.71, 2],
  ["level_03", "森林回声", 0.62, 2],
  ["level_04", "雪线之上", 0.55, 3],
  ["level_05", "云端回环", 0.48, 3],
  ["level_06", "暮色急弯", 0.41, 4],
  ["level_07", "星落峡谷", 0.36, 4],
  ["level_08", "终点之前", 0.3, 5],
];
const ugcLevels = [
  ["ugc_demo_sky", "天空折返跑", "阿岚", "wechat", 0.58, 2, 1860, 342, 96],
  ["ugc_demo_night", "夜航星轨", "小北", "android", 0.34, 3, 1240, 270, 71],
  ["ugc_demo_park", "旋转木马惊魂", "Momo", "windows", 0.67, 2, 980, 165, 44],
  ["ugc_demo_loop", "三连死亡环", "轨研所", "wechat", 0.12, 5, 2100, 512, 188],
  ["ugc_demo_snow", "雪国慢车", "Nora", "wechat", 0.46, 2, 1520, 244, 86],
  ["ugc_demo_dream", "梦游轨道", "白噪音", "android", 0.24, 4, 1740, 305, 120],
];

const createdAt = new Date(Date.now() - 26 * 86_400_000).toISOString();
for (const [id, name, author, platformId, , difficulty, plays, likes, favorites] of ugcLevels) {
  insertUgc.run(
    id, name, `author_${id}`, author, "demo data", platformId, difficulty,
    createdAt, createdAt, plays, likes, favorites,
  );
}

const now = Date.now();
const events = [];
let eventIndex = 0;
function addEvent(type, platformId, levelId, levelName, custom, date, payload) {
  eventIndex += 1;
  events.push({
    event_id: `demo_${eventIndex}`,
    type,
    platform: platformId,
    level_id: levelId,
    level_name: levelName,
    custom,
    received_at: date.toISOString(),
    client_ts: date.getTime() / 1000,
    payload: {
      player_id: `SW-demo-${Math.floor(random() * 48).toString().padStart(2, "0")}`,
      session_id: `s_demo_${Math.floor(random() * 96)}`,
      ...payload,
    },
  });
}

function obstacleFor(levelIndex) {
  const types = ["bird", "crate", "barrier", "storm", "caterpillar", "fan"];
  const motions = ["static", "wave", "linear", "circular"];
  return { type: types[levelIndex % types.length], motion: motions[levelIndex % motions.length] };
}

for (let dayOffset = 29; dayOffset >= 0; dayOffset -= 1) {
  const day = new Date(now - dayOffset * 86_400_000);
  const baseRuns = 20 + Math.floor(random() * 16) + (dayOffset < 7 ? 6 : 0);
  const orphanEnters = dayOffset < 7 ? 2 + Math.floor(random() * 3) : Math.floor(random() * 2);
  for (let extra = 0; extra < orphanEnters; extra += 1) {
    const [id, name, , , , difficulty] = pick(ugcLevels);
    const date = new Date(day.getTime() + Math.floor(between(9, 23) * 3_600_000));
    addEvent("enter_custom_level", pickPlatform(), id, name, true, date, {
      run_id: `orphan_${eventIndex}`,
      custom: true,
      level_name: name,
      difficulty,
    });
  }
  for (let runIndex = 0; runIndex < baseRuns; runIndex += 1) {
    const isUgc = random() < 0.27;
    const platformId = pickPlatform();
    const date = new Date(day.getTime() + Math.floor(between(8, 23) * 3_600_000));
    if (isUgc) {
      const [id, name, , , completionChance, difficulty] = pick(ugcLevels);
      const completed = random() < completionChance;
      const progress = completed ? 1 : pick([0.18, 0.27, 0.35, 0.42, 0.51, 0.58, 0.66, 0.74, 0.83]);
      const collisionCount = completed ? Math.floor(random() * 2) : 1 + Math.floor(random() * 3);
      addEvent("enter_custom_level", platformId, id, name, true, new Date(date.getTime() - 2000), {
        run_id: `run_${eventIndex}`,
        custom: true,
        level_name: name,
        difficulty,
      });
      addEvent("run_end", platformId, id, name, true, date, {
        run_id: `run_${eventIndex}`,
        completed,
        passengers: completed ? Math.max(1, 3 - Math.floor(random() * 2)) : 0,
        starting_passengers: 3,
        lost_passengers: completed ? Math.floor(random() * 2) : 3,
        time_seconds: Math.round(between(completed ? 35 : 18, completed ? 92 : 48) * 100) / 100,
        stars: completed ? (random() < 0.35 ? 3 : random() < 0.65 ? 2 : 1) : 0,
        progress,
        collisions: collisionCount,
        difficulty,
        custom: true,
        track_length: 4800,
      });
      for (let collisionIndex = 0; collisionIndex < collisionCount; collisionIndex += 1) {
        const obstacle = obstacleFor(collisionIndex + id.length);
        addEvent("collision", platformId, id, name, true, new Date(date.getTime() - 800), {
          obstacle_type: obstacle.type,
          motion_type: obstacle.motion,
          track_progress: Math.min(0.97, Math.max(0.05, progress + between(-0.06, 0.06))),
          s: progress * 4800,
          speed: between(180, 620),
          damage: 1,
        });
      }
    } else {
      const [id, name, completionChance, difficulty] = pick(mainLevels);
      const completed = random() < completionChance;
      const progress = completed ? 1 : pick([0.22, 0.31, 0.39, 0.48, 0.57, 0.63, 0.72, 0.81]);
      const collisionCount = completed ? Math.floor(random() * 2) : 1 + Math.floor(random() * 4);
      addEvent("run_end", platformId, id, name, false, date, {
        run_id: `run_${eventIndex}`,
        completed,
        passengers: completed ? Math.max(1, 3 - Math.floor(random() * 2)) : 0,
        starting_passengers: 3,
        lost_passengers: completed ? Math.floor(random() * 2) : 3,
        time_seconds: Math.round(between(completed ? 32 : 15, completed ? 88 : 42) * 100) / 100,
        stars: completed ? (random() < 0.45 ? 3 : random() < 0.72 ? 2 : 1) : 0,
        progress,
        collisions: collisionCount,
        difficulty,
        custom: false,
        track_length: 6200,
      });
      for (let collisionIndex = 0; collisionIndex < collisionCount; collisionIndex += 1) {
        const obstacle = obstacleFor(collisionIndex + id.length);
        addEvent("collision", platformId, id, name, false, new Date(date.getTime() - 700), {
          obstacle_type: obstacle.type,
          motion_type: obstacle.motion,
          track_progress: Math.min(0.97, Math.max(0.04, progress + between(-0.05, 0.05))),
          s: progress * 6200,
          speed: between(160, 640),
          damage: 1,
        });
      }
    }
  }
}

const insertMany = db.transaction((rows) => {
  for (const row of rows) {
    insertEvent.run(
      row.event_id, row.type, row.platform, row.level_id, row.level_name, "solo",
      row.custom ? 1 : 0, row.client_ts, row.received_at, JSON.stringify(row.payload),
    );
  }
});
insertMany(events);

console.log(`demo database: ${dbPath}`);
console.log(`events: ${events.length}`);
console.log(`ugc: ${ugcLevels.length}`);
db.close();

import fs from "node:fs";
import path from "node:path";
import Database from "better-sqlite3";

/**
 * 旧版本数据库可能没有后来新增的遥测列。CREATE TABLE IF NOT EXISTS 不会补列，
 * 这里做一次幂等迁移，避免看板聚合因 no such column 变成 500。
 */
function ensureColumns(db, table, definitions) {
  const existing = new Set(db.prepare(`PRAGMA table_info(${table})`).all().map((row) => row.name));
  for (const [name, ddl] of Object.entries(definitions)) {
    if (!existing.has(name)) {
      db.exec(`ALTER TABLE ${table} ADD COLUMN ${name} ${ddl}`);
    }
  }
  return existing;
}

/**
 * 打开 SQLite 数据库并执行幂等建表。
 *
 * 关卡正文以规范化后的 JSON 文本保存，列表接口只读取摘要列，避免把
 * 完整关卡数据带进广场列表响应。
 */
export function openDatabase(dbPath) {
  if (dbPath !== ":memory:") {
    fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  }
  const db = new Database(dbPath);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  db.pragma("busy_timeout = 5000");

  db.exec(`
    CREATE TABLE IF NOT EXISTS ugc_levels (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      author_id TEXT NOT NULL,
      author_name TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      platform TEXT NOT NULL,
      difficulty INTEGER NOT NULL DEFAULT 1,
      schema_version INTEGER NOT NULL DEFAULT 2,
      level_bytes INTEGER NOT NULL,
      level_json TEXT NOT NULL,
      review_status TEXT NOT NULL DEFAULT 'pending',
      review_provider TEXT NOT NULL DEFAULT 'mock',
      review_reason TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      plays INTEGER NOT NULL DEFAULT 0,
      likes INTEGER NOT NULL DEFAULT 0,
      favorites INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS ugc_likes (
      entry_id TEXT NOT NULL,
      player_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY (entry_id, player_id),
      FOREIGN KEY (entry_id) REFERENCES ugc_levels(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS ugc_favorites (
      entry_id TEXT NOT NULL,
      player_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY (entry_id, player_id),
      FOREIGN KEY (entry_id) REFERENCES ugc_levels(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS telemetry_events (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,
      event_id TEXT UNIQUE,
      event_type TEXT NOT NULL,
      platform TEXT NOT NULL,
      level_id TEXT NOT NULL DEFAULT '',
      level_name TEXT NOT NULL DEFAULT '',
      mode TEXT NOT NULL DEFAULT '',
      custom INTEGER NOT NULL DEFAULT 0,
      client_ts REAL,
      received_at TEXT NOT NULL,
      payload_json TEXT NOT NULL
    );

  `);

  const telemetryBefore = ensureColumns(db, "telemetry_events", {
    event_id: "TEXT",
    event_type: "TEXT NOT NULL DEFAULT ''",
    platform: "TEXT NOT NULL DEFAULT 'unknown'",
    level_id: "TEXT NOT NULL DEFAULT ''",
    level_name: "TEXT NOT NULL DEFAULT ''",
    mode: "TEXT NOT NULL DEFAULT ''",
    custom: "INTEGER NOT NULL DEFAULT 0",
    client_ts: "REAL",
    received_at: "TEXT NOT NULL DEFAULT ''",
    payload_json: "TEXT NOT NULL DEFAULT '{}'",
  });
  ensureColumns(db, "ugc_levels", {
    plays: "INTEGER NOT NULL DEFAULT 0",
    likes: "INTEGER NOT NULL DEFAULT 0",
    favorites: "INTEGER NOT NULL DEFAULT 0",
    // 内容指纹：可空，旧数据迁移后为 NULL（UNIQUE 索引中 NULL 互不相等，不影响历史记录）。
    content_hash: "TEXT",
  });
  // 早期版本若使用 payload 列，把已有正文迁到 payload_json。
  if (!telemetryBefore.has("payload_json")) {
    const payloadColumns = new Set(db.prepare("PRAGMA table_info(telemetry_events)").all().map((row) => row.name));
    if (payloadColumns.has("payload")) {
      db.exec("UPDATE telemetry_events SET payload_json = payload WHERE payload_json = '{}'");
    }
  }

  // 索引放在补列之后创建：旧库即使缺少新列，也能先迁移再建索引。
  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_ugc_levels_feed
      ON ugc_levels (review_status, created_at DESC);
    DROP INDEX IF EXISTS idx_ugc_levels_hot;
    CREATE INDEX IF NOT EXISTS idx_ugc_levels_hot
      ON ugc_levels (review_status, likes DESC, plays DESC);
    CREATE INDEX IF NOT EXISTS idx_ugc_levels_author
      ON ugc_levels (author_id, created_at DESC);
    CREATE UNIQUE INDEX IF NOT EXISTS idx_ugc_levels_author_hash
      ON ugc_levels (author_id, content_hash);
    CREATE INDEX IF NOT EXISTS idx_telemetry_received
      ON telemetry_events (received_at DESC);
    CREATE INDEX IF NOT EXISTS idx_telemetry_level
      ON telemetry_events (level_id, event_type);
    CREATE INDEX IF NOT EXISTS idx_telemetry_type_received
      ON telemetry_events (event_type, received_at DESC);
    CREATE INDEX IF NOT EXISTS idx_telemetry_platform_received
      ON telemetry_events (platform, received_at DESC);
  `);

  return db;
}

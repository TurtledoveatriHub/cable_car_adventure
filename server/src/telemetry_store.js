/**
 * 遥测事件落库与看板聚合。
 *
 * 原始事件保留完整 payload，便于后续 pandas / 数仓重算；
 * 看板接口只返回聚合结果，不暴露玩家 ID、session 等明细。
 */

const BIN_COUNT = 20;

function number(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function percent(part, total) {
  if (!total) {
    return 0;
  }
  return (number(part) / number(total)) * 100;
}

function round(value, digits = 2) {
  const factor = 10 ** digits;
  return Math.round(number(value) * factor) / factor;
}

function pctChange(current, previous) {
  if (!previous) {
    return current > 0 ? 100 : 0;
  }
  return ((current - previous) / previous) * 100;
}

function safeJson(text) {
  try {
    const value = JSON.parse(text || "{}");
    return value && typeof value === "object" && !Array.isArray(value) ? value : {};
  } catch {
    return {};
  }
}

function playerExpr(alias = "payload_json") {
  return `COALESCE(NULLIF(json_extract(${alias}, '$.player_id'), ''), NULLIF(json_extract(${alias}, '$.session_id'), ''), 'anonymous')`;
}

function completedExpr(alias = "payload_json") {
  return `(CASE WHEN json_extract(${alias}, '$.completed') IN (1, 'true') THEN 1 ELSE 0 END)`;
}

function dayKeys(since, until) {
  const keys = [];
  const cursor = new Date(since);
  cursor.setUTCHours(0, 0, 0, 0);
  while (cursor <= until && keys.length < 100) {
    keys.push(cursor.toISOString().slice(0, 10));
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return keys;
}

/** 与 dashboard 完全同构的空数据；也作为脏数据/旧库的降级响应。 */
function emptyDashboard(days, warning = "") {
  const now = new Date();
  const since = new Date(now.getTime() - days * 86_400_000);
  const progressBins = Array.from({ length: BIN_COUNT }, (_, index) => ({
    index,
    from: index * (100 / BIN_COUNT),
    to: (index + 1) * (100 / BIN_COUNT),
    label: `${Math.round(index * (100 / BIN_COUNT))}-${Math.round((index + 1) * (100 / BIN_COUNT))}%`,
    collisions: 0,
    failures: 0,
    score: 0,
  }));
  return {
    ok: true,
    degraded: Boolean(warning),
    warning,
    days,
    generated_at: now.toISOString(),
    range: { from: since.toISOString(), to: now.toISOString() },
    kpis: {
      runs: 0, completed: 0, completion_rate: 0, unique_players: 0, sessions: 0,
      collisions: 0, collisions_per_run: 0, avg_time: 0, avg_stars: 0,
      lost_passengers: 0, saved_passengers: 0, total_events: 0,
      mainline_runs: 0, ugc_runs: 0, active_levels: 0,
    },
    previous: { runs: 0, completed: 0, completion_rate: 0, unique_players: 0, collisions: 0, avg_time: 0 },
    deltas: { runs: 0, completion_rate: 0, unique_players: 0, collisions: 0, avg_time: 0 },
    trend: dayKeys(since, now).slice(-days).map((date) => ({
      date, runs: 0, completed: 0, failures: 0, completion_rate: 0, collisions: 0, players: 0,
    })),
    platforms: [],
    main_levels: [],
    collisions: {
      total: 0,
      payload_collisions: 0,
      by_type: [],
      by_motion: [],
      progress_bins: progressBins,
      by_level: [],
    },
    choke_levels: [],
    ugc: {
      levels: [],
      top_heat: [],
      funnel: {
        enters: 0, plays: 0, runs: 0, completed: 0, likes: 0, favorites: 0,
        enter_to_run_rate: 0, completion_rate: 0, churn_rate: 0,
      },
      platforms: [],
      totals: { levels: 0, plays: 0, likes: 0, favorites: 0, runs: 0, completed: 0, churn_rate: 0 },
      bin_count: BIN_COUNT,
    },
    recent_runs: [],
    event_counts: {},
    passengers: { saved: 0, lost: 0, saved_ratio: 0 },
  };
}

export class TelemetryStore {
  constructor(db) {
    this.db = db;
  }

  insert(event) {
    const eventId = event.eventId || `tel_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    try {
      this.db.prepare(`
        INSERT INTO telemetry_events (
          event_id, event_type, platform, level_id, level_name, mode, custom,
          client_ts, received_at, payload_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        eventId,
        event.eventType,
        event.platform,
        event.levelId,
        event.levelName,
        event.mode,
        event.custom ? 1 : 0,
        event.clientTs,
        new Date().toISOString(),
        JSON.stringify(event.payload),
      );
      return { ok: true, duplicate: false, eventId };
    } catch (error) {
      if (error.code === "SQLITE_CONSTRAINT_UNIQUE" || error.code === "SQLITE_CONSTRAINT_PRIMARYKEY") {
        return { ok: true, duplicate: true, eventId };
      }
      throw error;
    }
  }

  summary(days = 7) {
    const normalizedDays = Math.max(1, Math.min(90, Number(days) || 7));
    const since = new Date(Date.now() - normalizedDays * 86_400_000).toISOString();
    const byDay = this.db.prepare(`
      SELECT substr(received_at, 1, 10) AS day, event_type, platform, COUNT(*) AS count
      FROM telemetry_events
      WHERE received_at >= ?
      GROUP BY day, event_type, platform
      ORDER BY day DESC, event_type ASC
    `).all(since);
    const totals = this.db.prepare(`
      SELECT event_type, COUNT(*) AS count
      FROM telemetry_events
      WHERE received_at >= ?
      GROUP BY event_type
    `).all(since);
    return {
      days: normalizedDays,
      since,
      by_day: byDay,
      totals,
    };
  }

  /**
   * 看板聚合入口。聚合失败（历史脏数据、旧库缺列等）时返回合法空结构，
   * 绝不让监控看板因为单条异常事件变成 500。
   */
  dashboard(days = 7) {
    const normalizedDays = Math.max(1, Math.min(90, Number(days) || 7));
    try {
      return this._dashboard(normalizedDays);
    } catch (error) {
      console.error("[telemetry] dashboard aggregation failed:", error);
      return emptyDashboard(normalizedDays, String(error?.message || error));
    }
  }

  /**
   * 看板聚合。所有字段都来自真实事件；没有数据时返回完整的零值结构，
   * 前端不需要为“空库”写第二套分支。
   */
  _dashboard(normalizedDays) {
    const now = new Date();
    const since = new Date(now.getTime() - normalizedDays * 86_400_000);
    const previousSince = new Date(since.getTime() - normalizedDays * 86_400_000);
    const sinceIso = since.toISOString();
    const previousSinceIso = previousSince.toISOString();

    const runRows = this.db.prepare(`
      SELECT
        platform,
        level_id,
        level_name,
        custom,
        COUNT(*) AS runs,
        SUM(${completedExpr()}) AS completed,
        SUM(COALESCE(json_extract(payload_json, '$.time_seconds'), 0)) AS total_time,
        SUM(COALESCE(json_extract(payload_json, '$.passengers'), 0)) AS total_passengers,
        SUM(COALESCE(json_extract(payload_json, '$.lost_passengers'), 0)) AS total_lost,
        SUM(COALESCE(json_extract(payload_json, '$.stars'), 0)) AS total_stars,
        SUM(COALESCE(json_extract(payload_json, '$.collisions'), 0)) AS total_collisions,
        SUM(COALESCE(json_extract(payload_json, '$.difficulty'), 0)) AS total_difficulty,
        AVG(COALESCE(json_extract(payload_json, '$.progress'), 0)) AS avg_progress,
        AVG(COALESCE(json_extract(payload_json, '$.time_seconds'), 0)) AS avg_time,
        MAX(received_at) AS last_seen
      FROM telemetry_events
      WHERE event_type = 'run_end' AND received_at >= ? AND json_valid(payload_json)
      GROUP BY platform, level_id, custom
      ORDER BY level_id ASC
    `).all(sinceIso);

    const collisionByType = this.db.prepare(`
      SELECT COALESCE(json_extract(payload_json, '$.obstacle_type'), 'unknown') AS type,
             COUNT(*) AS count
      FROM telemetry_events
      WHERE event_type = 'collision' AND received_at >= ? AND json_valid(payload_json)
      GROUP BY type ORDER BY count DESC
    `).all(sinceIso);

    const collisionByMotion = this.db.prepare(`
      SELECT COALESCE(json_extract(payload_json, '$.motion_type'), 'unknown') AS type,
             COUNT(*) AS count
      FROM telemetry_events
      WHERE event_type = 'collision' AND received_at >= ? AND json_valid(payload_json)
      GROUP BY type ORDER BY count DESC
    `).all(sinceIso);

    const collisionBinsRaw = this.db.prepare(`
      SELECT
        CASE
          WHEN COALESCE(json_extract(payload_json, '$.track_progress'), 0) <= 0 THEN 0
          WHEN COALESCE(json_extract(payload_json, '$.track_progress'), 0) >= 0.999 THEN ${BIN_COUNT - 1}
          ELSE CAST(COALESCE(json_extract(payload_json, '$.track_progress'), 0) * ${BIN_COUNT} AS INTEGER)
        END AS bin,
        COUNT(*) AS count
      FROM telemetry_events
      WHERE event_type = 'collision' AND received_at >= ? AND json_valid(payload_json)
      GROUP BY bin ORDER BY bin ASC
    `).all(sinceIso);

    const collisionByLevel = this.db.prepare(`
      SELECT level_id, level_name, COUNT(*) AS count
      FROM telemetry_events
      WHERE event_type = 'collision' AND received_at >= ? AND json_valid(payload_json)
      GROUP BY level_id ORDER BY count DESC
    `).all(sinceIso);

    const failureBinsRaw = this.db.prepare(`
      SELECT
        CASE
          WHEN COALESCE(json_extract(payload_json, '$.progress'), 0) <= 0 THEN 0
          WHEN COALESCE(json_extract(payload_json, '$.progress'), 0) >= 0.999 THEN ${BIN_COUNT - 1}
          ELSE CAST(COALESCE(json_extract(payload_json, '$.progress'), 0) * ${BIN_COUNT} AS INTEGER)
        END AS bin,
        COUNT(*) AS count
      FROM telemetry_events
      WHERE event_type = 'run_end'
        AND received_at >= ?
        AND json_valid(payload_json)
        AND ${completedExpr()} = 0
      GROUP BY bin ORDER BY bin ASC
    `).all(sinceIso);

    const enterRows = this.db.prepare(`
      SELECT level_id, level_name,
             COUNT(*) AS enters,
             COUNT(DISTINCT ${playerExpr()}) AS players,
             MAX(received_at) AS last_seen
      FROM telemetry_events
      WHERE event_type = 'enter_custom_level' AND received_at >= ? AND json_valid(payload_json)
      GROUP BY level_id ORDER BY enters DESC
    `).all(sinceIso);

    const dailyRows = this.db.prepare(`
      SELECT
        substr(received_at, 1, 10) AS day,
        SUM(CASE WHEN event_type = 'run_end' THEN 1 ELSE 0 END) AS runs,
        SUM(CASE WHEN event_type = 'run_end' AND ${completedExpr()} = 1 THEN 1 ELSE 0 END) AS completed,
        SUM(CASE WHEN event_type = 'collision' THEN 1 ELSE 0 END) AS collisions,
        COUNT(DISTINCT CASE WHEN event_type = 'run_end' THEN ${playerExpr()} END) AS players
      FROM telemetry_events
      WHERE received_at >= ? AND json_valid(payload_json)
      GROUP BY day ORDER BY day ASC
    `).all(sinceIso);

    const currentKpi = this.db.prepare(`
      SELECT
        SUM(CASE WHEN event_type = 'run_end' THEN 1 ELSE 0 END) AS runs,
        SUM(CASE WHEN event_type = 'run_end' AND ${completedExpr()} = 1 THEN 1 ELSE 0 END) AS completed,
        SUM(CASE WHEN event_type = 'collision' THEN 1 ELSE 0 END) AS collisions,
        COUNT(DISTINCT CASE WHEN event_type IN ('run_end', 'enter_custom_level', 'collision') THEN ${playerExpr()} END) AS players,
        COUNT(DISTINCT CASE WHEN event_type = 'run_end' THEN json_extract(payload_json, '$.session_id') END) AS sessions,
        SUM(CASE WHEN event_type = 'run_end' AND ${completedExpr()} = 1 THEN COALESCE(json_extract(payload_json, '$.time_seconds'), 0) ELSE 0 END) AS completed_time,
        SUM(CASE WHEN event_type = 'run_end' AND ${completedExpr()} = 1 THEN COALESCE(json_extract(payload_json, '$.stars'), 0) ELSE 0 END) AS completed_stars,
        SUM(CASE WHEN event_type = 'run_end' THEN COALESCE(json_extract(payload_json, '$.lost_passengers'), 0) ELSE 0 END) AS lost_passengers,
        SUM(CASE WHEN event_type = 'run_end' THEN COALESCE(json_extract(payload_json, '$.passengers'), 0) ELSE 0 END) AS saved_passengers,
        COUNT(*) AS total_events
      FROM telemetry_events
      WHERE received_at >= ? AND json_valid(payload_json)
    `).get(sinceIso);

    const previousKpi = this.db.prepare(`
      SELECT
        SUM(CASE WHEN event_type = 'run_end' THEN 1 ELSE 0 END) AS runs,
        SUM(CASE WHEN event_type = 'run_end' AND ${completedExpr()} = 1 THEN 1 ELSE 0 END) AS completed,
        SUM(CASE WHEN event_type = 'collision' THEN 1 ELSE 0 END) AS collisions,
        COUNT(DISTINCT CASE WHEN event_type IN ('run_end', 'enter_custom_level', 'collision') THEN ${playerExpr()} END) AS players,
        SUM(CASE WHEN event_type = 'run_end' AND ${completedExpr()} = 1 THEN COALESCE(json_extract(payload_json, '$.time_seconds'), 0) ELSE 0 END) AS completed_time
      FROM telemetry_events
      WHERE received_at >= ? AND received_at < ? AND json_valid(payload_json)
    `).get(previousSinceIso, sinceIso);

    const ugcRows = this.db.prepare(`
      SELECT id, name, author_name, platform, difficulty, plays, likes, favorites,
             review_status, created_at, updated_at
      FROM ugc_levels
      ORDER BY created_at DESC
    `).all();

    const ugcRuns = this.db.prepare(`
      SELECT level_id, level_name,
             COUNT(*) AS runs,
             SUM(${completedExpr()}) AS completed,
             SUM(COALESCE(json_extract(payload_json, '$.time_seconds'), 0)) AS total_time,
             AVG(COALESCE(json_extract(payload_json, '$.progress'), 0)) AS avg_progress,
             MAX(received_at) AS last_seen
      FROM telemetry_events
      WHERE event_type = 'run_end' AND custom = 1 AND received_at >= ? AND json_valid(payload_json)
      GROUP BY level_id
    `).all(sinceIso);

    const recentRows = this.db.prepare(`
      SELECT platform, level_id, level_name, custom, received_at, payload_json
      FROM telemetry_events
      WHERE event_type = 'run_end' AND received_at >= ? AND json_valid(payload_json)
      ORDER BY received_at DESC LIMIT 12
    `).all(sinceIso);

    const eventCounts = this.db.prepare(`
      SELECT event_type, COUNT(*) AS count
      FROM telemetry_events
      WHERE received_at >= ?
      GROUP BY event_type
    `).all(sinceIso);

    // ---------- 运行级聚合 ----------
    const mainLevels = new Map();
    const platformMap = new Map();
    const levelCollisionMap = new Map();
    let runTotal = 0;
    let completedTotal = 0;
    let mainlineRuns = 0;
    let ugcRunsTotal = 0;
    let currentCompletedTime = 0;
    let currentCompletedStars = 0;
    let totalPassengers = 0;
    let totalLost = 0;
    let totalPayloadCollisions = 0;

    for (const row of runRows) {
      const runs = number(row.runs);
      const completed = number(row.completed);
      runTotal += runs;
      completedTotal += completed;
      currentCompletedTime += number(row.total_time);
      currentCompletedStars += number(row.total_stars);
      totalPassengers += number(row.total_passengers);
      totalLost += number(row.total_lost);
      totalPayloadCollisions += number(row.total_collisions);

      const platformKey = row.platform || "unknown";
      if (!platformMap.has(platformKey)) {
        platformMap.set(platformKey, {
          id: platformKey, runs: 0, completed: 0, total_time: 0, total_stars: 0,
        });
      }
      const platform = platformMap.get(platformKey);
      platform.runs += runs;
      platform.completed += completed;
      platform.total_time += number(row.total_time);
      platform.total_stars += number(row.total_stars);

      if (Number(row.custom) === 1) {
        ugcRunsTotal += runs;
        continue;
      }
      mainlineRuns += runs;
      const key = row.level_id || "unknown";
      if (!mainLevels.has(key)) {
        mainLevels.set(key, {
          level_id: key,
          name: row.level_name || key,
          runs: 0,
          completed: 0,
          total_time: 0,
          total_stars: 0,
          total_difficulty: 0,
          collisions: 0,
          total_lost: 0,
          avg_progress: 0,
        });
      }
      const level = mainLevels.get(key);
      level.runs += runs;
      level.completed += completed;
      level.total_time += number(row.total_time);
      level.total_stars += number(row.total_stars);
      level.total_difficulty += number(row.total_difficulty);
      level.collisions += number(row.total_collisions);
      level.total_lost += number(row.total_lost);
      level.avg_progress += number(row.avg_progress) * runs;
    }

    const mainLevelList = [...mainLevels.values()].map((level) => ({
      level_id: level.level_id,
      name: level.name,
      runs: level.runs,
      completed: level.completed,
      failed: level.runs - level.completed,
      completion_rate: round(percent(level.completed, level.runs)),
      avg_time: level.completed ? round(level.total_time / level.completed) : 0,
      avg_stars: level.completed ? round(level.total_stars / level.completed) : 0,
      avg_difficulty: level.runs ? round(level.total_difficulty / level.runs) : 0,
      collisions: level.collisions,
      lost_passengers: level.total_lost,
      avg_progress: level.runs ? round(level.avg_progress / level.runs, 3) : 0,
    })).sort((a, b) => a.level_id.localeCompare(b.level_id));

    for (const row of collisionByLevel) {
      levelCollisionMap.set(row.level_id || "unknown", number(row.count));
    }

    const platforms = [...platformMap.values()].map((platform) => ({
      id: platform.id,
      runs: platform.runs,
      completed: platform.completed,
      completion_rate: round(percent(platform.completed, platform.runs)),
      avg_time: platform.completed ? round(platform.total_time / platform.completed) : 0,
      avg_stars: platform.completed ? round(platform.total_stars / platform.completed) : 0,
      share: round(percent(platform.runs, runTotal)),
      players: number(platform.players),
    })).sort((a, b) => b.runs - a.runs);

    // 平台玩家数来自单独查询，补回 rows。
    const platformPlayerRows = this.db.prepare(`
      SELECT platform, COUNT(DISTINCT ${playerExpr()}) AS players
      FROM telemetry_events
      WHERE event_type = 'run_end' AND received_at >= ? AND json_valid(payload_json)
      GROUP BY platform
    `).all(sinceIso);
    const platformPlayers = new Map(platformPlayerRows.map((row) => [row.platform, number(row.players)]));
    for (const platform of platforms) {
      platform.players = platformPlayers.get(platform.id) || 0;
    }

    // ---------- 每日趋势 ----------
    const dailyMap = new Map(dailyRows.map((row) => [row.day, row]));
    const trend = dayKeys(since, now).slice(-normalizedDays).map((day) => {
      const row = dailyMap.get(day) || {};
      return {
        date: day,
        runs: number(row.runs),
        completed: number(row.completed),
        failures: number(row.runs) - number(row.completed),
        completion_rate: round(percent(row.completed, row.runs)),
        collisions: number(row.collisions),
        players: number(row.players),
      };
    });

    // ---------- 卡点 ----------
    const collisionBins = Array.from({ length: BIN_COUNT }, (_, index) => ({ bin: index, count: 0 }));
    for (const row of collisionBinsRaw) {
      if (row.bin >= 0 && row.bin < BIN_COUNT) {
        collisionBins[row.bin].count = number(row.count);
      }
    }
    const failureBins = Array.from({ length: BIN_COUNT }, (_, index) => ({ bin: index, count: 0 }));
    for (const row of failureBinsRaw) {
      if (row.bin >= 0 && row.bin < BIN_COUNT) {
        failureBins[row.bin].count = number(row.count);
      }
    }
    const progressBins = collisionBins.map((item, index) => ({
      index,
      from: index * (100 / BIN_COUNT),
      to: (index + 1) * (100 / BIN_COUNT),
      label: `${Math.round(index * (100 / BIN_COUNT))}-${Math.round((index + 1) * (100 / BIN_COUNT))}%`,
      collisions: item.count,
      failures: failureBins[index].count,
      score: item.count + failureBins[index].count * 2,
    }));

    const chokeLevels = [...mainLevelList, ...buildUgcChokeLevels(ugcRows, ugcRuns, enterRows, collisionByLevel)]
      .map((level) => {
        const failed = number(level.failed);
        const collisions = number(level.collisions || levelCollisionMap.get(level.level_id) || 0);
        return {
          level_id: level.level_id,
          name: level.name,
          custom: Boolean(level.custom),
          runs: number(level.runs),
          completion_rate: round(number(level.completion_rate)),
          failed,
          collisions,
          score: failed * 2 + collisions,
        };
      })
      .filter((level) => level.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, 8);

    // ---------- UGC ----------
    const ugc = buildUgcDashboard({ ugcRows, ugcRuns, enterRows, collisionByLevel, binCount: BIN_COUNT });

    // ---------- KPI ----------
    const kpis = {
      runs: number(currentKpi.runs),
      completed: number(currentKpi.completed),
      completion_rate: round(percent(currentKpi.completed, currentKpi.runs)),
      unique_players: number(currentKpi.players),
      sessions: number(currentKpi.sessions),
      collisions: number(currentKpi.collisions),
      collisions_per_run: round(number(currentKpi.collisions) / Math.max(1, number(currentKpi.runs))),
      avg_time: number(currentKpi.completed) ? round(number(currentKpi.completed_time) / number(currentKpi.completed)) : 0,
      avg_stars: number(currentKpi.completed) ? round(number(currentKpi.completed_stars) / number(currentKpi.completed)) : 0,
      lost_passengers: number(currentKpi.lost_passengers),
      saved_passengers: number(currentKpi.saved_passengers),
      total_events: number(currentKpi.total_events),
      mainline_runs: mainlineRuns,
      ugc_runs: ugcRunsTotal,
      active_levels: mainLevelList.filter((level) => level.runs > 0).length,
    };

    const prev = {
      runs: number(previousKpi.runs),
      completed: number(previousKpi.completed),
      completion_rate: round(percent(previousKpi.completed, previousKpi.runs)),
      unique_players: number(previousKpi.players),
      collisions: number(previousKpi.collisions),
      avg_time: number(previousKpi.completed) ? number(previousKpi.completed_time) / number(previousKpi.completed) : 0,
    };
    const deltas = {
      runs: round(pctChange(kpis.runs, prev.runs), 1),
      completion_rate: round(kpis.completion_rate - prev.completion_rate, 1),
      unique_players: round(pctChange(kpis.unique_players, prev.unique_players), 1),
      collisions: round(pctChange(kpis.collisions, prev.collisions), 1),
      avg_time: round(pctChange(kpis.avg_time, prev.avg_time), 1),
    };

    // ---------- 实时事件流 ----------
    const recentRuns = recentRows.map((row) => {
      const payload = safeJson(row.payload_json);
      return {
        level_id: row.level_id,
        level_name: row.level_name || row.level_id,
        platform: row.platform,
        custom: Boolean(row.custom),
        completed: Boolean(payload.completed),
        passengers: number(payload.passengers),
        starting_passengers: number(payload.starting_passengers),
        time_seconds: number(payload.time_seconds),
        stars: number(payload.stars),
        collisions: number(payload.collisions),
        progress: number(payload.progress),
        received_at: row.received_at,
      };
    });

    const typeRows = collisionByType.map((row) => ({ id: row.type, count: number(row.count) }));
    const motionRows = collisionByMotion.map((row) => ({ id: row.type, count: number(row.count) }));
    const collisionTotal = number(currentKpi.collisions);

    return {
      ok: true,
      days: normalizedDays,
      generated_at: now.toISOString(),
      range: { from: sinceIso, to: now.toISOString() },
      kpis,
      previous: prev,
      deltas,
      trend,
      platforms,
      main_levels: mainLevelList,
      collisions: {
        total: collisionTotal,
        payload_collisions: totalPayloadCollisions,
        by_type: typeRows,
        by_motion: motionRows,
        progress_bins: progressBins,
        by_level: [...levelCollisionMap.entries()]
          .map(([level_id, count]) => ({ level_id, count }))
          .sort((a, b) => b.count - a.count),
      },
      choke_levels: chokeLevels,
      ugc,
      recent_runs: recentRuns,
      event_counts: Object.fromEntries(eventCounts.map((row) => [row.event_type, number(row.count)])),
      passengers: {
        saved: totalPassengers,
        lost: totalLost,
        saved_ratio: round(percent(totalPassengers, totalPassengers + totalLost)),
      },
    };
  }
}

function buildUgcChokeLevels(ugcRows, ugcRuns, enterRows, collisionByLevel) {
  const runsMap = new Map(ugcRuns.map((row) => [row.level_id, row]));
  const enterMap = new Map(enterRows.map((row) => [row.level_id, row]));
  const collisionMap = new Map(collisionByLevel.map((row) => [row.level_id, number(row.count)]));
  return ugcRows.map((row) => {
    const run = runsMap.get(row.id) || {};
    const enter = enterMap.get(row.id) || {};
    const runs = number(run.runs);
    const completed = number(run.completed);
    return {
      level_id: row.id,
      name: row.name,
      custom: true,
      runs,
      completed,
      failed: runs - completed,
      completion_rate: percent(completed, runs),
      collisions: collisionMap.get(row.id) || 0,
      enters: number(enter.enters),
    };
  });
}

function buildUgcDashboard({ ugcRows, ugcRuns, enterRows, collisionByLevel, binCount }) {
  const runsMap = new Map(ugcRuns.map((row) => [row.level_id, row]));
  const enterMap = new Map(enterRows.map((row) => [row.level_id, row]));
  const collisionMap = new Map(collisionByLevel.map((row) => [row.level_id, number(row.count)]));
  const levels = ugcRows.map((row) => {
    const run = runsMap.get(row.id) || {};
    const enter = enterMap.get(row.id) || {};
    const runs = number(run.runs);
    const completed = number(run.completed);
    const enters = number(enter.enters);
    const baseEnters = enters > 0 ? enters : runs;
    const plays = number(row.plays);
    const likes = number(row.likes);
    const favorites = number(row.favorites);
    return {
      level_id: row.id,
      name: row.name,
      author_name: row.author_name,
      platform: row.platform,
      difficulty: number(row.difficulty),
      review_status: row.review_status,
      created_at: row.created_at,
      plays,
      likes,
      favorites,
      enters,
      runs,
      completed,
      failed: runs - completed,
      collisions: collisionMap.get(row.id) || 0,
      completion_rate: round(percent(completed, runs)),
      churn_rate: round(percent(Math.max(0, baseEnters - completed), baseEnters)),
      fail_rate: round(percent(runs - completed, runs)),
      quit_rate: round(percent(Math.max(0, enters - runs), enters)),
      avg_time: completed ? round(number(run.total_time) / completed) : 0,
      avg_progress: round(number(run.avg_progress), 3),
      engagement: plays + likes * 4 + favorites * 6,
      heat_raw: Math.log1p(plays) * 0.34 + Math.log1p(Math.max(enters, runs)) * 0.30
        + Math.log1p(likes) * 0.22 + Math.log1p(favorites) * 0.14,
    };
  });

  // 热度归一化到 0-100，避免不同量级 UGC 在同一张散点图上不可读。
  const maxHeat = Math.max(1, ...levels.map((level) => level.heat_raw));
  for (const level of levels) {
    level.heat_score = Math.round((level.heat_raw / maxHeat) * 100);
    delete level.heat_raw;
  }
  levels.sort((a, b) => b.heat_score - a.heat_score);

  const totalEnters = levels.reduce((sum, level) => sum + level.enters, 0);
  const totalRuns = levels.reduce((sum, level) => sum + level.runs, 0);
  const totalCompleted = levels.reduce((sum, level) => sum + level.completed, 0);
  const totalPlays = levels.reduce((sum, level) => sum + level.plays, 0);
  const totalLikes = levels.reduce((sum, level) => sum + level.likes, 0);
  const totalFavorites = levels.reduce((sum, level) => sum + level.favorites, 0);
  const baseEnters = totalEnters > 0 ? totalEnters : totalRuns;

  const platformMap = new Map();
  for (const level of levels) {
    const key = level.platform || "unknown";
    if (!platformMap.has(key)) {
      platformMap.set(key, { id: key, levels: 0, plays: 0, likes: 0, runs: 0 });
    }
    const platform = platformMap.get(key);
    platform.levels += 1;
    platform.plays += level.plays;
    platform.likes += level.likes;
    platform.runs += level.runs;
  }

  return {
    levels,
    top_heat: levels.slice(0, 8),
    funnel: {
      enters: totalEnters,
      plays: totalPlays,
      runs: totalRuns,
      completed: totalCompleted,
      likes: totalLikes,
      favorites: totalFavorites,
      enter_to_run_rate: round(percent(totalRuns, totalEnters)),
      completion_rate: round(percent(totalCompleted, totalRuns)),
      churn_rate: round(percent(Math.max(0, baseEnters - totalCompleted), baseEnters)),
    },
    platforms: [...platformMap.values()].sort((a, b) => b.plays - a.plays),
    totals: {
      levels: levels.length,
      plays: totalPlays,
      likes: totalLikes,
      favorites: totalFavorites,
      runs: totalRuns,
      completed: totalCompleted,
      churn_rate: round(percent(Math.max(0, baseEnters - totalCompleted), baseEnters)),
    },
    bin_count: binCount,
  };
}

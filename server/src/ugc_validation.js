/**
 * UGC 关卡与遥测数据的服务端校验 / 规范化。
 *
 * 原则：
 * - 客户端上传的任何字段都不可信，只保留白名单字段；
 * - 所有数字必须有限且落在玩法可承受的范围内；
 * - 关卡正文按 2MB 上限拦截，防止恶意大包拖垮内存与数据库；
 * - 输出结构与 Godot 的 LevelData / TrackGeometry 保持一致。
 */

import crypto from "node:crypto";

export const MAX_LEVEL_BYTES = 2 * 1024 * 1024;
export const MAX_TELEMETRY_BYTES = 32 * 1024;
export const MAX_PIECES = 300;
export const MAX_OBSTACLES = 500;
export const MAX_TRACK_LENGTH = 120_000;
export const MIN_TRACK_LENGTH = 400;

const PIECE_TYPES = new Set(["straight", "arc", "curve", "loop"]);
const OBSTACLE_PREFABS = new Set([
  "bird", "crate", "barrier", "hot_air_balloon", "ferris_wheel",
  "large_ferris_wheel", "caterpillar", "vine", "venus_flytrap",
  "snow_elf", "ice_crystal", "storm", "fan", "flying_bird", "flying_fish",
  "meteor", "dream_elf", "bubble", "cannonball", "dream_void",
]);
const BACKGROUNDS = new Set(["paradise", "forest", "snow", "clouds", "dream"]);
const MOTION_TYPES = new Set(["static", "oscillate_x", "oscillate_y", "circle", "ellipse"]);
const PLATFORMS = new Set([
  "windows", "android", "ios", "web", "wechat", "douyin", "linux", "macos", "unknown",
]);
const TELEMETRY_TYPES = new Set(["run_end", "enter_custom_level", "collision"]);
const COLOR_KEYS = [
  "sky_top", "sky_bottom", "mountain_far", "mountain_near",
  "track", "track_highlight", "accent", "tint",
];

export class ValidationError extends Error {
  constructor(code, message, status = 400) {
    super(message);
    this.name = "ValidationError";
    this.code = code;
    this.status = status;
  }
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requireObject(value, code, label) {
  if (!isPlainObject(value)) {
    throw new ValidationError(code, `${label}必须是对象`);
  }
  return value;
}

function asNumber(value, fallback, min, max, label) {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }
  const number = Number(value);
  if (!Number.isFinite(number)) {
    throw new ValidationError("invalid_number", `${label}必须是有限数字`);
  }
  if (number < min || number > max) {
    throw new ValidationError("number_out_of_range", `${label}超出允许范围 ${min}..${max}`);
  }
  return number;
}

function asText(value, fallback, maxLength, label, { required = false, multiline = false } = {}) {
  let text = value === undefined || value === null ? fallback : String(value);
  text = text
    .replace(/\r\n?/g, "\n")
    .replace(multiline ? /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g : /[\u0000-\u001F\u007F]/g, "")
    .trim();
  if (required && text.length === 0) {
    throw new ValidationError("missing_text", `${label}不能为空`);
  }
  if ([...text].length > maxLength) {
    throw new ValidationError("text_too_long", `${label}不能超过 ${maxLength} 个字符`);
  }
  return text;
}

function point(value, label, max = 1_000_000) {
  if (value === undefined || value === null) {
    return null;
  }
  let x;
  let y;
  if (Array.isArray(value) && value.length >= 2) {
    x = value[0];
    y = value[1];
  } else if (isPlainObject(value)) {
    x = value.x;
    y = value.y;
  } else {
    throw new ValidationError("invalid_point", `${label}必须是 {x,y} 或 [x,y]`);
  }
  const nx = asNumber(x, null, -max, max, `${label}.x`);
  const ny = asNumber(y, null, -max, max, `${label}.y`);
  if (nx === null || ny === null) {
    throw new ValidationError("invalid_point", `${label}缺少 x 或 y`);
  }
  return [round(nx), round(ny)];
}

function pointObject(value, label, max = 1_000_000) {
  const pointValue = point(value, label, max);
  return pointValue === null ? null : { x: pointValue[0], y: pointValue[1] };
}

function round(value) {
  return Math.round(Number(value) * 1000) / 1000;
}

function bool(value, fallback = false) {
  return value === undefined || value === null ? fallback : Boolean(value);
}

function color(value, label) {
  if (typeof value !== "string" || !/^#[0-9a-fA-F]{6}$/.test(value)) {
    throw new ValidationError("invalid_color", `${label}必须是 #RRGGBB`);
  }
  return value.toLowerCase();
}

function normalizePiece(raw, index, headingState) {
  const piece = requireObject(raw, "invalid_track_piece", `轨道片段 #${index}`);
  const type = String(piece.type || "straight");
  if (!PIECE_TYPES.has(type)) {
    throw new ValidationError("invalid_track_piece", `轨道片段 #${index} 类型无效`);
  }
  const normalized = { type: type === "curve" ? "arc" : type };
  const origin = point(piece.origin, `轨道片段 #${index}.origin`);
  if (origin !== null) {
    if (headingState.havePoint) {
      headingState.total += Math.hypot(
        origin[0] - headingState.x,
        origin[1] - headingState.y,
      );
    }
    headingState.x = origin[0];
    headingState.y = origin[1];
    headingState.havePoint = true;
    normalized.origin = origin;
    normalized.heading_deg = round(
      asNumber(piece.heading_deg, 0, -3600, 3600, `轨道片段 #${index}.heading_deg`),
    );
    headingState.heading = (normalized.heading_deg * Math.PI) / 180;
  } else if (!headingState.havePoint) {
    headingState.havePoint = true;
    headingState.x = 0;
    headingState.y = 0;
  }

  const direction = asNumber(piece.direction, 1, -1, 1, `轨道片段 #${index}.direction`);
  normalized.direction = direction < 0 ? -1 : 1;
  if (bool(piece.direction_anchor, false)) {
    normalized.direction_anchor = true;
  }
  const breakAfter = asNumber(piece.break_after, 0, 0, 60, `轨道片段 #${index}.break_after`);
  if (breakAfter > 0) {
    normalized.break_after = round(breakAfter);
  }

  if (normalized.type === "straight") {
    const length = asNumber(piece.length, 240, 0, 100_000, `轨道片段 #${index}.length`);
    normalized.length = round(length);
    headingState.x += Math.cos(headingState.heading) * length;
    headingState.y += Math.sin(headingState.heading) * length;
    headingState.total += length;
    return normalized;
  }

  const radius = asNumber(piece.radius, normalized.type === "loop" ? 90 : 120, 4, 10_000, `轨道片段 #${index}.radius`);
  let angle = asNumber(
    piece.angle,
    normalized.type === "loop" ? -360 : -90,
    -3600,
    3600,
    `轨道片段 #${index}.angle`,
  );
  if (normalized.type === "arc" && Math.abs(angle) < 0.01) {
    angle = -90;
  }
  normalized.radius = round(radius);
  normalized.angle = round(angle);
  const radians = (angle * Math.PI) / 180;
  const localX = radius * Math.sin(radians);
  const localY = radius * (1 - Math.cos(radians));
  const cos = Math.cos(headingState.heading);
  const sin = Math.sin(headingState.heading);
  headingState.x += localX * cos - localY * sin;
  headingState.y += localX * sin + localY * cos;
  headingState.heading += radians;
  headingState.total += radius * Math.abs(radians);
  return normalized;
}

function normalizeTrack(raw) {
  const track = requireObject(raw, "invalid_track", "track");
  const piecesInput = track.pieces;
  if (!Array.isArray(piecesInput) || piecesInput.length === 0) {
    throw new ValidationError("invalid_track", "track.pieces 至少需要一个片段");
  }
  if (piecesInput.length > MAX_PIECES) {
    throw new ValidationError("too_many_pieces", `轨道片段不能超过 ${MAX_PIECES} 个`);
  }
  const headingState = { heading: 0, x: 0, y: 0, havePoint: false, total: 0 };
  const startAngle = asNumber(track.start_angle_deg, 0, -3600, 3600, "track.start_angle_deg");
  headingState.heading = (startAngle * Math.PI) / 180;
  const pieces = piecesInput.map((piece, index) => normalizePiece(piece, index, headingState));
  const total = headingState.total;
  if (total < MIN_TRACK_LENGTH) {
    throw new ValidationError("track_too_short", `轨道总长度至少 ${MIN_TRACK_LENGTH}px`);
  }
  if (total > MAX_TRACK_LENGTH) {
    throw new ValidationError("track_too_long", `轨道总长度不能超过 ${MAX_TRACK_LENGTH}px`);
  }
  // 服务端的弧长是几何近似值；客户端用 Godot 采样得到的精确值可能略大。
  // 允许 5% + 200px 的误差，既不放宽玩法边界，也避免误杀合法关卡。
  const tolerance = total * 0.05 + 200;
  const startS = asNumber(track.start_s, 60, 0, total + tolerance, "track.start_s");
  const finishS = asNumber(track.finish_s, total - 100, 0, total + tolerance, "track.finish_s");
  if (Math.abs(finishS - startS) < 100) {
    throw new ValidationError("start_finish_too_close", "起点与终点距离至少 100px");
  }
  return {
    start_angle_deg: round(startAngle),
    pieces,
    start_s: round(startS),
    finish_s: round(finishS),
    total_length: round(total),
  };
}

function normalizeObstacle(raw, index, totalLength) {
  const obstacle = requireObject(raw, "invalid_obstacle", `障碍 #${index}`);
  const prefab = String(obstacle.prefab || obstacle.type || "");
  if (!OBSTACLE_PREFABS.has(prefab)) {
    throw new ValidationError("invalid_obstacle", `障碍 #${index} 的 prefab 无效`);
  }
  if (obstacle.s === undefined || obstacle.s === null || obstacle.s === "") {
    throw new ValidationError("invalid_obstacle", `障碍 #${index} 缺少轨道位置 s`);
  }
  const normalized = {
    prefab,
    s: round(asNumber(obstacle.s, null, 0, totalLength + totalLength * 0.05 + 200, `障碍 #${index}.s`)),
    offset: pointObject(obstacle.offset, `障碍 #${index}.offset`, 100_000) || { x: 0, y: 0 },
    flip_x: bool(obstacle.flip_x, false),
  };
  if (obstacle.motion !== undefined && obstacle.motion !== null) {
    const motion = requireObject(obstacle.motion, "invalid_motion", `障碍 #${index}.motion`);
    const motionType = String(motion.type || "static");
    if (!MOTION_TYPES.has(motionType)) {
      throw new ValidationError("invalid_motion", `障碍 #${index} 的运动类型无效`);
    }
    normalized.motion = {
      type: motionType,
      amplitude: pointObject(motion.amplitude, `障碍 #${index}.motion.amplitude`, 5000) || { x: 0, y: 0 },
      speed: round(asNumber(motion.speed, 0, 0, 100, `障碍 #${index}.motion.speed`)),
      phase: round(asNumber(motion.phase, 0, -1000, 1000, `障碍 #${index}.motion.phase`)),
    };
  }
  if (obstacle.radius !== undefined) {
    normalized.radius = round(asNumber(obstacle.radius, 26, 8, 2000, `障碍 #${index}.radius`));
  }
  if (obstacle.damage !== undefined) {
    normalized.damage = Math.trunc(asNumber(obstacle.damage, 1, 1, 99, `障碍 #${index}.damage`));
  }
  if (Array.isArray(obstacle.collision_offsets)) {
    normalized.collision_offsets = obstacle.collision_offsets
      .slice(0, 8)
      .map((value, offsetIndex) => pointObject(value, `障碍 #${index}.collision_offsets[${offsetIndex}]`, 5000) || { x: 0, y: 0 });
  }
  if (Array.isArray(obstacle.collision_radii)) {
    normalized.collision_radii = obstacle.collision_radii
      .slice(0, 8)
      .map((value, radiusIndex) => round(asNumber(value, 26, 4, 2000, `障碍 #${index}.collision_radii[${radiusIndex}]`)));
  }
  if (obstacle.interval_enabled !== undefined) {
    normalized.interval_enabled = bool(obstacle.interval_enabled, false);
    normalized.interval_period = round(asNumber(obstacle.interval_period, 2, 0.2, 60, `障碍 #${index}.interval_period`));
    normalized.interval_active = round(asNumber(
      obstacle.interval_active,
      1.2,
      0.05,
      normalized.interval_period,
      `障碍 #${index}.interval_active`,
    ));
  }
  if (obstacle.trigger_enabled !== undefined) {
    normalized.trigger_enabled = bool(obstacle.trigger_enabled, false);
  }
  if (obstacle.clockwise !== undefined) {
    normalized.clockwise = bool(obstacle.clockwise, false);
  }
  return normalized;
}

function normalizeTheme(raw) {
  if (raw === undefined || raw === null) {
    return undefined;
  }
  const theme = requireObject(raw, "invalid_theme", "theme");
  const clean = {};
  for (const key of COLOR_KEYS) {
    if (theme[key] !== undefined) {
      clean[key] = color(theme[key], `theme.${key}`);
    }
  }
  if (theme.tint_alpha !== undefined) {
    clean.tint_alpha = round(asNumber(theme.tint_alpha, 0, 0, 1, "theme.tint_alpha"));
  }
  if (theme.id !== undefined) {
    clean.id = asText(theme.id, "", 24, "theme.id");
  }
  return Object.keys(clean).length > 0 ? clean : undefined;
}

function normalizeCameraBounds(raw) {
  if (raw === undefined || raw === null) {
    return undefined;
  }
  const bounds = requireObject(raw, "invalid_camera_bounds", "camera_bounds");
  const width = asNumber(bounds.w ?? bounds.width, null, 64, 200_000, "camera_bounds.w");
  const height = asNumber(bounds.h ?? bounds.height, null, 64, 200_000, "camera_bounds.h");
  const x = asNumber(bounds.x, null, -1_000_000, 1_000_000, "camera_bounds.x");
  const y = asNumber(bounds.y, null, -1_000_000, 1_000_000, "camera_bounds.y");
  if (width === null || height === null || x === null || y === null) {
    throw new ValidationError("invalid_camera_bounds", "camera_bounds 缺少 x/y/w/h");
  }
  return { x: round(x), y: round(y), w: round(width), h: round(height) };
}

/**
 * 把客户端关卡规范化成可入库、可被 Godot 重新导入的结构。
 * 返回值包含 total_length 仅用于服务端校验，落库前会删掉。
 */
export function normalizeLevel(raw) {
  const level = requireObject(raw, "invalid_level", "level_data");
  const track = normalizeTrack(level.track);
  const totalLength = track.total_length;
  delete track.total_length;

  const obstaclesInput = level.obstacles === undefined ? [] : level.obstacles;
  if (!Array.isArray(obstaclesInput)) {
    throw new ValidationError("invalid_obstacles", "obstacles 必须是数组");
  }
  if (obstaclesInput.length > MAX_OBSTACLES) {
    throw new ValidationError("too_many_obstacles", `障碍不能超过 ${MAX_OBSTACLES} 个`);
  }
  const obstacles = obstaclesInput.map((obstacle, index) => normalizeObstacle(obstacle, index, totalLength));

  const normalized = {
    schema_version: 2,
    id: asText(level.id, "", 64, "id"),
    name: asText(level.name, "未命名关卡", 48, "name", { required: true }),
    subtitle: asText(level.subtitle, "", 72, "subtitle", { multiline: true }),
    description: asText(level.description, "", 500, "description", { multiline: true }),
    difficulty: Math.trunc(asNumber(level.difficulty, 1, 1, 5, "difficulty")),
    par_time: round(asNumber(level.par_time, 60, 1, 3600, "par_time")),
    countdown_seconds: round(asNumber(level.countdown_seconds, 3, 0.5, 10, "countdown_seconds")),
    time_limit_seconds: round(asNumber(level.time_limit_seconds, 0, 0, 86_400, "time_limit_seconds")),
    background_id: BACKGROUNDS.has(String(level.background_id || "paradise"))
      ? String(level.background_id || "paradise")
      : "paradise",
    custom: true,
    source: "community",
    track,
    obstacles,
    analytics_tags: [],
  };

  const theme = normalizeTheme(level.theme);
  if (theme) {
    normalized.theme = theme;
  }
  const cameraBounds = normalizeCameraBounds(level.camera_bounds);
  if (cameraBounds) {
    normalized.camera_bounds = cameraBounds;
  }
  if (Array.isArray(level.analytics_tags)) {
    normalized.analytics_tags = level.analytics_tags
      .slice(0, 16)
      .map((tag, index) => asText(tag, "", 32, `analytics_tags[${index}]`))
      .filter((tag) => tag.length > 0);
  }
  return normalized;
}

export function normalizeUploadEnvelope(body) {
  const envelope = requireObject(body, "invalid_body", "请求体");
  const rawLevel = envelope.level_data ?? envelope.level;
  if (rawLevel === undefined) {
    throw new ValidationError("missing_level_data", "缺少 level_data");
  }
  const rawBytes = Buffer.byteLength(JSON.stringify(rawLevel), "utf8");
  if (rawBytes > MAX_LEVEL_BYTES) {
    throw new ValidationError("payload_too_large", "关卡数据不能超过 2MB", 413);
  }

  const level = normalizeLevel(rawLevel);
  const name = asText(
    envelope.name ?? level.name,
    level.name,
    48,
    "name",
    { required: true },
  );
  const authorName = asText(
    envelope.author_name ?? envelope.author,
    "游客",
    24,
    "author_name",
    { required: true },
  );
  const authorId = asText(envelope.author_id, "anonymous", 64, "author_id", { required: true });
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(authorId)) {
    throw new ValidationError("invalid_author_id", "author_id 只能包含字母、数字、下划线、点或短横线");
  }
  const platform = PLATFORMS.has(String(envelope.platform || "unknown"))
    ? String(envelope.platform || "unknown")
    : "unknown";
  const description = asText(
    envelope.description ?? level.description ?? level.subtitle,
    "",
    200,
    "description",
    { multiline: true },
  );

  level.id = ""; // 由服务端生成后再写入，绝不信任客户端 id。
  level.name = name;
  level.description = description;
  const canonicalBytes = Buffer.byteLength(JSON.stringify(level), "utf8");
  if (canonicalBytes > MAX_LEVEL_BYTES) {
    throw new ValidationError("payload_too_large", "关卡数据不能超过 2MB", 413);
  }

  // 内容指纹：只覆盖玩法内容，剔除 id/name/description/custom/source。
  // 改名或改简介不应被视为新关卡；指纹完全由服务端复算，绝不信任客户端传入值。
  const fingerprintSource = { ...level };
  delete fingerprintSource.id;
  delete fingerprintSource.name;
  delete fingerprintSource.description;
  delete fingerprintSource.custom;
  delete fingerprintSource.source;
  const contentHash = computeContentHash(fingerprintSource);

  return {
    name,
    authorName,
    authorId,
    platform,
    description,
    level,
    levelBytes: canonicalBytes,
    contentHash,
  };
}

/**
 * 递归按键名升序生成确定性紧凑 JSON 字符串。
 * 保证同一份关卡内容无论字段插入顺序如何都得到相同字节流，指纹因而稳定可复现。
 * 数组保序；数字/字符串/布尔/null 用 JSON.stringify 原样编码。
 */
function canonicalize(value) {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalize).join(",")}]`;
  }
  if (value !== null && typeof value === "object") {
    const keys = Object.keys(value).sort();
    const parts = keys.map((key) => `${JSON.stringify(key)}:${canonicalize(value[key])}`);
    return `{${parts.join(",")}}`;
  }
  return JSON.stringify(value);
}

/**
 * 计算关卡玩法内容的 SHA-256 指纹（64 位小写十六进制）。
 * 输入必须是 normalizeLevel 之后、且已剔除 id/name/description 等易变字段的字典。
 */
export function computeContentHash(level) {
  return crypto.createHash("sha256").update(canonicalize(level), "utf8").digest("hex");
}

export function assertPlatform(value) {
  const platform = String(value || "unknown");
  return PLATFORMS.has(platform) ? platform : "unknown";
}

export function normalizeTelemetry(body) {
  const envelope = requireObject(body, "invalid_telemetry", "遥测请求体");
  const eventType = String(envelope.event_type || envelope.type || "");
  if (!TELEMETRY_TYPES.has(eventType)) {
    throw new ValidationError("invalid_event_type", "不支持的遥测事件类型");
  }
  const platform = String(envelope.platform || "unknown");
  if (!PLATFORMS.has(platform)) {
    throw new ValidationError("invalid_platform", "platform 无效");
  }
  const payload = envelope.payload === undefined ? {} : envelope.payload;
  requireObject(payload, "invalid_payload", "payload");
  const payloadBytes = Buffer.byteLength(JSON.stringify(payload), "utf8");
  if (payloadBytes > MAX_TELEMETRY_BYTES) {
    throw new ValidationError("payload_too_large", "遥测 payload 不能超过 32KB", 413);
  }
  return {
    eventId: asText(envelope.event_id, "", 128, "event_id"),
    eventType,
    platform,
    levelId: asText(envelope.level_id, "", 64, "level_id"),
    levelName: asText(envelope.level_name, "", 64, "level_name"),
    mode: asText(envelope.mode, "", 16, "mode"),
    custom: bool(envelope.custom, false),
    clientTs: envelope.ts === undefined ? null : asNumber(envelope.ts, null, 0, 9_999_999_999, "ts"),
    payload,
  };
}

export const UGC_LIMITS = {
  MAX_LEVEL_BYTES,
  MAX_TELEMETRY_BYTES,
  MAX_PIECES,
  MAX_OBSTACLES,
  MAX_TRACK_LENGTH,
  MIN_TRACK_LENGTH,
};

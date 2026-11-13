export const PLATFORM_META = {
  windows: { label: "Windows", short: "PC", color: "#62b6ff", glyph: "⊞" },
  android: { label: "Android", short: "安卓", color: "#66e0c2", glyph: "◈" },
  ios: { label: "iOS", short: "iOS", color: "#d8b4fe", glyph: "" },
  web: { label: "Web", short: "Web", color: "#f7b267", glyph: "◎" },
  wechat: { label: "微信小游戏", short: "微信", color: "#34d399", glyph: "微" },
  linux: { label: "Linux", short: "Linux", color: "#facc15", glyph: "◐" },
  macos: { label: "macOS", short: "mac", color: "#c4b5fd", glyph: "◑" },
  unknown: { label: "未知端", short: "未知", color: "#94a3b8", glyph: "?" },
};

export const OBSTACLE_LABELS = {
  bird: "海鸥",
  crate: "木箱",
  barrier: "路障",
  storm: "风暴",
  fan: "风扇",
  caterpillar: "毛毛虫",
  meteor: "陨石",
  ferris_wheel: "摩天轮",
  unknown: "未知",
};

export function platform(id) {
  return PLATFORM_META[id] || PLATFORM_META.unknown;
}

export function obstacleLabel(id) {
  return OBSTACLE_LABELS[id] || id || "未知";
}

export function number(value, digits = 0) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return "0";
  return parsed.toLocaleString("zh-CN", {
    maximumFractionDigits: digits,
    minimumFractionDigits: 0,
  });
}

export function compact(value) {
  const numeric = Number(value) || 0;
  if (Math.abs(numeric) >= 10000) {
    return `${(numeric / 10000).toFixed(numeric >= 100000 ? 0 : 1)}w`;
  }
  if (Math.abs(numeric) >= 1000) {
    return `${(numeric / 1000).toFixed(1)}k`;
  }
  return number(numeric);
}

export function percent(value, digits = 1) {
  const numeric = Number(value);
  return `${Number.isFinite(numeric) ? numeric.toFixed(digits) : "0.0"}%`;
}

export function duration(seconds) {
  const total = Math.max(0, Math.round(Number(seconds) || 0));
  if (total < 60) return `${total}s`;
  const minutes = Math.floor(total / 60);
  const rest = total % 60;
  if (minutes < 60) return `${minutes}:${String(rest).padStart(2, "0")}`;
  const hours = Math.floor(minutes / 60);
  return `${hours}h ${String(minutes % 60).padStart(2, "0")}m`;
}

export function shortDate(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value || "";
  return `${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

export function relativeTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "刚刚";
  const seconds = Math.max(0, Math.round((Date.now() - date.getTime()) / 1000));
  if (seconds < 45) return "刚刚";
  if (seconds < 3600) return `${Math.floor(seconds / 60)} 分钟前`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} 小时前`;
  return `${Math.floor(seconds / 86400)} 天前`;
}

export function signedPercent(value) {
  const numeric = Number(value) || 0;
  const sign = numeric > 0 ? "+" : "";
  return `${sign}${numeric.toFixed(1)}%`;
}

export function deltaTone(value, inverse = false) {
  const numeric = Number(value) || 0;
  if (Math.abs(numeric) < 0.05) return "flat";
  const positive = inverse ? numeric < 0 : numeric > 0;
  return positive ? "up" : "down";
}

export function levelDisplayName(level) {
  return level?.name || level?.level_name || level?.level_id || "未命名关卡";
}

export function heatTone(value) {
  const numeric = Number(value) || 0;
  if (numeric >= 70) return "hot";
  if (numeric >= 40) return "warm";
  return "cool";
}

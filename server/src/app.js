import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import cors from "cors";
import express from "express";
import { UgcStore } from "./ugc_store.js";
import { TelemetryStore } from "./telemetry_store.js";
import {
  ValidationError,
  normalizeTelemetry,
  normalizeUploadEnvelope,
} from "./ugc_validation.js";

const PLATFORM_ID_RE = /^[A-Za-z0-9_.-]{1,64}$/;
const UGC_ID_RE = /^[A-Za-z0-9_-]{1,80}$/;

function base64url(value) {
  return Buffer.from(value).toString("base64url");
}

function signSession(openid, secret) {
  const expires = Math.floor(Date.now() / 1000) + 7 * 24 * 3600;
  const payload = base64url(JSON.stringify({ openid, expires }));
  const signature = crypto.createHmac("sha256", secret).update(payload).digest("base64url");
  return `${payload}.${signature}`;
}

function verifySession(token, secret) {
  if (typeof token !== "string" || !token.includes(".")) {
    return null;
  }
  const [payload, signature] = token.split(".");
  const expected = crypto.createHmac("sha256", secret).update(payload).digest("base64url");
  const a = Buffer.from(signature);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    return null;
  }
  try {
    const data = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
    if (!data.openid || Number(data.expires) < Math.floor(Date.now() / 1000)) {
      return null;
    }
    return data.openid;
  } catch {
    return null;
  }
}

function createRateLimiter({ windowMs, max, keyPrefix }) {
  const buckets = new Map();
  return (req, res, next) => {
    const key = `${keyPrefix}:${req.ip || "unknown"}`;
    const now = Date.now();
    if (buckets.size > 5000) {
      for (const [bucketKey, bucketValue] of buckets) {
        if (now > bucketValue.reset) {
          buckets.delete(bucketKey);
        }
      }
    }
    const bucket = buckets.get(key) || { count: 0, reset: now + windowMs };
    if (now > bucket.reset) {
      bucket.count = 0;
      bucket.reset = now + windowMs;
    }
    bucket.count += 1;
    buckets.set(key, bucket);
    if (bucket.count > max) {
      res.status(429).json({ ok: false, error: "rate_limited" });
      return;
    }
    next();
  };
}

function parsePositiveInt(value, fallback, min, max) {
  const number = Number(value);
  if (!Number.isInteger(number)) {
    return fallback;
  }
  return Math.max(min, Math.min(max, number));
}

function requireId(value) {
  const id = String(value || "");
  if (!UGC_ID_RE.test(id)) {
    throw new ValidationError("invalid_id", "关卡 id 格式无效");
  }
  return id;
}

function requirePlayerId(value) {
  const id = String(value || "");
  if (!PLATFORM_ID_RE.test(id)) {
    throw new ValidationError("invalid_player_id", "player_id 格式无效");
  }
  return id;
}

function makeUgcId() {
  return `ugc_${Date.now().toString(36)}_${crypto.randomBytes(4).toString("hex")}`;
}

/**
 * 审核占位实现。
 *
 * TODO: 微信端正式上线前把这里替换为服务端 msgSecCheck：
 *   1. 使用 /api/login 换到的 openid；
 *   2. 对关卡名、简介、作者昵称分别调用 wxa/msg_sec_check；
 *   3. 审核通过把 review_status 写成 approved；
 *   4. 需要人工复核时写 pending，广场列表接口不会返回 pending。
 *
 * 当前默认 mock 模式直接返回 approved，便于 PC/安卓/微信三端联调。
 */
async function moderateUgcContent({ platform }) {
  if (platform === "wechat") {
    // TODO: 后续接入微信 msgSecCheck；当前使用 mock 审核流转。
  }
  return {
    status: "approved",
    provider: "mock",
    reason: "mock_auto_approve",
  };
}

/**
 * 创建 Express 应用。抽出 app 便于自动化测试直接监听随机端口。
 */
export function createApp({ db, config }) {
  const app = express();
  const ugcStore = new UgcStore(db);
  const telemetryStore = new TelemetryStore(db);
  const publicDir = config.publicDir;
  const allowedOrigin = config.allowedOrigin || "*";
  const sessionSecret = config.sessionSecret || "dev-session-secret";
  const appId = config.appId || "";
  const appSecret = config.appSecret || "";
  const ugcScene = Number(config.ugcScene || 2);
  const reviewMode = config.reviewMode || "mock";
  const maxLevelsPerAuthor = Number(config.maxLevelsPerAuthor || 3);

  app.set("trust proxy", 1);
  app.disable("x-powered-by");

  // CORS 与限流放在 body parser 之前，保证 413 / 429 响应也带 CORS 头。
  app.use(cors({
    origin: allowedOrigin,
    methods: ["GET", "POST", "DELETE", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization", "X-Player-Id"],
    optionsSuccessStatus: 204,
  }));

  const apiRateLimit = createRateLimiter({ windowMs: 60_000, max: 120, keyPrefix: "api" });
  const uploadRateLimit = createRateLimiter({ windowMs: 3_600_000, max: 30, keyPrefix: "upload" });
  app.use("/api", apiRateLimit);

  // 上传接口单独放宽到 3MB，路由内部再按 2MB 关卡正文精确拦截。
  app.use("/api/ugc/upload", express.json({ limit: "3mb" }));
  // 遥测 payload 上限 32KB；信封本身允许少量额外字段。
  app.use("/api/telemetry", express.json({ limit: "128kb" }));
  app.use(express.json({ limit: "64kb" }));

  let accessTokenCache = { value: "", expiresAt: 0 };
  async function getAccessToken() {
    if (accessTokenCache.value && Date.now() < accessTokenCache.expiresAt) {
      return accessTokenCache.value;
    }
    if (!appSecret) {
      throw new Error("WECHAT_APP_SECRET 未配置");
    }
    const url = new URL("https://api.weixin.qq.com/cgi-bin/token");
    url.searchParams.set("grant_type", "client_credential");
    url.searchParams.set("appid", appId);
    url.searchParams.set("secret", appSecret);
    const response = await fetch(url);
    const data = await response.json();
    if (!data.access_token) {
      throw new Error(`access_token 获取失败: ${data.errcode || "unknown"} ${data.errmsg || ""}`);
    }
    accessTokenCache = {
      value: data.access_token,
      expiresAt: Date.now() + Math.max(60, Number(data.expires_in || 7200) - 120) * 1000,
    };
    return accessTokenCache.value;
  }

  app.get("/health", (_req, res) => {
    res.json({
      ok: true,
      service: "cablecar-server",
      appid: appId,
      has_secret: Boolean(appSecret),
      database: "sqlite",
      ugc_review_mode: reviewMode,
      time: new Date().toISOString(),
    });
  });

  // ---------- 微信登录 / 文本审核（保留原有接口） ----------

  app.post("/api/login", async (req, res) => {
    const code = String(req.body?.code || "");
    if (!code) {
      res.status(400).json({ ok: false, error: "missing_code" });
      return;
    }
    if (!appSecret) {
      res.status(503).json({ ok: false, error: "server_appsecret_missing" });
      return;
    }
    try {
      const url = new URL("https://api.weixin.qq.com/sns/jscode2session");
      url.searchParams.set("appid", appId);
      url.searchParams.set("secret", appSecret);
      url.searchParams.set("js_code", code);
      url.searchParams.set("grant_type", "authorization_code");
      const response = await fetch(url);
      const data = await response.json();
      if (!data.openid) {
        res.status(401).json({ ok: false, error: "wechat_login_failed", detail: data });
        return;
      }
      res.json({ ok: true, openid: data.openid, token: signSession(data.openid, sessionSecret) });
    } catch (error) {
      res.status(502).json({ ok: false, error: "wechat_unreachable", detail: String(error.message || error) });
    }
  });

  app.post("/api/ugc/check", async (req, res) => {
    const token = String(req.headers.authorization || "").replace(/^Bearer\s+/i, "");
    const openid = verifySession(token, sessionSecret);
    if (!openid) {
      res.status(401).json({ ok: false, error: "invalid_session" });
      return;
    }
    const content = String(req.body?.content || "").trim();
    if (!content) {
      res.status(400).json({ ok: false, error: "empty_content" });
      return;
    }
    if (content.length > 2500) {
      res.status(400).json({ ok: false, error: "content_too_long" });
      return;
    }
    try {
      const accessToken = await getAccessToken();
      const url = new URL("https://api.weixin.qq.com/wxa/msg_sec_check");
      url.searchParams.set("access_token", accessToken);
      const response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          content,
          version: 2,
          scene: ugcScene,
          openid,
        }),
      });
      const data = await response.json();
      const suggest = String(data?.result?.suggest || "");
      const pass = data.errcode === 0 && suggest === "pass";
      res.status(pass ? 200 : 422).json({
        ok: pass,
        suggest,
        label: Number(data?.result?.label || 0),
        errcode: Number(data.errcode || 0),
        errmsg: String(data.errmsg || ""),
      });
    } catch (error) {
      res.status(502).json({ ok: false, error: "wechat_moderation_failed", detail: String(error.message || error) });
    }
  });

  // ---------- UGC 关卡广场 ----------

  app.post("/api/ugc/upload", uploadRateLimit, async (req, res, next) => {
    try {
      const normalized = normalizeUploadEnvelope(req.body);
      const contentHash = normalized.contentHash;

      // 幂等查重：同一作者上传相同内容时不重复入库，直接返回已有记录。
      // 放在上传上限检查之前，保证重复上传优先得到 duplicate 而非 429。
      const existing = ugcStore.findByAuthorHash(normalized.authorId, contentHash);
      if (existing) {
        res.status(200).json({
          ok: true,
          id: existing.id,
          duplicate: true,
          content_hash: contentHash,
          review_status: existing.reviewStatus,
          review_provider: existing.reviewProvider,
          entry: ugcStore.getSummary(existing.id, true),
        });
        return;
      }

      if (ugcStore.countByAuthor(normalized.authorId) >= maxLevelsPerAuthor) {
        throw new ValidationError("author_upload_limit", `每个作者最多上传 ${maxLevelsPerAuthor} 张关卡`, 429);
      }
      const review = reviewMode === "pending"
        ? { status: "pending", provider: "mock", reason: "review_pending" }
        : await moderateUgcContent(normalized);
      const id = makeUgcId();
      normalized.level.id = id;
      let entry;
      try {
        entry = ugcStore.create({
          id,
          name: normalized.name,
          authorId: normalized.authorId,
          authorName: normalized.authorName,
          description: normalized.description,
          platform: normalized.platform,
          level: normalized.level,
          contentHash,
          reviewStatus: review.status,
          reviewProvider: review.provider,
          reviewReason: review.reason,
        });
      } catch (insertError) {
        // 并发兜底：两个相同内容请求同时通过查重时，UNIQUE(author_id, content_hash)
        // 会让后到的 INSERT 撞约束；回查已有记录按幂等返回，防止刷库。
        if (String(insertError && insertError.code).includes("SQLITE_CONSTRAINT")) {
          const raced = ugcStore.findByAuthorHash(normalized.authorId, contentHash);
          if (raced) {
            res.status(200).json({
              ok: true,
              id: raced.id,
              duplicate: true,
              content_hash: contentHash,
              review_status: raced.reviewStatus,
              review_provider: raced.reviewProvider,
              entry: ugcStore.getSummary(raced.id, true),
            });
            return;
          }
        }
        throw insertError;
      }
      res.status(review.status === "approved" ? 201 : 202).json({
        ok: true,
        id,
        duplicate: false,
        content_hash: contentHash,
        review_status: review.status,
        review_provider: review.provider,
        entry,
      });
    } catch (error) {
      next(error);
    }
  });

  app.get("/api/ugc/list", (req, res) => {
    const page = parsePositiveInt(req.query.page, 1, 1, 10_000);
    const pageSize = parsePositiveInt(req.query.page_size ?? req.query.pageSize, 20, 1, 50);
    const sort = ["latest", "hot", "oldest"].includes(String(req.query.sort))
      ? String(req.query.sort)
      : "latest";
    const authorId = String(req.query.author_id || "");
    const platform = String(req.query.platform || "");
    const q = String(req.query.q || "").slice(0, 32);
    const playerId = String(req.query.player_id || "");
    if (authorId && !PLATFORM_ID_RE.test(authorId)) {
      res.status(400).json({ ok: false, error: "invalid_author_id" });
      return;
    }
    if (playerId && !PLATFORM_ID_RE.test(playerId)) {
      res.status(400).json({ ok: false, error: "invalid_player_id" });
      return;
    }
    const result = ugcStore.list({ page, pageSize, sort, authorId, platform, q, playerId });
    res.json({ ok: true, ...result });
  });

  app.get("/api/ugc/detail/:id", (req, res) => {
    let id;
    try {
      id = requireId(req.params.id);
    } catch (error) {
      res.status(400).json({ ok: false, error: error.code || "invalid_id" });
      return;
    }
    const playerId = String(req.query.player_id || "");
    if (playerId && !PLATFORM_ID_RE.test(playerId)) {
      res.status(400).json({ ok: false, error: "invalid_player_id" });
      return;
    }
    const entry = ugcStore.getDetail(id, playerId);
    if (!entry) {
      res.status(404).json({ ok: false, error: "not_found" });
      return;
    }
    res.json({ ok: true, entry });
  });

  app.post("/api/ugc/:id/play", (req, res) => {
    let id;
    try {
      id = requireId(req.params.id);
    } catch (error) {
      res.status(400).json({ ok: false, error: error.code || "invalid_id" });
      return;
    }
    const result = ugcStore.incrementPlays(id);
    if (!result) {
      res.status(404).json({ ok: false, error: "not_found" });
      return;
    }
    res.json({ ok: true, plays: result.plays });
  });

  app.post("/api/ugc/:id/like", (req, res) => {
    let id;
    let playerId;
    try {
      id = requireId(req.params.id);
      playerId = requirePlayerId(req.body?.player_id);
    } catch (error) {
      res.status(400).json({ ok: false, error: error.code || "invalid_request" });
      return;
    }
    const result = ugcStore.toggleLike(id, playerId);
    if (!result) {
      res.status(404).json({ ok: false, error: "not_found" });
      return;
    }
    res.json({ ok: true, liked: result.active, likes: result.count });
  });

  app.post("/api/ugc/:id/favorite", (req, res) => {
    let id;
    let playerId;
    try {
      id = requireId(req.params.id);
      playerId = requirePlayerId(req.body?.player_id);
    } catch (error) {
      res.status(400).json({ ok: false, error: error.code || "invalid_request" });
      return;
    }
    const result = ugcStore.toggleFavorite(id, playerId);
    if (!result) {
      res.status(404).json({ ok: false, error: "not_found" });
      return;
    }
    res.json({ ok: true, favorited: result.active, favorites: result.count });
  });

  app.delete("/api/ugc/:id", (req, res) => {
    let id;
    let authorId;
    try {
      id = requireId(req.params.id);
      authorId = requirePlayerId(req.body?.author_id || req.headers["x-player-id"]);
    } catch (error) {
      res.status(400).json({ ok: false, error: error.code || "invalid_request" });
      return;
    }
    const result = ugcStore.delete(id, authorId);
    if (!result.ok && result.reason === "not_found") {
      res.status(404).json({ ok: false, error: "not_found" });
      return;
    }
    if (!result.ok) {
      res.status(403).json({ ok: false, error: "forbidden" });
      return;
    }
    res.json({ ok: true });
  });

  // ---------- 遥测 ----------

  app.post("/api/telemetry", (req, res) => {
    try {
      const event = normalizeTelemetry(req.body);
      const result = telemetryStore.insert(event);
      res.status(202).json({ ok: true, duplicate: result.duplicate, event_id: result.eventId });
    } catch (error) {
      if (error instanceof ValidationError) {
        res.status(error.status).json({ ok: false, error: error.code, detail: error.message });
        return;
      }
      throw error;
    }
  });

  // 看板数据源，只返回聚合结果，不暴露玩家明细。
  app.get("/api/telemetry/summary", (req, res) => {
    const days = parsePositiveInt(req.query.days, 7, 1, 90);
    res.json({ ok: true, ...telemetryStore.summary(days) });
  });

  // Vue + ECharts 看板的一次性聚合接口：KPI、趋势、三端、主线、卡点、UGC 全量数据。
  app.get("/api/telemetry/dashboard", (req, res) => {
    const days = parsePositiveInt(req.query.days, 7, 1, 90);
    res.json(telemetryStore.dashboard(days));
  });

  // ---------- 远程资源 ----------
  if (publicDir) {
    app.use(
      "/game",
      express.static(path.join(publicDir, "game"), {
        fallthrough: false,
        setHeaders(res, filePath) {
          if (filePath.endsWith(".wasm")) {
            res.setHeader("Content-Type", "application/wasm");
          }
          if (filePath.endsWith(".br")) {
            res.setHeader("Content-Encoding", "br");
            res.setHeader("Content-Type", "application/octet-stream");
          }
          if (filePath.endsWith(".pck")) {
            res.setHeader("Content-Type", "application/octet-stream");
          }
          res.setHeader("Cache-Control", "public, max-age=3600");
        },
      }),
    );
  }

  app.use((error, _req, res, _next) => {
    if (error instanceof ValidationError) {
      res.status(error.status).json({
        ok: false,
        error: error.code,
        detail: error.message,
      });
      return;
    }
    if (error?.type === "entity.too.large") {
      res.status(413).json({ ok: false, error: "payload_too_large", detail: "请求体超过大小上限" });
      return;
    }
    if (error instanceof SyntaxError && "body" in error) {
      res.status(400).json({ ok: false, error: "invalid_json" });
      return;
    }
    console.error(error);
    res.status(500).json({ ok: false, error: "internal_error" });
  });

  app.locals.ugcStore = ugcStore;
  app.locals.telemetryStore = telemetryStore;
  return app;
}

export function ensurePublicDir(publicDir) {
  if (publicDir && !fs.existsSync(publicDir)) {
    fs.mkdirSync(publicDir, { recursive: true });
  }
}

import crypto from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";
import "dotenv/config";
import { createApp, ensurePublicDir } from "./app.js";
import { openDatabase } from "./db.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");
const publicDir = path.join(rootDir, "public");
const dbPath = process.env.UGC_DB_PATH || path.join(rootDir, "data", "cablecar.sqlite");
const PORT = Number(process.env.PORT || 3000);

ensurePublicDir(publicDir);
const db = openDatabase(dbPath);

const app = createApp({
  db,
  config: {
    publicDir,
    appId: String(process.env.WECHAT_APP_ID || "wx02e59af7baf92fcf"),
    appSecret: String(process.env.WECHAT_APP_SECRET || ""),
    sessionSecret: String(process.env.SESSION_SECRET || crypto.randomBytes(32).toString("hex")),
    ugcScene: Number(process.env.UGC_SCENE || 2),
    allowedOrigin: String(process.env.ALLOWED_ORIGIN || "*"),
    reviewMode: String(process.env.UGC_REVIEW_MODE || "mock"),
    maxLevelsPerAuthor: Number(process.env.UGC_MAX_LEVELS_PER_AUTHOR || 3),
  },
});

const server = app.listen(PORT, "0.0.0.0", () => {
  console.log(`cablecar-server listening on http://0.0.0.0:${PORT}`);
  console.log(`database=${dbPath}`);
  console.log(`wechat_appid=${process.env.WECHAT_APP_ID || "wx02e59af7baf92fcf"}`);
  console.log(`wechat_secret=${process.env.WECHAT_APP_SECRET ? "configured" : "missing"}`);
});

function shutdown(signal) {
  console.log(`received ${signal}, shutting down`);
  server.close(() => {
    db.close();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 5000).unref();
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));

/**
 * UGC 关卡的 SQLite 读写层。
 *
 * 列表查询只取摘要列；完整 level_json 仅在详情接口读取。
 */
export class UgcStore {
  constructor(db) {
    this.db = db;
  }

  create(entry) {
    const now = new Date().toISOString();
    const levelJson = JSON.stringify(entry.level);
    this.db.prepare(`
      INSERT INTO ugc_levels (
        id, name, author_id, author_name, description, platform, difficulty,
        schema_version, level_bytes, level_json, content_hash, review_status, review_provider,
        review_reason, created_at, updated_at
      ) VALUES (
        @id, @name, @author_id, @author_name, @description, @platform, @difficulty,
        @schema_version, @level_bytes, @level_json, @content_hash, @review_status, @review_provider,
        @review_reason, @created_at, @updated_at
      )
    `).run({
      id: entry.id,
      name: entry.name,
      author_id: entry.authorId,
      author_name: entry.authorName,
      description: entry.description || "",
      platform: entry.platform,
      difficulty: entry.level.difficulty,
      schema_version: entry.level.schema_version,
      level_bytes: Buffer.byteLength(levelJson, "utf8"),
      level_json: levelJson,
      content_hash: entry.contentHash || null,
      review_status: entry.reviewStatus,
      review_provider: entry.reviewProvider,
      review_reason: entry.reviewReason || "",
      created_at: now,
      updated_at: now,
    });
    return this.getSummary(entry.id, true);
  }

  list({ page = 1, pageSize = 20, sort = "latest", authorId = "", platform = "", q = "", playerId = "" }) {
    const where = ["l.review_status = 'approved'"];
    const params = {};
    if (authorId) {
      where.push("l.author_id = @author_id");
      params.author_id = authorId;
    }
    if (platform) {
      where.push("l.platform = @platform");
      params.platform = platform;
    }
    if (q) {
      where.push("l.name LIKE @query ESCAPE '\\'");
      params.query = `%${String(q).replace(/[\\%_]/g, "\\$&")}%`;
    }
    const whereSql = where.join(" AND ");
    const total = Number(this.db.prepare(`SELECT COUNT(*) AS total FROM ugc_levels l WHERE ${whereSql}`).get(params).total);
    const offset = (page - 1) * pageSize;
    const orderSql = sort === "hot"
      ? "l.likes DESC, l.plays DESC, l.created_at DESC"
      : sort === "oldest"
        ? "l.created_at ASC, l.id ASC"
        : "l.created_at DESC, l.id DESC";

    const selectPlayer = playerId
      ? `EXISTS(SELECT 1 FROM ugc_likes x WHERE x.entry_id = l.id AND x.player_id = @player_id) AS liked,
         EXISTS(SELECT 1 FROM ugc_favorites x WHERE x.entry_id = l.id AND x.player_id = @player_id) AS favorited`
      : "0 AS liked, 0 AS favorited";
    if (playerId) {
      params.player_id = playerId;
    }
    params.limit = pageSize;
    params.offset = offset;
    const rows = this.db.prepare(`
      SELECT l.id, l.name, l.author_id, l.author_name, l.description, l.platform,
             l.difficulty, l.plays, l.likes, l.favorites, l.created_at,
             ${selectPlayer}
      FROM ugc_levels l
      WHERE ${whereSql}
      ORDER BY ${orderSql}
      LIMIT @limit OFFSET @offset
    `).all(params);

    return {
      page,
      pageSize,
      total,
      hasMore: offset + rows.length < total,
      entries: rows.map((row) => this.toSummary(row)),
    };
  }

  getSummary(id, includeUnapproved = false) {
    const row = this.db.prepare(`
      SELECT id, name, author_id, author_name, description, platform,
             difficulty, plays, likes, favorites, created_at
      FROM ugc_levels
      WHERE id = ? ${includeUnapproved ? "" : "AND review_status = 'approved'"}
    `).get(id);
    return row ? this.toSummary(row) : null;
  }

  getDetail(id, playerId = "") {
    const row = this.db.prepare(`
      SELECT l.*,
        ${playerId
          ? `EXISTS(SELECT 1 FROM ugc_likes x WHERE x.entry_id = l.id AND x.player_id = @player_id) AS liked,
             EXISTS(SELECT 1 FROM ugc_favorites x WHERE x.entry_id = l.id AND x.player_id = @player_id) AS favorited`
          : "0 AS liked, 0 AS favorited"}
      FROM ugc_levels l
      WHERE l.id = @id AND l.review_status = 'approved'
    `).get(playerId ? { id, player_id: playerId } : { id });
    if (!row) {
      return null;
    }
    const summary = this.toSummary(row);
    return {
      ...summary,
      review_status: row.review_status,
      level_bytes: row.level_bytes,
      level_data: JSON.parse(row.level_json),
    };
  }

  incrementPlays(id) {
    const result = this.db.prepare(`
      UPDATE ugc_levels SET plays = plays + 1, updated_at = ?
      WHERE id = ? AND review_status = 'approved'
    `).run(new Date().toISOString(), id);
    if (result.changes === 0) {
      return null;
    }
    const row = this.db.prepare("SELECT plays FROM ugc_levels WHERE id = ?").get(id);
    return { plays: Number(row.plays) };
  }

  toggleLike(id, playerId) {
    return this.#toggleRelation("ugc_likes", "likes", id, playerId);
  }

  toggleFavorite(id, playerId) {
    return this.#toggleRelation("ugc_favorites", "favorites", id, playerId);
  }

  #toggleRelation(table, countColumn, id, playerId) {
    const row = this.db.prepare("SELECT id FROM ugc_levels WHERE id = ? AND review_status = 'approved'").get(id);
    if (!row) {
      return null;
    }
    const transaction = this.db.transaction(() => {
      const existing = this.db.prepare(`SELECT 1 FROM ${table} WHERE entry_id = ? AND player_id = ?`).get(id, playerId);
      let active;
      if (existing) {
        this.db.prepare(`DELETE FROM ${table} WHERE entry_id = ? AND player_id = ?`).run(id, playerId);
        active = false;
      } else {
        this.db.prepare(`INSERT INTO ${table} (entry_id, player_id, created_at) VALUES (?, ?, ?)`)
          .run(id, playerId, new Date().toISOString());
        active = true;
      }
      const count = Number(this.db.prepare(`SELECT COUNT(*) AS total FROM ${table} WHERE entry_id = ?`).get(id).total);
      this.db.prepare(`UPDATE ugc_levels SET ${countColumn} = ?, updated_at = ? WHERE id = ?`)
        .run(count, new Date().toISOString(), id);
      return { active, count };
    });
    const result = transaction();
    return { active: result.active, count: result.count };
  }

  delete(id, authorId) {
    const row = this.db.prepare("SELECT author_id FROM ugc_levels WHERE id = ?").get(id);
    if (!row) {
      return { ok: false, reason: "not_found" };
    }
    if (row.author_id !== authorId) {
      return { ok: false, reason: "forbidden" };
    }
    this.db.prepare("DELETE FROM ugc_levels WHERE id = ?").run(id);
    return { ok: true };
  }

  countByAuthor(authorId) {
    return Number(this.db.prepare(
      "SELECT COUNT(*) AS total FROM ugc_levels WHERE author_id = ? AND review_status = 'approved'",
    ).get(authorId).total);
  }

  // 按作者 + 内容指纹查已有记录（含未审核），用于上传幂等去重。
  findByAuthorHash(authorId, contentHash) {
    if (!contentHash) {
      return null;
    }
    const row = this.db.prepare(
      "SELECT id, review_status, review_provider FROM ugc_levels WHERE author_id = ? AND content_hash = ?",
    ).get(authorId, contentHash);
    return row
      ? { id: row.id, reviewStatus: row.review_status, reviewProvider: row.review_provider }
      : null;
  }

  toSummary(row) {
    return {
      id: row.id,
      name: row.name,
      author: row.author_name,
      author_id: row.author_id,
      description: row.description || "",
      platform: row.platform,
      difficulty: Number(row.difficulty),
      plays: Number(row.plays),
      likes: Number(row.likes),
      favorites: Number(row.favorites),
      clears: 0,
      created_at: row.created_at,
      liked: Boolean(row.liked),
      favorited: Boolean(row.favorited),
    };
  }
}

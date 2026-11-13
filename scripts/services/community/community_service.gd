extends Node
## 关卡广场服务。
##
## 线上模式：列表 / 详情 / 上传 / 游玩计数全部走后端 API；
## 本地只保存点赞、收藏、单关成绩等轻量状态，不保存完整关卡正文。
## offline_mode 仅用于自动化测试与离线截图，生产 UI 默认走线上。
signal changed

const LOCAL_STATE_PATH := "user://community/local_state.json"
const PAGE_SIZE := 24
const MAX_LOCAL_UPLOADS := 3
const BANNED_WORDS := ["色情", "赌博", "毒品", "傻逼", "操你", "fuck", "shit", "porn"]

var last_error: String = ""
var offline_mode: bool = false

var _entries: Array[Dictionary] = []
## 离线/截图模式下的完整列表快照；分页追加会修改 _entries，不能拿它当数据源。
var _offline_feed_cache: Array[Dictionary] = []
var _details: Dictionary = {}
var _local_state: Dictionary = _default_local_state()
var _feed_generation: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_local_state()
	if not offline_mode:
		call_deferred("_refresh_upload_count")


## 测试 / 截图专用：不访问网络，使用进程内本地数据。
func set_offline_mode(value: bool) -> void:
	offline_mode = value
	if offline_mode:
		_entries.clear()
		_offline_feed_cache.clear()
		_details.clear()


## 广场归属使用稳定展示 id（SW-xxxxxx），而不是所有本地存档共用的 local_player。
func _author_id() -> String:
	return SaveManager.get_player_id()


func get_user_upload_count() -> int:
	if offline_mode:
		var count := 0
		for entry in _entries:
			if str(entry.get("author_id", "")) == _author_id():
				count += 1
		return count
	return int(_local_state.get("upload_count", 0))


func upload_level(level_id: String, display_name: String, callback: Callable) -> void:
	if not PlatformConfig.can_upload_ugc:
		_finish(callback, {"ok": false, "error": "当前平台不支持上传到关卡广场"})
		return
	var raw := LevelCatalog.get_raw_level(level_id)
	if not bool(raw.get("ok", false)):
		_finish(callback, {"ok": false, "error": "读取自制关卡失败"})
		return
	# 本地状态锁：已有 server_id 说明这张关卡已上传，直接拒绝、不发请求，杜绝重复上传。
	var mark := LevelRepository.get_upload_mark(level_id)
	if not str(mark.get("server_id", "")).is_empty():
		_finish(callback, {"ok": false, "error": "该关卡已上传到广场，无需重复上传"})
		return
	if not SaveManager.is_level_cleared(level_id):
		_finish(callback, {"ok": false, "error": "请先亲自通关该关卡，再上传到广场"})
		return
	if LevelRepository.needs_reclear(level_id):
		_finish(callback, {"ok": false, "error": "关卡在上传后又修改过，请重新通关一次再上传"})
		return
	if get_user_upload_count() >= MAX_LOCAL_UPLOADS:
		_finish(callback, {"ok": false, "error": "最多只能上传 3 张自制关卡，请先撤销旧上传"})
		return
	var clean_name := display_name.strip_edges()
	if clean_name.is_empty():
		clean_name = str((raw.get("data", {}) as Dictionary).get("name", "无名关卡"))
	if _contains_banned(clean_name):
		_finish(callback, {"ok": false, "error": "关卡名称包含违禁词，请修改"})
		return
	var document := UgcLevelDocument.make_upload_body(raw.get("data", {}), {
		"name": clean_name,
		"author_name": SaveManager.get_player_name(),
		"author_id": _author_id(),
		"platform": PlatformConfig.get_platform_id(),
		"description": str((raw.get("data", {}) as Dictionary).get("description", "")),
	})
	if not bool(document.get("ok", false)):
		_finish(callback, {"ok": false, "error": str(document.get("error", "关卡序列化失败"))})
		return
	var upload_level_data: Dictionary = document.get("body", {}).get("level_data", {})
	var uploaded_local_hash := LevelRepository.compute_content_hash(upload_level_data)
	if offline_mode:
		_upload_offline(level_id, document, clean_name, callback)
		return
	ApiClient.post_json("/api/ugc/upload", document.get("body", {}), func(result: Dictionary) -> void:
		if not bool(result.get("ok", false)):
			last_error = _error_text(result)
			_finish(callback, {"ok": false, "error": last_error})
			return
		var data: Dictionary = result.get("data", {})
		var entry := _entry_from_api(data.get("entry", {}))
		var entry_id := str(data.get("id", entry.get("id", "")))
		if entry_id.is_empty():
			last_error = "服务器没有返回关卡 id"
			_finish(callback, {"ok": false, "error": last_error})
			return
		var is_duplicate := bool(data.get("duplicate", false))
		var content_hash := str(data.get("content_hash", ""))
		# 回写本地已上传标记：server_id + 服务端指纹，重启后据此显示“已上传”并禁用按钮。
		LevelRepository.mark_uploaded(level_id, entry_id, content_hash, uploaded_local_hash)
		var level_data: Dictionary = (document.get("body", {}).get("level_data", {}) as Dictionary).duplicate(true)
		level_data["id"] = entry_id
		level_data["source"] = "community"
		level_data["custom"] = true
		_details[entry_id] = level_data
		if entry.is_empty():
			entry = {
				"id": entry_id,
				"name": clean_name,
				"author": SaveManager.get_player_name(),
				"author_id": _author_id(),
				"description": str(level_data.get("description", "")),
				"level_data": {},
				"plays": 0,
				"likes": 0,
				"clears": 0,
				"created_at": int(Time.get_unix_time_from_system()),
				"scores": [],
			}
		entry["review_status"] = str(data.get("review_status", "approved"))
		# 幂等命中（duplicate）时服务端未新增记录，本地也不应重复累加上传计数或重复插入列表。
		if not is_duplicate:
			_entries.push_front(entry)
			_local_state["upload_count"] = int(_local_state.get("upload_count", 0)) + 1
		_save_local_state()
		changed.emit()
		_finish(callback, {"ok": true, "entry": entry, "duplicate": is_duplicate})
	)


func fetch_feed(sort_mode: String, callback: Callable) -> void:
	_feed_generation += 1
	_request_feed(sort_mode, 1, callback, true, _feed_generation)


## 分页追加。收藏/随机只取首批，避免把不完整的服务端排序误当成全量。
func fetch_feed_page(sort_mode: String, page: int, callback: Callable) -> void:
	_request_feed(sort_mode, maxi(1, page), callback, false, _feed_generation)


func _request_feed(
	sort_mode: String,
	page: int,
	callback: Callable,
	replace_entries: bool,
	generation: int
) -> void:
	if offline_mode:
		var offline := _offline_feed(sort_mode)
		if replace_entries or _offline_feed_cache.is_empty():
			_offline_feed_cache.clear()
			for entry: Variant in offline.get("entries", []):
				if entry is Dictionary:
					_offline_feed_cache.append(entry as Dictionary)
		var all_entries: Array = _offline_feed_cache
		var start := (page - 1) * PAGE_SIZE
		var end := mini(all_entries.size(), start + PAGE_SIZE)
		var page_entries: Array = [] if start >= all_entries.size() else all_entries.slice(start, end)
		if replace_entries:
			_entries.clear()
		_append_entries(page_entries)
		_finish(callback, {
			"ok": true,
			"entries": page_entries,
			"total": all_entries.size(),
			"has_more": end < all_entries.size(),
			"page": page,
			"error": offline.get("error", ""),
		})
		return
	var query := {
		"page": page,
		"page_size": PAGE_SIZE,
		"sort": "hot" if sort_mode == "hot" else "latest",
		"player_id": _author_id(),
	}
	if sort_mode == "mine":
		query["author_id"] = _author_id()
	ApiClient.get_json("/api/ugc/list", query, func(result: Dictionary) -> void:
		if generation != _feed_generation:
			return
		if not bool(result.get("ok", false)):
			last_error = _error_text(result)
			_finish(callback, {
				"ok": false,
				"entries": _entries.duplicate(true),
				"total": _entries.size(),
				"has_more": false,
				"page": page,
				"error": last_error,
			})
			return
		var data: Dictionary = result.get("data", {})
		var next: Array[Dictionary] = []
		var raw_entries: Variant = data.get("entries", [])
		if raw_entries is Array:
			for item: Variant in raw_entries:
				if item is Dictionary:
					next.append(_entry_from_api(item as Dictionary))
		var total := int(data.get("total", next.size()))
		var has_more := bool(data.get("hasMore", false))
		if sort_mode == "favorite":
			var favorites: Array[Dictionary] = []
			for entry in next:
				if bool(entry.get("favorited", false)):
					favorites.append(entry)
			next = favorites
			total = favorites.size()
			has_more = false
		elif sort_mode == "random":
			next.shuffle()
			# 随机模式只在首批内洗牌，不把分页顺序当成稳定 ranking。
			has_more = false
		if replace_entries:
			_entries.clear()
		_append_entries(next)
		_finish(callback, {
			"ok": true,
			"entries": next,
			"total": total,
			"has_more": has_more,
			"page": page,
			"error": "",
		})
	)


func _append_entries(page_entries: Array) -> void:
	var known: Dictionary = {}
	for entry in _entries:
		known[str(entry.get("id", ""))] = true
	for item: Variant in page_entries:
		if not item is Dictionary:
			continue
		var entry: Dictionary = item
		var entry_id := str(entry.get("id", ""))
		if entry_id.is_empty() or known.has(entry_id):
			continue
		known[entry_id] = true
		_entries.append(entry)


func get_entry(entry_id: String) -> Dictionary:
	for entry in _entries:
		if str(entry.get("id", "")) == entry_id:
			return entry
	return {}


func get_level_data(entry_id: String) -> Dictionary:
	var value: Variant = _details.get(entry_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


## 列表只含摘要，试玩前必须单独拉取完整关卡。
func fetch_detail(entry_id: String, callback: Callable) -> void:
	if _details.has(entry_id):
		_finish(callback, {"ok": true, "level_data": get_level_data(entry_id), "error": ""})
		return
	if offline_mode:
		var entry := get_entry(entry_id)
		var local_data: Variant = entry.get("level_data", {})
		if local_data is Dictionary and not (local_data as Dictionary).is_empty():
			_finish(callback, {"ok": true, "level_data": (local_data as Dictionary).duplicate(true), "error": ""})
		else:
			_finish(callback, {"ok": false, "level_data": {}, "error": "本地关卡不存在"})
		return
	ApiClient.get_json("/api/ugc/detail/%s" % entry_id.uri_encode(), {
		"player_id": _author_id(),
	}, func(result: Dictionary) -> void:
		if not bool(result.get("ok", false)):
			last_error = _error_text(result)
			_finish(callback, {"ok": false, "level_data": {}, "error": last_error})
			return
		var data: Dictionary = result.get("data", {})
		var entry_value: Variant = data.get("entry", {})
		if not entry_value is Dictionary:
			last_error = "服务器返回的关卡详情格式错误"
			_finish(callback, {"ok": false, "level_data": {}, "error": last_error})
			return
		var imported := UgcLevelDocument.import_detail(entry_value as Dictionary)
		if not bool(imported.get("ok", false)):
			last_error = str(imported.get("error", "关卡校验失败"))
			_finish(callback, {"ok": false, "level_data": {}, "error": last_error})
			return
		_details[entry_id] = imported.get("level_data", {})
		_finish(callback, {"ok": true, "level_data": get_level_data(entry_id), "error": ""})
	)


func record_play(entry_id: String) -> void:
	var entry := get_entry(entry_id)
	if entry.is_empty():
		return
	entry["plays"] = int(entry.get("plays", 0)) + 1
	if offline_mode:
		changed.emit()
		return
	ApiClient.post_json("/api/ugc/%s/play" % entry_id.uri_encode(), {}, func(result: Dictionary) -> void:
		if bool(result.get("ok", false)):
			var data: Dictionary = result.get("data", {})
			entry["plays"] = int(data.get("plays", entry.get("plays", 0)))
			changed.emit()
	)


func toggle_like(entry_id: String) -> Dictionary:
	var entry := get_entry(entry_id)
	if entry.is_empty():
		return {"ok": false, "error": "关卡不存在"}
	var liked := not bool(entry.get("liked", false))
	entry["liked"] = liked
	entry["likes"] = maxi(0, int(entry.get("likes", 0)) + (1 if liked else -1))
	_store_local_flag("likes", entry_id, liked)
	if offline_mode:
		changed.emit()
		return {"ok": true, "liked": liked, "likes": int(entry["likes"])}
	ApiClient.post_json("/api/ugc/%s/like" % entry_id.uri_encode(), {
		"player_id": _author_id(),
	}, func(result: Dictionary) -> void:
		if bool(result.get("ok", false)):
			var data: Dictionary = result.get("data", {})
			entry["liked"] = bool(data.get("liked", entry.get("liked", false)))
			entry["likes"] = int(data.get("likes", entry.get("likes", 0)))
			_store_local_flag("likes", entry_id, bool(entry["liked"]))
		else:
			entry["liked"] = not liked
			entry["likes"] = maxi(0, int(entry["likes"]) + (-1 if liked else 1))
			_store_local_flag("likes", entry_id, bool(entry["liked"]))
			last_error = _error_text(result)
		changed.emit()
	)
	return {"ok": true, "liked": liked, "likes": int(entry["likes"])}


func submit_score(entry_id: String, passengers: int, time_seconds: float, completed: bool) -> void:
	var entry := get_entry(entry_id)
	if entry.is_empty() or not completed:
		return
	entry["clears"] = int(entry.get("clears", 0)) + 1
	var scores: Array = entry.get("scores", [])
	scores.append({
		"name": SaveManager.get_player_name(),
		"passengers": passengers,
		"time_seconds": time_seconds,
		"created_at": int(Time.get_unix_time_from_system()),
	})
	scores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("passengers", 0)) != int(b.get("passengers", 0)):
			return int(a.get("passengers", 0)) > int(b.get("passengers", 0))
		return float(a.get("time_seconds", 999999.0)) < float(b.get("time_seconds", 999999.0))
	)
	if scores.size() > 20:
		scores.resize(20)
	entry["scores"] = scores
	_local_state["scores"][entry_id] = scores.duplicate(true)
	_save_local_state()
	changed.emit()


func is_liked(entry_id: String) -> bool:
	var entry := get_entry(entry_id)
	if not entry.is_empty():
		return bool(entry.get("liked", false))
	return bool((_local_state.get("likes", {}) as Dictionary).get(entry_id, false))


func toggle_favorite(entry_id: String) -> Dictionary:
	var entry := get_entry(entry_id)
	if entry.is_empty():
		return {"ok": false, "error": "关卡不存在"}
	var favorited := not bool(entry.get("favorited", false))
	entry["favorited"] = favorited
	_store_local_flag("favorites", entry_id, favorited)
	if offline_mode:
		changed.emit()
		return {"ok": true, "favorited": favorited}
	ApiClient.post_json("/api/ugc/%s/favorite" % entry_id.uri_encode(), {
		"player_id": _author_id(),
	}, func(result: Dictionary) -> void:
		if bool(result.get("ok", false)):
			var data: Dictionary = result.get("data", {})
			entry["favorited"] = bool(data.get("favorited", entry.get("favorited", false)))
			_store_local_flag("favorites", entry_id, bool(entry["favorited"]))
		else:
			entry["favorited"] = not favorited
			_store_local_flag("favorites", entry_id, bool(entry["favorited"]))
			last_error = _error_text(result)
		changed.emit()
	)
	return {"ok": true, "favorited": favorited}


func is_favorited(entry_id: String) -> bool:
	var entry := get_entry(entry_id)
	if not entry.is_empty():
		return bool(entry.get("favorited", false))
	return bool((_local_state.get("favorites", {}) as Dictionary).get(entry_id, false))


func withdraw_entry(entry_id: String, callback: Callable = Callable()) -> Dictionary:
	var entry := get_entry(entry_id)
	# 上传弹窗按本地 server_id 撤销，此时该关卡可能不在当前分页/排序列表中；
	# 不在列表时交给服务端按 author_id 做最终鉴权，不能仅因本地没缓存就拒绝。
	if not entry.is_empty() and str(entry.get("author_id", "")) != _author_id():
		_finish(callback, {"ok": false, "error": "只能撤销自己上传的关卡"})
		return {"ok": false, "error": "只能撤销自己上传的关卡"}
	if offline_mode:
		if entry.is_empty():
			_finish(callback, {"ok": false, "error": "关卡不存在"})
			return {"ok": false, "error": "关卡不存在"}
		_remove_entry(entry_id)
		_finish(callback, {"ok": true})
		return {"ok": true}
	ApiClient.delete_json("/api/ugc/%s" % entry_id.uri_encode(), {
		"author_id": _author_id(),
	}, func(result: Dictionary) -> void:
		if not bool(result.get("ok", false)):
			last_error = _error_text(result)
			_finish(callback, {"ok": false, "error": last_error})
			return
		_remove_entry(entry_id)
		_finish(callback, {"ok": true})
	)
	return {"ok": true}


func clear_all() -> void:
	_entries.clear()
	_offline_feed_cache.clear()
	_details.clear()
	_local_state = _default_local_state()
	_save_local_state()
	changed.emit()


func get_user_levels() -> Array[Dictionary]:
	return LevelCatalog.get_user_summaries()


func _upload_offline(level_id: String, document: Dictionary, clean_name: String, callback: Callable) -> void:
	var entry_id := "plaza_%d_%d" % [int(Time.get_unix_time_from_system()), randi_range(100, 999)]
	var level_data: Dictionary = (document.get("body", {}).get("level_data", {}) as Dictionary).duplicate(true)
	# 在改成广场 entry_id 之前计算，指纹必须对应本地关卡文件的内容。
	var uploaded_local_hash := LevelRepository.compute_content_hash(level_data)
	level_data["id"] = entry_id
	level_data["name"] = clean_name
	level_data["custom"] = true
	level_data["source"] = "community"
	var entry := {
		"id": entry_id,
		"level_id": entry_id,
		"name": clean_name,
		"author": SaveManager.get_player_name(),
		"author_id": _author_id(),
		"description": str(level_data.get("description", "")),
		"difficulty": clampi(int(level_data.get("difficulty", 1)), 1, 5),
		"level_data": level_data,
		"likes": 0,
		"plays": 0,
		"clears": 0,
		"created_at": int(Time.get_unix_time_from_system()),
		"review_status": "approved",
		"liked": false,
		"favorited": false,
		"scores": [],
	}
	_entries.append(entry)
	_local_state["upload_count"] = int(_local_state.get("upload_count", 0)) + 1
	# 离线模式同样回写本地标记（指纹留空），保证状态锁与撤销清理在测试中一致。
	# 必须用原始 level_id（存档文件名），而非规范化后的 level_data.id，否则标记会落到错误文件。
	LevelRepository.mark_uploaded(level_id, entry_id, "", uploaded_local_hash)
	_save_local_state()
	changed.emit()
	_finish(callback, {"ok": true, "entry": entry})


func _offline_feed(sort_mode: String) -> Dictionary:
	var result: Array[Dictionary] = []
	for entry in _entries:
		if str(entry.get("review_status", "approved")) == "approved":
			result.append(entry.duplicate(true))
	if sort_mode == "mine":
		var mine: Array[Dictionary] = []
		for entry in result:
			if str(entry.get("author_id", "")) == _author_id():
				mine.append(entry)
		return {"ok": true, "entries": mine, "error": ""}
	if sort_mode == "favorite":
		var favorites: Array[Dictionary] = []
		for entry in result:
			if bool(entry.get("favorited", false)):
				favorites.append(entry)
		return {"ok": true, "entries": favorites, "error": ""}
	match sort_mode:
		"hot":
			result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var likes_a := int(a.get("likes", 0))
				var likes_b := int(b.get("likes", 0))
				if likes_a != likes_b:
					return likes_a > likes_b
				var plays_a := int(a.get("plays", 0))
				var plays_b := int(b.get("plays", 0))
				if plays_a != plays_b:
					return plays_a > plays_b
				return int(a.get("created_at", 0)) > int(b.get("created_at", 0))
			)
		"random":
			result.shuffle()
		_:
			result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("created_at", 0)) > int(b.get("created_at", 0))
			)
	return {"ok": true, "entries": result, "error": ""}


func _entry_from_api(item: Dictionary) -> Dictionary:
	var entry_id := str(item.get("id", ""))
	var scores_value: Variant = (_local_state.get("scores", {}) as Dictionary).get(entry_id, [])
	var entry := {
		"id": entry_id,
		"level_id": entry_id,
		"name": str(item.get("name", "无名关卡")),
		"author": str(item.get("author", "游客")),
		"author_id": str(item.get("author_id", "")),
		"description": str(item.get("description", "")),
		"difficulty": clampi(int(item.get("difficulty", 1)), 1, 5),
		"level_data": get_level_data(entry_id) if _details.has(entry_id) else {},
		"likes": int(item.get("likes", 0)),
		"plays": int(item.get("plays", 0)),
		"clears": int(item.get("clears", 0)),
		"created_at": str(item.get("created_at", "")),
		"platform": str(item.get("platform", "unknown")),
		"review_status": str(item.get("review_status", "approved")),
		"liked": bool(item.get("liked", (_local_state.get("likes", {}) as Dictionary).get(entry_id, false))),
		"favorited": bool(item.get("favorited", (_local_state.get("favorites", {}) as Dictionary).get(entry_id, false))),
		"scores": scores_value.duplicate(true) if scores_value is Array else [],
	}
	return entry


func _remove_entry(entry_id: String) -> void:
	for index in _entries.size():
		if str(_entries[index].get("id", "")) == entry_id:
			_entries.remove_at(index)
			break
	_details.erase(entry_id)
	(_local_state.get("scores", {}) as Dictionary).erase(entry_id)
	(_local_state.get("likes", {}) as Dictionary).erase(entry_id)
	(_local_state.get("favorites", {}) as Dictionary).erase(entry_id)
	_local_state["upload_count"] = maxi(0, int(_local_state.get("upload_count", 0)) - 1)
	# 撤销上传后清空本地已上传标记（只持有 server_id，反查对应关卡），允许重新上传。
	LevelRepository.clear_upload_mark_by_server_id(entry_id)
	_save_local_state()
	changed.emit()


func _refresh_upload_count() -> void:
	if offline_mode or not ApiClient.is_configured():
		return
	ApiClient.get_json("/api/ugc/list", {
		"author_id": _author_id(),
		"page": 1,
		"page_size": 1,
	}, func(result: Dictionary) -> void:
		if bool(result.get("ok", false)):
			var data: Dictionary = result.get("data", {})
			_local_state["upload_count"] = int(data.get("total", 0))
			_save_local_state()
	)


func _store_local_flag(key: String, entry_id: String, value: bool) -> void:
	var flags: Dictionary = _local_state.get(key, {})
	flags[entry_id] = value
	_local_state[key] = flags
	_save_local_state()


func _contains_banned(text: String) -> bool:
	var lowered := text.to_lower()
	for word in BANNED_WORDS:
		if lowered.contains(str(word)):
			return true
	return false


func _error_text(result: Dictionary) -> String:
	var error := str(result.get("error", "")).strip_edges()
	if not error.is_empty():
		return error
	match int(result.get("status", 0)):
		413:
			return "关卡文件超过 2MB 上限"
		429:
			return "操作太频繁，请稍后重试"
		404:
			return "关卡不存在或已下架"
		_:
			return "服务器请求失败"


func _finish(callback: Callable, result: Dictionary) -> void:
	if callback.is_valid():
		callback.call(result)


func _default_local_state() -> Dictionary:
	return {
		"version": 1,
		"likes": {},
		"favorites": {},
		"scores": {},
		"upload_count": 0,
	}


func _load_local_state() -> void:
	_local_state = _default_local_state()
	if not FileAccess.file_exists(LOCAL_STATE_PATH):
		return
	var text := FileAccess.get_file_as_string(LOCAL_STATE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		last_error = "广场本地状态损坏"
		return
	var source: Dictionary = parsed
	for key in ["likes", "favorites", "scores"]:
		var value: Variant = source.get(key, {})
		if value is Dictionary:
			_local_state[key] = (value as Dictionary).duplicate(true)
	_local_state["upload_count"] = maxi(0, int(source.get("upload_count", 0)))


func _save_local_state() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://community"))
	var file := FileAccess.open(LOCAL_STATE_PATH, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入广场本地状态"
		return
	file.store_string(JSON.stringify(_local_state, "\t"))
	file.close()

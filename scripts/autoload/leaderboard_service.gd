extends Node
## 排行榜服务：UI 的唯一入口。
## 当前注入 MockLeaderboardProvider；未来调用 set_provider(RemoteLeaderboardProvider) 即可。
## 该服务负责把玩家本地最佳成绩并入返回列表，保证离线也有个人名次。

signal provider_changed

var last_error: String = ""

var _provider: LeaderboardProvider


func _ready() -> void:
	_provider = MockLeaderboardProvider.new()


func set_provider(provider: LeaderboardProvider) -> void:
	_provider = provider
	last_error = ""
	provider_changed.emit()


func get_provider_id() -> String:
	return _provider.get_provider_id() if _provider != null else "none"


func get_provider_name() -> String:
	return _provider.get_display_name() if _provider != null else "未配置排行榜"


## 异步查询。callback.call({ok, entries, error})。
func fetch_scores(level_id: String, limit: int = 10, callback: Callable = Callable()) -> void:
	if _provider == null:
		last_error = "排行榜数据源未初始化"
		_finish_fetch(callback, {"ok": false, "entries": [], "error": last_error})
		return

	var summary := LevelCatalog.get_summary(level_id)
	if summary.is_empty():
		last_error = "未知关卡：%s" % level_id
		_finish_fetch(callback, {"ok": false, "entries": [], "error": last_error})
		return

	var request := {
		"level_id": level_id,
		"level_name": str(summary.get("name", level_id)),
		"difficulty": int(summary.get("difficulty", 2)),
		"par_time": float(summary.get("par_time", 60.0)),
		"limit": maxi(1, limit),
		"player_name": SaveManager.get_player_name(),
	}

	_provider.fetch_scores(request, func(result: Dictionary) -> void:
		_handle_fetch_result(request, result, callback)
	)


func _handle_fetch_result(request: Dictionary, result: Dictionary, callback: Callable) -> void:
	if not bool(result.get("ok", false)):
		last_error = str(result.get("error", "排行榜查询失败"))
		_finish_fetch(callback, {"ok": false, "entries": [], "error": last_error})
		return

	# 同一玩家只取自己的最佳成绩；兼容旧数据时按昵称去重。
	var by_player: Dictionary = {}
	var raw_entries: Variant = result.get("entries", [])
	if raw_entries is Array:
		for item: Variant in raw_entries:
			if not item is Dictionary:
				continue
			var entry := (item as Dictionary).duplicate(true)
			var key := str(entry.get("player_id", entry.get("player_name", "")))
			if key.is_empty():
				continue
			if not by_player.has(key) or ScoreRules.is_better(entry, by_player[key]):
				by_player[key] = entry

	# 玩家最佳成绩始终并入；如果同一玩家已在远端列表，只保留更优的一条。
	var level_id := str(request.get("level_id", ""))
	var best := SaveManager.get_level_best(level_id)
	var has_local := false
	if not best.is_empty():
		var local_entry := best.duplicate(true)
		local_entry["player_name"] = SaveManager.get_player_name()
		local_entry["player_id"] = SaveManager.profile_id
		local_entry["is_local"] = true
		local_entry["level_id"] = level_id
		var local_key := str(local_entry.get("player_id", local_entry.get("player_name", "")))
		if not by_player.has(local_key) or ScoreRules.is_better(local_entry, by_player[local_key]):
			by_player[local_key] = local_entry
		else:
			var existing: Dictionary = by_player[local_key]
			existing["is_local"] = true
			by_player[local_key] = existing
		has_local = true

	var merged: Array[Dictionary] = []
	for entry: Variant in by_player.values():
		merged.append((entry as Dictionary).duplicate(true))
	merged.sort_custom(ScoreRules.compare_entries)
	var limit := maxi(1, int(request.get("limit", 10)))
	var local_rank := -1
	for index in merged.size():
		if bool(merged[index].get("is_local", false)):
			local_rank = index + 1
			break

	var visible_entries: Array[Dictionary] = []
	for index in mini(limit, merged.size()):
		var entry := merged[index].duplicate(true)
		entry["rank"] = index + 1
		visible_entries.append(entry)

	# 若玩家排名在前 N 之外，额外追加一条“我的排名”，避免本地成绩被列表截断。
	if has_local and local_rank > limit:
		var local_entry := merged[local_rank - 1].duplicate(true)
		local_entry["rank"] = local_rank
		local_entry["outside_top_limit"] = true
		visible_entries.append(local_entry)

	for entry in visible_entries:
		if not entry.has("is_local"):
			entry["is_local"] = false

	last_error = ""
	_finish_fetch(callback, {"ok": true, "entries": visible_entries, "my_rank": local_rank, "error": ""})


func _finish_fetch(callback: Callable, result: Dictionary) -> void:
	if callback.is_valid():
		callback.call(result)


## 提交成绩。UI 不直接调用，由游戏结算流程调用。
func submit_score(entry: Dictionary, callback: Callable = Callable()) -> void:
	if _provider == null:
		if callback.is_valid():
			callback.call({"ok": false, "error": "排行榜数据源未初始化"})
		return
	_provider.submit_score(entry, func(result: Dictionary) -> void:
		if callback.is_valid():
			callback.call(result)
	)

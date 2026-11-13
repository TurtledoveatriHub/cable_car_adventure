extends Node
## 行为数据聚合服务：
## JSONL 原始事件 -> 运行级聚合 -> 看板 KPI / 趋势 / 碰撞热点 / CSV 导出。
## UI 只调用本服务，不直接读取遥测文件。

signal dashboard_loaded(success: bool)

const COLLISION_BIN_COUNT := 20
const TYPE_LABELS := {
	"bird": "海鸥",
	"storm": "风暴",
	"barrier": "路障",
	"crate": "木箱",
	"fan": "风扇",
	"unknown": "未知",
}
const MOTION_LABELS := {
	"static": "静止",
	"oscillate_x": "左右",
	"oscillate_y": "上下",
	"circle": "圆周",
	"ellipse": "椭圆",
	"unknown": "未知",
}

var last_error: String = ""
var last_dashboard: Dictionary = {}


func load_dashboard(level_filter: String = "", callback: Callable = Callable()) -> void:
	TelemetryService.load_events(func(result: Dictionary) -> void:
		if not bool(result.get("ok", false)):
			last_error = str(result.get("error", "遥测数据读取失败"))
			dashboard_loaded.emit(false)
			if callback.is_valid():
				callback.call({"ok": false, "dashboard": {}, "error": last_error})
			return
		var dashboard := aggregate(result.get("events", []), level_filter)
		last_dashboard = dashboard
		dashboard_loaded.emit(true)
		if callback.is_valid():
			callback.call({"ok": true, "dashboard": dashboard, "error": ""})
	)


## 个人主页专用：复用 TelemetryService 启动时建立的缓存，不再二次读取 JSONL。
## 这样从转场进入个人页时不会在 UI 线程做第二次磁盘解析。
func load_dashboard_cached(level_filter: String = "", callback: Callable = Callable()) -> void:
	var events := TelemetryService.get_events()
	var dashboard := aggregate(events, level_filter)
	last_dashboard = dashboard
	dashboard_loaded.emit(true)
	if callback.is_valid():
		callback.call({"ok": true, "dashboard": dashboard, "error": ""})


func aggregate(events: Array, level_filter: String = "") -> Dictionary:
	var run_ends: Array[Dictionary] = []
	var collisions: Array[Dictionary] = []
	for item: Variant in events:
		if not item is Dictionary:
			continue
		var event := item as Dictionary
		var level_id := str(event.get("level_id", ""))
		if not level_filter.is_empty() and level_id != level_filter:
			continue
		match str(event.get("type", "")):
			"run_end":
				run_ends.append(event)
			"collision":
				collisions.append(event)

	run_ends.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("ts", 0.0)) < float(b.get("ts", 0.0))
	)

	var completed_runs: Array[Dictionary] = []
	for run in run_ends:
		if bool(run.get("completed", false)):
			completed_runs.append(run)

	var total_time := 0.0
	var total_passengers := 0
	var total_lost := 0
	var cart_counts: Dictionary = {}
	var cart_names: Dictionary = {}
	var best_time := INF
	for run in completed_runs:
		total_time += float(run.get("time_seconds", 0.0))
		total_passengers += int(run.get("passengers", 0))
		var starting := int(run.get("starting_passengers", 0))
		var lost := int(run.get("lost_passengers", maxi(0, starting - int(run.get("passengers", 0)))))
		total_lost += lost
		var cart_id := str(run.get("cart_id", "dove"))
		cart_counts[cart_id] = int(cart_counts.get(cart_id, 0)) + 1
		cart_names[cart_id] = str(run.get("cart_name", cart_id))
		best_time = minf(best_time, float(run.get("time_seconds", INF)))
	var most_used_cart := ""
	var most_used_cart_count := 0
	for cart_id: Variant in cart_counts.keys():
		if int(cart_counts[cart_id]) > most_used_cart_count:
			most_used_cart = str(cart_names.get(str(cart_id), str(cart_id)))
			most_used_cart_count = int(cart_counts[cart_id])

	var type_counts: Dictionary = {}
	var motion_counts: Dictionary = {}
	var bins: Array[int] = []
	bins.resize(COLLISION_BIN_COUNT)
	bins.fill(0)
	for collision in collisions:
		var type_id := str(collision.get("obstacle_type", "unknown"))
		var motion_id := str(collision.get("motion_type", "unknown"))
		type_counts[type_id] = int(type_counts.get(type_id, 0)) + 1
		motion_counts[motion_id] = int(motion_counts.get(motion_id, 0)) + 1
		var progress := clampf(float(collision.get("track_progress", 0.0)), 0.0, 0.999)
		var bin_index := int(progress * COLLISION_BIN_COUNT)
		bins[clampi(bin_index, 0, COLLISION_BIN_COUNT - 1)] += 1

	var collision_types: Array[Dictionary] = []
	for type_id: Variant in type_counts.keys():
		collision_types.append({
			"id": str(type_id),
			"label": str(TYPE_LABELS.get(str(type_id), str(type_id))),
			"count": int(type_counts[type_id]),
		})
	collision_types.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("count", 0)) > int(b.get("count", 0))
	)
	var motion_stats: Array[Dictionary] = []
	for motion_id: Variant in motion_counts.keys():
		motion_stats.append({
			"id": str(motion_id),
			"label": str(MOTION_LABELS.get(str(motion_id), str(motion_id))),
			"count": int(motion_counts[motion_id]),
		})
	motion_stats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("count", 0)) > int(b.get("count", 0))
	)

	var per_level: Dictionary = {}
	for run in run_ends:
		var level_id := str(run.get("level_id", "unknown"))
		if not per_level.has(level_id):
			per_level[level_id] = {
				"level_id": level_id,
				"level_name": str(run.get("level_name", level_id)),
				"runs": 0,
				"completed": 0,
				"total_passengers": 0,
				"total_lost": 0,
				"total_time": 0.0,
				"best_time": INF,
				"collisions": 0,
			}
		var bucket: Dictionary = per_level[level_id]
		bucket["runs"] = int(bucket["runs"]) + 1
		bucket["collisions"] = int(bucket["collisions"]) + int(run.get("collisions", 0))
		if bool(run.get("completed", false)):
			bucket["completed"] = int(bucket["completed"]) + 1
			bucket["total_passengers"] = int(bucket["total_passengers"]) + int(run.get("passengers", 0))
			bucket["total_lost"] = int(bucket["total_lost"]) + int(run.get("lost_passengers", 0))
			bucket["total_time"] = float(bucket["total_time"]) + float(run.get("time_seconds", 0.0))
			bucket["best_time"] = minf(float(bucket["best_time"]), float(run.get("time_seconds", INF)))
		per_level[level_id] = bucket

	var level_rows: Array[Dictionary] = []
	for level_id: Variant in per_level.keys():
		var bucket: Dictionary = per_level[level_id]
		var completed := int(bucket.get("completed", 0))
		var runs := int(bucket.get("runs", 0))
		var avg_passengers := 0.0 if completed <= 0 else float(bucket.get("total_passengers", 0)) / float(completed)
		var avg_lost := 0.0 if completed <= 0 else float(bucket.get("total_lost", 0)) / float(completed)
		var avg_time := 0.0 if completed <= 0 else float(bucket.get("total_time", 0.0)) / float(completed)
		var best := float(bucket.get("best_time", INF))
		level_rows.append({
			"level_id": str(level_id),
			"level_name": str(bucket.get("level_name", level_id)),
			"runs": runs,
			"completed": completed,
			"success_rate": 0.0 if runs <= 0 else float(completed) / float(runs) * 100.0,
			"avg_passengers": avg_passengers,
			"avg_lost_passengers": avg_lost,
			"avg_time": avg_time,
			"best_time": 0.0 if best == INF else best,
			"collisions": int(bucket.get("collisions", 0)),
		})
	level_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("runs", 0)) > int(b.get("runs", 0))
	)

	var recent: Array[Dictionary] = []
	var start_index := maxi(0, run_ends.size() - 12)
	for index in range(start_index, run_ends.size()):
		var run: Dictionary = run_ends[index]
		recent.append({
			"ts": float(run.get("ts", 0.0)),
			"level_id": str(run.get("level_id", "")),
			"level_name": str(run.get("level_name", "")),
			"passengers": int(run.get("passengers", 0)),
			"time_seconds": float(run.get("time_seconds", 0.0)),
			"completed": bool(run.get("completed", false)),
			"stars": int(run.get("stars", 0)),
			"collisions": int(run.get("collisions", 0)),
		})

	var completion_rate := 0.0 if run_ends.is_empty() else float(completed_runs.size()) / float(run_ends.size()) * 100.0
	return {
		"level_filter": level_filter,
		"total_runs": run_ends.size(),
		"completed_runs": completed_runs.size(),
		"failed_runs": run_ends.size() - completed_runs.size(),
		"completion_rate": completion_rate,
		"avg_passengers": 0.0 if completed_runs.is_empty() else float(total_passengers) / float(completed_runs.size()),
		"avg_lost_passengers": 0.0 if completed_runs.is_empty() else float(total_lost) / float(completed_runs.size()),
		"most_used_cart": most_used_cart,
		"avg_time": 0.0 if completed_runs.is_empty() else total_time / float(completed_runs.size()),
		"best_time": 0.0 if best_time == INF else best_time,
		"total_lost_passengers": total_lost,
		"total_collisions": collisions.size(),
		"collisions_per_run": 0.0 if run_ends.is_empty() else float(collisions.size()) / float(run_ends.size()),
		"collision_types": collision_types,
		"motion_stats": motion_stats,
		"collision_bins": bins,
		"trend": recent,
		"levels": level_rows,
		"event_count": events.size(),
	}


func export_csv(level_filter: String = "", callback: Callable = Callable()) -> void:
	TelemetryService.load_events(func(result: Dictionary) -> void:
		if not bool(result.get("ok", false)):
			if callback.is_valid():
				callback.call({"ok": false, "error": result.get("error", "读取失败"), "path": "", "count": 0})
			return
		var events: Array = result.get("events", [])
		var directory := "user://analytics"
		DirAccess.make_dir_recursive_absolute(directory)
		var path := directory.path_join("export.csv")
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			if callback.is_valid():
				callback.call({"ok": false, "error": "无法写入 CSV（错误码 %d）" % FileAccess.get_open_error(), "path": "", "count": 0})
			return
		var headers := [
			"ts", "type", "session_id", "run_id", "level_id", "level_name", "mode",
			"completed", "passengers", "starting_passengers", "time_seconds", "stars",
			"collisions", "obstacle_type", "motion_type", "s", "track_progress", "speed",
			"difficulty", "obstacle_scale", "engine_scale",
		]
		file.store_line(",".join(headers))
		var count := 0
		for item: Variant in events:
			if not item is Dictionary:
				continue
			var event := item as Dictionary
			if not level_filter.is_empty() and str(event.get("level_id", "")) != level_filter:
				continue
			var row: Array[String] = []
			for header: String in headers:
				row.append(_csv_cell(event.get(header, "")))
			file.store_line(",".join(row))
			count += 1
		file.flush()
		file.close()
		if callback.is_valid():
			callback.call({
				"ok": true,
				"error": "",
				"path": ProjectSettings.globalize_path(path),
				"user_path": path,
				"count": count,
			})
	)


func _csv_cell(value: Variant) -> String:
	var text := str(value)
	if text.contains(",") or text.contains("\"") or text.contains("\n"):
		text = "\"" + text.replace("\"", "\"\"") + "\""
	return text

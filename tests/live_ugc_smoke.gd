extends Node
## 需要本机后端的联调冒烟测试（不进入普通无头测试套件）。
## 启动 server 后运行：
## Godot ... --headless --path . res://tests/live_ugc_smoke.tscn

const API_BASE := "http://127.0.0.1:3100"

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		print("  FAIL ", label)


func _run() -> void:
	CommunityService.set_offline_mode(false)
	CommunityService.clear_all()
	ApiClient.set_base_url(API_BASE)
	TelemetryService.set_remote_enabled(true)
	await get_tree().process_frame

	var source_level := OS.get_environment("UGC_SMOKE_LEVEL")
	if source_level.is_empty():
		source_level = "level_01"
	var raw := LevelCatalog.get_raw_level(source_level)
	if not bool(raw.get("ok", false)):
		print("LIVE UGC: 无法读取 %s" % source_level)
		get_tree().quit(1)
		return
	var data: Dictionary = (raw.get("data", {}) as Dictionary).duplicate(true)
	var suffix := str(Time.get_ticks_msec() % 100000)
	data["id"] = "custom_live_%s" % suffix
	data["name"] = "联调%s" % suffix
	data["custom"] = true
	data["source"] = "user"
	var saved := LevelCatalog.save_user_level(data)
	_check(bool(saved.get("ok", false)), "创建联调自制关卡")
	var level_id := str(saved.get("id", ""))
	SaveManager.record_result({
		"level_id": level_id,
		"level_starting_passengers": 3,
		"passengers": 3,
		"time_seconds": 18.0,
		"completed": true,
		"stars": 3,
	})

	var upload_state := {"done": false, "result": {}}
	CommunityService.upload_level(level_id, str(data.get("name", "联调关卡")), func(result: Dictionary) -> void:
		upload_state["done"] = true
		upload_state["result"] = result
	)
	while not bool(upload_state["done"]):
		await get_tree().process_frame
	var upload: Dictionary = upload_state["result"]
	_check(bool(upload.get("ok", false)), "上传到联调后端")
	var entry: Dictionary = upload.get("entry", {})
	var entry_id := str(entry.get("id", ""))
	_check(not entry_id.is_empty(), "后端返回关卡 id")

	var feed_state := {"done": false, "result": {}}
	CommunityService.fetch_feed("latest", func(result: Dictionary) -> void:
		feed_state["done"] = true
		feed_state["result"] = result
	)
	while not bool(feed_state["done"]):
		await get_tree().process_frame
	var feed: Dictionary = feed_state["result"]
	_check(bool(feed.get("ok", false)), "读取广场列表")
	var found := false
	for item: Variant in feed.get("entries", []):
		if item is Dictionary and str((item as Dictionary).get("id", "")) == entry_id:
			found = true
	_check(found, "列表包含刚上传关卡")

	var plaza := (load("res://scenes/ui/plaza.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(plaza)
	await get_tree().create_timer(1.0).timeout
	var grid := plaza.get_node("%CardGrid") as GridContainer
	_check(grid.get_child_count() > 0, "广场界面渲染远程关卡卡片")
	plaza.call("_on_like_pressed", entry_id)
	await get_tree().create_timer(0.4).timeout
	var card_refs: Dictionary = (plaza.get("_card_refs_by_id") as Dictionary).get(entry_id, {})
	_check(card_refs.get("likes") is Label, "远程点赞后卡片引用仍是 Label")
	plaza.call("_open_upload_dialog")
	await get_tree().process_frame
	_check(plaza.get("_upload_panel") != null, "广场上传弹窗可打开")
	plaza.call("_close_upload_dialog")
	await get_tree().create_timer(0.3).timeout
	plaza.queue_free()
	await get_tree().process_frame

	var detail_state := {"done": false, "result": {}}
	CommunityService.fetch_detail(entry_id, func(result: Dictionary) -> void:
		detail_state["done"] = true
		detail_state["result"] = result
	)
	while not bool(detail_state["done"]):
		await get_tree().process_frame
	var detail: Dictionary = detail_state["result"]
	_check(bool(detail.get("ok", false)), "读取完整关卡详情")
	var imported := LevelData.from_dictionary(detail.get("level_data", {}))
	_check(imported != null and imported.is_valid(), "服务端关卡可重新载入游戏")

	CommunityService.record_play(entry_id)
	var like := CommunityService.toggle_like(entry_id)
	_check(bool(like.get("ok", false)), "点赞请求")
	var favorite := CommunityService.toggle_favorite(entry_id)
	_check(bool(favorite.get("ok", false)), "收藏请求")
	await get_tree().create_timer(0.5).timeout

	var telemetry_state := {"ok": false}
	TelemetryService.set_remote_enabled(true)
	TelemetryService.begin_run(imported, GameSession.MODE_SOLO, {}, {"starting_passengers": 3})
	TelemetryService.end_run({"completed": true, "passengers": 3, "time_seconds": 12.0})
	ApiClient.get_json("/api/telemetry/summary", {"days": 1}, func(result: Dictionary) -> void:
		telemetry_state["ok"] = bool(result.get("ok", false))
	)
	for index in 30:
		if bool(telemetry_state["ok"]):
			break
		await get_tree().create_timer(0.1).timeout
	_check(bool(telemetry_state["ok"]), "遥测接口可读取汇总")

	var delete_state := {"done": false, "result": {}}
	CommunityService.withdraw_entry(entry_id, func(result: Dictionary) -> void:
		delete_state["done"] = true
		delete_state["result"] = result
	)
	while not bool(delete_state["done"]):
		await get_tree().process_frame
	_check(bool((delete_state["result"] as Dictionary).get("ok", false)), "撤销联调上传")

	LevelCatalog.delete_user_level(level_id)
	print("LIVE UGC CHECKS: %d / %d" % [_checks - _failures.size(), _checks])
	get_tree().quit(0 if _failures.is_empty() else 1)

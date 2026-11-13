extends Node
## 游戏行为遥测服务：统一收集运行开始、碰撞、拾取、结束等事件。
## 玩法 / UI 只调用 log_event / begin_run / end_run，不直接写文件。
## 数据格式为 JSONL，字段可直接进入 pandas / PySpark 分析流程。

signal event_logged(event: Dictionary)
signal events_loaded(success: bool)

var last_error: String = ""
var session_id: String = ""
## 是否把关键事件异步上报到后端 /api/telemetry（测试/截图可关闭）。
var remote_enabled: bool = true

var _backend: TelemetryBackend
var _remote: RemoteTelemetryReporter
var _events: Array[Dictionary] = []
var _current_run: Dictionary = {}
var _run_counter: int = 0
## 本地 JSONL 由逐事件同步写入改为批量落盘。
## 关卡进行中绝不主动刷盘；只在开局前、结算、失焦/退出时写入，彻底避开碰撞帧。
const LOCAL_FLUSH_INTERVAL := 10.0
var _flush_accum: float = 0.0


func _ready() -> void:
	session_id = "s_%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 100000]
	_backend = LocalTelemetryBackend.new()
	_remote = RemoteTelemetryReporter.new()
	if PlatformConfig.is_wechat:
		# 真机上历史 JSONL 可能很大；不要让它的读取阻塞引擎第一帧。
		call_deferred("_reload_cache_after_boot")
	else:
		_reload_cache()
	set_process(true)


func _reload_cache_after_boot() -> void:
	await get_tree().create_timer(0.6, true, false, true).timeout
	_reload_cache()


func _process(delta: float) -> void:
	# 关卡进行中只累积到内存；高帧率玩法里不做周期文件 I/O。
	if _backend == null or not _backend.has_pending() or not _current_run.is_empty():
		_flush_accum = 0.0
		return
	_flush_accum += delta
	if _flush_accum < LOCAL_FLUSH_INTERVAL:
		return
	_flush_accum = 0.0
	var result := _backend.flush_pending()
	if not bool(result.get("ok", false)):
		last_error = str(result.get("error", "遥测落盘失败"))
		push_warning("[Telemetry] " + last_error)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		flush_pending()


## 主动落盘；切后台、退出关卡或看板读取前调用。
func flush_pending() -> void:
	if _backend == null:
		return
	var result := _backend.flush_pending()
	if not bool(result.get("ok", false)):
		last_error = str(result.get("error", "遥测落盘失败"))
		push_warning("[Telemetry] " + last_error)


## 黑屏过渡期间分批写入；每帧只写一小段，不让单帧承担全部 I/O。
func flush_pending_chunked(max_lines: int = 24) -> void:
	if _backend == null:
		return
	var guard := 0
	while _backend.has_pending() and guard < 60:
		guard += 1
		var result := _backend.flush_pending_chunk(max_lines)
		if not bool(result.get("ok", false)):
			last_error = str(result.get("error", "遥测落盘失败"))
			push_warning("[Telemetry] " + last_error)
			return
		if _backend.has_pending():
			await get_tree().process_frame


func set_remote_enabled(value: bool) -> void:
	remote_enabled = value
	if _remote != null:
		_remote.enabled = value


func set_backend(backend: TelemetryBackend) -> void:
	if _backend != null:
		_backend.flush_pending()
	_backend = backend
	_current_run = {}
	_flush_accum = 0.0
	_reload_cache()


func get_backend_id() -> String:
	return _backend.get_backend_id() if _backend != null else "none"


func get_events_path() -> String:
	return _backend.get_path() if _backend is LocalTelemetryBackend else ""


func begin_run(level: LevelData, mode: String, difficulty_info: Dictionary = {}, extra: Dictionary = {}) -> String:
	# 新关卡开始前不主动写文件；上一局的队列已在黑屏过渡中分批落盘。
	_run_counter += 1
	var run_id := "%s_r%d" % [session_id, _run_counter]
	_current_run = {
		"run_id": run_id,
		"level_id": level.id,
		"level_name": level.name,
		"mode": mode,
		"custom": level.custom,
		"difficulty": level.difficulty,
		"starting_passengers": int(extra.get("starting_passengers", 3)),
		"track_length": level.track.total_length,
		"par_time": level.par_time,
		"obstacle_scale": float(difficulty_info.get("obstacle_speed_scale", 1.0)),
		"engine_scale": float(difficulty_info.get("engine_scale", 1.0)),
		"collisions": 0,
	}
	for key: Variant in extra.keys():
		_current_run[key] = extra[key]
	var start_event := log_event("run_start", _current_run.duplicate(true))
	if level.custom:
		_remote_report("enter_custom_level", start_event)
	return run_id


func log_event(event_type: String, data: Dictionary = {}) -> Dictionary:
	var event := {
		"type": event_type,
		"ts": Time.get_unix_time_from_system(),
		"platform": PlatformConfig.get_platform_id(),
		"session_id": session_id,
		"event_id": "%s_%d_%d" % [session_id, Time.get_ticks_msec(), randi() % 100000],
	}
	if not _current_run.is_empty():
		event["run_id"] = _current_run.get("run_id", "")
		event["level_id"] = _current_run.get("level_id", "")
		event["mode"] = _current_run.get("mode", "solo")
	for key: Variant in data.keys():
		event[key] = data[key]
	if event_type == "collision" and not _current_run.is_empty():
		_current_run["collisions"] = int(_current_run.get("collisions", 0)) + 1
	_events.append(event.duplicate(true))
	event_logged.emit(event)
	if _backend != null:
		_backend.append_event(event, func(result: Dictionary) -> void:
			if not bool(result.get("ok", false)):
				last_error = str(result.get("error", "遥测写入失败"))
				push_warning("[Telemetry] " + last_error)
		)
	# 碰撞是卡点分析的核心数据；只上报稀疏事件，并由 reporter 串行批处理。
	if event_type == "collision":
		_remote_report("collision", event)
	return event


func end_run(data: Dictionary) -> Dictionary:
	var payload := data.duplicate(true)
	if not _current_run.is_empty():
		payload["level_id"] = _current_run.get("level_id", payload.get("level_id", ""))
		payload["level_name"] = _current_run.get("level_name", "")
		payload["starting_passengers"] = _current_run.get("starting_passengers", 3)
		payload["track_length"] = _current_run.get("track_length", 0.0)
		payload["par_time"] = _current_run.get("par_time", 60.0)
		payload["difficulty"] = _current_run.get("difficulty", 1)
		payload["custom"] = _current_run.get("custom", false)
		payload["collisions"] = _current_run.get("collisions", 0)
		payload["obstacle_scale"] = _current_run.get("obstacle_scale", 1.0)
		payload["engine_scale"] = _current_run.get("engine_scale", 1.0)
		payload["cart_id"] = _current_run.get("cart_id", "dove")
		payload["cart_name"] = _current_run.get("cart_name", "")
		payload["lost_passengers"] = maxi(0, int(_current_run.get("starting_passengers", 3)) - int(payload.get("passengers", 0)))
	var event := log_event("run_end", payload)
	# 只入内存队列；SceneRouter 会在黑屏转场里分批落盘。
	_remote_report("run_end", event)
	_current_run = {}
	return event


func _remote_report(event_type: String, event: Dictionary) -> void:
	if not remote_enabled or _remote == null:
		return
	if not ApiClient.is_configured():
		return
	_remote.report(event_type, event)


func get_events() -> Array[Dictionary]:
	return _events.duplicate(true)


func load_events(callback: Callable = Callable()) -> void:
	if _backend == null:
		if callback.is_valid():
			callback.call({"ok": false, "events": [], "error": "遥测后端未初始化"})
		return
	_backend.load_events(func(result: Dictionary) -> void:
		if not bool(result.get("ok", false)):
			last_error = str(result.get("error", "遥测读取失败"))
			if callback.is_valid():
				callback.call(result)
			return
		var loaded: Array[Dictionary] = []
		for item: Variant in result.get("events", []):
			if item is Dictionary:
				loaded.append((item as Dictionary).duplicate(true))
		_events = loaded
		events_loaded.emit(true)
		if callback.is_valid():
			callback.call({"ok": true, "events": _events.duplicate(true), "error": ""})
	)


func clear_events(callback: Callable = Callable()) -> void:
	_events.clear()
	_current_run = {}
	_flush_accum = 0.0
	if _backend == null:
		if callback.is_valid():
			callback.call({"ok": true, "error": ""})
		return
	_backend.clear_events(func(result: Dictionary) -> void:
		if callback.is_valid():
			callback.call(result)
	)


func _reload_cache() -> void:
	if _backend == null:
		return
	_backend.load_events(func(result: Dictionary) -> void:
		if bool(result.get("ok", false)):
			_events.clear()
			for item: Variant in result.get("events", []):
				if item is Dictionary:
					_events.append((item as Dictionary).duplicate(true))
			events_loaded.emit(true)
		else:
			last_error = str(result.get("error", "遥测加载失败"))
			events_loaded.emit(false)
	)


func get_current_run_id() -> String:
	return str(_current_run.get("run_id", ""))

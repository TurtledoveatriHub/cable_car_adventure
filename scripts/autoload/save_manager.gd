extends Node
## 独立存档管理模块。
## UI 与玩法只调用这里的高层 API；文件 / 云端读写全部交给 StorageBackend。
## 当前默认注入 LocalFileStorage，未来调用 set_storage_backend() 即可切换云端。

signal profile_loaded(success: bool)
signal profile_saved(success: bool)
signal data_changed
signal best_updated(level_id: String, best: Dictionary)

const SAVE_VERSION := 1
const PROGRESS_SCHEMA := 2
const LOCAL_PROFILE_ID := "local_player"
const DEFAULT_PLAYER_NAME := "游客"

var is_ready: bool = false
var last_error: String = ""
var profile_id: String = LOCAL_PROFILE_ID

var _backend: StorageBackend
var _data: Dictionary = {}
var _pending_save_count: int = 0
var _save_scheduled: bool = false
var _save_generation: int = 0


func _ready() -> void:
	# 微信端优先使用 wx.setStorageSync：WXMEMFS 的 rename/目录同步在部分
	# 真机与开发者工具上会导致 user:// 存档重启丢失。桌面/Web 继续用文件。
	# 同时检查 backend.is_available()，避免 autoload 初始化顺序影响平台判断。
	var wechat_backend := WeChatStorage.new()
	if wechat_backend.is_available():
		_backend = wechat_backend
	else:
		_backend = LocalFileStorage.new()
	reload_profile()


func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_WM_CLOSE_REQUEST
		or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT
		or what == NOTIFICATION_APPLICATION_FOCUS_OUT
		or what == NOTIFICATION_APPLICATION_PAUSED
	):
		flush_now()


## 替换存储后端。云端接入入口：保存管理器本身不需要任何改动。
func set_storage_backend(backend: StorageBackend, new_profile_id: String = LOCAL_PROFILE_ID) -> void:
	_backend = backend
	profile_id = new_profile_id
	reload_profile()


func get_storage_backend_id() -> String:
	return _backend.get_backend_id() if _backend != null else "none"


func get_storage_display_name() -> String:
	return _backend.get_display_name() if _backend != null else "未配置"


func reload_profile() -> void:
	is_ready = false
	last_error = ""
	if _backend == null:
		last_error = "存档后端未初始化"
		profile_loaded.emit(false)
		return

	_backend.load_profile(profile_id, _on_profile_loaded)


func _on_profile_loaded(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		last_error = str(result.get("error", "存档读取失败"))
		_data = _default_profile()
		is_ready = true
		push_error("[SaveManager] " + last_error)
		profile_loaded.emit(false)
		data_changed.emit()
		return

	var loaded_data: Variant = result.get("data", {})
	var loaded_schema := int((loaded_data as Dictionary).get("progress_schema", 0)) if loaded_data is Dictionary else 0
	if loaded_data is Dictionary:
		_data = _merge_with_defaults(loaded_data)
	else:
		_data = _default_profile()
		last_error = "存档数据格式错误，已使用默认存档"
		push_error("[SaveManager] " + last_error)

	if loaded_schema < PROGRESS_SCHEMA:
		# 旧版本把自制/试玩关卡混入主线统计；升级时清空一次关卡进度。
		_data["levels"] = {}
		_data["progress_schema"] = PROGRESS_SCHEMA
	is_ready = true
	request_save()
	profile_loaded.emit(true)
	data_changed.emit()


func _default_profile() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"progress_schema": PROGRESS_SCHEMA,
		"player_name": DEFAULT_PLAYER_NAME,
		"created_at": int(Time.get_unix_time_from_system()),
		"updated_at": int(Time.get_unix_time_from_system()),
		"levels": {},
		"settings": {
			"music_enabled": true,
			"sfx_enabled": true,
			"touch_controls": "auto",
			"duo_split": "stacked",
			"duo_show_ghost": true,
			"cart_p1": "dove",
			"cart_p2": "dove",
			"display_mode": 0,
			"master_volume": 70.0,
			"music_volume": 70.0,
			"sfx_volume": 70.0,
			"seen_cart_unlocks": ["dove"],
			"unlock_all_carts": false,
			"touch_single_size": 96.0,
			"touch_single_opacity": 0.72,
			"touch_single_y": 0.84,
			"touch_single_inset": 0.06,
			"touch_single_positions": {},
			"touch_duo_size": 82.0,
			"touch_duo_opacity": 0.68,
			"touch_duo_y": 0.80,
			"touch_duo_inset": 0.05,
			"touch_duo_positions": {},
			"touch_layout_version": 1,
		},
	}


## 兼容旧版本存档：缺失字段补默认值，但保留已有关卡成绩。
func _merge_with_defaults(raw: Dictionary) -> Dictionary:
	var merged := _default_profile()
	merged["version"] = SAVE_VERSION
	merged["player_name"] = str(raw.get("player_name", DEFAULT_PLAYER_NAME))
	if merged["player_name"].strip_edges().is_empty():
		merged["player_name"] = DEFAULT_PLAYER_NAME
	if merged["player_name"].length() > 8:
		merged["player_name"] = merged["player_name"].substr(0, 8)
	merged["created_at"] = int(raw.get("created_at", merged["created_at"]))

	var raw_levels: Variant = raw.get("levels", {})
	if raw_levels is Dictionary:
		for level_id: Variant in raw_levels.keys():
			var progress: Variant = raw_levels[level_id]
			if progress is Dictionary:
				merged["levels"][str(level_id)] = _sanitize_progress(progress)

	var raw_settings: Variant = raw.get("settings", {})
	if raw_settings is Dictionary:
		for key: Variant in raw_settings.keys():
			if merged["settings"].has(str(key)):
				merged["settings"][str(key)] = raw_settings[key]

	return merged


func _sanitize_progress(progress: Dictionary) -> Dictionary:
	var clean := {
		"attempts": maxi(0, int(progress.get("attempts", 0))),
		"cleared": bool(progress.get("cleared", false)),
		"stars": clampi(int(progress.get("stars", 0)), 0, 3),
		"last_played_at": int(progress.get("last_played_at", 0)),
		"best": {},
	}
	var best_value: Variant = progress.get("best", {})
	if best_value is Dictionary and bool(best_value.get("completed", false)):
		var time_seconds := maxf(0.0, float(best_value.get("time_seconds", 0.0)))
		var passengers := maxi(0, int(best_value.get("passengers", 0)))
		clean["best"] = ScoreRules.make_entry(
			str(best_value.get("level_id", "")),
			passengers,
			time_seconds,
			str(best_value.get("player_name", get_player_name())),
			true,
		)
	return clean


func get_player_name() -> String:
	return str(_data.get("player_name", DEFAULT_PLAYER_NAME))


func get_player_id() -> String:
	# 由本地档案创建时间派生稳定展示 ID，不暴露真实用户信息。
	return "SW-%06d" % (int(_data.get("created_at", 0)) % 1000000)


func get_player_created_at() -> int:
	return int(_data.get("created_at", 0))


func set_player_name(new_name: String) -> void:
	var clean_name := new_name.strip_edges()
	if clean_name.is_empty():
		clean_name = DEFAULT_PLAYER_NAME
	if clean_name.length() > 8:
		clean_name = clean_name.substr(0, 8)
	_data["player_name"] = clean_name
	request_save()


func get_level_progress(level_id: String) -> Dictionary:
	var levels: Dictionary = _data.get("levels", {})
	var value: Variant = levels.get(level_id, {})
	return value.duplicate(true) if value is Dictionary else {}


func get_level_best(level_id: String) -> Dictionary:
	var progress := get_level_progress(level_id)
	var best_value: Variant = progress.get("best", {})
	if not best_value is Dictionary:
		return {}
	return (best_value as Dictionary).duplicate(true)


func is_level_cleared(level_id: String) -> bool:
	return bool(get_level_progress(level_id).get("cleared", false))


func get_level_stars(level_id: String) -> int:
	return int(get_level_progress(level_id).get("stars", 0))


func get_total_stars() -> int:
	var total := 0
	var levels: Dictionary = _data.get("levels", {})
	for level_id: Variant in levels.keys():
		total += get_level_stars(str(level_id))
	return total


func get_cleared_count() -> int:
	var total := 0
	var levels: Dictionary = _data.get("levels", {})
	for level_id: Variant in levels.keys():
		if bool((levels[level_id] as Dictionary).get("cleared", false)):
			total += 1
	return total


## 游戏结束时写入成绩。只有通关成绩会刷新最佳记录，失败只累计挑战次数。
## 返回：{ "saved": bool, "is_new_best": bool, "best": Dictionary, "previous_best": Dictionary }
func record_result(result: Dictionary) -> Dictionary:
	var level_id := str(result.get("level_id", ""))
	if level_id.is_empty():
		return {"saved": false, "is_new_best": false, "best": {}, "previous_best": {}}

	var completed := bool(result.get("completed", false))
	var passengers := maxi(0, int(result.get("passengers", 0)))
	var time_seconds := maxf(0.0, float(result.get("time_seconds", 0.0)))
	var stars := clampi(int(result.get("stars", 0)), 0, 3)

	var levels: Dictionary = _data.get("levels", {})
	var progress: Dictionary = levels.get(level_id, {})
	if progress.is_empty():
		progress = {
			"attempts": 0,
			"cleared": false,
			"stars": 0,
			"last_played_at": 0,
			"best": {},
		}

	progress["attempts"] = int(progress.get("attempts", 0)) + 1
	progress["last_played_at"] = int(Time.get_unix_time_from_system())

	var previous_best := get_level_best(level_id)
	var is_new_best := false
	if completed:
		progress["cleared"] = true
		progress["stars"] = maxi(int(progress.get("stars", 0)), stars)
		var candidate := ScoreRules.make_entry(
			level_id,
			passengers,
			time_seconds,
			get_player_name(),
			true,
			int(result.get("level_starting_passengers", 0)),
			str(result.get("cart_id", "dove")),
			str(result.get("cart_name", "")),
		)
		if ScoreRules.is_better(candidate, previous_best):
			progress["best"] = candidate
			is_new_best = true

	levels[level_id] = progress
	_data["levels"] = levels
	request_save()
	# 通关后把“当前版本”记为已通关；若之后在工坊修改，上传前必须再通关一次。
	if completed and level_id.begins_with("custom_"):
		LevelRepository.mark_cleared(level_id)
	# 微信端在结算时立即落盘，避免玩家返回后直接杀进程导致 0.25 秒延迟写丢失。
	if PlatformConfig.is_wechat or (
		_backend != null and _backend.get_backend_id() == "wechat_storage"
	):
		flush_now()

	var final_best := get_level_best(level_id)
	if is_new_best and not final_best.is_empty():
		best_updated.emit(level_id, final_best)

	return {
		"saved": true,
		"is_new_best": is_new_best,
		"best": final_best,
		"previous_best": previous_best,
	}


func get_settings() -> Dictionary:
	var settings: Dictionary = _data.get("settings", {})
	return settings.duplicate(true)


func get_setting(key: String, fallback: Variant = null) -> Variant:
	var settings: Dictionary = _data.get("settings", {})
	return settings.get(key, fallback)


func set_setting(key: String, value: Variant) -> void:
	var settings: Dictionary = _data.get("settings", {})
	settings[key] = value
	_data["settings"] = settings
	request_save()
	data_changed.emit()


## 延迟写盘：结算/设置变化先只改内存，0.25 秒后落盘；SceneRouter 会在
## 黑屏转场里调用 flush_now，把实际文件 I/O 藏到转场幕后。
func request_save() -> void:
	if _backend == null or not is_ready:
		return
	_data["updated_at"] = int(Time.get_unix_time_from_system())
	if _save_scheduled:
		return
	_save_scheduled = true
	_save_generation += 1
	_schedule_save(_save_generation)


func _schedule_save(generation: int) -> void:
	await get_tree().create_timer(0.25, true, false, true).timeout
	if not _save_scheduled or generation != _save_generation:
		return
	flush_now()


## 强制把当前内存档写盘；黑屏转场、切后台/退出时调用。
func flush_now() -> void:
	if _backend == null or not is_ready or not _save_scheduled:
		return
	_save_scheduled = false
	_pending_save_count += 1
	_backend.save_profile(profile_id, _data.duplicate(true), _on_profile_saved)


func _on_profile_saved(result: Dictionary) -> void:
	_pending_save_count = maxi(0, _pending_save_count - 1)
	var ok := bool(result.get("ok", false))
	if not ok:
		last_error = str(result.get("error", "存档写入失败"))
		push_error("[SaveManager] " + last_error)
	profile_saved.emit(ok)
	data_changed.emit()


## 测试与开发工具用：直接清空进度，保留设置与玩家名。
func reset_progress() -> void:
	_data["levels"] = {}
	request_save()
	data_changed.emit()


func get_debug_snapshot() -> Dictionary:
	return _data.duplicate(true)

extends Node
## 全局关卡目录服务：合并内置 JSON 与 user://levels 自定义 JSON，并缓存关卡对象。
## 编辑器 / UI / 玩法都通过该单例访问关卡，不直接接触文件。

signal catalog_loaded(success: bool)

var last_error: String = ""
var _builtin_summaries: Array[Dictionary] = []
var _user_summaries: Array[Dictionary] = []
var _summaries: Array[Dictionary] = []
var _level_cache: Dictionary = {}
var _level_errors: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	_builtin_summaries.clear()
	_user_summaries.clear()
	_summaries.clear()
	_level_cache.clear()
	_level_errors.clear()
	last_error = ""

	var builtin_result := LevelRepository.load_index()
	if not bool(builtin_result.get("ok", false)):
		last_error = str(builtin_result.get("error", "内置关卡目录加载失败"))
		push_error("[LevelCatalog] " + last_error)
		catalog_loaded.emit(false)
		return
	_builtin_summaries = builtin_result.get("levels", [])
	_user_summaries = LevelRepository.load_user_level_summaries()
	_summaries.append_array(_builtin_summaries)
	for summary in _user_summaries:
		if not has_level(str(summary.get("id", ""))):
			_summaries.append(summary)

	catalog_loaded.emit(true)


func get_summaries() -> Array[Dictionary]:
	return _summaries.duplicate(true)


func get_builtin_summaries() -> Array[Dictionary]:
	return _builtin_summaries.duplicate(true)


func get_user_summaries() -> Array[Dictionary]:
	return _user_summaries.duplicate(true)


func next_unique_user_name(base_name: String) -> String:
	var base := base_name.strip_edges()
	if base.is_empty():
		base = "我的环线"
	var used: Dictionary = {}
	for summary in _user_summaries:
		used[str(summary.get("name", "")).strip_edges()] = true
	if not used.has(base):
		return base
	var index := 2
	while used.has("%s%d" % [base, index]):
		index += 1
	return "%s%d" % [base, index]


func get_summary(level_id: String) -> Dictionary:
	for summary in _summaries:
		if str(summary.get("id", "")) == level_id:
			return summary.duplicate(true)
	return {}


func has_level(level_id: String) -> bool:
	for summary in _summaries:
		if str(summary.get("id", "")) == level_id:
			return true
	return false


func get_level(level_id: String) -> LevelData:
	if _level_cache.has(level_id):
		return _level_cache[level_id] as LevelData
	var summary := get_summary(level_id)
	if summary.is_empty():
		last_error = "关卡不存在：%s" % level_id
		push_error("[LevelCatalog] " + last_error)
		return null
	var path := str(summary.get("path", ""))
	var is_user := path.begins_with("user://")
	var result := LevelRepository.load_level(path, is_user)
	if not bool(result.get("ok", false)):
		last_error = str(result.get("error", "关卡加载失败"))
		_level_errors[level_id] = last_error
		push_error("[LevelCatalog] " + last_error)
		return null
	var level := result.get("level") as LevelData
	if level == null:
		last_error = "关卡数据类型错误：%s" % level_id
		push_error("[LevelCatalog] " + last_error)
		return null
	if level.subtitle.is_empty():
		level.subtitle = str(summary.get("subtitle", ""))
	if level.description.is_empty():
		level.description = str(summary.get("description", ""))
	if level.name.is_empty():
		level.name = str(summary.get("name", level_id))
	level.source = str(summary.get("source", level.source))
	level.custom = bool(summary.get("custom", level.custom))
	_level_cache[level_id] = level
	return level


## 编辑器载入原始 JSON（用于复制内置关卡或编辑已有自定义关卡）。
func get_raw_level(level_id: String) -> Dictionary:
	var summary := get_summary(level_id)
	if summary.is_empty():
		return {"ok": false, "data": {}, "error": "关卡不存在"}
	var read_result := LevelRepository.read_json(str(summary.get("path", "")))
	if not bool(read_result.get("ok", false)):
		return {"ok": false, "data": {}, "error": str(read_result.get("error", "读取失败"))}
	return {"ok": true, "data": read_result.get("data", {}), "error": ""}


func save_user_level(data: Dictionary) -> Dictionary:
	var requested_name := str(data.get("name", "")).strip_edges()
	var requested_id := str(data.get("id", ""))
	if not requested_name.is_empty():
		for summary in _summaries:
			if not bool(summary.get("custom", false)):
				continue
			if str(summary.get("id", "")) == requested_id:
				continue
			if str(summary.get("name", "")).strip_edges().to_lower() == requested_name.to_lower():
				return {"ok": false, "error": "自制关卡名称不能重复，请换一个名称"}
	var result := LevelRepository.save_user_level(data)
	if not bool(result.get("ok", false)):
		return result
	reload()
	var level_id := str(result.get("id", ""))
	if not has_level(level_id):
		return {"ok": false, "error": "自定义关卡保存后未能重新载入"}
	return {
		"ok": true,
		"id": level_id,
		"summary": get_summary(level_id),
		"error": "",
	}


func delete_user_level(level_id: String) -> Dictionary:
	var result := LevelRepository.delete_user_level(level_id)
	if bool(result.get("ok", false)):
		reload()
	return result


func generate_custom_id() -> String:
	var timestamp := Time.get_datetime_dict_from_system()
	return "custom_%04d%02d%02d_%02d%02d%02d" % [
		int(timestamp.year),
		int(timestamp.month),
		int(timestamp.day),
		int(timestamp.hour),
		int(timestamp.minute),
		int(timestamp.second),
	]


func get_level_error(level_id: String) -> String:
	return str(_level_errors.get(level_id, ""))


func get_level_count() -> int:
	return _summaries.size()


func get_builtin_count() -> int:
	return _builtin_summaries.size()

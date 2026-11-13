class_name LevelRepository
extends RefCounted
## 关卡 JSON 的唯一文件读写入口。
## 内置关卡在 res://data/levels；编辑器产出的自定义关卡在 user://levels。
## UI 和玩法层只通过 LevelCatalog 访问，不直接使用 FileAccess。

const LEVEL_INDEX_PATH := "res://data/levels/index.json"
const USER_LEVEL_DIRECTORY := "user://levels"


static func load_index(index_path: String = LEVEL_INDEX_PATH) -> Dictionary:
	var read_result := read_json(index_path)
	if not bool(read_result.get("ok", false)):
		return {"ok": false, "levels": [], "error": str(read_result.get("error", "未知错误"))}

	var root: Variant = read_result.get("data")
	if not root is Dictionary:
		return {"ok": false, "levels": [], "error": "关卡目录根节点必须是对象"}

	var raw_levels: Variant = root.get("levels", [])
	if not raw_levels is Array:
		return {"ok": false, "levels": [], "error": "关卡目录缺少 levels 数组"}

	var base_dir := index_path.get_base_dir()
	var levels: Array[Dictionary] = []
	for index in raw_levels.size():
		var item: Variant = raw_levels[index]
		if not item is Dictionary:
			return {"ok": false, "levels": [], "error": "关卡目录第 %d 项不是对象" % index}
		var summary: Dictionary = (item as Dictionary).duplicate(true)
		var id := str(summary.get("id", ""))
		var file := str(summary.get("file", ""))
		if id.is_empty() or file.is_empty():
			return {"ok": false, "levels": [], "error": "关卡目录第 %d 项缺少 id 或 file" % index}
		summary["path"] = file if file.begins_with("res://") else base_dir.path_join(file)
		summary["source"] = "builtin"
		summary["custom"] = false
		levels.append(summary)

	if levels.is_empty():
		return {"ok": false, "levels": [], "error": "关卡目录为空"}

	return {"ok": true, "levels": levels, "error": ""}


## 扫描 user://levels 下的自定义关卡，构造与内置关卡一致的摘要列表。
static func load_user_level_summaries() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	var dir := DirAccess.open(USER_LEVEL_DIRECTORY)
	if dir == null:
		return summaries
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".json"):
			var path := USER_LEVEL_DIRECTORY.path_join(file_name)
			var loaded := load_level(path, true)
			if bool(loaded.get("ok", false)):
				var level := loaded.get("level") as LevelData
				var summary := level.get_summary()
				summary["path"] = path
				summary["file"] = file_name
				summary["source"] = "user"
				summary["custom"] = true
				summaries.append(summary)
			else:
				push_warning("[LevelRepository] 跳过损坏的自定义关卡 %s：%s" % [
					file_name,
					str(loaded.get("error", "")),
				])
		file_name = dir.get_next()
	dir.list_dir_end()
	summaries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	return summaries


static func load_level(level_path: String, is_user_level: bool = false) -> Dictionary:
	var read_result := read_json(level_path)
	if not bool(read_result.get("ok", false)):
		return {"ok": false, "level": null, "error": str(read_result.get("error", "未知错误"))}

	var data: Variant = read_result.get("data")
	if not data is Dictionary:
		return {"ok": false, "level": null, "error": "关卡根节点必须是对象"}

	var level_data: Dictionary = (data as Dictionary).duplicate(true)
	level_data["source"] = "user" if is_user_level else "builtin"
	level_data["custom"] = is_user_level
	var level := LevelData.from_dictionary(level_data)
	if not level.is_valid():
		return {
			"ok": false,
			"level": level,
			"error": "关卡 %s 校验失败：%s" % [level.id, "；".join(level.validation_errors)],
		}
	return {"ok": true, "level": level, "error": ""}


## 编辑器保存自定义关卡。仅允许 custom_ 前缀，避免覆盖内置关卡。
static func save_user_level(data: Dictionary) -> Dictionary:
	var level_id := sanitize_user_id(str(data.get("id", "")))
	if level_id.is_empty():
		return {"ok": false, "error": "自定义关卡 id 不能为空"}
	if not level_id.begins_with("custom_"):
		level_id = "custom_" + level_id
	var payload := data.duplicate(true)
	payload["id"] = level_id
	payload["source"] = "user"
	payload["custom"] = true
	payload["schema_version"] = LevelData.SCHEMA_VERSION
	# 编辑器重存会整体覆写 JSON，必须保留既有已上传标记，否则改一次关卡就丢 server_id、又能重复上传。
	# 仅在调用方未显式携带这些字段时从磁盘旧文件回填。
	_preserve_upload_mark(payload, level_id)
	var level := LevelData.from_dictionary(payload)
	if not level.is_valid():
		return {"ok": false, "error": "；".join(level.validation_errors)}

	var error := DirAccess.make_dir_recursive_absolute(USER_LEVEL_DIRECTORY)
	if error != OK and error != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": "无法创建自定义关卡目录（错误码 %d）" % error}
	var path := get_user_level_path(level_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "无法写入自定义关卡（错误码 %d）" % FileAccess.get_open_error()}
	file.store_string(JSON.stringify(payload, "\t", false))
	file.flush()
	file.close()
	return {"ok": true, "id": level_id, "path": path, "error": ""}


static func delete_user_level(level_id: String) -> Dictionary:
	var safe_id := sanitize_user_id(level_id)
	if not safe_id.begins_with("custom_"):
		return {"ok": false, "error": "只能删除 custom_ 前缀的自定义关卡"}
	var path := get_user_level_path(safe_id)
	if not FileAccess.file_exists(path):
		return {"ok": true, "error": ""}
	var error := DirAccess.remove_absolute(path)
	return {"ok": error == OK, "error": "" if error == OK else "删除失败（错误码 %d）" % error}


static func get_user_level_path(level_id: String) -> String:
	return USER_LEVEL_DIRECTORY.path_join(sanitize_user_id(level_id) + ".json")


## 已上传标记字段。写在 user://levels/*.json 顶层，均在规范化输出之外，不影响指纹与关卡加载。
const UPLOAD_MARK_KEYS := [
	"server_id", "server_content_hash", "server_uploaded_at", "uploaded_local_hash",
]
const CLEARED_HASH_KEY := "cleared_local_hash"
const RECLEAR_KEY := "upload_needs_reclear"


## 读取本地关卡的已上传标记。返回 {} 表示未上传或文件不存在。
static func get_upload_mark(level_id: String) -> Dictionary:
	var path := get_user_level_path(level_id)
	if not FileAccess.file_exists(path):
		return {}
	var read_result := read_json(path)
	if not bool(read_result.get("ok", false)) or not (read_result.get("data") is Dictionary):
		return {}
	var data: Dictionary = read_result.get("data")
	if str(data.get("server_id", "")).is_empty():
		return {}
	return {
		"server_id": str(data.get("server_id", "")),
		"server_content_hash": str(data.get("server_content_hash", "")),
		"uploaded_local_hash": str(data.get("uploaded_local_hash", "")),
		"server_uploaded_at": int(data.get("server_uploaded_at", 0)),
	}


## 上传成功后把服务端返回的 id 与指纹回写到本地关卡 JSON。
## local_hash 是客户端对“本次上传内容”的指纹；服务端 content_hash 算法变化时
## 仍可用它判断上传后是否又在工坊里改过。
static func mark_uploaded(
	level_id: String,
	server_id: String,
	content_hash: String,
	local_hash: String = ""
) -> Dictionary:
	var path := get_user_level_path(level_id)
	var read_result := read_json(path)
	if not bool(read_result.get("ok", false)) or not (read_result.get("data") is Dictionary):
		return {"ok": false, "error": "关卡文件不存在或已损坏"}
	var data: Dictionary = read_result.get("data")
	if local_hash.is_empty():
		local_hash = compute_content_hash(data)
	data["server_id"] = server_id
	data["server_content_hash"] = content_hash
	data["uploaded_local_hash"] = local_hash
	data[RECLEAR_KEY] = false
	data["server_uploaded_at"] = int(Time.get_unix_time_from_system())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "无法写入关卡文件（错误码 %d）" % FileAccess.get_open_error()}
	file.store_string(JSON.stringify(data, "\t", false))
	file.flush()
	file.close()
	return {"ok": true, "error": ""}


## 通关/试玩成功时记录“当前版本已通关”的指纹。
## 之后若内容再变化，needs_reclear 会阻止直接重新上传，直到玩家再次通关。
static func mark_cleared(level_id: String) -> void:
	var path := get_user_level_path(level_id)
	var read_result := read_json(path)
	if not bool(read_result.get("ok", false)) or not (read_result.get("data") is Dictionary):
		return
	var data: Dictionary = read_result.get("data")
	data[CLEARED_HASH_KEY] = compute_content_hash(data)
	data.erase(RECLEAR_KEY)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "\t", false))
	file.flush()
	file.close()


static func needs_reclear(level_id: String) -> bool:
	var data := _read_level_data(level_id)
	return bool(data.get(RECLEAR_KEY, false))


## 计算与上传标记无关的内容指纹，用于检测“上传后是否改过”。
static func compute_content_hash(data: Dictionary) -> String:
	var clean := data.duplicate(true)
	for key in UPLOAD_MARK_KEYS:
		clean.erase(key)
	clean.erase(CLEARED_HASH_KEY)
	clean.erase(RECLEAR_KEY)
	var validation := UgcLevelDocument.validate_level(clean)
	if not bool(validation.get("ok", false)):
		return ""
	var normalized: Dictionary = validation.get("level_data", {})
	return JSON.stringify(normalized, "", false).sha256_text()


## 撤销上传后清空本地标记，允许重新上传；内容指纹与“需重新通关”状态保留。
static func clear_upload_mark(level_id: String) -> void:
	var path := get_user_level_path(level_id)
	if not FileAccess.file_exists(path):
		return
	var read_result := read_json(path)
	if not bool(read_result.get("ok", false)) or not (read_result.get("data") is Dictionary):
		return
	var data: Dictionary = read_result.get("data")
	var changed := false
	for key in UPLOAD_MARK_KEYS:
		if data.has(key):
			data.erase(key)
			changed = true
	if not changed:
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "\t", false))
	file.flush()
	file.close()


## 反查：给定服务端 entry_id，找到对应本地关卡并清空标记（撤销时只知道 entry_id）。
static func clear_upload_mark_by_server_id(server_id: String) -> void:
	if server_id.is_empty():
		return
	var dir := DirAccess.open(USER_LEVEL_DIRECTORY)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".json"):
			var path := USER_LEVEL_DIRECTORY.path_join(file_name)
			var read_result := read_json(path)
			if bool(read_result.get("ok", false)) and (read_result.get("data") is Dictionary):
				var data: Dictionary = read_result.get("data")
				if str(data.get("server_id", "")) == server_id:
					clear_upload_mark(str(data.get("id", "")))
		file_name = dir.get_next()
	dir.list_dir_end()


## 保存前从磁盘旧文件回填已上传标记，仅当 payload 未显式携带时生效。
static func _preserve_upload_mark(payload: Dictionary, level_id: String) -> void:
	var old := _read_level_data(level_id)
	if old.is_empty():
		return
	if str(payload.get("server_id", "")).is_empty() and not str(old.get("server_id", "")).is_empty():
		payload["server_id"] = str(old.get("server_id", ""))
		payload["server_content_hash"] = str(old.get("server_content_hash", ""))
		payload["server_uploaded_at"] = int(old.get("server_uploaded_at", 0))
	# 编辑器草稿不一定知道这些内部字段；缺少时从磁盘旧文件回填，避免保存后丢基准。
	if str(payload.get("uploaded_local_hash", "")).is_empty() and old.has("uploaded_local_hash"):
		payload["uploaded_local_hash"] = str(old.get("uploaded_local_hash", ""))
	if str(payload.get(CLEARED_HASH_KEY, "")).is_empty() and old.has(CLEARED_HASH_KEY):
		payload[CLEARED_HASH_KEY] = str(old.get(CLEARED_HASH_KEY, ""))
	if not payload.has(RECLEAR_KEY) and old.has(RECLEAR_KEY):
		payload[RECLEAR_KEY] = bool(old.get(RECLEAR_KEY, false))
	# 以“最近一次通关的版本”为基准；老存档没有 cleared 指纹时退回上传指纹。
	var baseline := str(old.get(CLEARED_HASH_KEY, ""))
	if baseline.is_empty():
		baseline = str(old.get("uploaded_local_hash", ""))
	if baseline.is_empty():
		return
	var current := compute_content_hash(payload)
	if current.is_empty():
		return
	if current == baseline:
		payload.erase(RECLEAR_KEY)
	else:
		payload[RECLEAR_KEY] = true


static func _read_level_data(level_id: String) -> Dictionary:
	var path := get_user_level_path(level_id)
	if not FileAccess.file_exists(path):
		return {}
	var read_result := read_json(path)
	if not bool(read_result.get("ok", false)) or not (read_result.get("data") is Dictionary):
		return {}
	return (read_result.get("data") as Dictionary)


static func sanitize_user_id(raw_id: String) -> String:
	var safe := ""
	for character in raw_id.strip_edges().to_lower():
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character == "_":
			safe += character
	if safe.is_empty():
		return ""
	if safe.length() > 48:
		safe = safe.substr(0, 48)
	return safe


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": null, "error": "文件不存在：%s" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"data": null,
			"error": "无法读取 %s（错误码 %d）" % [path, FileAccess.get_open_error()],
		}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var parse_error := json.parse(text)
	if parse_error != OK:
		return {
			"ok": false,
			"data": null,
			"error": "JSON 解析失败 %s 第 %d 行：%s" % [path, json.get_error_line(), json.get_error_message()],
		}
	return {"ok": true, "data": json.data, "error": ""}

class_name LocalFileStorage
extends StorageBackend
## 当前版本的本地存档后端。
## 仅该文件允许接触 FileAccess；未来切换云端时替换为云后端即可。

const SAVE_DIRECTORY := "user://save"
const PROFILE_TEMPLATE := "profile_%s.json"


func get_backend_id() -> String:
	return "local_file"


func get_display_name() -> String:
	return "本地文件"


func load_profile(profile_id: String, callback: Callable) -> void:
	var path := _get_profile_path(profile_id)
	if not FileAccess.file_exists(path):
		callback.call({"ok": true, "exists": false, "data": {}, "error": ""})
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		callback.call({
			"ok": false,
			"exists": false,
			"data": {},
			"error": "无法打开存档（错误码 %d）" % FileAccess.get_open_error(),
		})
		return

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		callback.call({
			"ok": false,
			"exists": true,
			"data": {},
			"error": "存档 JSON 损坏：第 %d 行 %s" % [json.get_error_line(), json.get_error_message()],
		})
		return

	if not json.data is Dictionary:
		callback.call({"ok": false, "exists": true, "data": {}, "error": "存档根节点不是对象"})
		return

	callback.call({"ok": true, "exists": true, "data": json.data, "error": ""})


func save_profile(profile_id: String, data: Dictionary, callback: Callable) -> void:
	var ensure_error := DirAccess.make_dir_recursive_absolute(SAVE_DIRECTORY)
	if ensure_error != OK and ensure_error != ERR_ALREADY_EXISTS:
		callback.call({"ok": false, "error": "无法创建存档目录（错误码 %d）" % ensure_error})
		return

	var path := _get_profile_path(profile_id)
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		callback.call({"ok": false, "error": "无法写入临时存档（错误码 %d）" % FileAccess.get_open_error()})
		return

	file.store_string(JSON.stringify(data, "\t", false))
	file.flush()
	file.close()

	# 原子替换，尽量避免半写入存档。
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var rename_error := DirAccess.rename_absolute(temp_path, path)
	if rename_error != OK:
		callback.call({"ok": false, "error": "存档替换失败（错误码 %d）" % rename_error})
		return

	callback.call({"ok": true, "error": ""})


func delete_profile(profile_id: String, callback: Callable) -> void:
	var path := _get_profile_path(profile_id)
	if not FileAccess.file_exists(path):
		callback.call({"ok": true, "error": ""})
		return
	var error := DirAccess.remove_absolute(path)
	callback.call({"ok": error == OK, "error": "" if error == OK else "删除失败（错误码 %d）" % error})


func get_profile_file_path(profile_id: String) -> String:
	return _get_profile_path(profile_id)


func _get_profile_path(profile_id: String) -> String:
	var safe_id := profile_id.validate_filename().to_lower()
	if safe_id.is_empty():
		safe_id = "local_player"
	return SAVE_DIRECTORY.path_join(PROFILE_TEMPLATE % safe_id)

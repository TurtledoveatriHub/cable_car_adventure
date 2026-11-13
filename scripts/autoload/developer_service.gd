extends Node
## 隐蔽的开发者关卡设计入口。
## 通过密码解锁后，游戏内工坊可以直接设计主线关卡，并导出为项目资源或用户 JSON。

const PASSWORD := "666666"
const BUILTIN_DIR := "res://data/levels"
const INDEX_PATH := "res://data/levels/index.json"
const USER_EXPORT_DIR := "user://developer_levels"

var unlocked: bool = false


func unlock(password: String) -> bool:
	unlocked = password.strip_edges() == PASSWORD
	return unlocked


func lock() -> void:
	unlocked = false


## 把工坊草稿导出为主线资源。
## 在 Godot 编辑器运行时写 res://data/levels，可随项目一起打包；
## 在导出后的游戏中 res:// 只读，则退化为 user://developer_levels，需要再用编辑器导入。
func export_mainline(data: Dictionary) -> Dictionary:
	if not unlocked:
		return {"ok": false, "error": "开发者模式未解锁"}
	var level_id := str(data.get("id", ""))
	if not level_id.begins_with("level_"):
		level_id = _next_level_id()
	var exported := data.duplicate(true)
	exported["id"] = level_id
	exported["custom"] = false
	exported["source"] = "builtin"
	var can_write_project := _can_write_project_resources()
	var target_dir := BUILTIN_DIR if can_write_project else USER_EXPORT_DIR
	var target_path := target_dir.path_join(level_id + ".json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_dir))
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "无法写入 %s" % target_path}
	file.store_string(JSON.stringify(exported, "\t"))
	file.close()
	if can_write_project:
		_upsert_index(exported)
		LevelCatalog.reload()
	return {"ok": true, "id": level_id, "path": target_path, "project_resource": can_write_project}


func _can_write_project_resources() -> bool:
	var test_path := BUILTIN_DIR.path_join(".developer_write_test")
	var file := FileAccess.open(test_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("ok")
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	return true


func save_level(data: Dictionary) -> Dictionary:
	if not unlocked:
		return {"ok": false, "error": "开发者模式未解锁"}
	var level_id := str(data.get("id", ""))
	if not level_id.begins_with("level_"):
		return {"ok": false, "error": "开发者模式只能保存主线 level_XX 关卡"}
	var exported := data.duplicate(true)
	exported["custom"] = false
	exported["source"] = "builtin"
	if not _can_write_project_resources():
		return {"ok": false, "error": "当前环境不能写 res://data/levels，请在 Godot 编辑器内运行"}
	var target_path := BUILTIN_DIR.path_join(level_id + ".json")
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "无法写入 " + target_path}
	file.store_string(JSON.stringify(exported, "\t"))
	file.close()
	_upsert_index(exported)
	LevelCatalog.reload()
	return {"ok": true, "id": level_id, "path": target_path}


func _next_level_id() -> String:
	var max_number := 0
	for summary in LevelCatalog.get_summaries():
		var summary_id := str(summary.get("id", ""))
		if summary_id.begins_with("level_"):
			max_number = maxi(max_number, int(summary_id.trim_prefix("level_")))
	return "level_%02d" % (max_number + 1)


## 供工坊“新建空白环线”使用，避免编辑器自己拼 id。
func next_level_id() -> String:
	return _next_level_id()


func _upsert_index(data: Dictionary) -> void:
	var text := FileAccess.get_file_as_string(INDEX_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	var index := parsed as Dictionary
	var levels: Array = index.get("levels", [])
	var level_id := str(data.get("id", ""))
	var entry := {
		"id": level_id,
		"name": str(data.get("name", level_id)),
		"subtitle": str(data.get("subtitle", "")),
		"description": str(data.get("description", "")),
		"file": level_id + ".json",
		"difficulty": int(data.get("difficulty", 1)),
		"par_time": float(data.get("par_time", 60.0)),
		"accent": "#ff6b5b",
		"source": "builtin",
	}
	var found := false
	for i in levels.size():
		if levels[i] is Dictionary and str(levels[i].get("id", "")) == level_id:
			levels[i] = entry
			found = true
			break
	if not found:
		levels.append(entry)
	index["levels"] = levels
	var file := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(index, "\t"))
		file.close()

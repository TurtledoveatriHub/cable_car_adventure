extends SceneTree
## 导出前校验场景引用的资源真实存在，避免改名纹理后把坏引用带进 PCK。

var _missing: Array[String] = []
var _pattern := RegEx.new()


func _init() -> void:
	_pattern.compile('path="res://([^"]+)"')
	_scan_dir("res://scenes")
	if _missing.is_empty():
		print("RESOURCE CHECK: OK")
		quit(0)
		return
	for entry in _missing:
		printerr("RESOURCE CHECK MISSING: ", entry)
	quit(1)


func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".tscn"):
			_check_scene(path.path_join(file))
	for subdir in dir.get_directories():
		_scan_dir(path.path_join(subdir))


func _check_scene(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	for match in _pattern.search_all(text):
		var resource_path := match.get_string(1)
		if not FileAccess.file_exists(resource_path):
			_missing.append("%s -> %s" % [path, resource_path])

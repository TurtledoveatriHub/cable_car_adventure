@tool
extends EditorScript
## 在 Godot 编辑器中运行：把当前打开的 LevelAuthoringRoot 场景导出为关卡 JSON。
## 用法：打开 scenes/levels/level_01.tscn，Script 编辑器打开本文件，按 Ctrl+Shift+X 运行。

func _run() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or not root is LevelAuthoringRoot:
		push_error("当前场景根节点不是 LevelAuthoringRoot")
		return
	var authoring := root as LevelAuthoringRoot
	var data := authoring.build_level_data()
	var path := ""
	if authoring.level_id.begins_with("level_"):
		path = "res://data/levels/%s.json" % authoring.level_id
	else:
		path = "user://levels/%s.json" % authoring.level_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.substr(0, path.rfind("/"))))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入 " + path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("已导出关卡 JSON：" + path)
	EditorInterface.get_resource_filesystem().scan()

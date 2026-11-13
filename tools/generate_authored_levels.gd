extends Node
## 把 data/levels/*.json 生成可编辑的 Godot 场景。
## 运行：godot --headless --path . res://tools/generate_authored_levels.tscn

const LEVEL_DIR := "res://data/levels"
const OUTPUT_DIR := "res://scenes/levels"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var index_text := FileAccess.get_file_as_string(LEVEL_DIR + "/index.json")
	var index_data: Variant = JSON.parse_string(index_text)
	if not index_data is Dictionary:
		push_error("无法读取关卡索引")
		get_tree().quit(1)
		return
	for item: Variant in (index_data as Dictionary).get("levels", []):
		if item is Dictionary:
			_generate(item as Dictionary)
	get_tree().quit(0)


func _generate(summary: Dictionary) -> void:
	var file_name := str(summary.get("file", ""))
	var path := LEVEL_DIR + "/" + file_name
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("无法读取 " + path)
		return
	var data := parsed as Dictionary
	var track_data: Dictionary = data.get("track", {})
	var root := LevelAuthoringRoot.new()
	root.name = str(data.get("id", "level"))
	root.play_on_ready = true
	root.custom = false
	root.level_id = str(data.get("id", ""))
	root.level_name = str(data.get("name", ""))
	root.subtitle = str(data.get("subtitle", ""))
	root.description = str(data.get("description", ""))
	root.starting_passengers = int(data.get("starting_passengers", 3))
	root.max_passengers = int(data.get("max_passengers", 6))
	root.difficulty = int(data.get("difficulty", 1))
	root.speed_limit = float(data.get("speed_limit", 420.0))
	root.reverse_speed_limit = float(data.get("reverse_speed_limit", 300.0))
	root.engine_acceleration = float(data.get("engine_acceleration", 330.0))
	root.reverse_acceleration = float(data.get("reverse_acceleration", 300.0))
	root.gravity_accel = float(data.get("gravity_accel", 620.0))
	root.uphill_engine_assist = float(data.get("uphill_engine_assist", 0.9))
	root.rolling_friction = float(data.get("rolling_friction", 34.0))
	root.air_drag = float(data.get("air_drag", 0.18))
	root.par_time = float(data.get("par_time", 60.0))
	root.start_s = float(track_data.get("start_s", 60.0))
	root.finish_s = float(track_data.get("finish_s", 1000.0))
	root.theme_id = _theme_id(data.get("theme", {}))
	var camera_data: Variant = data.get("camera_bounds", null)
	if camera_data is Dictionary:
		root.camera_bounds = Rect2(
			float(camera_data.get("x", 0.0)), float(camera_data.get("y", 0.0)),
			float(camera_data.get("w", 1280.0)), float(camera_data.get("h", 720.0))
		)

	for piece_data: Variant in track_data.get("pieces", []):
		if not piece_data is Dictionary:
			continue
		var piece := TrackPieceDefinition.new()
		var source := piece_data as Dictionary
		piece.type = str(source.get("type", "straight"))
		piece.length = float(source.get("length", 260.0))
		piece.radius = float(source.get("radius", 200.0))
		piece.angle_deg = float(source.get("angle", -45.0))
		if source.has("origin"):
			piece.free_origin = true
			var origin_value: Variant = source.get("origin")
			if origin_value is Array and (origin_value as Array).size() >= 2:
				piece.origin = Vector2(float(origin_value[0]), float(origin_value[1]))
			piece.heading_deg = float(source.get("heading_deg", 0.0))
		piece.break_after = float(source.get("break_after", 0.0))
		root.track_pieces.append(piece)

	var obstacle_index := 0
	for obstacle_data: Variant in data.get("obstacles", []):
		if not obstacle_data is Dictionary:
			continue
		var source := obstacle_data as Dictionary
		var prefab_id := str(source.get("prefab", source.get("type", "bird")))
		var spawner := ObstacleSpawner.new()
		spawner.name = "Obstacle_%d" % (obstacle_index + 1)
		obstacle_index += 1
		spawner.prefab_id = prefab_id
		spawner.scene = ObstacleDefinitionDB.get_scene(prefab_id)
		spawner.track_s = float(source.get("s", 0.0))
		var off: Variant = source.get("offset", {})
		if off is Dictionary:
			spawner.offset = Vector2(float(off.get("x", 0.0)), float(off.get("y", 0.0)))
		root.add_child(spawner)
		spawner.owner = root


	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		push_error("打包失败：" + root.level_id)
		return
	var output := OUTPUT_DIR + "/" + root.level_id + ".tscn"
	var save_error := ResourceSaver.save(packed, output)
	if save_error != OK:
		push_error("保存失败：" + output)
	else:
		print("生成 " + output)


func _theme_id(theme: Variant) -> String:
	if theme is Dictionary:
		var sky_top := str((theme as Dictionary).get("sky_top", ""))
		for theme_id in LevelData.get_theme_ids():
			var preset := LevelData.get_theme_preset(theme_id)
			if str(preset.get("sky_top", "")) == sky_top:
				return theme_id
	return "sky"

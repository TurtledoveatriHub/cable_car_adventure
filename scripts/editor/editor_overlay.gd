class_name EditorOverlay
extends Node2D
## 关卡编辑器世界层：绘制网格、起终点、障碍/乘客标记、运动轨迹与放置预览。

var level: LevelData
var selected_kind: String = ""
var selected_index: int = -1
var placement_mode: String = ""
var mouse_world: Vector2 = Vector2.ZERO
var nearest_s: float = 0.0
var track_preview_points: PackedVector2Array = PackedVector2Array()
var track_preview_snapped: bool = false
var track_preview_snap_point: Vector2 = Vector2.ZERO
var grid_visible: bool = false
var obstacle_preview_id: String = "bird"
var obstacle_trigger_range: float = 0.0
var obstacle_preview_path: PackedVector2Array = PackedVector2Array()
var selected_obstacle_path: PackedVector2Array = PackedVector2Array()
var selected_obstacle_base: Vector2 = Vector2.ZERO
var selected_obstacle_range: float = 0.0
var selected_obstacle_scale: float = 1.0

const OBSTACLE_COLORS := {
	"bird": Color(0.36, 0.66, 0.82),
	"storm": Color(0.55, 0.45, 0.78),
	"barrier": Color(0.95, 0.72, 0.2),
	"crate": Color(0.76, 0.5, 0.26),
	"fan": Color(0.7, 0.8, 0.85),
}


func update_preview(
	preview_level: LevelData,
	kind: String,
	index: int,
	mode: String,
	cursor_world: Vector2
) -> void:
	level = preview_level
	selected_kind = kind
	selected_index = index
	placement_mode = mode
	mouse_world = cursor_world
	if level != null and level.track != null and level.track.is_valid():
		nearest_s = level.track.nearest_s(cursor_world)
	queue_redraw()


func _draw() -> void:
	_draw_grid()
	if level == null or level.track == null or not level.track.is_valid():
		return
	_draw_route_guide()
	_draw_start_finish()
	_draw_obstacles()
	_draw_selected_obstacle_path()
	_draw_camera_bounds()
	_draw_placement_ghost()
	_draw_help()


func set_grid_visible(enabled: bool) -> void:
	grid_visible = enabled
	queue_redraw()


func _obstacle_offset() -> Vector2:
	match obstacle_preview_id:
		"storm":
			return Vector2(220, 0)
		"bird":
			return Vector2(120, 60)
		"fan":
			return Vector2(90, 0)
		_:
			return Vector2.ZERO


func _draw_grid() -> void:
	if not grid_visible:
		return
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var zoom := maxf(0.05, camera.zoom.x)
	var center := camera.get_screen_center_position()
	var half := get_viewport_rect().size / (2.0 * zoom)
	var left := floorf((center.x - half.x) / 60.0) * 60.0
	var right := center.x + half.x
	var top := floorf((center.y - half.y) / 60.0) * 60.0
	var bottom := center.y + half.y
	var x := left
	while x <= right:
		var major := int(x / 60.0) % 5 == 0
		draw_line(Vector2(x, top), Vector2(x, bottom), Color(0.04, 0.08, 0.12, 0.22 if not major else 0.5), 1.0 if not major else 1.6)
		x += 60.0
	var y := top
	while y <= bottom:
		var major := int(y / 60.0) % 5 == 0
		draw_line(Vector2(left, y), Vector2(right, y), Color(0.04, 0.08, 0.12, 0.22 if not major else 0.5), 1.0 if not major else 1.6)
		y += 60.0
	# 坐标轴。
	draw_line(Vector2(left, 0), Vector2(right, 0), Color(0.04, 0.08, 0.12, 0.55), 1.5)
	draw_line(Vector2(0, top), Vector2(0, bottom), Color(0.04, 0.08, 0.12, 0.55), 1.5)


func _draw_camera_bounds() -> void:
	if level == null or level.camera_bounds.size.x < 64.0:
		return
	var rect := level.camera_bounds
	var color := Color(0.95, 0.78, 0.25, 0.9)
	draw_rect(rect, Color(0.95, 0.78, 0.25, 0.06), true)
	draw_rect(rect, color, false, 2.0)
	var corners := [
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size,
		rect.position + Vector2(0, rect.size.y),
	]
	for index in 4:
		var a: Vector2 = corners[index]
		var b: Vector2 = corners[(index + 1) % 4]
		var direction := (b - a).normalized()
		draw_line(a, a + direction * 28.0, color, 4.0, true)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 22), "相机范围", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)


func _draw_route_guide() -> void:
	var start_point := level.track.sample_at(level.start_s)
	var finish_point := level.track.sample_at(level.finish_s)
	draw_circle(start_point, 19.0, Color(0.31, 0.85, 0.53, 0.28))
	draw_arc(start_point, 19.0, 0, TAU, 24, Color(0.12, 0.5, 0.3), 3.0, true)
	draw_string(ThemeDB.fallback_font, start_point + Vector2(-17, -26), "起点", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.08, 0.3, 0.2))
	draw_circle(finish_point, 19.0, Color(1.0, 0.82, 0.25, 0.35))
	draw_arc(finish_point, 19.0, 0, TAU, 24, Color(0.76, 0.48, 0.08), 3.0, true)
	draw_string(ThemeDB.fallback_font, finish_point + Vector2(-17, -26), "终点", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.46, 0.28, 0.05))


func _draw_start_finish() -> void:
	var start_point := level.track.sample_at(level.start_s)
	var finish_point := level.track.sample_at(level.finish_s)
	if selected_kind == "start":
		draw_arc(start_point, 25.0, 0, TAU, 28, Color(1.0, 0.78, 0.2), 3.0, true)
	if selected_kind == "finish":
		draw_arc(finish_point, 25.0, 0, TAU, 28, Color(1.0, 0.78, 0.2), 3.0, true)


func _draw_obstacles() -> void:
	for index in level.obstacles.size():
		var obstacle: Dictionary = level.obstacles[index]
		# 新格式由 LevelEditor 实例化真实障碍场景预览；这里只兜底旧版无场景数据。
		if not str(obstacle.get("prefab", "")).is_empty() and ObstacleDefinitionDB.get_scene(str(obstacle.get("prefab", ""))) != null:
			if selected_kind == "obstacle" and selected_index == index:
				var selected_offset: Vector2 = obstacle.get("offset", Vector2.ZERO)
				var selected_base := level.track.sample_at(float(obstacle.get("s", 0.0))) + LevelData.CART_ANCHOR_OFFSET + selected_offset
				draw_arc(selected_base, 34.0 * selected_obstacle_scale, 0, TAU, 36, Color(1.0, 0.78, 0.2, 1.0), 4.0, true)
				draw_arc(selected_base, 40.0 * selected_obstacle_scale, 0, TAU, 36, Color(1.0, 0.9, 0.5, 0.35), 2.0, true)
			continue
		obstacle = obstacle.duplicate(true)
		var offset: Vector2 = obstacle.get("offset", Vector2.ZERO)
		var base := level.track.sample_at(float(obstacle.get("s", 0.0))) + LevelData.CART_ANCHOR_OFFSET + offset
		var motion: Dictionary = obstacle.get("motion", {})
		var motion_type := str(motion.get("type", "static"))
		var amplitude: Vector2 = motion.get("amplitude", Vector2.ZERO)
		# 运动轨迹。
		if motion_type == "oscillate_x":
			draw_line(base - Vector2(amplitude.x, 0), base + Vector2(amplitude.x, 0), Color(0.95, 0.55, 0.25, 0.55), 2.0, true)
		elif motion_type == "oscillate_y":
			draw_line(base - Vector2(0, amplitude.y), base + Vector2(0, amplitude.y), Color(0.95, 0.55, 0.25, 0.55), 2.0, true)
		elif motion_type in ["circle", "ellipse"]:
			_draw_ellipse(base, amplitude, Color(0.95, 0.55, 0.25, 0.55), 2.0)
		var color: Color = OBSTACLE_COLORS.get(str(obstacle.get("type", "bird")), Color(0.9, 0.4, 0.35))
		draw_circle(base, 17.0, Color(color, 0.9))
		draw_arc(base, 17.0, 0, TAU, 22, Color(0.06, 0.15, 0.2), 2.0, true)
		var type_label := _type_label(str(obstacle.get("type", "bird")))
		draw_string(ThemeDB.fallback_font, base + Vector2(-7, 5), type_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		if selected_kind == "obstacle" and selected_index == index:
			draw_arc(base, 25.0, 0, TAU, 26, Color(1.0, 0.78, 0.2), 3.0, true)
		# 连接轨道锚点，帮助理解偏移。


func set_obstacle_preview(prefab_id: String, trigger_range: float, path: PackedVector2Array = PackedVector2Array()) -> void:
	obstacle_preview_id = prefab_id
	obstacle_trigger_range = trigger_range
	obstacle_preview_path = path


## 选中已有障碍时，显示它自己的运动轨迹（起点为障碍基准点）。
func set_selected_obstacle_path(base: Vector2, path: PackedVector2Array, trigger_range: float, scene_scale: float = 1.0) -> void:
	selected_obstacle_base = base
	selected_obstacle_path = path
	selected_obstacle_range = trigger_range
	selected_obstacle_scale = maxf(0.1, scene_scale)
	queue_redraw()


func _draw_selected_obstacle_path() -> void:
	if not placement_mode.is_empty():
		return
	if selected_obstacle_path.size() < 2:
		return
	var color := Color(1.0, 0.76, 0.2, 0.72)
	var world_path := PackedVector2Array()
	for path_point in selected_obstacle_path:
		world_path.append(selected_obstacle_base + path_point)
	draw_polyline(world_path, color, 2.0, true)
	draw_circle(world_path[world_path.size() - 1], 5.0, color)
	draw_string(ThemeDB.fallback_font, world_path[world_path.size() - 1] + Vector2(8, -8), "运动轨迹", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	if selected_obstacle_range > 0.0:
		draw_circle(selected_obstacle_base, selected_obstacle_range, Color(0.25, 0.85, 0.95, 0.05))
		draw_arc(selected_obstacle_base, selected_obstacle_range, 0, TAU, 64, Color(0.25, 0.85, 0.95, 0.45), 1.5, true)


func set_track_preview(points: PackedVector2Array, will_snap: bool, snap_point: Vector2) -> void:
	track_preview_points = points
	track_preview_snapped = will_snap
	track_preview_snap_point = snap_point
	queue_redraw()


func _draw_placement_ghost() -> void:
	if placement_mode.is_empty() or level == null:
		return
	var color := Color(1.0, 0.75, 0.2, 0.8)
	if placement_mode.begins_with("track:"):
		if track_preview_points.size() >= 2:
			draw_polyline(track_preview_points, Color(color, 0.55), 10.0, true)
			draw_polyline(track_preview_points, Color(1.0, 0.95, 0.75, 0.9), 1.0, true)
		if track_preview_snapped:
			draw_circle(track_preview_snap_point, 20.0, Color(color, 0.2))
			draw_arc(track_preview_snap_point, 20.0, 0, TAU, 26, color, 2.0, true)
			draw_string(ThemeDB.fallback_font, track_preview_snap_point + Vector2(-32, -30), "吸附连接", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		else:
			draw_circle(track_preview_snap_point, 8.0, color)
			draw_string(ThemeDB.fallback_font, track_preview_snap_point + Vector2(10, -16), "分段轨道", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		return
	if placement_mode in ["start", "finish"]:
		var point := level.track.sample_at(nearest_s)
		draw_circle(point, 22.0, Color(color, 0.2))
		draw_arc(point, 22.0, 0, TAU, 26, color, 2.0, true)
		draw_string(ThemeDB.fallback_font, point + Vector2(-42, -30), "点击设置%s" % ("起点" if placement_mode == "start" else "终点"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
	else:
		draw_circle(mouse_world, 19.0, Color(color, 0.15))
		draw_arc(mouse_world, 19.0, 0, TAU, 24, color, 2.0, true)
		if placement_mode == "obstacle":
			if obstacle_preview_path.size() >= 2:
				var world_path := PackedVector2Array()
				for path_point in obstacle_preview_path:
					world_path.append(mouse_world + path_point)
				draw_polyline(world_path, Color(color, 0.55), 2.0, true)
				draw_circle(world_path[world_path.size() - 1], 5.0, color)
				draw_string(ThemeDB.fallback_font, world_path[world_path.size() - 1] + Vector2(8, -8), "运动轨迹", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
			if obstacle_trigger_range > 0.0:
				draw_circle(mouse_world, obstacle_trigger_range, Color(0.25, 0.85, 0.95, 0.06))
				draw_arc(mouse_world, obstacle_trigger_range, 0, TAU, 64, Color(0.25, 0.85, 0.95, 0.55), 1.5, true)

func _draw_help() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var zoom := maxf(0.05, camera.zoom.x)
	var center := camera.get_screen_center_position()
	var top_left := center - get_viewport_rect().size / (2.0 * zoom)
	draw_string(
		ThemeDB.fallback_font,
		top_left + Vector2(26, 32),
		"左键选择/拖动 · 右键平移 · 滚轮缩放 · 先点轨道按钮再点世界放置",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color(0.08, 0.2, 0.28, 0.55)
	)


func _type_label(type: String) -> String:
	match type:
		"bird":
			return "鸟"
		"storm":
			return "雷"
		"barrier":
			return "障"
		"crate":
			return "箱"
		"fan":
			return "车"
		"large_ferris_wheel":
			return "大"
		"caterpillar":
			return "虫"
		"hot_air_balloon":
			return "气"
		"ferris_wheel":
			return "轮"
		"vine":
			return "松"
		"venus_flytrap":
			return "捕"
		"snow_elf":
			return "雪"
		"ice_crystal":
			return "冰"
		"flying_bird":
			return "鸟"
		"flying_fish":
			return "鱼"
		"meteor":
			return "陨"
		"dream_elf":
			return "梦"
		"bubble":
			return "泡"
		"cannonball":
			return "炮"
		"dream_void":
			return "虚"
		_:
			return "?"


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for index in 40:
		var angle := TAU * float(index) / 40.0
		points.append(center + Vector2(cos(angle) * maxf(radii.x, 4.0), sin(angle) * maxf(radii.y, 4.0)))
	points.append(points[0])
	draw_polyline(points, color, width, true)

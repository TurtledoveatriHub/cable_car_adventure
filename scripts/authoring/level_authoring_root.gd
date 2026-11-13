@tool
class_name LevelAuthoringRoot
extends Node2D
## 在 Godot 编辑器中直接搭关卡：
## - track_pieces 数组配置轨道片段（可勾选 free_origin 形成分段轨道）；
## - 子节点 ObstacleSpawner 配置障碍预制体；
## - 运行场景（play_on_ready）即可用真实游戏场景试玩。
## 游戏内关卡工坊仍然编辑 JSON 关卡；本节点用于 Godot 编辑器工作流。

## 运行该场景时是否自动进入游戏
@export var play_on_ready: bool = true
## 是否为玩家自制关卡
@export var custom: bool = true
## 关卡稳定 id
@export var level_id: String = "authored_demo"
## 关卡显示名称
@export var level_name: String = "Godot 编辑器关卡"
## 关卡描述
@export var description: String = "Godot 编辑器场景生成的关卡"
## 难度等级
@export var difficulty: int = 2
## 参考通关时间（秒）
@export var par_time: float = 60.0
## 关卡主题：sky / sunset / night / forest / gray
@export var theme_id: String = "sky"
## 起点在轨道上的弧长
@export var start_s: float = 60.0
## 终点在轨道上的弧长
@export var finish_s: float = 1200.0
## 空值则按轨道自动计算
@export var camera_bounds: Rect2 = Rect2(0, 0, 0, 0)
## TrackPieceDefinition 资源数组
@export var track_pieces: Array = []


func build_level_data() -> Dictionary:
	var pieces: Array = []
	for item: Variant in track_pieces:
		if item is TrackPieceDefinition:
			pieces.append((item as TrackPieceDefinition).to_piece())
	var obstacles: Array = []
	for child in get_children():
		if child is ObstacleSpawner:
			var data := (child as ObstacleSpawner).to_data()
			if not data.is_empty():
				obstacles.append(data)
	return {
		"schema_version": LevelData.SCHEMA_VERSION,
		"id": level_id,
		"name": level_name,
		"description": description,
		"difficulty": difficulty,
		"par_time": par_time,
		"theme": LevelData.get_theme_preset(theme_id),
		"track": {
			"start_angle_deg": 0.0,
			"pieces": pieces,
			"start_s": start_s,
			"finish_s": finish_s,
		},
		"camera_bounds": {
			"x": camera_bounds.position.x, "y": camera_bounds.position.y,
			"w": camera_bounds.size.x, "h": camera_bounds.size.y,
		} if camera_bounds.size.x > 64.0 and camera_bounds.size.y > 64.0 else {},
		"obstacles": obstacles,
		"custom": custom,
		"source": "user" if custom else "builtin",
	}


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	if not play_on_ready:
		return
	var data := build_level_data()
	GameSession.start_authored_level(data)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var data := build_level_data()
	var track := TrackGeometry.from_track_data(data.get("track", {}))
	if not track.is_valid():
		return
	draw_polyline(track.points, Color(0.24, 0.4, 0.55), 6.0, true)
	draw_circle(track.sample_at(start_s), 12.0, Color(0.3, 0.9, 0.55))
	draw_circle(track.sample_at(finish_s), 12.0, Color(0.95, 0.62, 0.2))
	var bounds := camera_bounds
	if bounds.size.x <= 64.0 or bounds.size.y <= 64.0:
		bounds = track.get_bounds(240.0)
	draw_rect(bounds, Color(0.95, 0.78, 0.25, 0.85), false, 2.0)
	draw_string(ThemeDB.fallback_font, bounds.position + Vector2(8, 20), "相机范围", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.78, 0.25))

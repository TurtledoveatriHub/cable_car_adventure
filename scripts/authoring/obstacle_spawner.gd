@tool
class_name ObstacleSpawner
extends Node2D
## Godot 编辑器内放置的障碍物。参数在独立障碍场景里修改，本节点只保存位置与预制体 id。

## 对应独立的障碍场景（由 prefab_id 区分）
@export var scene: PackedScene
## 关卡 JSON 中记录的预制体 id
@export var prefab_id: String = "bird"
## 在轨道上的弧长位置
@export var track_s: float = 0.0
## 相对轨道点的偏移
@export var offset: Vector2 = Vector2.ZERO


func to_data() -> Dictionary:
	return {
		"prefab": prefab_id,
		"s": track_s,
		"offset": {"x": offset.x, "y": offset.y},
	}


func _draw() -> void:
	draw_circle(Vector2.ZERO, 17.0, Color(0.95, 0.55, 0.25, 0.9))
	draw_arc(Vector2.ZERO, 17.0, 0, TAU, 24, Color(0.12, 0.16, 0.2), 2.0, true)
	draw_string(ThemeDB.fallback_font, Vector2(-6, 5), "障", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

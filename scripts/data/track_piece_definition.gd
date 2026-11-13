@tool
class_name TrackPieceDefinition
extends Resource
## Godot 编辑器关卡中的轨道片段配置。

## 类型枚举
@export_enum("straight", "arc", "loop") var type: String = "straight"
## 直线长度或曲线弧长（像素）
@export var length: float = 260.0
## 碰撞半径（像素）
@export var radius: float = 200.0
## 圆弧角度（度）；环圈使用 -360
@export var angle_deg: float = -45.0
## 是否使用自由起点；勾选后 origin 生效
@export var free_origin: bool = false
## 自由片段的世界坐标起点
@export var origin: Vector2 = Vector2.ZERO
## 自由片段的起始朝向（度）
@export var heading_deg: float = 0.0
## >0 时该片段在开局后若干秒断裂
@export var break_after: float = 0.0


func to_piece() -> Dictionary:
	var piece := {"type": type}
	if type == "straight":
		piece["length"] = length
	else:
		piece["radius"] = radius
		piece["angle"] = angle_deg
	if free_origin:
		piece["origin"] = [origin.x, origin.y]
		piece["heading_deg"] = heading_deg
	if break_after > 0.0:
		piece["break_after"] = break_after
	return piece

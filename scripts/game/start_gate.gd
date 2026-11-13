class_name StartGate
extends Node2D
## 起点站台视觉。只负责显示，不参与碰撞。

@onready var visual: AnimatedSprite2D = get_node_or_null("Visual") as AnimatedSprite2D
@onready var cart_start: Node2D = get_node_or_null("CartStart") as Node2D

var _cart_start_base_x: float = 0.0
var _base_scale_x: float = 2.0
var _facing_left: bool = false


func _ready() -> void:
	if cart_start != null:
		_cart_start_base_x = cart_start.position.x
	_base_scale_x = absf(scale.x)
	# 站台只在 configure() 里一次性定位、之后完全静止；保持插值开启会让
	# 首次定位从原点(0,0)平滑滑行到轨道位置。纯装饰、不参与碰撞，关闭无副作用。
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if visual != null and visual.sprite_frames != null and visual.sprite_frames.has_animation(&"IDLE"):
		visual.play(&"IDLE")


func get_passenger_global_position() -> Vector2:
	var spawn := get_node_or_null("PassengerSpawn") as Node2D
	return spawn.global_position if spawn != null else global_position


func configure(level: LevelData) -> void:
	if level == null or level.track == null:
		return
	global_position = level.track.sample_at(level.start_s)
	# 站台朝向必须沿“起点 -> 终点”的实际行车方向，而不是轨道几何的 +s 方向。
	# 反向关卡（finish_s < start_s）如果仍按 +s 旋转，站台和 CartStart 会整个反 180°。
	var course_sign := 1.0 if level.is_forward_course() else -1.0
	var travel_tangent := level.track.tangent_at(level.start_s) * course_sign
	rotation = travel_tangent.angle()
	_facing_left = travel_tangent.x < -0.01
	# 用根节点水平镜像整个站台：纹理、CartStart 和站台装饰一起翻转，
	# 同时保持 CartStart 在轨道前进方向一侧（不会把缆车镜像到站台背面）。
	scale.x = -_base_scale_x if _facing_left else _base_scale_x
	if visual != null:
		visual.rotation = -rotation
		visual.flip_h = false
	if cart_start != null:
		cart_start.position.x = -absf(_cart_start_base_x) if _facing_left else absf(_cart_start_base_x)


func get_cart_start_global_position() -> Vector2:
	var start := get_node_or_null("CartStart") as Node2D
	return start.global_position if start != null else global_position


func is_facing_left() -> bool:
	return _facing_left

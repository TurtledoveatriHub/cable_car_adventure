class_name FinishGate
extends Area2D
## 终点触发区。沿轨道切线方向覆盖一小段范围，检测过山车经过。
## 视觉使用 AnimatedSprite2D：OFF 待机、MID 到达播放一次、ON 完成循环。

signal crossed(gate: FinishGate, coaster: CoasterController)

var finish_s: float = 0.0
var _triggered_ids: Array[int] = []
var _shape: RectangleShape2D
var _finish_animation_started: bool = false
var _facing_left: bool = false
var _base_scale_x: float = 2.0

@onready var visual: AnimatedSprite2D = get_node_or_null("Visual") as AnimatedSprite2D


func get_passenger_global_position() -> Vector2:
	var exit_point := get_node_or_null("PassengerExit") as Node2D
	return exit_point.global_position if exit_point != null else global_position


func _ready() -> void:
	collision_layer = 16
	collision_mask = 2
	monitoring = true
	monitorable = false
	z_index = 5
	_base_scale_x = absf(scale.x)
	# 闸门只在 configure() 里一次性定位、之后静止。物理插值仅平滑渲染变换，
	# 不参与 Area2D 判定（判定用真实物理变换），关闭可避免首次定位从原点滑行。
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_to_group("finish_gates")
	if visual != null and visual.sprite_frames != null and visual.sprite_frames.has_animation(&"OFF"):
		visual.play(&"OFF")
	body_entered.connect(_on_body_entered)
	var collision := $CollisionShape2D as CollisionShape2D
	_shape = collision.shape as RectangleShape2D
	if _shape == null:
		_shape = RectangleShape2D.new()
		collision.shape = _shape


func configure(level: LevelData) -> void:
	finish_s = level.finish_s
	var track := level.track
	global_position = track.sample_at(finish_s)
	# 终点站与起点站共用“起点 -> 终点”的实际行车方向；
	# 反向关卡必须把 +s 切线反过来，否则站台和碰撞体会倒转 180°。
	var course_sign := 1.0 if level.is_forward_course() else -1.0
	var travel_tangent := track.tangent_at(finish_s) * course_sign
	rotation = travel_tangent.angle()
	_facing_left = travel_tangent.x < -0.01
	# 根节点水平镜像整座终点站，纹理与装饰一次翻转。
	scale.x = -_base_scale_x if _facing_left else _base_scale_x
	if visual != null:
		visual.rotation = -rotation
		visual.flip_h = false
	var collision := $CollisionShape2D as CollisionShape2D
	collision.position = Vector2(0, LevelData.CART_ANCHOR_OFFSET.y)
	_shape.size = Vector2(76, 96)


func is_facing_left() -> bool:
	return _facing_left


func _on_body_entered(body: Node2D) -> void:
	if not body is CoasterController:
		return
	var id := body.get_instance_id()
	if _triggered_ids.has(id):
		return
	_triggered_ids.append(id)
	crossed.emit(self, body as CoasterController)
	_play_finish_animation()


func _play_finish_animation() -> void:
	if _finish_animation_started or visual == null or visual.sprite_frames == null:
		return
	_finish_animation_started = true
	var frames := visual.sprite_frames
	if frames.has_animation(&"MID"):
		visual.play(&"MID")
		await visual.animation_finished
	if not is_instance_valid(visual) or frames == null:
		return
	if frames.has_animation(&"ON"):
		visual.play(&"ON")
	elif frames.has_animation(&"OFF"):
		visual.play(&"OFF")

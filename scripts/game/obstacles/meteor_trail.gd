class_name MeteorTrail
extends Node2D
## 陨石专用拖尾：沿运动反方向绘制渐隐尾焰，并持续散落火星。
## 挂在 meteor.tscn 的节点下；发射器复制陨石时会一起复制。

@export_category("陨石拖尾")
## 拖尾总长度（像素）
@export var trail_length: float = 480.0
## 拖尾根部宽度（像素）
@export var trail_width: float = 120.0
## 拖尾分段数；越高越顺滑，开销也略高
@export_range(2, 24, 1) var trail_segments: int = 1
## 尾焰主色（alpha 控制整体透明度）
@export var trail_color: Color = Color(1.0, 0.447, 0.161, 0.78)
## 火星颜色
@export var ember_color: Color = Color(1.095, 0.894, 0.42, 0.949)
## 每秒生成火星数量
@export_range(0.0, 120.0, 1.0) var ember_spawn_rate: float = 16.0
## 火星存活时间（秒）
@export_range(0.05, 2.0, 0.05) var ember_lifetime: float = 0.55
## 火星向后飞散速度（像素/秒）
@export var ember_back_speed: float = 96.0
## 火星横向散开范围（像素/秒）
@export var ember_side_speed: float = 52.0
## 火星半径范围（像素）
@export var ember_radius_min: float = 1.0
@export var ember_radius_max: float = 3.2
## 是否启用拖尾
@export var enabled: bool = true

@export_category("陨石屏幕反馈")
## 陨石与缆车距离小于该值时触发相机抖动
@export var shake_trigger_distance: float = 1080.0
## 陨石与缆车距离小于该值时开始屏幕泛黄
@export var tint_start_distance: float = 640.0
## 陨石与缆车距离小于该值时泛黄达到峰值
@export var tint_peak_distance: float = 120.0
## 相机抖动强度（像素）
@export var camera_shake_strength: float = 1.46
## 相机抖动频率
@export var camera_shake_speed: float = 16.0
## 泛黄最大透明度
@export_range(0.0, 0.5, 0.01) var tint_max_alpha: float = 0.32

var _direction_local: Vector2 = Vector2.ZERO
var _sparks: Array[Dictionary] = []
var _spawn_accum: float = 0.0


func _ready() -> void:
	z_index = -1
	set_process(true)


func _process(delta: float) -> void:
	if not enabled:
		_sparks.clear()
		queue_redraw()
		return
	var obstacle := get_parent() as Obstacle
	if obstacle == null:
		return
	var direction := obstacle.get_motion_direction_global()
	if direction == Vector2.ZERO:
		queue_redraw()
		return
	# 将全局运动方向转换到本节点的局部坐标，父节点旋转后拖尾仍朝向正确。
	_direction_local = to_local(global_position + direction) - to_local(global_position)
	if _direction_local.length_squared() < 0.0001:
		return
	_direction_local = _direction_local.normalized()
	_spawn_embers(delta)
	_update_sparks(delta)
	_report_screen_feedback()
	queue_redraw()


func _report_screen_feedback() -> void:
	var game := _find_game_controller()
	if game == null or game.coaster == null:
		return
	var distance := global_position.distance_to(game.coaster.get_body_center())
	var shake := camera_shake_strength if distance < shake_trigger_distance else 0.0
	var tint := 0.0
	if distance < tint_start_distance:
		if distance <= tint_peak_distance:
			tint = tint_max_alpha
		else:
			var span := maxf(1.0, tint_start_distance - tint_peak_distance)
			tint = tint_max_alpha * (1.0 - (distance - tint_peak_distance) / span)
	if not PlatformConfig.level_fullscreen_fx:
		# 微信端泛黄全屏叠加成本高，只保留轻微震动提示。
		tint = 0.0
		shake *= 0.35
	game.report_meteor_feedback(shake, tint, trail_color, camera_shake_speed)


func _find_game_controller() -> GameController:
	var node := get_parent()
	while node != null:
		if node is GameController:
			return node as GameController
		node = node.get_parent()
	return null


func _spawn_embers(delta: float) -> void:
	_spawn_accum += delta * ember_spawn_rate * maxf(0.05, PlatformConfig.meteor_fx_scale)
	while _spawn_accum >= 1.0:
		_spawn_accum -= 1.0
		var back := -_direction_local
		var side := Vector2(-back.y, back.x)
		var distance := randf_range(0.15, 1.0) * trail_length
		var spawn_position := back * distance + side * randf_range(-trail_width * 0.35, trail_width * 0.35)
		var velocity := back * randf_range(10.0, ember_back_speed) + side * randf_range(-ember_side_speed, ember_side_speed)
		var lifetime := randf_range(ember_lifetime * 0.6, ember_lifetime)
		_sparks.append({
			"position": spawn_position,
			"velocity": velocity,
			"life": lifetime,
			"max_life": lifetime,
			"radius": randf_range(ember_radius_min, ember_radius_max),
		})


func _update_sparks(delta: float) -> void:
	for index in range(_sparks.size() - 1, -1, -1):
		var spark: Dictionary = _sparks[index]
		spark["life"] = float(spark["life"]) - delta
		if float(spark["life"]) <= 0.0:
			_sparks.remove_at(index)
			continue
		spark["position"] = Vector2(spark["position"]) + Vector2(spark["velocity"]) * delta
		spark["velocity"] = Vector2(spark["velocity"]) * maxf(0.0, 1.0 - delta * 2.4)
		_sparks[index] = spark


func _draw() -> void:
	if not enabled or _direction_local == Vector2.ZERO:
		return
	var back := -_direction_local
	var side := Vector2(-back.y, back.x)
	# 用带顶点颜色的四边形绘制，段数为 1 时也能做到末端收缩 + 淡出。
	for index in maxi(1, trail_segments):
		var t0 := float(index) / float(maxi(1, trail_segments))
		var t1 := float(index + 1) / float(maxi(1, trail_segments))
		var width0 := trail_width * 0.5 * (1.0 - t0)
		var width1 := maxf(0.4, trail_width * 0.5 * (1.0 - t1))
		var alpha0 := trail_color.a * pow(1.0 - t0, 1.6)
		var alpha1 := trail_color.a * pow(1.0 - t1, 1.6)
		var color0 := Color(trail_color.r, trail_color.g, trail_color.b, alpha0)
		var color1 := Color(trail_color.r, trail_color.g, trail_color.b, alpha1)
		var p0 := back * trail_length * t0
		var p1 := back * trail_length * t1
		var quad := PackedVector2Array([p0 + side * width0, p0 - side * width0, p1 - side * width1, p1 + side * width1])
		var colors := PackedColorArray([color0, color0, color1, color1])
		draw_polygon(quad, colors)
	for spark in _sparks:
		var ratio := maxf(0.0, float(spark["life"]) / float(spark["max_life"]))
		var color := Color(ember_color.r, ember_color.g, ember_color.b, ember_color.a * ratio)
		draw_circle(Vector2(spark["position"]), float(spark["radius"]) * (0.5 + ratio * 0.5), color)

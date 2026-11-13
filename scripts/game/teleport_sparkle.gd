class_name TeleportSparkle
extends Node2D
## 空间移动前后的短促星光，遮住旧位置/新位置切换的突兀感。

var _life: float = 0.96
var _age: float = 0.0
var strength: float = 1.0
var size_scale: float = 2.0


func configure(brightness: float, duration: float, scale_value: float) -> void:
	strength = brightness
	_life = maxf(0.1, duration)
	size_scale = maxf(0.5, scale_value)
	z_index = 18
	set_process(true)
	queue_redraw()


func _ready() -> void:
	# 位置由 _spawn_teleport_sparkle 在输入回调（物理帧之外）一次性写入，之后不再移动，
	# 插值对它没有收益，反而会因跨帧赋值产生一帧滑行。
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	z_index = 18
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	if _age >= _life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf(_age / _life, 0.0, 1.0)
	var alpha := (1.0 - t) * 0.95 * clampf(strength, 0.2, 2.0)
	var radius := (14.0 + t * 62.0) * size_scale
	for index in 12:
		var angle := TAU * float(index) / 12.0 + t * 2.4
		var distance := radius * (0.55 + 0.45 * sin(float(index) * 2.1 + t * 8.0))
		var point := Vector2(cos(angle), sin(angle)) * distance
		var size := (2.5 + 2.0 * (1.0 - t)) * size_scale
		draw_circle(point, size, Color(1.0, 0.95, 0.66, alpha))
		draw_line(point * 0.5, point, Color(1.0, 1.0, 0.9, alpha * 0.55), 1.4 * size_scale, true)
	draw_arc(Vector2.ZERO, radius * 0.72, 0, TAU, 32, Color(0.85, 0.92, 1.0, alpha * 0.55), 2.0 * size_scale, true)

class_name PassengerEject
extends Sprite2D
## 被障碍击飞的乘客：真实抛物线运动，不依赖 tween 直线瞬移。

var velocity: Vector2 = Vector2.ZERO
var gravity: float = 900.0
var spin_speed: float = 3.0
var lifetime: float = 1.15
var fade_start: float = 0.65
var _age: float = 0.0


func _ready() -> void:
	# 抛物线积分在 _process 内写入 position，与全局物理插值冲突（渲染帧写变换会抖动）。
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func configure(
	texture_value: Texture2D,
	start_global: Vector2,
	initial_velocity: Vector2,
	gravity_value: float,
	spin_value: float,
	life_value: float,
	fade_value: float,
	sprite_scale: Vector2
) -> void:
	texture = texture_value
	global_position = start_global
	velocity = initial_velocity
	gravity = gravity_value
	spin_speed = spin_value
	lifetime = maxf(0.2, life_value)
	fade_start = clampf(fade_value, 0.0, 0.95)
	scale = sprite_scale
	z_index = 9


func _process(delta: float) -> void:
	_age += delta
	velocity.y += gravity * delta
	position += velocity * delta
	rotation += spin_speed * delta
	var fade_begin := lifetime * fade_start
	if _age > fade_begin:
		modulate.a = clampf(1.0 - (_age - fade_begin) / maxf(0.01, lifetime - fade_begin), 0.0, 1.0)
	if _age >= lifetime:
		queue_free()

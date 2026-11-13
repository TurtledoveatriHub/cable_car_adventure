class_name ObstacleBullet
extends Area2D
## 障碍弹幕：自身控制场景纹理、速度、重力、生命周期与命中；发射几何由 ObstacleBulletEmitter 控制。

@export_category("飞行")
## 直线飞行速度（像素/秒）
@export var speed: float = 360.0
## 存活时间（秒）
@export var life_time: float = 5.0
## 是否受重力影响
@export var affected_by_gravity: bool = false
## 重力加速度（像素/秒²）
@export var bullet_gravity: float = 480.0
## 最大下落速度（像素/秒）
@export var max_fall_speed: float = 640.0
## 发射后多少秒内不受重力影响
@export var gravity_delay: float = 0.5
## 从 0 加速到 speed 的时间（秒）
@export var acceleration_time: float = 1.2
## 是否使用曲线加速：先缓慢加速，后段加速到 speed
@export var curve_acceleration_enabled: bool = false

@export_category("旋转设置")
## 是否旋转弹幕
@export var rotation_enabled: bool = true
## 旋转速度（度/秒）
@export var rotation_speed: float = 360.0
## 旋转方向：true=顺时针
@export var clockwise: bool = true
## 命中缆车后是否消失；默认不消失
@export var destroy_on_hit: bool = false

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

var _direction: Vector2 = Vector2.RIGHT
var _velocity: Vector2 = Vector2.ZERO
var _current_speed: float = 0.0
var _fall_speed: float = 0.0
var _life: float = 0.0
var _accel_elapsed: float = 0.0
var _gravity_delay_left: float = 0.0
var _source: Obstacle
var _pool_owner: ObstacleBulletEmitter
var _active: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func activate(direction: Vector2, source: Obstacle, pool_owner: ObstacleBulletEmitter) -> void:
	_direction = direction.normalized()
	_source = source
	_pool_owner = pool_owner
	_life = life_time
	_current_speed = 0.0
	_accel_elapsed = 0.0
	_gravity_delay_left = gravity_delay
	_fall_speed = 0.0
	_velocity = Vector2.ZERO
	if sprite != null:
		sprite.rotation = 0.0
	_active = true
	visible = true
	set_deferred("monitoring", true)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if acceleration_time > 0.0:
		if curve_acceleration_enabled:
			_accel_elapsed += delta
			var t := clampf(_accel_elapsed / acceleration_time, 0.0, 1.0)
			_current_speed = speed * t * t
		else:
			_current_speed = move_toward(_current_speed, speed, (speed / acceleration_time) * delta)
	else:
		_current_speed = speed
	_velocity = _direction * _current_speed
	if affected_by_gravity:
		if _gravity_delay_left > 0.0:
			_gravity_delay_left = maxf(0.0, _gravity_delay_left - delta)
		else:
			_fall_speed += bullet_gravity * delta
			_fall_speed = minf(_fall_speed, max_fall_speed)
			_velocity.y += _fall_speed
	global_position += _velocity * delta
	if rotation_enabled and sprite != null:
		sprite.rotation += deg_to_rad(rotation_speed) * delta * (1.0 if clockwise else -1.0)
	_life -= delta
	if _life <= 0.0:
		_finish()


func _on_body_entered(body: Node2D) -> void:
	if not body is CoasterController:
		return
	if is_instance_valid(_source):
		_source.touched.emit(_source, body as CoasterController)
	if destroy_on_hit:
		_finish()


func _finish() -> void:
	if not _active:
		return
	_active = false
	visible = false
	set_deferred("monitoring", false)
	set_physics_process(false)
	if is_instance_valid(_pool_owner):
		_pool_owner._recycle(self)
	else:
		queue_free()

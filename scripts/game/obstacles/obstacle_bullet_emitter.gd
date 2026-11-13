class_name ObstacleBulletEmitter
extends Node2D
## 障碍弹幕发射器：只负责发射几何（数量、间隔、扇形、固定角度、枪口、散射）。
## 障碍的 bullet_detection_enabled = true：检测到缆车时每隔 trigger_interval 秒瞄准缆车发射；
## false：常驻每隔 idle_interval 秒按 fixed_angle_deg 固定角度发射。
## 弹幕速度/重力/生命周期/纹理由 ObstacleBullet 场景控制。

@export_category("发射")
## 弹幕场景
@export var bullet_scene: PackedScene
## 每轮发射数量
@export_range(1, 32, 1) var bullet_count: int = 1
## 弹幕检测开启时的发射间隔（秒）
@export var trigger_interval: float = 5.0
## 常驻发射间隔（秒）
@export var idle_interval: float = 4.0
## 是否开启扇形散射
@export var spread_enabled: bool = false
## 扇形总张角（度）
@export var spread_angle_deg: float = 60.0
## 每发随机散射角（度）
@export var scatter_deg: float = 0.0
## 固定发射角度（度）；0=向右，45=右下
@export var fixed_angle_deg: float = 0.0
## 发射点相对障碍的偏移
@export var muzzle_offset: Vector2 = Vector2.ZERO

var _timer: float = 0.0
var _was_detecting: bool = false
var _has_fired: bool = false
var _pool: Array[ObstacleBullet] = []
var _active: Array[ObstacleBullet] = []


func _ready() -> void:
	var obstacle := get_parent() as Obstacle
	if obstacle == null:
		push_error("ObstacleBulletEmitter 必须作为 Obstacle 的子节点")
		return
	_timer = 0.0 if obstacle.bullet_detection_enabled else idle_interval


func _process(delta: float) -> void:
	var obstacle := get_parent() as Obstacle
	if obstacle == null:
		return
	var detect := obstacle.bullet_detection_enabled
	var interval := trigger_interval if detect else idle_interval
	var target: CoasterController = null
	if detect:
		target = _find_coaster(obstacle)
		if target == null:
			_was_detecting = false
			_timer = maxf(0.0, _timer - delta)
			return
		if not _was_detecting:
			_was_detecting = true
			# 首次进入范围立即发射；离开后重新进入则继续遵守剩余冷却。
			if not _has_fired or _timer <= 0.0:
				_has_fired = true
				_timer = interval
				_fire(obstacle, target)
				return
	_timer -= delta
	if _timer > 0.0:
		return
	_has_fired = true
	_timer = interval
	_fire(obstacle, target)


func _fire(obstacle: Obstacle, target: CoasterController) -> void:
	if bullet_scene == null:
		push_error("ObstacleBulletEmitter 缺少 bullet_scene")
		return
	var muzzle := obstacle.global_position + muzzle_offset
	if obstacle.scale.x < 0.0:
		muzzle.x = obstacle.global_position.x - muzzle_offset.x
	var base_direction: Vector2
	if target != null:
		base_direction = (target.global_position - muzzle).normalized()
	else:
		base_direction = Vector2.RIGHT.rotated(deg_to_rad(fixed_angle_deg))
		if obstacle.scale.x < 0.0:
			base_direction.x = -base_direction.x
	var count := maxi(1, bullet_count)
	for index in count:
		var direction := base_direction
		if spread_enabled and count > 1:
			var ratio := float(index) / float(count - 1)
			var angle := deg_to_rad(lerpf(-spread_angle_deg * 0.5, spread_angle_deg * 0.5, ratio))
			direction = base_direction.rotated(angle)
		if scatter_deg > 0.0:
			direction = direction.rotated(deg_to_rad(randf_range(-scatter_deg, scatter_deg)))
		var bullet := _take_bullet(obstacle)
		if bullet == null:
			return
		bullet.global_position = muzzle
		bullet.activate(direction, obstacle, self)
		# 子弹来自对象池，上一次的位置/旋转仍在插值历史里；
		# 不重置会从旧位置滑行到新枪口（streaking）。递归覆盖子 Sprite2D 的旋转复位。
		bullet.reset_physics_interpolation()


func _take_bullet(obstacle: Obstacle) -> ObstacleBullet:
	while not _pool.is_empty():
		var pooled: ObstacleBullet = _pool.pop_back()
		if is_instance_valid(pooled):
			_active.append(pooled)
			return pooled
	var bullet := bullet_scene.instantiate() as ObstacleBullet
	if bullet == null:
		push_error("ObstacleBulletEmitter 的 bullet_scene 根节点必须是 ObstacleBullet")
		return null
	var parent_node := obstacle.get_parent()
	if parent_node == null:
		parent_node = get_tree().current_scene
	parent_node.add_child(bullet)
	_active.append(bullet)
	return bullet


func _recycle(bullet: ObstacleBullet) -> void:
	_active.erase(bullet)
	if is_instance_valid(bullet) and not _pool.has(bullet):
		_pool.append(bullet)


func _find_coaster(obstacle: Obstacle) -> CoasterController:
	var detector := obstacle.get_node_or_null("PlayerDetector") as Area2D
	if detector == null:
		return null
	for body in detector.get_overlapping_bodies():
		if body is CoasterController:
			return body as CoasterController
	return null


func _exit_tree() -> void:
	for bullet in _active:
		if is_instance_valid(bullet):
			bullet.queue_free()
	for bullet in _pool:
		if is_instance_valid(bullet):
			bullet.queue_free()

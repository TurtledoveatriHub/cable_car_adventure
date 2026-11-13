class_name CoasterController
extends CharacterBody2D
## 单轨过山车控制器。
## 每辆缆车使用独立场景；速度、摩擦、重力、阻力、乘客数、外观、碰撞体直接来自场景根节点导出参数。
## 玩家只控制“沿轨道前进 / 后退”，车身自动贴合轨道。

signal hit_visual_started
signal jump_started

@onready var body_sprite: Sprite2D = get_node_or_null("BodySprite") as Sprite2D
@onready var bg_sprite: Sprite2D = get_node_or_null("BGSprite") as Sprite2D
@onready var passenger_seats: Node2D = get_node_or_null("PassengerSeats") as Node2D

@export_category("身份")
## 稳定 id
@export var cart_id: String = "dove"
## 显示名称
@export var display_name: String = "小斑鸠"
## 简短说明
@export var description: String = "均衡的初始缆车"


var track: TrackGeometry
var current_s: float = 0.0
var current_speed: float = 0.0
var passenger_count: int = 3
var active: bool = false
var run_finished: bool = false
var run_failed: bool = false

@export_category("动力手感")
## 沿轨道正向行驶的最高速度（像素/秒）。
@export var max_speed: float = 720.0
## 沿轨道倒车时的最高速度（像素/秒）。
@export var max_reverse_speed: float = 680.0
## 按住右方向时的正向加速度（像素/秒²）。
@export var engine_acceleration: float = 320.0
## 按住左方向时的反向加速度（像素/秒²）。
@export var reverse_acceleration: float = 290.0
## 与当前速度反向按键时的额外制动加速度（像素/秒²）；
## 越大越容易快速抵消残余的反向速度，不再和静止起步一样“顶不回来”。
@export var counter_brake_acceleration: float = 900.0
## 反向速度低于该值时仍按普通加速处理；0 表示任何反向速度都先强力制动。
@export var counter_brake_min_speed: float = 0.0
## 沿轨道坡度产生的重力加速度。
@export var gravity_accel: float = 900.0
## 上坡时引擎抵消重力的比例，0 表示不助力。
@export var uphill_engine_assist: float = 0.78
## 松开方向键后的滚动摩擦减速度。
@export var rolling_friction: float = 42.0
## 速度随时间的空气阻力衰减系数。
@export var air_drag: float = 0.28
## 飞行时施加的向下重力。
@export var air_gravity: float = 900.0
## 飞行时最大下落速度（像素/秒）
@export var max_fall_speed: float = 520.0
## 飞行结束回到轨道时的吸附检测半径。
@export var magnet_radius: float = 16.0

@export_category("外观")
## 车身 Sprite 相对轨道悬挂点的垂直偏移。
@export var body_offset_y: float = 24.0
## 车轮沿车身方向的分布半宽；1 个车轮固定在中心，2-4 个均匀分布。
@export var wheel_offset: float = 24.0
## 车轮数量（1-4），默认 2 个。
@export_range(1, 4, 1) var wheel_count: int = 2
## 车轮绘制半径，并用于计算滚动动画。
@export var wheel_radius: float = 8.0
## 车轮 PNG 贴图；为空时退回程序化圆轮。
@export var wheel_texture: Texture2D = preload("res://assets/visuals/carts/wheel.png")
## 乘客 Sprite 缩放；png 素材按实际大小绘制时设为 1.0。
@export var passenger_scale: float = 1.0
## 乘客上下车错峰间隔（秒）
@export var passenger_stagger_interval: float = 0.12

@export_category("乘客")
## 关卡开局时车上的乘客数量。
@export var starting_passengers: int = 3
## 缆车最多可容纳的乘客数量。
@export var max_passengers: int = 3
## 每个座位相对车身中心的局部坐标，用于乘客上下车动画。
@export var seat_offsets: Array[Vector2] = []

@export_category("解锁条件")
## 通关该关卡解锁；留空表示不限制关卡。
@export var unlock_level_id: String = ""
## 上传到广场的自制关卡数量达到该值解锁；0 表示不限制。
@export var unlock_uploads: int = 0
## 累计星星达到该值解锁；0 表示不限制。
@export var unlock_stars: int = 0

@export_category("闪避")
## 受到障碍伤害时免疫本次伤害的概率（0 表示不免疫）。
@export var evade_chance: float = 0.0

@export_category("护甲")
## 每局一次，抵消一次障碍伤害；可用时车身外显示圆形白环。
@export var armor_enabled: bool = false
## 护甲白环的半径（像素）。
@export var armor_radius: float = 46.0
## 护甲白环的线宽。
@export var armor_ring_width: float = 3.0

@export_category("冲刺")
## 快速双击同一方向键触发短时加速。
@export var dash_enabled: bool = false
## 冲刺期间速度/加速度倍率。
@export var dash_speed_multiplier: float = 1.88
## 冲刺持续时间（秒）。
@export var dash_duration: float = 1.0
## 冲刺结束后的恢复时间（秒）。
@export var dash_recovery: float = 0.5
## 冲刺冷却（秒）。
@export var dash_cooldown_seconds: float = 8.0
## 冲刺拖尾/速度线强度。
@export var dash_effect_strength: float = 1.0

@export_category("冲刺拖尾")
## 冲刺拖尾总开关（常态不显示拖尾）。
@export var dash_trail_enabled: bool = false
## 冲刺拖尾长度（像素）。
@export var dash_trail_length: float = 160.0
## 冲刺拖尾根部宽度。
@export var dash_trail_width: float = 14.0
## 冲刺拖尾颜色。
@export var dash_trail_color: Color = Color(1.0, 0.78, 0.24)
## 拖尾横向摆动幅度，做出卡通火焰感。
@export var dash_trail_wave: float = 8.0
## 拖尾分段数；越大渐变越平滑。
@export var dash_trail_segments: int = 16
## 拖尾相对缆车中心的偏移（x 沿轨道，y 垂直轨道）。
@export var dash_trail_offset: Vector2 = Vector2.ZERO

@export_category("空间移动")
## 快速双击方向键沿轨道瞬移；遇到断口只移动到断口。
@export var blink_enabled: bool = false
## 单次瞬移的轨道弧长（像素）。
@export var blink_distance: float = 240.0
## 瞬移冷却时间（秒）。
@export var blink_cooldown: float = 12.0
## 瞬移星光亮度/不透明度（不控制持续时间或大小）。
@export var blink_effect_strength: float = 1.0
## 星光特效大小倍率。
@export var blink_effect_scale: float = 2.0
## 星光特效持续时间（秒）。
@export var blink_effect_duration: float = 0.96

@export_category("乘客击飞")
## 乘客被击飞时的水平初速度上限。
@export var eject_horizontal_speed: float = 640.0
## 乘客被击飞时的向上初速度。
@export var eject_vertical_speed: float = 720.0
## 乘客被击飞后的重力。
@export var eject_gravity: float = 900.0
## 乘客被击飞时的旋转速度。
@export var eject_spin_speed: float = 1080.0
## 乘客被击飞后的存活时间。
@export var eject_lifetime: float = 4.00
## 存活时间中开始淡出的比例（0.9 表示后 10% 淡出）。
@export var eject_fade_start: float = 0.9

@export_category("冷却表现")
## 冲刺/空间移动冷却期间车体亮度。
@export var cooldown_dim_brightness: float = 0.9
## 冷却结束瞬间的亮起持续时间（秒）。
@export var cooldown_ready_flash_duration: float = 0.4
## 冷却结束瞬间的过曝亮度。
@export var cooldown_ready_flash_brightness: float = 1.52
## 空间移动发动后的过曝持续时间。
@export var blink_activation_flash_duration: float = 0.6
## 空间移动过曝后平滑过渡到冷却变暗的时间。
@export var blink_flash_to_dim_duration: float = 1.0

var _seat_sprites: Array[Sprite2D] = []
var _passenger_textures_used: Array[Texture2D] = []
var _wheel_layer: CartWheelLayer
var _boarding_done: bool = false
var _input_prefix: String = "solo"
var _armor_available: bool = false
var _dash_active_left: float = 0.0
var _dash_recover_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _blink_cooldown_left: float = 0.0
var _cooldown_ready_flash_left: float = 0.0
var _blink_activation_flash_left: float = 0.0
var _blink_flash_to_dim_left: float = 0.0
var _last_tap_action: String = ""
var _last_tap_msec: int = -1000
var _dash_trail_direction: float = -1.0
var _wheel_spin: float = 0.0
var _hit_flash_time: float = 0.0
var _cart_visual_error: bool = false
var _invulnerable_until_msec: int = 0
var _track_angle: float = 0.0
var _failed_tilt: float = 0.0
var _airborne: bool = false
var _air_velocity: Vector2 = Vector2.ZERO
var _track_forward_sign: float = 1.0
var _air_elapsed: float = 0.0
var _last_ground_speed: float = 0.0
var _boarding_global_position: Vector2 = Vector2.INF
var _alight_global_position: Vector2 = Vector2.INF
var _child_base_positions: Dictionary = {}
var _body_offset_scene_base: float = 0.0
var _body_offset_captured: bool = false
var _runs: Array[Dictionary] = []
## 每段连续轨道在关卡开始时算一次前进符号；同一段内永远不变。
## 符号来自“该段第一段轨道的方向 + 段起点切线”，与之后从哪边落轨无关。
var _run_forward_signs: Dictionary = {}
var _level_start_s: float = 0.0
var _level_finish_s: float = 0.0

# ---- 按需重绘脏标记 ----
# 缆车根节点 _draw() 只剩两样东西：冲刺拖尾（随时间波动）与装甲环（参数全静态）。
# 装甲环原先每帧重建两条 48 段圆弧（约 96 段），但它的半径/线宽/中心从不变化，
# 只在「护甲出现/消失」或「body_offset_y 变化」时才需要重画一次。
## 缆车自绘内容需要刷新；初始为 true 以保证首帧画出装甲环。
var _draw_dirty: bool = true
## 车轮层需要刷新（吊杆随轨道角变化，无贴图时轮辐还随 _wheel_spin 旋转）。
var _wheel_dirty: bool = true
var _last_wheel_spin: float = 0.0
var _last_wheel_angle: float = 0.0
## 车轮布局缓存：local 是「切线 = +X」的基准位置，pose 是旋转后的实际位置。
## 两个数组都长期复用，只在 wheel_count / wheel_offset 变化时重建。
var _wheel_local_positions: Array[Vector2] = []
var _wheel_pose_positions: Array[Vector2] = []
var _wheel_cache_count: int = -1
var _wheel_cache_offset: float = -1.0
## 车身精灵上次同步过的倾角，避免每帧重复写已插值子节点的变换。
var _applied_failed_tilt: float = 0.0
var _applied_flip_h: bool = false
var _body_visual_synced: bool = false
## 装甲环上一帧是否可见、以及当时的 body_offset_y；两者都不变就不必重画。
var _armor_was_visible: bool = false
var _armor_body_offset_y: float = 0.0
## 拖尾上一帧是否活跃；用于在拖尾结束的那一帧补一次重绘把它擦掉。
var _trail_was_active: bool = false

## 起飞后短暂禁止吸附，避免刚离开断口就贴回原轨。
const AIR_ATTACH_LOCK := 0.2


func _ready() -> void:
	if passenger_seats != null:
		passenger_seats.z_index = -1
	collision_layer = 2
	collision_mask = 0
	_ensure_wheel_layer()
	_capture_child_base_positions()
	_armor_available = armor_enabled
	_apply_visual_settings()
	queue_redraw()
	if _wheel_layer != null:
		_wheel_layer.queue_redraw()


## 车轮独立成层：同一 z_index 下排在 BGSprite/乘客之前，因此被它们遮住，
## 但仍高于轨道（缆车根节点 z_index 通常为 8，轨道为 0）。
func _ensure_wheel_layer() -> void:
	if _wheel_layer != null and is_instance_valid(_wheel_layer):
		return
	_wheel_layer = CartWheelLayer.new()
	_wheel_layer.name = "WheelLayer"
	_wheel_layer.cart = self
	_wheel_layer.z_index = -1
	add_child(_wheel_layer)
	move_child(_wheel_layer, 0)


## 返回各车轮相对缆车中心的位置。
##
## 内部用两个复用数组，避免每次重绘都堆分配一个新数组——Web/WASM 单线程下
## 这类短命对象会持续制造 GC 压力。返回的数组属于本节点，调用方只读、不要长期持有。
func _wheel_positions(tangent: Vector2) -> Array[Vector2]:
	return _wheel_positions_angle(tangent.angle())


## 同上，但直接吃角度，省掉热路径上一次 atan2（切线本就是由 _track_angle 算出来的）。
func _wheel_positions_angle(angle: float) -> Array[Vector2]:
	_refresh_wheel_local_positions()
	for index in _wheel_local_positions.size():
		_wheel_pose_positions[index] = _wheel_local_positions[index].rotated(angle)
	return _wheel_pose_positions


## 车轮的「切线方向 = +X」基准布局。只在 wheel_count / wheel_offset 变化时重建。
func _refresh_wheel_local_positions() -> void:
	var count := clampi(wheel_count, 1, 4)
	if count == _wheel_cache_count and is_equal_approx(wheel_offset, _wheel_cache_offset):
		return
	_wheel_cache_count = count
	_wheel_cache_offset = wheel_offset
	_wheel_local_positions.clear()
	_wheel_pose_positions.clear()
	if count == 1:
		_wheel_local_positions.append(Vector2.ZERO)
	else:
		for index in count:
			var ratio := float(index) / float(count - 1)
			_wheel_local_positions.append(Vector2(lerpf(-wheel_offset, wheel_offset, ratio), 0.0))
	for _index in _wheel_local_positions.size():
		_wheel_pose_positions.append(Vector2.ZERO)


func draw_wheels(target: CanvasItem) -> void:
	var ink := Color(0.106, 0.196, 0.282)
	for wheel_center in _wheel_positions_angle(_track_angle):
		if wheel_texture != null:
			var wheel_size := wheel_radius * 2.4
			target.draw_texture_rect(
				wheel_texture,
				Rect2(wheel_center - Vector2(wheel_size * 0.5, wheel_size * 0.5), Vector2(wheel_size, wheel_size)),
				false
			)
		else:
			target.draw_circle(wheel_center, wheel_radius + 2.0, ink)
			target.draw_circle(wheel_center, wheel_radius, Color(0.78, 0.85, 0.9))
			target.draw_circle(wheel_center, wheel_radius * 0.4, Color(0.3, 0.4, 0.48))
			for spoke in 4:
				var angle := _wheel_spin + TAU * float(spoke) / 4.0
				target.draw_line(wheel_center, wheel_center + Vector2(cos(angle), sin(angle)) * (wheel_radius - 1.0), ink, 1.2, true)
		target.draw_line(wheel_center, Vector2(0, body_offset_y - 16.0), ink, 2.0, true)


## 记录场景内各节点的初始位置；body_offset_y 变化时整体平移，保持彼此相对关系。
func _capture_child_base_positions() -> void:
	_child_base_positions.clear()
	for child in get_children():
		if child == _wheel_layer:
			continue
		if child is Node2D:
			_child_base_positions[child] = (child as Node2D).position
	_body_offset_scene_base = body_sprite.position.y if body_sprite != null else body_offset_y
	_body_offset_captured = true


func _apply_visual_settings() -> void:
	if not _body_offset_captured:
		_capture_child_base_positions()
	var shift := body_offset_y - _body_offset_scene_base
	for child: Node in _child_base_positions.keys():
		if is_instance_valid(child):
			(child as Node2D).position = (_child_base_positions[child] as Vector2) + Vector2(0.0, shift)
	queue_redraw()


func configure(level: LevelData, input_prefix: String = "solo") -> void:
	track = level.track
	_input_prefix = input_prefix
	_level_start_s = level.start_s
	_level_finish_s = level.finish_s
	_runs = track.get_track_runs() if track != null else []
	_cache_run_forward_signs()
	_airborne = false
	_air_velocity = Vector2.ZERO
	_air_elapsed = 0.0
	_last_ground_speed = 0.0
	_apply_visual_settings()
	_armor_available = armor_enabled
	_dash_active_left = 0.0
	_dash_recover_left = 0.0
	_dash_cooldown_left = 0.0
	_blink_cooldown_left = 0.0
	_last_tap_action = ""
	_last_tap_msec = -1000
	current_s = level.start_s
	current_speed = 0.0
	_track_forward_sign = _forward_sign_at_s(current_s)
	active = false
	run_finished = false
	run_failed = false
	_boarding_done = false
	_update_pose()
	queue_redraw()
	if _wheel_layer != null:
		_wheel_layer.queue_redraw()


func can_board() -> bool:
	return passenger_count < max_passengers


func max_capacity() -> int:
	return max_passengers


func get_seat_position(index: int) -> Vector2:
	if index >= 0 and index < seat_offsets.size():
		return seat_offsets[index]
	return Vector2(-28.0 + (index % 5) * 14.0, -12.0 + floori(float(index) / 5.0) * 16.0)


func _input(event: InputEvent) -> void:
	if not active or not (dash_enabled or blink_enabled):
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	for action in ["left", "right"]:
		if event.is_action_pressed(_action_name(action)):
			_register_dash_tap(action)
			return


func _register_dash_tap(action: String) -> void:
	var now := Time.get_ticks_msec()
	if _last_tap_action == action and now - _last_tap_msec <= 280:
		_last_tap_action = ""
		if blink_enabled:
			if _blink_cooldown_left <= 0.0:
				_perform_blink(action)
			return
		if dash_enabled and _dash_active_left <= 0.0 and _dash_recover_left <= 0.0 and _dash_cooldown_left <= 0.0:
			_dash_active_left = dash_duration
			_dash_recover_left = dash_recovery
			_dash_cooldown_left = dash_cooldown_seconds
			_dash_trail_direction = -_track_forward_sign if action == "right" else _track_forward_sign
			queue_redraw()
		return
	_last_tap_action = action
	_last_tap_msec = now


func _perform_blink(action: String) -> void:
	if track == null:
		return
	var direction := 1.0 if action == "right" else -1.0
	var target_s := current_s + direction * blink_distance
	# 瞬移只能发生在当前连续轨道段内；遇到 gap 停在断口。
	for run in track.get_track_runs():
		var run_start := float(run.get("start_s", 0.0))
		var run_end := float(run.get("end_s", 0.0))
		if current_s >= run_start - 0.01 and current_s <= run_end + 0.01:
			target_s = clampf(target_s, run_start, run_end)
			break
	target_s = clampf(target_s, 0.0, track.total_length)
	# 目标落在已断开的片段上时，停在断口边缘。
	var target_piece := track.piece_index_at_s(target_s)
	if track.is_piece_broken(target_piece):
		var range_data := track.get_piece_range(target_piece)
		if not range_data.is_empty():
			target_s = float(range_data.get("start_s", current_s)) if direction > 0.0 else float(range_data.get("end_s", current_s))
	if absf(target_s - current_s) < 1.0:
		return
	var old_position := track.sample_at(current_s)
	_spawn_teleport_sparkle(old_position)
	current_s = target_s
	_update_pose()
	# 传送由 _input 触发（物理帧之外），属于官方文档所述的“物理帧外瞬移”，
	# 必须重置插值历史，否则会插值出一段横跨 blink_distance 的滑行。
	reset_physics_interpolation()
	_spawn_teleport_sparkle(track.sample_at(current_s))
	_blink_cooldown_left = blink_cooldown
	_blink_activation_flash_left = blink_activation_flash_duration
	_blink_flash_to_dim_left = blink_flash_to_dim_duration
	queue_redraw()


func _spawn_teleport_sparkle(world_position: Vector2) -> void:
	var sparkle := TeleportSparkle.new()
	get_parent().add_child(sparkle)
	sparkle.configure(blink_effect_strength, blink_effect_duration, blink_effect_scale)
	sparkle.global_position = world_position


func _update_dash(delta: float) -> void:
	var blink_before := _blink_cooldown_left
	var dash_before := _dash_cooldown_left
	_blink_cooldown_left = maxf(0.0, _blink_cooldown_left - delta)
	_dash_cooldown_left = maxf(0.0, _dash_cooldown_left - delta)
	if (blink_before > 0.0 and _blink_cooldown_left <= 0.0) or (dash_before > 0.0 and _dash_cooldown_left <= 0.0):
		_cooldown_ready_flash_left = cooldown_ready_flash_duration
	if _dash_active_left > 0.0:
		_dash_active_left = maxf(0.0, _dash_active_left - delta)
	elif _dash_recover_left > 0.0:
		_dash_recover_left = maxf(0.0, _dash_recover_left - delta)


func get_dash_fade() -> float:
	if _dash_active_left > 0.0:
		return 1.0
	if _dash_recover_left > 0.0:
		return _dash_recover_left / maxf(0.001, dash_recovery)
	return 0.0


func _dash_multiplier() -> float:
	if _dash_active_left > 0.0:
		return dash_speed_multiplier
	if _dash_recover_left > 0.0:
		return 1.0 + (_dash_recover_left / maxf(0.001, dash_recovery)) * (dash_speed_multiplier - 1.0)
	return 1.0


func set_armor_available(value: bool) -> void:
	_armor_available = value
	queue_redraw()


func get_dash_active_left() -> float:
	return _dash_active_left


func get_dash_recover_left() -> float:
	return _dash_recover_left


func hide_mirror_collision() -> void:
	# 镜像/幽灵缆车由 DuoGameController 在 _process 内调用 sync_visual_from 写入位置，
	# 属于渲染帧写变换，与全局物理插值冲突（会算出错误的插值历史并抖动），故显式关闭。
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	collision_layer = 0
	collision_mask = 0
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null:
		collision.disabled = true


func sync_visual_from(source: CoasterController) -> void:
	if source == null:
		return
	current_s = source.current_s
	current_speed = source.current_speed
	_track_angle = source._track_angle
	_wheel_spin = source._wheel_spin
	_airborne = source._airborne
	_air_velocity = source._air_velocity
	_boarding_global_position = source._boarding_global_position
	_alight_global_position = source._alight_global_position
	_failed_tilt = source._failed_tilt
	_hit_flash_time = source._hit_flash_time
	modulate = source.modulate
	_dash_active_left = source.get_dash_active_left()
	_dash_recover_left = source.get_dash_recover_left()
	set_passenger_count(source.passenger_count if source._boarding_done else 0)
	set_armor_available(source.has_armor())
	if source._boarding_done and not _boarding_done:
		_boarding_done = true
		_animate_boarding()
	if source.run_finished and not run_finished:
		lock_at_finish()
	elif source.run_failed and not run_failed:
		play_failure()
	if source._airborne:
		# 镜像/残影只做视觉同步：在空中时直接复制世界坐标，不能再用轨道弧长摆位。
		global_position = source.global_position
		rotation = 0.0
	else:
		_update_pose()
	queue_redraw()


func has_armor() -> bool:
	return armor_enabled and _armor_available


func consume_armor() -> bool:
	if not has_armor():
		return false
	_armor_available = false
	queue_redraw()
	return true


func _physics_process(delta: float) -> void:
	# 车身精灵的倾角/翻转必须在物理帧同步：_draw() 于渲染帧执行，
	# 在那里写已插值子节点的变换会让物理插值算出错误的历史并抖动。
	_sync_body_visuals()
	if track == null:
		return
	if _airborne:
		_advance_flight(delta)
		_update_redraw_flags()
		return
	if run_finished or run_failed:
		_update_redraw_flags()
		return
	if track.is_piece_broken(track.piece_index_at_s(current_s)):
		detach_from_track()
		_update_redraw_flags()
		return
	if not active:
		current_speed = move_toward(current_speed, 0.0, rolling_friction * 2.0 * delta)
		_update_pose()
		_mark_visual_dirty()
		_update_redraw_flags()
		return

	_update_hit_flash(delta)
	_update_invulnerability_visual()
	_update_dash(delta)
	_update_cooldown_visual(delta)
	var dash_multiplier := _dash_multiplier()

	var axis := Input.get_axis(_action_name("left"), _action_name("right")) * _track_forward_sign
	var slope := track.slope_at(current_s)
	current_speed += gravity_accel * slope * delta
	# 上坡助力：只有“引擎方向正对着上坡”才抵消部分重力惩罚。
	var climbing := (axis > 0.01 and slope < -0.02) or (axis < -0.01 and slope > 0.02)
	if climbing:
		current_speed -= slope * gravity_accel * uphill_engine_assist * delta
	var counter_braking := (
		(axis > 0.01 and current_speed < -counter_brake_min_speed)
		or (axis < -0.01 and current_speed > counter_brake_min_speed)
	)
	if counter_braking:
		# 先抵掉反向惯性，但同一帧仍要施加引擎加速度；
		# 否则上坡时重力每帧把速度压回负数，会被制动逻辑锁死在 0。
		current_speed = move_toward(current_speed, 0.0, counter_brake_acceleration * dash_multiplier * delta)
	if axis > 0.01:
		current_speed += engine_acceleration * dash_multiplier * axis * delta
	elif axis < -0.01:
		current_speed += reverse_acceleration * dash_multiplier * axis * delta
	elif not counter_braking:
		current_speed = move_toward(current_speed, 0.0, rolling_friction * delta)
	if air_drag > 0.0:
		current_speed *= maxf(1.0 - air_drag * delta, 0.0)

	current_speed = clampf(current_speed, -max_reverse_speed * dash_multiplier, max_speed * dash_multiplier)
	if absf(current_speed) > 1.0:
		_last_ground_speed = current_speed
	var previous_s := current_s
	current_s += current_speed * delta

	var run_index := _run_index_at(previous_s)
	if run_index >= 0:
		var run: Dictionary = _runs[run_index]
		var run_start := float(run.get("start_s", 0.0))
		var run_end := float(run.get("end_s", track.total_length))
		if current_s > run_end:
			current_s = run_end
			if track.run_has_gap_at_end(run_index) or _is_open_global_end(run_end):
				_start_flight(1.0)
				return
			current_speed = 0.0
		elif current_s < run_start:
			current_s = run_start
			if track.run_has_gap_at_start(run_index):
				_start_flight(-1.0)
				return
			current_speed = 0.0
	else:
		current_s = clampf(current_s, 0.0, track.total_length)

	_update_pose()
	_wheel_spin += current_speed * delta / maxf(2.0, wheel_radius)
	_update_redraw_flags()


## 轨道断开时让缆车脱离轨道，保留当前速度自由飞行；之后只由相机范围判定失败。
func detach_from_track() -> void:
	if _airborne:
		return
	var outward := 1.0 if current_speed >= 0.0 else -1.0
	if absf(current_speed) < 1.0:
		outward = _track_forward_sign
	_begin_flight(track.sample_at(current_s), outward)


## 到达连续轨道段（run）的开放端点：保持在端点，沿切线飞出。
func _start_flight(outward: float) -> void:
	_begin_flight(track.sample_at(current_s), outward)


## 统一的起飞入口。exit_point 必须是当前轨道上的真实位置，不能是空档端点。
func _begin_flight(exit_point: Vector2, outward: float) -> void:
	var inside := track.sample_at(clampf(current_s - 6.0 * outward, 0.0, track.total_length))
	var flight_dir := exit_point - inside
	if flight_dir.length_squared() < 0.0001:
		flight_dir = track.tangent_at(current_s) * outward
	var speed := absf(current_speed)
	if speed < 1.0:
		speed = absf(_last_ground_speed)
	global_position = exit_point
	# 瞬移类赋值必须重置插值历史，否则会从上一物理步位置插值出一段滑行残影。
	reset_physics_interpolation()
	_air_velocity = flight_dir.normalized() * speed
	_airborne = true
	_air_elapsed = 0.0
	_track_angle = _air_velocity.angle()
	rotation = 0.0
	jump_started.emit()
	queue_redraw()


## 空中只受重力；对“上一帧位置→当前位置”做扫掠吸附，
## 避免高速时一帧跨过整条轨道、明明碰到却不吸附。
func _advance_flight(delta: float) -> void:
	var previous_position := global_position
	_air_elapsed += delta
	_air_velocity.y += air_gravity * delta
	_air_velocity.y = minf(_air_velocity.y, max_fall_speed)
	global_position += _air_velocity * delta
	_track_angle = _air_velocity.angle()
	rotation = 0.0
	if _air_elapsed <= AIR_ATTACH_LOCK:
		return
	var travel := global_position - previous_position
	var steps := clampi(int(ceil(travel.length() / maxf(4.0, magnet_radius * 0.5))), 1, 8)
	var best_distance := INF
	var best_s := -1.0
	for step in range(1, steps + 1):
		var probe := previous_position + travel * (float(step) / float(steps))
		var candidate_s := track.nearest_rail_s(probe)
		var distance := probe.distance_to(track.sample_at(candidate_s))
		if distance < best_distance:
			best_distance = distance
			best_s = candidate_s
	if best_s < 0.0 or best_distance > magnet_radius:
		return
	var along := _air_velocity.dot(track.tangent_at(best_s))
	# 前进方向是整条轨道的固定设置；同一段轨道无论怎么落上来映射都不变。
	_track_forward_sign = _forward_sign_at_s(best_s)
	_airborne = false
	current_s = best_s
	current_speed = clampf(along, -max_reverse_speed, max_speed)
	_update_pose()
	queue_redraw()


func _run_index_at(s: float) -> int:
	for index in _runs.size():
		var run: Dictionary = _runs[index]
		if s >= float(run.get("start_s", 0.0)) - 0.01 and s <= float(run.get("end_s", 0.0)) + 0.01:
			return index
	return -1


## 关卡开始时为每段连续轨道算一次 s 符号。
## 判定基准是该段第一段轨道（最早放置/最靠近段起点的那一段）：
## - 它的“轨道前进方向：右/左”决定该段整体朝向；
## - 用段起点的切线把“右/左”换算成 +s 或 -s；
## - 同一段内后半段即使切线反向（例如 U 型弯的下端），也沿用同一个 s 符号。
func _cache_run_forward_signs() -> void:
	_run_forward_signs.clear()
	for run_index in _runs.size():
		_run_forward_signs[run_index] = _compute_run_forward_sign(run_index)


func _forward_sign_at_s(s: float) -> float:
	var run_index := _run_index_at(s)
	return _forward_sign_for_run(run_index)


func _forward_sign_for_run(run_index: int) -> float:
	if run_index < 0:
		return 1.0
	if not _run_forward_signs.has(run_index):
		return _compute_run_forward_sign(run_index)
	return float(_run_forward_signs[run_index])


func _compute_run_forward_sign(run_index: int) -> float:
	if track == null or run_index < 0 or run_index >= _runs.size():
		return 1.0
	var anchor_piece := track.get_run_anchor_piece(run_index)
	if anchor_piece < 0 or anchor_piece >= track.piece_ranges.size():
		return 1.0
	var anchor_range: Dictionary = track.piece_ranges[anchor_piece]
	var anchor_start := float(anchor_range.get("start_s", 0.0))
	var anchor_end := float(anchor_range.get("end_s", anchor_start))
	var run_direction := track.get_piece_direction(anchor_piece)
	# 取锚点片段内部点；片段起点在接缝上，切线会采到空档连接线。
	var probe_s := minf(anchor_start + 8.0, (anchor_start + anchor_end) * 0.5)
	var tangent := track.tangent_at(probe_s)
	if absf(tangent.x) < 0.15:
		return 1.0 if run_direction >= 0.0 else -1.0
	return 1.0 if tangent.x * run_direction > 0.0 else -1.0


## 轨道尾端默认可以飞出；只有它本身就是起点/终点站台时才封闭。
## 这样朝上延伸、且位于轨道最末端的孤立轨道也能正常脱离。
func _is_open_global_end(edge_s: float) -> bool:
	if track == null:
		return false
	if absf(edge_s - track.total_length) > 0.01:
		return false
	if absf(edge_s - _level_finish_s) <= 120.0:
		return false
	if absf(edge_s - _level_start_s) <= 120.0:
		return false
	return true

func set_boarding_global_position(world_position: Vector2) -> void:
	_boarding_global_position = world_position


func set_alight_global_position(world_position: Vector2) -> void:
	_alight_global_position = world_position


func set_active(enabled: bool) -> void:
	active = enabled


func play_boarding_animation() -> void:
	_boarding_done = true
	_animate_boarding()


func _seat_position(index: int) -> Vector2:
	return get_seat_position(index)


func _make_seat(index: int, animate: bool = true) -> void:
	if passenger_seats == null:
		return
	var sprite := Sprite2D.new()
	var passenger_texture := PassengerCatalog.random_texture_excluding(_passenger_textures_used)
	if passenger_texture == null:
		passenger_texture = PassengerCatalog.random_texture()
	if passenger_texture != null and not _passenger_textures_used.has(passenger_texture):
		_passenger_textures_used.append(passenger_texture)
	sprite.texture = passenger_texture
	sprite.scale = Vector2.ONE * passenger_scale
	sprite.position = _seat_position(index)
	sprite.z_index = 0
	if not active:
		sprite.modulate.a = 0.0
	passenger_seats.add_child(sprite)
	_seat_sprites.append(sprite)
	if animate:
		var target := sprite.position
		sprite.position = target + Vector2(randf_range(-18, 18), 42)
		sprite.modulate.a = 0.0
		var tween := create_tween().set_parallel(true)
		# 座位 Sprite2D 继承缆车的物理插值；补间默认在渲染帧写变换会破坏插值历史，
		# 故切到物理帧时序（官方文档要求：间接移动也必须在物理帧内发生）。
		tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tween.tween_property(sprite, "position", target, 0.28).set_trans(Tween.TRANS_BACK)
		tween.tween_property(sprite, "modulate:a", 1.0, 0.2)


func _animate_boarding() -> void:
	var start_local := Vector2.ZERO
	if _boarding_global_position != Vector2.INF and passenger_seats != null:
		start_local = passenger_seats.to_local(_boarding_global_position)
	for index in _seat_sprites.size():
		var sprite := _seat_sprites[index]
		var target := _seat_position(index)
		sprite.position = start_local + Vector2(randf_range(-16, 16), randf_range(-8, 8))
		sprite.modulate.a = 0.0
		var delay := index * passenger_stagger_interval
		var tween := create_tween().set_parallel(true)
		tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tween.tween_property(sprite, "position", target, 0.42).set_trans(Tween.TRANS_BACK).set_delay(delay)
		tween.tween_property(sprite, "modulate:a", 1.0, 0.22).set_delay(delay)


func _eject_passenger() -> void:
	if _seat_sprites.is_empty():
		return
	var sprite: Sprite2D = _seat_sprites.pop_back()
	var start := sprite.global_position
	var sprite_scale := sprite.scale
	var passenger_texture := sprite.texture
	sprite.queue_free()
	var eject := PassengerEject.new()
	get_parent().add_child(eject)
	eject.configure(
		passenger_texture,
		start,
		Vector2(randf_range(-eject_horizontal_speed, eject_horizontal_speed), -randf_range(eject_vertical_speed * 0.75, eject_vertical_speed * 1.2)),
		eject_gravity,
		deg_to_rad(randf_range(-eject_spin_speed, eject_spin_speed)),
		eject_lifetime,
		eject_fade_start,
		sprite_scale
	)


func _animate_alighting() -> void:
	var exit_local := Vector2.ZERO
	var has_exit := _alight_global_position != Vector2.INF and passenger_seats != null
	if has_exit:
		exit_local = passenger_seats.to_local(_alight_global_position)
	for index in _seat_sprites.size():
		var sprite := _seat_sprites[index]
		var target := exit_local + Vector2(randf_range(-10, 10), 0) if has_exit else sprite.position + Vector2(randf_range(-40, 40), 110)
		var hop := target + Vector2(randf_range(-14, 14), -30)
		var tween := create_tween()
		tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tween.tween_property(sprite, "position", hop, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(index * passenger_stagger_interval)
		tween.tween_property(sprite, "position", target, 0.30).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tween.tween_interval(0.18)
		tween.tween_property(sprite, "modulate:a", 0.0, 0.28)
		tween.tween_callback(sprite.queue_free)
	_seat_sprites.clear()


func set_passenger_count(count: int) -> void:
	passenger_count = maxi(0, count)
	while _seat_sprites.size() < passenger_count:
		_make_seat(_seat_sprites.size(), active)
	while _seat_sprites.size() > passenger_count:
		_eject_passenger()
	queue_redraw()


func is_invulnerable() -> bool:
	return Time.get_ticks_msec() < _invulnerable_until_msec


func begin_invulnerability(duration_seconds: float = 0.9) -> void:
	_invulnerable_until_msec = max(
		_invulnerable_until_msec,
		Time.get_ticks_msec() + int(duration_seconds * 1000.0)
	)


func play_hit_flash() -> void:
	_hit_flash_time = 0.26
	hit_visual_started.emit()
	queue_redraw()


func lock_at_finish() -> void:
	run_finished = true
	active = false
	_animate_alighting()
	queue_redraw()


func play_failure() -> void:
	run_failed = true
	active = false
	_failed_tilt = 0.4
	queue_redraw()


func get_progress_ratio() -> float:
	if track == null or track.total_length <= 0.0:
		return 0.0
	return clampf(current_s / track.total_length, 0.0, 1.0)


func get_track_angle() -> float:
	return _track_angle


func get_tangent() -> Vector2:
	if track == null:
		return Vector2.RIGHT
	return track.tangent_at(current_s)


func get_look_ahead_position(distance: float = 260.0, look_dir: float = 1.0) -> Vector2:
	if track == null:
		return global_position
	var look_s := clampf(current_s + look_dir * distance, 0.0, track.total_length)
	return track.sample_at(look_s)


func is_jumping() -> bool:
	return _airborne


func get_body_center() -> Vector2:
	return global_position + Vector2(0, body_offset_y)


func _update_pose() -> void:
	if track == null:
		return
	global_position = track.sample_at(current_s)
	_track_angle = track.angle_at(current_s)
	rotation = 0.0


func _update_cooldown_visual(delta: float) -> void:
	if _blink_activation_flash_left > 0.0:
		_blink_activation_flash_left = maxf(0.0, _blink_activation_flash_left - delta)
	elif _blink_flash_to_dim_left > 0.0:
		_blink_flash_to_dim_left = maxf(0.0, _blink_flash_to_dim_left - delta)
	if _cooldown_ready_flash_left > 0.0:
		_cooldown_ready_flash_left = maxf(0.0, _cooldown_ready_flash_left - delta)
	var brightness := 1.0
	var dim := cooldown_dim_brightness if (_dash_cooldown_left > 0.0 or _blink_cooldown_left > 0.0) else 1.0
	if _blink_activation_flash_left > 0.0:
		brightness = cooldown_ready_flash_brightness
	elif _blink_flash_to_dim_left > 0.0:
		var t := 1.0 - _blink_flash_to_dim_left / maxf(0.001, blink_flash_to_dim_duration)
		brightness = lerpf(cooldown_ready_flash_brightness, dim, t)
	elif _dash_active_left > 0.0:
		brightness = cooldown_ready_flash_brightness
	elif _dash_recover_left > 0.0:
		var t := 1.0 - _dash_recover_left / maxf(0.001, dash_recovery)
		brightness = lerpf(cooldown_ready_flash_brightness, dim, t)
	else:
		brightness = dim
	if _cooldown_ready_flash_left > 0.0:
		brightness = cooldown_ready_flash_brightness
	# 使用 modulate 而不是 self_modulate：BodySprite 是子节点，self_modulate 不会影响它。
	modulate = Color(brightness, brightness, brightness, modulate.a)


func _update_hit_flash(delta: float) -> void:
	if _hit_flash_time > 0.0:
		_hit_flash_time = maxf(0.0, _hit_flash_time - delta)


func _update_invulnerability_visual() -> void:
	if is_invulnerable():
		var blink := int(Time.get_ticks_msec() / 80.0) % 2 == 0
		modulate.a = 0.5 if blink else 1.0
	else:
		modulate.a = 1.0


func _action_name(suffix: String) -> StringName:
	if _input_prefix.is_empty() or _input_prefix == "solo":
		return StringName("move_" + suffix)
	return StringName(_input_prefix + "_" + suffix)


## 车身精灵状态同步。原先这段副作用写在 _draw() 里，而 _draw() 在渲染帧执行；
## 开启物理插值后于渲染帧写子节点变换会得到错误的插值历史并抖动，故移到物理帧。
func _sync_body_visuals() -> void:
	var has_scene_sprite := body_sprite != null and body_sprite.texture != null
	if not has_scene_sprite:
		if not _cart_visual_error:
			_cart_visual_error = true
			push_error("Coaster '%s' 缺少 BodySprite 纹理" % name)
		return
	var flip := body_sprite.flip_h
	# 只在倾角或翻转真正变化时写子节点，避免每帧重复触发插值历史更新。
	if _body_visual_synced and is_equal_approx(_applied_failed_tilt, _failed_tilt) and _applied_flip_h == flip:
		return
	_applied_failed_tilt = _failed_tilt
	_applied_flip_h = flip
	_body_visual_synced = true
	# 吊厢。始终竖直，对应原作的悬挂式车厢。
	body_sprite.rotation = _failed_tilt
	if bg_sprite != null:
		bg_sprite.rotation = _failed_tilt
		bg_sprite.flip_h = flip


## 判定本帧是否真的需要重绘。缆车根节点 _draw() 只画两样东西：
## 冲刺拖尾（随时间与轨道角波动）与装甲环（参数全静态）；车轮层画吊杆与轮辐。
func _update_redraw_flags() -> void:
	# 拖尾：冲刺或恢复淡出期间每帧都在变；结束那一帧还要补画一次把残影擦掉。
	var trail_active := dash_trail_enabled and active and get_dash_fade() > 0.01
	if trail_active or _trail_was_active:
		_draw_dirty = true
	_trail_was_active = trail_active
	# 装甲环：半径/线宽/颜色都是常量，只有可见性与垂直偏移会影响画面。
	var armor_visible := armor_enabled and _armor_available
	if armor_visible != _armor_was_visible \
			or (armor_visible and not is_equal_approx(body_offset_y, _armor_body_offset_y)):
		_draw_dirty = true
	_armor_was_visible = armor_visible
	_armor_body_offset_y = body_offset_y
	# 车轮：吊杆随轨道角变化；没有贴图时轮辐还随 _wheel_spin 旋转。
	if not is_equal_approx(_track_angle, _last_wheel_angle) \
			or (wheel_texture == null and not is_equal_approx(_wheel_spin, _last_wheel_spin)):
		_wheel_dirty = true
	_last_wheel_angle = _track_angle
	_last_wheel_spin = _wheel_spin
	if _draw_dirty:
		_draw_dirty = false
		queue_redraw()
	if _wheel_dirty:
		_wheel_dirty = false
		if _wheel_layer != null:
			_wheel_layer.queue_redraw()


## 强制刷新缆车自绘与车轮层（配置、镜像同步、脱轨等状态突变时调用）。
func _mark_visual_dirty() -> void:
	_draw_dirty = true
	_wheel_dirty = true
	_update_redraw_flags()


func _draw() -> void:
	var tangent := Vector2(cos(_track_angle), sin(_track_angle))
	var normal := Vector2(-tangent.y, tangent.x)

	# 吊杆在车轮层里随车轮一起绘制；这里只保留车身/拖尾/护甲。

	# 冲刺拖尾：只保留一条渐变透明的卡通火箭尾焰。
	var dash_fade := 0.0
	if _dash_active_left > 0.0:
		dash_fade = 1.0
	elif _dash_recover_left > 0.0:
		dash_fade = _dash_recover_left / maxf(0.001, dash_recovery)
	if dash_trail_enabled and active and dash_fade > 0.01:
		var direction := _dash_trail_direction
		var trail_origin := Vector2(0, body_offset_y) + dash_trail_offset
		var segment_count := maxi(4, dash_trail_segments)
		var trail_points := PackedVector2Array()
		var trail_colors := PackedColorArray()
		for index in segment_count + 1:
			var ratio := float(index) / float(segment_count)
			var wave := sin(ratio * PI * 2.2 + Time.get_ticks_msec() * 0.012) * dash_trail_wave * ratio
			var point := trail_origin + tangent * direction * (ratio * dash_trail_length) + normal * wave
			trail_points.append(point)
			var alpha := pow(1.0 - ratio, 1.35) * dash_fade * dash_effect_strength * 0.9
			var color := dash_trail_color.lerp(Color(1.0, 0.98, 0.82), 1.0 - ratio)
			trail_colors.append(Color(color, alpha))
		draw_polyline_colors(trail_points, trail_colors, dash_trail_width * (0.7 + dash_fade * 0.3), true)
		# 根部亮芯，让火焰与缆车连接更自然。
		draw_circle(trail_origin + tangent * direction * 10.0, dash_trail_width * 0.45, Color(1.0, 0.95, 0.72, 0.55 * dash_fade))
	if armor_enabled and _armor_available:
		var ring_center := Vector2(0, body_offset_y)
		draw_arc(ring_center, armor_radius, 0, TAU, 48, Color(1, 1, 1, 0.92), armor_ring_width, true)
		draw_arc(ring_center, armor_radius + 4.0, 0, TAU, 48, Color(1, 1, 1, 0.18), armor_ring_width * 2.2, true)
	# 吊厢的倾角/翻转由 _sync_body_visuals() 在物理帧写入，
	# 不在这里操作子节点：_draw() 运行于渲染帧，写已插值节点会破坏插值历史。

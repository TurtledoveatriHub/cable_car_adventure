class_name Obstacle
extends Area2D
## 障碍 HurtBox：移动参数与 warma-shadow-test/HurtBox.gd 完全同单位、同默认值。
## move_speed_out/move_speed_back 单位是像素/秒；end_offset 是像素目标偏移。所有检测范围由场景检测节点提供。

signal touched(obstacle: Obstacle, coaster: CoasterController)

const MODE_STATIC := 0
const MODE_LINEAR := 1
const MODE_WAVE := 2
const MODE_CIRCULAR := 3

enum MineState { OFF, WAITING, IDLE, COOLDOWN }

@export_category("基础")
## 工坊 / JSON 使用的预制体 id
@export var prefab_id: String = ""
## 工坊显示名称
@export var display_name: String = "障碍物"
## 视觉类型
@export var obstacle_type: String = "bird"
## 碰撞扣除的乘客数
@export var damage: int = 1

@export_category("移动模式")
## 0=静止，1=直线往返，2=波浪往返，3=圆周往返
@export_enum("STATIC", "LINEAR", "WAVE", "CIRCULAR") var movement_mode: int = 0
## 根据移动速度方向翻转纹理（默认向右，向左移动时翻转）
@export var flip_by_motion: bool = true

@export_category("移动通用参数")
## 从初始点移动到终点偏移的速度（像素/秒）。
@export var move_speed_out: float = 120.0
## 从终点偏移返回初始点的速度（像素/秒）。
@export var move_speed_back: float = 120.0
## 终点偏移（相对编辑器放置位置，像素）
@export var end_offset: Vector2 = Vector2(240, 0)
## 在初始端停留时间（秒）
@export var start_wait_time: float = 0.5
## 在终点偏移端停留时间（秒）
@export var end_wait_time: float = 0.5
## 加速时间（秒）
@export var acceleration_time: float = 0.5
## 减速时间（秒）
@export var deceleration_time: float = 0.5

@export_category("波浪专用参数")
## 振幅（像素），偏离直线的最大垂直距离
@export var wave_amplitude: float = 240.0
## 周期，每次往返中正弦波完成几个完整振荡
@export var wave_period: float = 1.0
## 波浪初始方向：true=先向上，false=先向下
@export var wave_start_up: bool = true
## 往返时波浪方向相反（折返时正弦相位翻转）
@export var wave_reverse_on_return: bool = true

@export_category("圆周专用参数")
## 圆周运动方向（仅在 CIRCULAR 模式有效）
@export var circular_clockwise: bool = true

@export_category("旋转设置")
## 是否启用旋转；关闭时其它旋转参数无效
@export var rotation_enabled: bool = false
## 初始位置不旋转：开启且 rotation_enabled 时，起点/停靠点保持初始角度，离开后才旋转。
@export var no_rotation_at_start: bool = false
## 旋转速度（度/秒，0=不旋转）
@export var rotation_speed: float = 360.0
## 旋转方向：true=顺时针
@export var clockwise: bool = true
## 是否让碰撞体一起旋转
@export var rotate_collision: bool = false


@export_category("动画")
## 静止/等待时循环动画名
@export var idle_animation: String = "idle"
## 移动时循环动画名
@export var move_animation: String = "move"
## 周期伤害关闭期间的循环动画名
@export var off_animation: String = "off"

@export_category("周期生效")
## 开启后 idle 播放一遍 → off 播放一遍，循环；移动时也无视 move 动画。
@export var interval_enabled: bool = false

@export_category("触发器模式")
## 开启后：PlayerDetector 检测到缆车才启动，并完整执行一次往返；
## 往返期间不再重复检测，回到起点后才重新允许下一次触发。
@export var trigger_enabled: bool = false
## 两端触发：第一次检测移动到终点后停下并恢复检测；再次检测则回到起点停下并恢复检测。
@export var trigger_two_ends: bool = false
## 弹幕检测：独立于 trigger_enabled；开启后检测到缆车才发射，并瞄准缆车。
@export var bullet_detection_enabled: bool = false
## 触发地雷：默认 off 循环；检测到缆车后延迟 trigger_mine_delay 秒，播放一遍 idle，再回 off。
## 与“周期生效”冲突；开启后忽略周期生效与普通触发器/两端触发。
@export var trigger_mine: bool = false
## 触发地雷延迟（秒）
@export var trigger_mine_delay: float = 0.3
## 触发地雷冷却（秒）：idle 播放完后先冷却，再恢复检测
@export var trigger_mine_cooldown: float = 0.66
## 普通触发/两端触发结束后的检测冷却（秒）
@export var trigger_cooldown: float = 0.66

@export_category("发射器模式")
## 与触发器模式互斥；开启后立即发射一个，之后按随机间隔在初始位置继续发射。
@export var emitter_enabled: bool = false
## 发射间隔下限（秒）
@export var emitter_interval_min: float = 5.0
## 发射间隔上限（秒）
@export var emitter_interval_max: float = 6.0

var _track_s: float = 0.0
var _base_position: Vector2 = Vector2.ZERO
var _source_end_offset: Vector2 = Vector2.ZERO
var _flipped: bool = false
var _start_pos: Vector2 = Vector2.ZERO
var _end_pos: Vector2 = Vector2.ZERO
var _path_length: float = 0.0
var _perp_dir: Vector2 = Vector2.UP
var _circle_center: Vector2 = Vector2.ZERO
var _circle_radius: float = 0.0
var _progress: float = 0.0
var _moving_to_end: bool = true
var _current_speed: float = 0.0
var _wait_timer: float = 0.0
var _is_waiting: bool = false
var _motion_time_scale: float = 1.0
var _initialized: bool = false
var _triggered: bool = true
var _trigger_cycle_active: bool = false
var _trigger_cooldown_left: float = 0.0
var _returned_to_start: bool = false
var _two_end_at_end: bool = false
var _two_end_armed: bool = false
var _last_collision_active: bool = true
var _visual_error_reported: bool = false
var _interval_phase_idle: bool = true
var _interval_phase_time: float = 0.0
var _mine_state: int = MineState.OFF
var _mine_timer: float = 0.0
var _rotation_offset: float = 0.0
var _base_rotation: float = 0.0
var _visual_base_rotation: float = 0.0
var _rotation_captured: bool = false
var _base_scale: Vector2 = Vector2.ONE
var _scale_captured: bool = false
var _emitter_pool: Array[Obstacle] = []
var _emitter_alive: Array[Obstacle] = []
var _emitter_timer: float = 0.0
var _emitter_spawned: int = 0
var _emitter_template: Obstacle
var _is_emitted: bool = false
var _emitted_off_playing: bool = false
var _emitted_off_timer: float = 0.0
var _emitter_owner: Obstacle
var _detector_base_position: Vector2 = Vector2.ZERO
var _detector_base_scale: Vector2 = Vector2.ONE
var _detector_captured: bool = false
## 移动端降频：逻辑/碰撞仍按物理帧，视觉与持续接触检测走独立计时器。
var _visual_accum: float = 0.0
var _visual_delta: float = 0.0
var _contact_accum: float = 0.0
var _overlay_signature: String = ""
var _offscreen_paused: bool = false

@onready var visual: Node2D = get_node_or_null("Visual") as Node2D


func _ready() -> void:
	# 障碍运动在 _process 内写入变换（见 _update_position），而项目已开启全局物理插值。
	# 在渲染帧写已插值节点的变换会算出错误的插值历史并产生抖动，故此处显式关闭插值。
	# 子节点（Visual / PlayerDetector / Frame / CabinSlots / MeteorTrail 等）默认 INHERIT，一并生效。
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	monitorable = false
	z_index = 7
	add_to_group("obstacles")
	body_entered.connect(_on_body_entered)
	var detector := get_node_or_null("PlayerDetector") as Area2D
	if detector != null:
		detector.monitoring = true
		detector.body_entered.connect(_on_player_detector_body_entered)
	_base_rotation = rotation
	_visual_base_rotation = visual.rotation if visual != null else 0.0
	_rotation_captured = true
	_base_scale = Vector2(absf(scale.x), absf(scale.y))
	_scale_captured = true
	_source_end_offset = end_offset
	_reset_motion(global_position)
	if trigger_enabled:
		_triggered = false
		_last_collision_active = false
		set_deferred("monitoring", true)
	if trigger_mine:
		_mine_state = MineState.OFF
		_mine_timer = 0.0
		_triggered = false
		_last_collision_active = false
		set_deferred("monitoring", false)
	_interval_phase_idle = true
	_interval_phase_time = 0.0
	_initialized = true
	_setup_animations()
	if emitter_enabled:
		# 开局立即发射一个，后续再进入随机间隔计时。
		_emitter_timer = 0.0
	set_process(true)


func configure(data: Dictionary, track: TrackGeometry, motion_time_scale: float = 1.0) -> void:
	_track_s = float(data.get("s", 0.0))
	# 触发范围以场景里的 PlayerDetector 为准；关卡数据不再写入默认半径覆盖场景。
	if bool(data.get("trigger_enabled", false)):
		trigger_enabled = true
	var offset_value: Variant = data.get("offset", Vector2.ZERO)
	var offset := Vector2.ZERO
	if offset_value is Vector2:
		offset = offset_value
	elif offset_value is Dictionary:
		offset = Vector2(float(offset_value.get("x", 0.0)), float(offset_value.get("y", 0.0)))
	_base_position = track.sample_at(_track_s) + LevelData.CART_ANCHOR_OFFSET + offset
	_source_end_offset = end_offset
	_motion_time_scale = clampf(motion_time_scale, 0.5, 2.0)
	_reset_motion(_base_position)
	_rotation_offset = 0.0
	_apply_rotation_offset()
	_emitter_timer = 0.0
	if trigger_enabled:
		_triggered = false
		_trigger_cycle_active = false
		_returned_to_start = false
		_last_collision_active = false
		set_deferred("monitoring", true)
	if trigger_mine:
		_mine_state = MineState.OFF
		_mine_timer = 0.0
		_triggered = false
		_last_collision_active = false
		set_deferred("monitoring", false)
	_interval_phase_idle = true
	_interval_phase_time = 0.0
	_initialized = true
	apply_flip(bool(data.get("flip_x", false)))
	_setup_animations()


func _reset_motion(base: Vector2) -> void:
	_start_pos = base
	_end_pos = base + end_offset
	_path_length = end_offset.length()
	_perp_dir = Vector2(-end_offset.normalized().y, end_offset.normalized().x) if _path_length > 0.0 else Vector2.UP
	_circle_center = _start_pos + end_offset * 0.5
	_circle_radius = _path_length * 0.5
	_progress = 0.0
	_moving_to_end = true
	_current_speed = 0.0
	_wait_timer = 0.0
	_is_waiting = false
	_two_end_at_end = false
	_two_end_armed = false
	global_position = _start_pos
	_rotation_offset = 0.0
	_apply_rotation_offset()
	_mine_state = MineState.OFF
	_mine_timer = 0.0
	_interval_phase_idle = true
	_interval_phase_time = 0.0


func apply_flip(flip: bool) -> void:
	_flipped = flip
	if not _scale_captured:
		_base_scale = Vector2(absf(scale.x), absf(scale.y))
		_scale_captured = true
	scale = Vector2(absf(_base_scale.x) * (-1.0 if flip else 1.0), absf(_base_scale.y))
	# 未进入场景树的预览实例不会走 _ready，这里补一次基准偏移。
	if _source_end_offset == Vector2.ZERO and end_offset != Vector2.ZERO:
		_source_end_offset = end_offset
	end_offset = _source_end_offset
	if flip:
		end_offset.x = -end_offset.x
	var previous_perp := _perp_dir
	_reset_motion(_base_position)
	# WAVE 只镜像终点偏移的 X 与横向波形，垂直波形方向保持不变。
	if flip and movement_mode == MODE_WAVE:
		_perp_dir = Vector2(-previous_perp.x, previous_perp.y)


func set_motion_time_scale(scale_value: float) -> void:
	_motion_time_scale = clampf(scale_value, 0.5, 2.0)


## 工坊运动预览开关：暂停 Obstacle 及其子节点（摩天轮旋转、弹幕发射、动画）。
func set_motion_preview_enabled(enabled: bool) -> void:
	set_process(enabled)
	propagate_call("set_process", [enabled])


func get_motion_type() -> String:
	match movement_mode:
		MODE_LINEAR:
			return "linear"
		MODE_WAVE:
			return "wave"
		MODE_CIRCULAR:
			return "circular"
		_:
			return "static"


func get_track_s() -> float:
	return _track_s


## 供 GameController 裁剪屏幕外障碍的脚本轮询。
func is_gameplay_active() -> bool:
	return _trigger_cycle_active or _mine_state != MineState.OFF or not _emitter_alive.is_empty()


## 热气球/陨石的发射物拥有很长轨迹，且需要在远离缆车时继续运动/旋转：
## 按距离暂停会把整条轨迹和发射计时冻结在半空。
func is_cull_exempt() -> bool:
	return prefab_id == "hot_air_balloon" or prefab_id == "meteor"


## 同时冻结自身与摩天轮/陨石拖尾/弹幕子节点；靠近时恢复。
## 远离时也关闭 HurtBox/PlayerDetector 的物理轮询，避免长关卡里几十个 Area2D 白跑。
func set_offscreen_paused(paused: bool) -> void:
	if _offscreen_paused == paused:
		return
	# 防御性保护：触发/发射状态机正在运行或仍有存活发射物时，绝不能因为一次
	# 距离检查的时序差而停在中途。GameController 也会先判断，这里是最后一道闸。
	if paused and is_gameplay_active():
		return
	_offscreen_paused = paused
	set_process(not paused)
	for child in get_children():
		if child.has_method("set_process"):
			child.set_process(not paused)
		if child is Area2D:
			(child as Area2D).set_deferred("monitoring", not paused)
	if paused:
		_visual_accum = 0.0
		_visual_delta = 0.0
		_contact_accum = 0.0
		set_deferred("monitoring", false)
		var detector := get_node_or_null("PlayerDetector") as Area2D
		if detector != null:
			detector.set_deferred("monitoring", false)
	else:
		set_deferred("monitoring", _should_monitor())
		var detector := get_node_or_null("PlayerDetector") as Area2D
		if detector != null:
			detector.set_deferred("monitoring", true)


func _should_monitor() -> bool:
	if trigger_mine:
		return _mine_state == MineState.IDLE
	if trigger_enabled:
		return _triggered and _trigger_cooldown_left <= 0.0
	if interval_enabled:
		return _interval_phase_idle
	return true


func get_motion_direction_global() -> Vector2:
	if _path_length <= 0.0:
		return Vector2.ZERO
	var direction := (_end_pos - _start_pos).normalized()
	return direction if _moving_to_end else -direction


func _capture_detector_base() -> void:
	if _detector_captured:
		return
	var detector := get_node_or_null("PlayerDetector") as Area2D
	if detector == null:
		return
	_detector_base_position = detector.position
	_detector_base_scale = detector.scale
	_detector_captured = true


func _apply_detector_mirror() -> void:
	if not _detector_captured:
		_capture_detector_base()
	var detector := get_node_or_null("PlayerDetector") as Area2D
	if detector == null:
		return
	var mirror_x := false
	var mirror_y := false
	if bullet_detection_enabled:
		var target := _detected_coaster()
		if target != null:
			mirror_x = target.global_position.x < global_position.x
			if _flipped:
				mirror_x = not mirror_x
	elif trigger_enabled and trigger_two_ends:
		mirror_x = _two_end_at_end
		mirror_y = _two_end_at_end
		if _flipped:
			mirror_x = not mirror_x
	detector.position = Vector2(
		-_detector_base_position.x if mirror_x else _detector_base_position.x,
		-_detector_base_position.y if mirror_y else _detector_base_position.y
	)
	detector.scale = Vector2(
		-_detector_base_scale.x if mirror_x else _detector_base_scale.x,
		-_detector_base_scale.y if mirror_y else _detector_base_scale.y
	)


func _apply_motion_flip() -> void:
	var animated := visual as AnimatedSprite2D
	if animated == null:
		return
	if bullet_detection_enabled:
		# 弹幕检测优先：只有 PlayerDetector 内有缆车时才按相对位置翻转。
		var target := _detected_coaster()
		if target != null:
			var target_is_left := target.global_position.x < global_position.x
			animated.flip_h = not target_is_left if _flipped else target_is_left
		else:
			animated.flip_h = false
		return
	if not flip_by_motion:
		return
	# 静态障碍没有“朝哪边移动”，不能用默认 end_offset 误翻纹理；
	# 否则工坊翻转后根节点已经镜像，再翻一次 texture 就会和碰撞体错位。
	if movement_mode == MODE_STATIC:
		return
	var motion_dir := 0.0
	if not _is_waiting and _path_length > 0.0:
		motion_dir = 1.0 if _moving_to_end else -1.0
		var direction := (_end_pos - _start_pos).normalized()
		motion_dir *= signf(direction.x)
	if motion_dir == 0.0:
		return
	# 工坊翻转后纹理朝向已经相反，移动翻转逻辑也要反过来。
	var flip_texture := motion_dir < 0.0
	if _flipped:
		flip_texture = not flip_texture
	animated.flip_h = flip_texture


func _apply_rotation(delta: float) -> void:
	if not rotation_enabled or rotation_speed <= 0.0:
		return
	if not _rotation_captured:
		_base_rotation = rotation
		_visual_base_rotation = visual.rotation if visual != null else 0.0
		_rotation_captured = true
	var direction := 1.0 if clockwise else -1.0
	if _flipped:
		direction = -direction
	var step := deg_to_rad(rotation_speed) * direction * delta
	if no_rotation_at_start and _progress <= 0.001:
		_rotation_offset = 0.0
	else:
		_rotation_offset += step
	_apply_rotation_offset()


func _apply_rotation_offset() -> void:
	if not _rotation_captured:
		return
	if rotate_collision:
		rotation = _base_rotation + _rotation_offset
	elif visual != null:
		visual.rotation = _visual_base_rotation + _rotation_offset


func _process(delta: float) -> void:
	var fixed_delta := minf(delta, 1.0 / 30.0) * _motion_time_scale
	if not _initialized:
		return
	_visual_accum += delta
	_visual_delta += delta
	var visual_hz := PlatformConfig.obstacle_visual_hz
	var visual_due := visual_hz <= 0.0 or _visual_accum >= 1.0 / visual_hz
	if visual_due:
		_visual_accum = 0.0
		# 只有弹幕/两端触发需要每帧根据玩家位置镜像检测器；普通障碍直接跳过。
		if bullet_detection_enabled or (trigger_enabled and trigger_two_ends):
			_apply_detector_mirror()

	if emitter_enabled:
		# 发射器模式与触发器模式互斥，发射器优先。
		_process_emitter(fixed_delta)
		_is_waiting = true
		_finish_visual_tick(visual_due)
		return

	if interval_enabled and not trigger_mine:
		_update_interval_phase(fixed_delta)

	if trigger_mine:
		_update_trigger_mine(fixed_delta)
		_finish_visual_tick(visual_due)
		return

	if trigger_enabled and _trigger_cooldown_left > 0.0:
		_trigger_cooldown_left = maxf(0.0, _trigger_cooldown_left - fixed_delta)
		_triggered = false
		_last_collision_active = false
		set_deferred("monitoring", false)
		_finish_visual_tick(visual_due, true)
		return

	if trigger_enabled and trigger_two_ends:
		# 两端触发：移动到一端后停下，等缆车离开再进入才触发下一段。
		if not _trigger_cycle_active:
			_triggered = true
			if not _two_end_armed:
				if not _has_coaster_in_range():
					_two_end_armed = true
			elif _has_coaster_in_range() and movement_mode != MODE_STATIC:
				_start_two_end_cycle()
			else:
				_is_waiting = true
				if _contact_check_due(delta):
					_check_contact_damage()
				_finish_visual_tick(visual_due)
				return
	elif trigger_enabled:
		if not _trigger_cycle_active:
			# 只有空闲状态才检测；一旦触发，整段往返期间锁定，不再重复检测。
			_triggered = false
			if _has_coaster_in_range() and movement_mode != MODE_STATIC:
				_start_trigger_cycle()
			else:
				_finish_visual_tick(visual_due)
				return
		elif _returned_to_start:
			_finish_trigger_cycle()
			_finish_visual_tick(visual_due, true)
			return
	else:
		_triggered = true

	if movement_mode != MODE_STATIC:
		_handle_movement(fixed_delta)
	if monitoring and _contact_check_due(delta):
		_check_contact_damage()
	var collision_active := true
	if interval_enabled:
		collision_active = _interval_phase_idle
	collision_active = collision_active and _triggered
	if collision_active != _last_collision_active:
		_last_collision_active = collision_active
		set_deferred("monitoring", collision_active)
	_finish_visual_tick(visual_due)


## 视觉降频后统一结算旋转、贴图翻转、动画状态和调试环重绘。
func _finish_visual_tick(visual_due: bool, force: bool = false) -> void:
	if not visual_due and not force:
		return
	if visual_due:
		_apply_rotation(minf(_visual_delta, 0.25))
		_apply_motion_flip()
		_update_animation_state()
		_visual_delta = 0.0
	_refresh_overlay_redraw()


func _contact_check_due(delta: float) -> bool:
	var contact_hz := PlatformConfig.obstacle_contact_hz
	if contact_hz <= 0.0:
		return true
	_contact_accum += delta
	if _contact_accum < 1.0 / contact_hz:
		return false
	_contact_accum = 0.0
	return true


## 调试触发环不是每帧动画；状态不变时不做 queue_redraw。
func _refresh_overlay_redraw() -> void:
	var signature := ""
	if trigger_enabled and not _triggered:
		signature = "trigger"
	elif interval_enabled and not _interval_phase_idle:
		signature = "interval"
	if signature == _overlay_signature:
		return
	_overlay_signature = signature
	queue_redraw()


func _update_interval_phase(delta: float) -> void:
	if not interval_enabled:
		_interval_phase_idle = true
		_interval_phase_time = 0.0
		return
	if _interval_phase_time <= 0.0:
		_interval_phase_time = _animation_duration(idle_animation if _interval_phase_idle else off_animation)
		if _interval_phase_time <= 0.0:
			return
	_interval_phase_time -= delta
	if _interval_phase_time <= 0.0:
		_interval_phase_idle = not _interval_phase_idle
		_interval_phase_time = _animation_duration(idle_animation if _interval_phase_idle else off_animation)


func _animation_duration(animation_name: String) -> float:
	var animated := visual as AnimatedSprite2D
	if animated == null or animated.sprite_frames == null:
		return 0.0
	if not animated.sprite_frames.has_animation(animation_name):
		return 0.0
	var total := 0.0
	for frame_index in animated.sprite_frames.get_frame_count(animation_name):
		total += animated.sprite_frames.get_frame_duration(animation_name, frame_index)
	var animation_speed := maxf(0.001, animated.sprite_frames.get_animation_speed(animation_name))
	return total / (animation_speed * maxf(0.001, animated.speed_scale))


func _update_trigger_mine(delta: float) -> void:
	match _mine_state:
		MineState.OFF:
			_triggered = false
			if _has_coaster_in_range():
				_mine_state = MineState.WAITING
				_mine_timer = trigger_mine_delay
		MineState.WAITING:
			_mine_timer -= delta
			if _mine_timer <= 0.0:
				_mine_state = MineState.IDLE
				_mine_timer = _animation_duration(idle_animation)
		MineState.IDLE:
			_mine_timer -= delta
			if _mine_timer <= 0.0:
				_mine_state = MineState.COOLDOWN
				_mine_timer = maxf(0.0, trigger_mine_cooldown)
		MineState.COOLDOWN:
			_mine_timer -= delta
			if _mine_timer <= 0.0:
				_mine_state = MineState.OFF
	var active := _mine_state == MineState.IDLE
	_triggered = active
	if active != _last_collision_active:
		_last_collision_active = active
		set_deferred("monitoring", active)
	if active and _contact_check_due(delta):
		_check_contact_damage()


func _process_emitter(delta: float) -> void:
	_emitter_timer -= delta
	if _emitter_timer > 0.0:
		return
	_emitter_timer = _next_emitter_interval()
	_emit_obstacle()


func _next_emitter_interval() -> float:
	var low := minf(emitter_interval_min, emitter_interval_max)
	var high := maxf(emitter_interval_min, emitter_interval_max)
	return randf_range(maxf(0.05, low), maxf(0.05, high))


## 从对象池复用发射物；只有池空时才复制节点，避免频繁创建/销毁。
func _emit_obstacle() -> void:
	var clone: Obstacle = null
	while not _emitter_pool.is_empty():
		var candidate: Obstacle = _emitter_pool.pop_back() as Obstacle
		if is_instance_valid(candidate):
			clone = candidate
			break
	if clone == null:
		if _emitter_template == null:
			# 第一次复制时发射器还没有任何发射物子节点，作为干净模板保存。
			_emitter_template = duplicate() as Obstacle
			_emitter_template.name = "EmitterTemplate"
		clone = _emitter_template.duplicate() as Obstacle
		if clone == null:
			return
		clone.name = "EmittedObstacle_%d" % _emitter_spawned
		_emitter_spawned += 1
		clone.top_level = true
		add_child(clone)
	clone._is_emitted = true
	clone._emitted_off_playing = false
	clone._emitted_off_timer = 0.0
	clone._emitter_owner = self
	clone.emitter_enabled = false
	clone.trigger_enabled = false
	clone.trigger_two_ends = false
	clone.start_wait_time = start_wait_time
	clone.end_wait_time = end_wait_time
	clone._base_position = _base_position
	clone._source_end_offset = _source_end_offset
	clone._start_pos = _start_pos
	clone._end_pos = _end_pos
	clone._path_length = _path_length
	clone._perp_dir = _perp_dir
	clone._circle_center = _circle_center
	clone._circle_radius = _circle_radius
	clone._progress = 0.0
	clone._moving_to_end = true
	clone._current_speed = 0.0
	clone._wait_timer = 0.0
	clone._is_waiting = false
	clone._triggered = false
	clone._trigger_cycle_active = false
	clone._returned_to_start = false
	clone._two_end_at_end = false
	clone._two_end_armed = false
	clone._initialized = true
	clone._rotation_offset = 0.0
	clone.visible = true
	clone.set_process(true)
	clone.monitoring = true
	clone.set_deferred("monitoring", true)
	clone.global_position = clone._start_pos
	clone.global_scale = scale
	clone.global_rotation = rotation
	clone._apply_rotation_offset()
	clone._update_position()
	clone.add_to_group("obstacles")
	if not clone.touched.is_connected(_on_emitted_touched):
		clone.touched.connect(_on_emitted_touched)
	_emitter_alive.append(clone)


func _on_emitted_touched(_obstacle: Obstacle, coaster: CoasterController) -> void:
	# 发射物把伤害转发给发射器，复用关卡已连接的 touched 信号。
	touched.emit(self, coaster)


func _recycle_emitted() -> void:
	_is_emitted = false
	_emitted_off_playing = false
	_emitted_off_timer = 0.0
	_is_waiting = false
	_progress = 0.0
	visible = false
	set_process(false)
	monitoring = false
	set_deferred("monitoring", false)
	remove_from_group("obstacles")
	if is_instance_valid(_emitter_owner):
		_emitter_owner._emitter_alive.erase(self)
		_emitter_owner._emitter_pool.append(self)
		global_position = _emitter_owner._start_pos
	else:
		queue_free()


func _exit_tree() -> void:
	if _emitter_template != null and is_instance_valid(_emitter_template):
		_emitter_template.free()


func _start_trigger_cycle() -> void:
	_trigger_cycle_active = true
	_triggered = true
	_returned_to_start = false
	_progress = 0.0
	_moving_to_end = true
	_is_waiting = false
	_wait_timer = 0.0
	_current_speed = 0.0
	global_position = _start_pos
	_last_collision_active = true
	set_deferred("monitoring", true)


func _finish_trigger_cycle() -> void:
	_trigger_cycle_active = false
	_triggered = false
	_trigger_cooldown_left = trigger_cooldown
	_returned_to_start = false
	_progress = 0.0
	_moving_to_end = true
	_is_waiting = false
	_wait_timer = 0.0
	_current_speed = 0.0
	global_position = _start_pos
	_last_collision_active = false
	set_deferred("monitoring", false)


## 两端触发：从当前端出发到另一端，停下并重新武装检测。
func _start_two_end_cycle() -> void:
	_trigger_cycle_active = true
	_triggered = true
	_returned_to_start = false
	_is_waiting = false
	_wait_timer = 0.0
	_current_speed = 0.0
	_moving_to_end = not _two_end_at_end
	_progress = 0.0 if _moving_to_end else 1.0
	global_position = _start_pos if _moving_to_end else _end_pos
	_last_collision_active = true
	set_deferred("monitoring", true)


func _finish_two_end_move(at_end: bool) -> void:
	_two_end_at_end = at_end
	_progress = 1.0 if at_end else 0.0
	_moving_to_end = at_end
	global_position = _end_pos if at_end else _start_pos
	_is_waiting = true
	_wait_timer = 0.0
	_current_speed = 0.0
	_trigger_cycle_active = false
	_triggered = false
	_trigger_cooldown_left = trigger_cooldown
	_two_end_armed = false
	_last_collision_active = false
	set_deferred("monitoring", false)


func _on_player_detector_body_entered(body: Node2D) -> void:
	if emitter_enabled or trigger_mine or not trigger_enabled or _trigger_cycle_active or _trigger_cooldown_left > 0.0:
		return
	if trigger_two_ends:
		# 两端触发由 _process 武装/边沿检测，避免进入范围后立刻来回切换。
		return
	if body is CoasterController and movement_mode != MODE_STATIC:
		_start_trigger_cycle()


## 持续接触：每隔无敌时间结束后再次造成伤害，而不是只在 body_entered 时结算一次。
func _check_contact_damage() -> void:
	if not monitoring:
		return
	if interval_enabled and not _interval_phase_idle:
		return
	if trigger_enabled and not _triggered:
		return
	if trigger_mine and _mine_state != MineState.IDLE:
		return
	for body in get_overlapping_bodies():
		var coaster := body as CoasterController
		if coaster != null and not coaster.is_invulnerable():
			touched.emit(self, coaster)
			return


func _has_detector() -> bool:
	return get_node_or_null("PlayerDetector") is Area2D


func _detected_coaster() -> CoasterController:
	var detector := get_node_or_null("PlayerDetector") as Area2D
	if detector == null:
		return null
	for body in detector.get_overlapping_bodies():
		if body is CoasterController:
			return body as CoasterController
	return null


func _has_coaster_in_range() -> bool:
	return _detected_coaster() != null


func _setup_animations() -> void:
	var animated := visual as AnimatedSprite2D
	if animated == null or animated.sprite_frames == null:
		return
	var frames := animated.sprite_frames
	if not frames.has_animation("default"):
		return
	var source_texture := frames.get_frame_texture("default", 0)
	for animation_name in [idle_animation, move_animation, off_animation]:
		if animation_name.is_empty():
			continue
		if not frames.has_animation(animation_name):
			frames.add_animation(animation_name)
			if source_texture != null:
				frames.add_frame(animation_name, source_texture)
		if frames.get_frame_count(animation_name) > 0:
			frames.set_animation_loop(animation_name, true)


func _update_animation_state() -> void:
	if _emitted_off_playing:
		return
	var animated := visual as AnimatedSprite2D
	if animated == null or animated.sprite_frames == null:
		return
	var target := idle_animation
	if trigger_mine:
		target = idle_animation if _mine_state == MineState.IDLE else off_animation
	elif interval_enabled:
		target = idle_animation if _interval_phase_idle else off_animation
	else:
		# 触发器障碍在“未触发/等待/已到端点”时必须是 idle；
		# 只有真正处于触发往返的移动段才播放 move。
		var moving := movement_mode != MODE_STATIC and not _is_waiting
		if trigger_enabled:
			moving = _trigger_cycle_active and not _is_waiting
		if emitter_enabled:
			moving = false
		if moving:
			target = move_animation
	if target.is_empty() or not animated.sprite_frames.has_animation(target):
		return
	if animated.animation != StringName(target) or not animated.is_playing():
		animated.play(target)


func _active_move_speed() -> float:
	return maxf(0.0, move_speed_out if _moving_to_end else move_speed_back)


func _position_at_progress(progress: float, moving_to_end: bool = true) -> Vector2:
	match movement_mode:
		MODE_LINEAR:
			return _start_pos.lerp(_end_pos, progress)
		MODE_WAVE:
			var linear_pos := _start_pos.lerp(_end_pos, progress)
			var t := progress if moving_to_end else (1.0 - progress)
			var phase := 0.0 if wave_start_up else PI
			var sign_mult := 1.0
			if wave_reverse_on_return and not moving_to_end:
				sign_mult = -1.0
			var osc := sin(t * TAU * wave_period + phase) * sign_mult
			return linear_pos + _perp_dir * wave_amplitude * osc
		MODE_CIRCULAR:
			var end_dir := end_offset.normalized()
			if end_dir.length() < 0.001:
				return _start_pos
			var perp := Vector2(-end_dir.y, end_dir.x)
			var dir_sign := 1.0 if circular_clockwise else -1.0
			var angle := dir_sign * PI * (1.0 - progress) if moving_to_end else -dir_sign * PI * (1.0 - progress)
			return _circle_center + _circle_radius * (end_dir * cos(angle) + perp * sin(angle))
		_:
			return _start_pos


## 工坊预览使用：返回相对放置点的完整运动路径。
func get_preview_path(samples: int = 48) -> PackedVector2Array:
	var points := PackedVector2Array()
	if movement_mode == MODE_STATIC or _path_length <= 0.0:
		return points
	for index in samples + 1:
		var progress := float(index) / float(samples)
		points.append(_position_at_progress(progress, true) - _start_pos)
	if not emitter_enabled:
		for index in range(samples - 1, 0, -1):
			var progress := float(index) / float(samples)
			points.append(_position_at_progress(progress, false) - _start_pos)
	return points


func _current_wait_time() -> float:
	return end_wait_time if _moving_to_end else start_wait_time


func _handle_movement(delta: float) -> void:
	var active_speed := _active_move_speed()
	if _path_length <= 0.0 or active_speed <= 0.0:
		return
	if not is_finite(_progress): _progress = 0.0
	if not is_finite(_current_speed): _current_speed = 0.0
	if not is_finite(_wait_timer): _wait_timer = 0.0
	if _is_waiting:
		_wait_timer -= delta
		if _wait_timer <= 0.0:
			if _is_emitted and _moving_to_end:
				if not _emitted_off_playing:
					_emitted_off_playing = true
					_emitted_off_timer = maxf(0.15, _animation_duration(off_animation))
					var animated := visual as AnimatedSprite2D
					if animated != null and animated.sprite_frames != null and animated.sprite_frames.has_animation(off_animation):
						animated.play(off_animation)
				_emitted_off_timer -= delta
				if _emitted_off_timer <= 0.0:
					_recycle_emitted()
				return
			_is_waiting = false
			_moving_to_end = not _moving_to_end
			_current_speed = 0.0
		return
	var dist_done: float
	var dist_left: float
	if _moving_to_end:
		dist_done = _progress * _path_length
		dist_left = (1.0 - _progress) * _path_length
	else:
		dist_done = (1.0 - _progress) * _path_length
		dist_left = _progress * _path_length
	var half_accel := acceleration_time * active_speed / 2.0
	var half_decel := deceleration_time * active_speed / 2.0
	var accel := active_speed / acceleration_time if acceleration_time > 0.0 else active_speed
	var decel := active_speed / deceleration_time if deceleration_time > 0.0 else active_speed
	if dist_done < half_accel:
		_current_speed = minf(_current_speed + accel * delta, active_speed)
	elif dist_left < half_decel:
		_current_speed = maxf(_current_speed - decel * delta, 0.0)
	else:
		_current_speed = active_speed
	if _current_speed <= 0.0 and dist_left < half_decel * 0.5:
		if trigger_enabled and trigger_two_ends:
			_finish_two_end_move(_moving_to_end)
			return
		_progress = 1.0 if _moving_to_end else 0.0
		global_position = _end_pos if _moving_to_end else _start_pos
		_is_waiting = true
		_wait_timer = _current_wait_time()
		if trigger_enabled and not _moving_to_end:
			_returned_to_start = true
		return
	var step := (_current_speed * delta) / _path_length
	if not is_finite(step): step = 0.0
	_progress += step if _moving_to_end else -step
	# 到达判定必须跟着当前方向走：返回途中即使仍停在终点附近，
	# 也不能再次触发“到达终点”，否则会反复重置等待、永远回不到起点。
	if _moving_to_end and _progress >= 1.0 - 0.001:
		if trigger_enabled and trigger_two_ends:
			_finish_two_end_move(true)
			return
		_progress = 1.0
		global_position = _end_pos
		_is_waiting = true
		_wait_timer = _current_wait_time()
		return
	if not _moving_to_end and _progress <= 0.001:
		if trigger_enabled and trigger_two_ends:
			_finish_two_end_move(false)
			return
		_progress = 0.0
		global_position = _start_pos
		_is_waiting = true
		_wait_timer = _current_wait_time()
		if trigger_enabled:
			_returned_to_start = true
		return
	_progress = clampf(_progress, 0.0, 1.0)
	_update_position()


func _update_position() -> void:
	global_position = _position_at_progress(_progress, _moving_to_end)


func _on_body_entered(body: Node2D) -> void:
	if not body is CoasterController:
		return
	if trigger_enabled and not _triggered:
		return
	if interval_enabled and not _interval_phase_idle:
		return
	if trigger_mine and _mine_state != MineState.IDLE:
		return
	touched.emit(self, body as CoasterController)


func _draw() -> void:
	var has_visual := false
	if visual is AnimatedSprite2D:
		has_visual = (visual as AnimatedSprite2D).sprite_frames != null
	elif visual is Sprite2D:
		has_visual = (visual as Sprite2D).texture != null
	if not has_visual:
		if not _visual_error_reported:
			_visual_error_reported = true
			push_error("Obstacle '%s' 缺少 Visual 纹理" % name)
		return
	if trigger_enabled and not _triggered:
		draw_arc(Vector2(0, -2), 22.0, 0, TAU, 24, Color(0.85, 0.9, 0.95, 0.35), 1.5, true)
	if interval_enabled and not _interval_phase_idle:
		draw_arc(Vector2(0, -2), 19.0, 0, TAU, 24, Color(0.95, 0.75, 0.2, 0.55), 2.0, true)

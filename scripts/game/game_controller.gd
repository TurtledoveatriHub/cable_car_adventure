class_name GameController
extends Node2D
## 单轨关卡运行时总控：生成轨道/障碍/乘客/终点/吊厢，管理计时、乘客、失败与结算。
## 玩法层只调用服务；关卡 JSON 读取由 LevelCatalog 完成。

signal run_completed(result: Dictionary)

enum RunPhase {
	COUNTDOWN,
	RUNNING,
	ENDING,
	DONE,
}

const OBSTACLE_SCENE := preload("res://scenes/game/obstacles/bird.tscn")
const FINISH_SCENE := preload("res://scenes/game/finish_gate.tscn")
const START_SCENE := preload("res://scenes/game/start_gate.tscn")

const FAIL_PASSENGERS := "passengers"
const FAIL_TIME := "time"
const FAIL_VIEW := "view"
const FAIL_VIEW_MARGIN := 96.0
## 防止“相机跟随两人中点”时两人一起下坠、永远不出视野。
const FAIL_HARD_DROP := 4000.0
## 只让缆车 1200px 内的障碍运行脚本/碰撞轮询；远处障碍彻底休眠，进入范围后恢复。
## 热气球和陨石需要在整条长轨迹上保持运动/发射，不能按距离休眠（见 Obstacle.is_cull_exempt）。
const OBSTACLE_ACTIVE_RANGE := 1200.0
## 检查频率略高于视觉刷新；既减少远距离障碍的无效轮询，又避免高速进入范围时明显迟滞。
const OBSTACLE_ACTIVITY_INTERVAL := 0.2

@export_group("节奏")
## 开局倒计时
@export var countdown_seconds: float = 3.0
## 终点/失败后进入结算的延迟
@export var finish_delay_seconds: float = 1.6
## 碰撞后的短暂无敌时间
@export var hit_invulnerability_seconds: float = 0.9
## 结束后是否自动进入结算（测试可关闭）
@export var auto_route_to_result: bool = true
## 双人分屏时由父控制器统一保存
@export var save_results: bool = true
## p1 / p2 / solo
@export var input_prefix: String = "solo"
## 分屏时隐藏每块屏幕内的独立 HUD
@export var hud_enabled: bool = true
## 分屏时由父控制器统一处理 Esc
@export var handle_pause_input: bool = true
## 玩家显示名称
@export var player_label: String = "玩家 1"

@export_group("镜头")
## 镜头相对吊厢中心的偏移
@export var camera_offset: Vector2 = Vector2.ZERO
## 镜头跟随平滑度
@export var camera_smoothing_speed: float = 8.0
## 吊厢在屏幕中心的死区半径
@export var camera_deadzone: Vector2 = Vector2(0.0, 0.0)
## 是否用关卡 camera_bounds 限制相机；双人分屏关闭后相机始终跟随本屏缆车。
@export var camera_limits_enabled: bool = true
## 相机可活动范围相对关卡 camera_bounds 的倍数；分屏使用 2 倍，禁止完全开放。
@export var camera_limit_scale: float = 1.0

@export_group("反馈")
## 碰撞震动强度
@export var camera_shake_strength: float = 9.0
## 碰撞震动时长
@export var camera_shake_seconds: float = 0.32

@onready var backdrop: SkyBackdrop = $BackdropLayer/SkyBackdrop
@onready var track_renderer: TrackRenderer = $World/Track
@onready var obstacles_root: Node2D = $World/Obstacles
@onready var gates_root: Node2D = $World/Gates
@onready var coasters_root: Node2D = $World/Coasters
@onready var fx_root: Node2D = $World/Fx
@onready var camera: Camera2D = $Camera2D
@onready var hud: GameHUD = $HudLayer/GameHUD
@onready var hud_layer: CanvasLayer = $HudLayer

var level: LevelData
var coaster: CoasterController
var passengers: int = 3
var time_seconds: float = 0.0
var cart_profile: CartProfile
var external_camera_control: bool = false
var _starting_passengers: int = 3
var _max_passengers: int = 6

var _phase: RunPhase = RunPhase.COUNTDOWN
var _countdown_left: float = 0.0
var _countdown_display: int = -1
var _ending_left: float = 0.0
var _hud_accum: float = 0.0
var _paused: bool = false
var _shake_left: float = 0.0
var _last_s: float = 0.0
var _run_finished: bool = false
var _run_failed: bool = false
var _fail_reason: String = ""
var _fail_text: String = ""
var _result_sent: bool = false
var _start_gate: StartGate
var _finish_gate: FinishGate
var _difficulty_info: Dictionary = {}
var _telemetry_run_id: String = ""
var _telemetry_finished: bool = false
var _break_jobs: Array[Dictionary] = []
var last_result: Dictionary = {}
var _camera_bounds: Rect2 = Rect2()
var _meteor_tint_rect: ColorRect
var _meteor_tint_alpha: float = 0.0
var _meteor_shake_offset: Vector2 = Vector2.ZERO
var _meteor_target_shake: float = 0.0
var _meteor_target_tint: float = 0.0
var _meteor_target_color: Color = Color(1.0, 0.52, 0.16)
var _meteor_target_speed: float = 16.0
var _meteor_report_msec: int = -100000
var _meteor_report_frame: int = -1
var _obstacle_activity_accum: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 根节点保持 ALWAYS 以便暂停菜单可用；世界与背景单独设为 PAUSABLE。
	$World.process_mode = Node.PROCESS_MODE_PAUSABLE
	$BackdropLayer.process_mode = Node.PROCESS_MODE_PAUSABLE
	# Fx 层只承载 _spawn_floating_text 的漂浮文字：位置由 IDLE 补间在渲染帧写入，
	# 参与物理插值会得到错误的插值历史并抖动，故整层关闭（子 Label 默认 INHERIT 一并覆盖）。
	fx_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var tint_layer := CanvasLayer.new()
	tint_layer.layer = 5
	add_child(tint_layer)
	_meteor_tint_rect = ColorRect.new()
	_meteor_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meteor_tint_rect.color = Color(1.0, 0.52, 0.16, 0.0)
	_meteor_tint_rect.visible = false
	tint_layer.add_child(_meteor_tint_rect)
	_meteor_tint_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not hud_enabled:
		hud_layer.visible = false
	get_tree().paused = false
	var level_id := GameSession.selected_level_id
	if not GameSession.authored_level_data.is_empty():
		level = LevelData.from_dictionary(GameSession.authored_level_data)
	else:
		if level_id.is_empty() or LevelCatalog.get_summary(level_id).is_empty():
			var summaries := LevelCatalog.get_summaries()
			if not summaries.is_empty():
				level_id = str(summaries[0].get("id", ""))
				GameSession.selected_level_id = level_id
		level = LevelCatalog.get_level(level_id)
	if level == null:
		_show_fatal_error("关卡加载失败\n%s" % LevelCatalog.last_error)
		return
	_setup_level()
	_connect_hud()
	_setup_touch_controls()
	_update_hud()
	_start_countdown()


func _setup_touch_controls() -> void:
	if input_prefix != "solo" or not TouchControls.is_touch_device():
		return
	var controls := TouchControls.new()
	hud_layer.add_child(controls)
	hud_layer.move_child(controls, 0)
	controls.configure("solo")


func _process(delta: float) -> void:
	if get_tree().paused or _paused or _result_sent or level == null:
		return
	_update_meteor_feedback(delta)
	match _phase:
		RunPhase.COUNTDOWN:
			_process_countdown(delta)
		RunPhase.RUNNING:
			_process_running(delta)
		RunPhase.ENDING:
			_process_ending(delta)
		RunPhase.DONE:
			pass
	_update_obstacle_activity(delta)


## 相机跟随与抖动必须在物理帧内写入变换。
## 项目开启了 physics_interpolation，缆车位置在 _physics_process 写入并被引擎插值；
## 若相机仍在渲染帧跟随，读到的是未插值坐标，两者插值因子不同 → 缆车会相对画面“游动”。
## 放在物理帧后，相机与缆车共用同一插值因子，帧率抖动时相对关系保持稳定。
func _physics_process(delta: float) -> void:
	if get_tree().paused or _paused or _result_sent or level == null:
		return
	_update_shake(delta)
	_update_camera(delta)
	backdrop.camera_x = camera.global_position.x


func _unhandled_input(event: InputEvent) -> void:
	if not handle_pause_input:
		return
	if event.is_action_pressed("pause") and _phase in [RunPhase.COUNTDOWN, RunPhase.RUNNING]:
		_set_paused(not _paused)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("restart_run") and _phase in [RunPhase.COUNTDOWN, RunPhase.RUNNING]:
		AudioDirector.play_click()
		_restart_run()
		get_viewport().set_input_as_handled()
		return


func _setup_level() -> void:
	backdrop.game_mode = true
	backdrop.apply_theme(level.theme, level.background_id)
	AudioDirector.set_background_music(level.background_id)
	level.track.reset_breaks()
	track_renderer.configure(level, false)

	var bounds := level.camera_bounds
	if bounds.size.x < 64.0 or bounds.size.y < 64.0:
		bounds = level.track.get_bounds(120.0)
	_camera_bounds = bounds
	camera.zoom = Vector2(0.9, 0.9)
	_apply_camera_limits()
	if not get_viewport().size_changed.is_connected(_apply_camera_limits):
		get_viewport().size_changed.connect(_apply_camera_limits)
	call_deferred("_apply_camera_limits")

	_difficulty_info = AdaptiveDifficultyService.get_modifiers(level.id)
	for index in level.obstacles.size():
		var raw_data: Dictionary = level.obstacles[index]
		var prefab_id := str(raw_data.get("prefab", ""))
		var prefab_scene := ObstacleDefinitionDB.get_scene(prefab_id) if not prefab_id.is_empty() else null
		var data: Dictionary = raw_data
		var obstacle := (prefab_scene.instantiate() if prefab_scene != null else OBSTACLE_SCENE.instantiate()) as Obstacle
		obstacles_root.add_child(obstacle)
		obstacle.configure(data, level.track, float(_difficulty_info.get("obstacle_speed_scale", 1.0)))
		obstacle.touched.connect(_on_obstacle_touched)


	_start_gate = START_SCENE.instantiate() as StartGate
	gates_root.add_child(_start_gate)
	_start_gate.configure(level)
	_finish_gate = FINISH_SCENE.instantiate() as FinishGate
	gates_root.add_child(_finish_gate)
	_finish_gate.configure(level)
	_finish_gate.crossed.connect(_on_finish_gate_crossed)

	var cart_slot := "p2" if input_prefix == "p2" else "p1"
	var cart_id := str(SaveManager.get_setting("cart_" + cart_slot, "dove"))
	cart_profile = CartCatalog.get_profile(cart_id)
	if cart_profile == null or not CartCatalog.is_unlocked(cart_profile):
		cart_id = "dove"
		cart_profile = CartCatalog.get_profile("dove")
	var cart_scene := CartCatalog.get_scene(cart_id)
	if cart_scene == null:
		cart_scene = CartCatalog.get_scene("dove")
	coaster = cart_scene.instantiate() as CoasterController
	coasters_root.add_child(coaster)
	coaster.configure(level, input_prefix)
	var cart_start := _start_gate.get_cart_start_global_position()
	coaster.current_s = level.track.nearest_s(cart_start)
	coaster._update_pose()
	coaster.set_boarding_global_position(_start_gate.get_passenger_global_position())
	coaster.set_alight_global_position(_finish_gate.get_passenger_global_position())
	var engine_scale := float(_difficulty_info.get("engine_scale", 1.0))
	coaster.engine_acceleration *= engine_scale
	coaster.reverse_acceleration *= engine_scale
	_starting_passengers = coaster.starting_passengers
	_max_passengers = coaster.max_passengers
	passengers = _starting_passengers
	coaster.set_passenger_count(passengers)
	_last_s = coaster.current_s
	_update_obstacle_activity(0.0, true)
	_break_jobs.clear()
	for index in level.track.pieces.size():
		var break_after := float(level.track.pieces[index].get("break_after", 0.0))
		if break_after > 0.0:
			var range_data := level.track.get_piece_range(index)
			_break_jobs.append({
				"index": index,
				"delay": break_after,
				"left": break_after,
				"piece_start": float(range_data.get("start_s", 0.0)),
				"piece_end": float(range_data.get("end_s", 0.0)),
				"started": false,
				"triggered": false,
			})

	var play_mode := GameSession.MODE_DUO if input_prefix != "solo" else GameSession.MODE_SOLO
	hud.setup(level, play_mode, _starting_passengers, _max_passengers)
	TelemetryService.begin_run(level, play_mode, _difficulty_info, {
		"starting_passengers": _starting_passengers,
		"cart_id": cart_profile.id if cart_profile != null else "dove",
		"cart_name": cart_profile.display_name if cart_profile != null else "鸽子",
	})
	_telemetry_run_id = TelemetryService.get_current_run_id()
	_update_camera(0.0)
	camera.global_position = _get_camera_target()
	# 瞬移类赋值必须重置插值历史，否则会从旧位置插值出一段滑行。
	camera.reset_physics_interpolation()


## Camera2D 的限制是“相机中心可达范围”。按实际视口半宽/半高扩展，
## 使相机中心能到达关卡边界：分屏子视口更窄时也不会比单人更早被卡住。
func _apply_camera_limits() -> void:
	if not camera_limits_enabled or external_camera_control or level == null:
		return
	var bounds := _camera_bounds
	if bounds.size.x < 64.0 or bounds.size.y < 64.0:
		return
	var view_size := get_viewport_rect().size
	if view_size.x < 1.0 or view_size.y < 1.0:
		return
	var view_half := view_size * 0.5 / camera.zoom
	var center := bounds.position + bounds.size * 0.5
	var scaled_size := bounds.size * maxf(0.1, camera_limit_scale)
	var scaled := Rect2(center - scaled_size * 0.5, scaled_size)
	camera.limit_left = int(floor(scaled.position.x - view_half.x))
	camera.limit_top = int(floor(scaled.position.y - view_half.y))
	camera.limit_right = int(ceil(scaled.position.x + scaled.size.x + view_half.x))
	camera.limit_bottom = int(ceil(scaled.position.y + scaled.size.y + view_half.y))
	camera.limit_smoothed = true
	camera.position_smoothing_enabled = false


## 长关卡里 90% 的障碍都在屏幕外；停掉它们的脚本轮询可显著降低微信端 CPU。
## 以缆车为中心 1200px 判定：只认空间距离，避免折返/环圈关卡因 s 相近而误判。
## 正在触发/发射的障碍即使暂时超出范围也继续运行，避免状态机半途冻结。
func _update_obstacle_activity(delta: float, force: bool = false) -> void:
	if coaster == null:
		return
	_obstacle_activity_accum += delta
	if not force and _obstacle_activity_accum < OBSTACLE_ACTIVITY_INTERVAL:
		return
	_obstacle_activity_accum = 0.0
	var cart_position := coaster.get_body_center()
	var range_squared := OBSTACLE_ACTIVE_RANGE * OBSTACLE_ACTIVE_RANGE
	for child in obstacles_root.get_children():
		var obstacle := child as Obstacle
		if obstacle == null or not is_instance_valid(obstacle):
			continue
		# 热气球/陨石的发射物拥有很长轨迹；发射器必须持续运转，否则会冻结在半空。
		var should_process := obstacle.is_cull_exempt() or obstacle.is_gameplay_active()
		if not should_process:
			should_process = obstacle.global_position.distance_squared_to(cart_position) <= range_squared
		if obstacle.is_processing() != should_process:
			obstacle.set_offscreen_paused(not should_process)


func _connect_hud() -> void:
	hud.pause_requested.connect(_on_hud_pause_requested)
	hud.resume_requested.connect(_on_hud_resume_requested)
	hud.restart_requested.connect(_on_hud_restart_requested)
	hud.quit_requested.connect(_on_hud_quit_requested)


func _start_countdown() -> void:
	_phase = RunPhase.COUNTDOWN
	_countdown_left = maxf(0.6, countdown_seconds)
	_countdown_display = -1
	hud.countdown_layer.visible = true
	_update_hud()


func _process_countdown(delta: float) -> void:
	_countdown_left -= delta
	var number := int(ceil(_countdown_left))
	if number > 0 and number != _countdown_display and number <= 3:
		_countdown_display = number
		hud.show_countdown(str(number), "→ 前进　← 刹车 / 后退")
		AudioDirector.play_countdown(false)
	if _countdown_left <= 0.0:
		_begin_running()


func _begin_running() -> void:
	if _phase == RunPhase.RUNNING:
		return
	_phase = RunPhase.RUNNING
	coaster.set_active(true)
	coaster.play_boarding_animation()
	hud.show_countdown("GO!", "沿轨道出发！")
	AudioDirector.play_countdown(true)
	_countdown_display = -1
	var timer := get_tree().create_timer(0.75, true, false, true)
	timer.timeout.connect(hud.hide_countdown)
	timer.timeout.connect(_fade_hint)


func _fade_hint() -> void:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(3.0)


func _process_running(delta: float) -> void:
	time_seconds += delta
	_update_break_jobs(delta)
	_check_finish_crossing()
	if _run_finished:
		_update_hud_throttled(delta)
		return
	if level != null and level.time_limit_seconds > 0.0 and time_seconds >= level.time_limit_seconds:
		_fail_run(FAIL_TIME)
		return
	if coaster != null and coaster.is_jumping() and _is_outside_camera_view(coaster.get_body_center()):
		_fail_run(FAIL_VIEW)
		return
	_update_hud_throttled(delta)
	if not _run_finished and not _run_failed and passengers <= 0:
		_fail_run(FAIL_PASSENGERS)

func _process_ending(delta: float) -> void:
	_ending_left -= delta
	_update_hud_throttled(delta)
	if _ending_left <= 0.0 and not _result_sent:
		_result_sent = true
		_go_to_result()


## 缆车是否已经真正离开相机可见范围（不是离开“相机中心可活动范围”）。
## 相机中心被关卡边界夹住时，缆车仍可能在画面内，必须等它离开画面才判失败。
func _is_outside_camera_view(world_position: Vector2) -> bool:
	if level == null or camera == null:
		return false
	var view_size := get_viewport_rect().size
	if view_size.x < 1.0 or view_size.y < 1.0:
		return false
	var half := view_size * 0.5 / camera.zoom
	var center := camera.get_screen_center_position()
	if center == Vector2.ZERO:
		center = camera.global_position
	var visible_rect := Rect2(center - half, half * 2.0).grow(FAIL_VIEW_MARGIN)
	if not visible_rect.has_point(world_position):
		return true
	# 共享相机跟随两人中点，两人一起下坠时可能永远不离开画面；保留一个很远的硬下限。
	if level.camera_bounds.size.y > 1.0 and world_position.y > level.camera_bounds.position.y + level.camera_bounds.size.y + FAIL_HARD_DROP:
		return true
	return false


func _check_finish_crossing() -> void:
	if coaster == null or _run_finished or _run_failed:
		return
	var current := coaster.current_s
	if coaster.is_jumping():
		_last_s = current
		return
	var finish := level.finish_s
	if absf(current - _last_s) > 120.0:
		# 飞离/落到另一段轨道时弧长会跳变；只有已经落在终点附近才允许完成。
		_last_s = current
		var near_finish := current >= finish and current - finish <= 120.0
		if not level.is_forward_course():
			near_finish = current <= finish and finish - current <= 120.0
		if near_finish:
			_finish_run()
		return
	var crossed := false
	if level.is_forward_course():
		crossed = _last_s < finish and current >= finish
	else:
		crossed = _last_s > finish and current <= finish
	_last_s = current
	if crossed:
		_finish_run()


func _update_hud_throttled(delta: float) -> void:
	var hz := PlatformConfig.hud_update_hz
	if hz <= 0.0:
		_update_hud()
		return
	_hud_accum += delta
	if _hud_accum >= 1.0 / hz:
		_hud_accum = 0.0
		_update_hud()


func _update_hud() -> void:
	if hud == null or level == null:
		return
	var progress := _get_course_progress()
	var status := "前进中"
	if _run_finished:
		status = "抵达终点"
	elif _run_failed:
		status = str(_fail_messages(_fail_reason).get("short", "挑战失败"))
	elif _phase == RunPhase.RUNNING:
		if absf(coaster.current_speed) < 5.0:
			status = "等待出发"
		elif coaster.current_speed < 0.0:
			status = "后退中"
		else:
			status = "前进中"
	hud.update_run(0, passengers, _max_passengers, time_seconds, progress, status)


func _get_course_progress() -> float:
	if coaster == null or level == null:
		return 0.0
	var start := level.start_s
	var finish := level.finish_s
	if absf(finish - start) < 0.01:
		return 0.0
	var progress := (coaster.current_s - start) / (finish - start)
	return clampf(progress, 0.0, 1.0)


func _get_camera_target() -> Vector2:
	if coaster == null:
		return camera.global_position
	if coaster.is_jumping():
		return coaster.global_position + camera_offset
	return coaster.get_body_center() + camera_offset


func _update_camera(delta: float) -> void:
	if external_camera_control or coaster == null:
		return
	var target := _get_camera_target()
	var delta_to_target := target - camera.global_position
	var move := Vector2.ZERO
	if absf(delta_to_target.x) > camera_deadzone.x:
		move.x = delta_to_target.x - signf(delta_to_target.x) * camera_deadzone.x
	if absf(delta_to_target.y) > camera_deadzone.y:
		move.y = delta_to_target.y - signf(delta_to_target.y) * camera_deadzone.y
	var follow := clampf(1.0 - exp(-camera_smoothing_speed * delta), 0.0, 1.0)
	camera.global_position += move * follow


func _update_shake(delta: float) -> void:
	var damage_offset := Vector2.ZERO
	if _shake_left > 0.0:
		_shake_left = maxf(0.0, _shake_left - delta)
		var strength := camera_shake_strength * (_shake_left / maxf(0.01, camera_shake_seconds))
		damage_offset = Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
	camera.offset = damage_offset + _meteor_shake_offset


func report_meteor_feedback(shake_strength: float, tint_alpha: float, tint_color: Color, shake_speed: float) -> void:
	var frame := Engine.get_process_frames()
	if frame != _meteor_report_frame:
		_meteor_report_frame = frame
		_meteor_target_shake = 0.0
		_meteor_target_tint = 0.0
	_meteor_report_msec = Time.get_ticks_msec()
	_meteor_target_shake = maxf(_meteor_target_shake, shake_strength)
	_meteor_target_tint = maxf(_meteor_target_tint, tint_alpha)
	_meteor_target_color = tint_color
	_meteor_target_speed = shake_speed


func _update_meteor_feedback(delta: float) -> void:
	# 陨石特效绝大部分时间处于闲置状态；闲置时跳过时间戳读取、三角函数、lerp
	# 与全屏 ColorRect 的属性写入。早退要求四个量都已归零，因此不会漏掉收尾帧。
	if _meteor_target_shake <= 0.0 and _meteor_target_tint <= 0.0 \
			and _meteor_shake_offset == Vector2.ZERO and _meteor_tint_alpha <= 0.002 \
			and (_meteor_tint_rect == null or not _meteor_tint_rect.visible):
		return
	var now := Time.get_ticks_msec()
	if now - _meteor_report_msec > 120:
		_meteor_target_shake = 0.0
		_meteor_target_tint = 0.0
	var phase := now * 0.001 * _meteor_target_speed
	_meteor_shake_offset = Vector2(sin(phase * 1.7), cos(phase * 2.3)) * _meteor_target_shake if _meteor_target_shake > 0.0 else Vector2.ZERO
	_meteor_tint_alpha = lerpf(_meteor_tint_alpha, _meteor_target_tint, clampf(delta * 3.0, 0.0, 1.0))
	if _meteor_tint_rect != null:
		# alpha=0 时隐藏全屏 ColorRect，避免每帧一次无意义的全屏混合。
		var tint_visible := _meteor_tint_alpha > 0.002
		_meteor_tint_rect.visible = tint_visible
		if tint_visible:
			_meteor_tint_rect.color = Color(_meteor_target_color.r, _meteor_target_color.g, _meteor_target_color.b, _meteor_tint_alpha)


func _update_break_jobs(delta: float) -> void:
	if coaster == null:
		return
	for job in _break_jobs:
		if bool(job.get("triggered", false)):
			continue
		var piece_index := int(job.get("index", -1))
		if not bool(job.get("started", false)):
			# 缆车碰到该片段的任意位置就开始倒计时。
			var piece_start := float(job.get("piece_start", 0.0))
			var piece_end := float(job.get("piece_end", 0.0))
			if coaster.current_s < piece_start or coaster.current_s > piece_end:
				continue
			job["started"] = true
			job["left"] = float(job.get("delay", 0.0))
			track_renderer.set_warning(piece_index, true)
			AudioDirector.play_countdown(false)
			continue
		job["left"] = float(job.get("left", 0.0)) - delta
		if float(job["left"]) > 0.0:
			continue
		job["triggered"] = true
		track_renderer.set_warning(piece_index, false)
		level.track.break_piece(piece_index)
		track_renderer.notify_piece_broken(piece_index)
		AudioDirector.play_hit()
		if level.track.piece_index_at_s(coaster.current_s) == piece_index:
			coaster.detach_from_track()


func _on_obstacle_touched(obstacle: Obstacle, hit_coaster: CoasterController) -> void:
	if _paused or _phase != RunPhase.RUNNING or _run_finished or _run_failed:
		return
	if hit_coaster != coaster or coaster.is_invulnerable():
		return
	if coaster.consume_armor():
		coaster.begin_invulnerability(0.7)
		coaster.play_hit_flash()
		_spawn_floating_text("护甲抵消", UITheme.COLOR_CREAM, coaster.get_body_center() + Vector2(0, -90))
		AudioDirector.play_pickup()
		return
	if coaster.evade_chance > 0.0 and randf() < coaster.evade_chance:
		coaster.begin_invulnerability(0.7)
		return
	coaster.begin_invulnerability(hit_invulnerability_seconds)
	coaster.play_hit_flash()
	TelemetryService.log_event("collision", {
		"level_id": level.id,
		"obstacle_type": obstacle.obstacle_type,
		"motion_type": obstacle.get_motion_type(),
		"obstacle_s": obstacle.get_track_s(),
		"s": coaster.current_s,
		"track_progress": _get_course_progress(),
		"speed": coaster.current_speed,
		"damage": obstacle.damage,
		"passengers_before": passengers,
	})
	_apply_damage(obstacle.damage)


func _apply_damage(amount: int) -> void:
	if _run_finished or _run_failed:
		return
	passengers = maxi(0, passengers - amount)
	coaster.set_passenger_count(passengers)
	_shake_left = camera_shake_seconds
	AudioDirector.play_hit()
	_update_hud()
	if passengers <= 0:
		_fail_run()


func _on_finish_gate_crossed(_gate: FinishGate, gate_coaster: CoasterController) -> void:
	if gate_coaster != coaster or _run_finished or _run_failed:
		return
	# 终点门就是由 level.finish_s 配置出来的；门触发即完成，不再用弧长二次排除。
	_finish_run()


func _finish_run() -> void:
	if _run_finished or _run_failed:
		return
	_run_finished = true
	_phase = RunPhase.ENDING
	_ending_left = finish_delay_seconds
	coaster.lock_at_finish()
	AudioDirector.play_success()
	hud.show_toast("抵达终点！", UITheme.COLOR_YELLOW, 1.0)
	_spawn_floating_text("通关！", UITheme.COLOR_YELLOW, coaster.get_body_center() + Vector2(0, -100))


func _fail_run(reason: String = FAIL_PASSENGERS) -> void:
	if _run_failed or _run_finished:
		return
	_run_failed = true
	_fail_reason = reason
	var messages := _fail_messages(reason)
	_fail_text = str(messages.get("title", "挑战失败"))
	_phase = RunPhase.ENDING
	_ending_left = finish_delay_seconds
	coaster.play_failure()
	AudioDirector.play_fail()
	_shake_left = camera_shake_seconds * 2.0
	hud.show_toast(_fail_text, UITheme.COLOR_CORAL, 1.4)
	_spawn_floating_text(str(messages.get("short", "挑战失败")), UITheme.COLOR_CORAL, coaster.get_body_center() + Vector2(0, -100))


func _fail_messages(reason: String) -> Dictionary:
	match reason:
		FAIL_TIME:
			return {"title": "时间耗尽，挑战失败", "short": "时间耗尽", "result": "时间耗尽"}
		FAIL_VIEW:
			return {"title": "缆车坠出视野，挑战失败", "short": "坠出视野", "result": "缆车坠出视野"}
		_:
			return {"title": "乘客全部离场，挑战失败", "short": "乘客归零", "result": "乘客全部离场"}


func _go_to_result() -> void:
	var completed := _run_finished
	var stars := 0
	if completed:
		var lost := maxi(0, _starting_passengers - passengers)
		var time_ok_three := true
		var time_ok_two := true
		if level != null and level.time_limit_seconds > 0.0:
			var remaining := level.time_limit_seconds - time_seconds
			time_ok_three = remaining >= level.time_limit_seconds * 0.40
			time_ok_two = remaining >= level.time_limit_seconds * 0.20
		if lost == 0 and time_ok_three:
			stars = 3
		elif lost <= 1 and time_ok_two:
			stars = 2
		else:
			stars = 1
	if not _telemetry_finished:
		_telemetry_finished = true
		TelemetryService.end_run({
			"completed": completed,
			"passengers": passengers,
			"time_seconds": snappedf(time_seconds, 0.01),
			"stars": stars,
			"progress": _get_course_progress(),
			"run_id": _telemetry_run_id,
		})
	var save_info: Dictionary = {}
	if save_results:
		save_info = SaveManager.record_result({
			"level_id": level.id,
			"level_starting_passengers": _starting_passengers,
			"passengers": passengers,
			"time_seconds": snappedf(time_seconds, 0.01),
			"completed": completed,
			"stars": stars,
			"mode": GameSession.MODE_SOLO,
		})
		if completed:
			LeaderboardService.submit_score({
				"level_id": level.id,
				"player_name": SaveManager.get_player_name(),
				"player_id": SaveManager.profile_id,
				"passengers": passengers,
				"lost_passengers": maxi(0, _starting_passengers - passengers),
				"level_starting_passengers": _starting_passengers,
				"time_seconds": float(snappedf(time_seconds, 0.01)),
				"completed": true,
				"cart_id": cart_profile.id if cart_profile != null else "dove",
				"cart_name": cart_profile.display_name if cart_profile != null else "鸽子",
			})
	var play_mode := GameSession.MODE_DUO if input_prefix != "solo" else GameSession.MODE_SOLO
	if completed and not GameSession.community_entry_id.is_empty():
		CommunityService.submit_score(
			GameSession.community_entry_id,
			passengers,
			float(snappedf(time_seconds, 0.01)),
			true
		)
	var result := {
		"mode": play_mode,
		"community_entry_id": GameSession.community_entry_id,
		"level_id": level.id,
		"level_name": level.name,
		"level_subtitle": level.subtitle,
		"completed": completed,
		"failed": not completed,
		"players": [{
			"slot": 0,
			"name": player_label,
			"passengers": passengers,
			"lost_passengers": maxi(0, _starting_passengers - passengers),
			"time_seconds": snappedf(time_seconds, 0.01),
			"completed": completed,
			"failed": not completed,
			"fail_reason": "" if completed else _fail_reason,
			"fail_text": "" if completed else str(_fail_messages(_fail_reason).get("result", "挑战失败")),
			"stars": stars,
		}],
		"winner_slot": 0 if completed else -1,
		"save_info": save_info,
		"level_starting_passengers": _starting_passengers,
		"lost_passengers": maxi(0, _starting_passengers - passengers),
		"is_new_best": bool(save_info.get("is_new_best", false)),
		"fail_reason": "" if completed else _fail_reason,
		"fail_text": "" if completed else str(_fail_messages(_fail_reason).get("result", "挑战失败")),
		"cart_id": cart_profile.id if cart_profile != null else "dove",
		"cart_name": cart_profile.display_name if cart_profile != null else "鸽子",
		"authored": not GameSession.authored_level_data.is_empty(),
	}
	last_result = result
	_phase = RunPhase.DONE
	run_completed.emit(result)
	if auto_route_to_result:
		GameSession.complete_run(result)
	elif not GameSession.is_duo():
		GameSession.last_result = result


func _spawn_floating_text(text: String, color: Color, world_position: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.theme = UITheme.theme
	label.add_theme_font_override("font", UITheme.body_font)
	label.theme_type_variation = &"HudLabel"
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", color)
	label.position = world_position
	label.z_index = 20
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_root.add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(label, "position:y", world_position.y - 52.0, 0.85).set_trans(Tween.TRANS_SINE)
	tween.tween_property(label, "modulate:a", 0.0, 0.85).set_delay(0.22)
	tween.chain().tween_callback(label.queue_free)


func _set_paused(paused: bool) -> void:
	_paused = paused
	get_tree().paused = paused
	hud.set_paused(paused)


func _on_hud_pause_requested() -> void:
	if _phase in [RunPhase.COUNTDOWN, RunPhase.RUNNING]:
		_set_paused(true)


func _on_hud_resume_requested() -> void:
	_set_paused(false)


func _on_hud_restart_requested() -> void:
	get_tree().paused = false
	_restart_run()


func _on_hud_quit_requested() -> void:
	get_tree().paused = false
	if GameSession.test_from_editor:
		GameSession.return_to_editor()
	else:
		GameSession.return_to_level_select()


func _restart_run() -> void:
	get_tree().paused = false
	GameSession.start_level(level.id, GameSession.MODE_SOLO, GameSession.test_from_editor)


func _show_fatal_error(message: String) -> void:
	push_error("[GameController] " + message)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"PaperPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(340, 260)
	panel.custom_minimum_size = Vector2(600, 200)
	layer.add_child(panel)
	var label := Label.new()
	label.text = message + "\n\n请检查 data/levels 下的 JSON 文件。"
	label.theme_type_variation = &"HeadingLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)


# ---------- 测试 / 调试接口 ----------

func debug_skip_countdown() -> void:
	if _phase == RunPhase.COUNTDOWN:
		_countdown_left = 0.0
		_begin_running()
		hud.hide_countdown()


func debug_apply_damage(amount: int = 1) -> void:
	_apply_damage(amount)


func debug_finish_run() -> void:
	_finish_run()


func debug_set_s(s: float) -> void:
	if coaster != null:
		coaster.current_s = clampf(s, 0.0, level.track.total_length)
		coaster._update_pose()
		_last_s = coaster.current_s


func debug_get_run() -> Dictionary:
	return {
		"passengers": passengers,
		"time_seconds": time_seconds,
		"s": coaster.current_s if coaster != null else 0.0,
		"finish_s": level.finish_s if level != null else 0.0,
		"finished": _run_finished,
		"failed": _run_failed,
		"progress": _get_course_progress(),
		"phase": _phase,
	}


func get_countdown_left() -> float:
	return _countdown_left if _phase == RunPhase.COUNTDOWN else 0.0


func get_player_state() -> Dictionary:
	var status := "前进中"
	if _run_finished:
		status = "抵达终点"
	elif _run_failed:
		status = str(_fail_messages(_fail_reason).get("short", "挑战失败"))
	elif _phase == RunPhase.COUNTDOWN:
		status = "准备"
	elif coaster != null and absf(coaster.current_speed) < 5.0:
		status = "等待出发"
	elif coaster != null and coaster.current_speed < 0.0:
		status = "后退中"
	return {
		"passengers": passengers,
		"max_passengers": _max_passengers,
		"time_seconds": time_seconds,
		"progress": _get_course_progress(),
		"status": status,
		"completed": _run_finished,
		"failed": _run_failed,
		"fail_reason": _fail_reason,
		"fail_text": str(_fail_messages(_fail_reason).get("short", "")) if _run_failed else "",
		"result": last_result,
	}


func get_coaster() -> CoasterController:
	return coaster


func get_hud() -> GameHUD:
	return hud


func is_run_active() -> bool:
	return _phase == RunPhase.RUNNING

class_name DuoGameController
extends Control
## 本地双人：两个独立 SubViewport 各自运行一份单轨世界。
## 分屏时各自显示自己的世界；不分屏时在 Game1 中额外实例化完整 P2 缆车。

@onready var views: GridContainer = %Views
@onready var game1: GameController = %Game1
@onready var game2: GameController = %Game2
@onready var shared_hud: GameHUD = %SharedHUD
@onready var view1: SubViewportContainer = $Views/View1
@onready var view2: SubViewportContainer = $Views/View2
@onready var marker_overlay: DuoOffscreenMarkers = $MarkerOverlay

var _results: Array[Dictionary] = [{}, {}]
var _shared_p2_cart: CoasterController
var _split_p2_ghost: CoasterController
var _split_p1_ghost: CoasterController
var _countdown_hidden: bool = false
var _duo_hint: String = "P1 方向键 · P2 WASD"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not GameSession.is_duo():
		GameSession.set_mode(GameSession.MODE_DUO)
	var shared := GameSession.duo_split == GameSession.SPLIT_SHARED
	var side_by_side := GameSession.duo_split == GameSession.SPLIT_SIDE_BY_SIDE
	views.columns = 2 if side_by_side else 1
	view2.visible = not shared
	view1.stretch = true
	view2.stretch = true
	if side_by_side:
		# P2 固定在左半屏，P1 固定在右半屏；只交换显示位置，不改变 P1=方向键、P2=WASD 的约定。
		views.move_child(view2, 0)
		_duo_hint = "左 P2 WASD · 右 P1 方向键"
	if shared:
		game1.external_camera_control = true
		# 固定相机范围：不随两人距离缩放，超出视野只靠边缘标记。
		game1.camera.zoom = Vector2.ONE
		var wide := 100000
		game1.camera.limit_left = -wide
		game1.camera.limit_top = -wide
		game1.camera.limit_right = wide
		game1.camera.limit_bottom = wide
		marker_overlay.configure(game1.camera)
		marker_overlay.visible = true
	else:
		marker_overlay.visible = false
		# 分屏沿用 GameController 的默认相机尺寸；相机活动范围放宽到关卡边界的 1.5 倍，
		# 既不会被终点前的边界卡住，也不是完全开放。
		for game: GameController in [game1, game2]:
			game.camera_limit_scale = 1.5
			game.camera_limits_enabled = true
			game._apply_camera_limits()
	shared_hud.setup(game1.level, GameSession.MODE_DUO)
	shared_hud.set_player_cards_swapped(side_by_side)
	shared_hud.pause_requested.connect(_on_pause_requested)
	shared_hud.resume_requested.connect(_on_resume_requested)
	shared_hud.restart_requested.connect(_on_restart_requested)
	shared_hud.quit_requested.connect(_on_quit_requested)
	game1.run_completed.connect(_on_player_completed.bind(0))
	game2.run_completed.connect(_on_player_completed.bind(1))
	_make_shared_visual()
	_make_split_ghost()
	if TouchControls.is_touch_device():
		var controls := TouchControls.new()
		$HudLayer.add_child(controls)
		$HudLayer.move_child(controls, 0)
		controls.configure("duo")
	shared_hud.show_countdown("3", "双人分屏 · " + _duo_hint)
	set_process_unhandled_input(true)


func _process(_delta: float) -> void:
	if get_tree().paused:
		return
	_update_player_hud(0, game1)
	_update_player_hud(1, game2)
	_update_shared_visual()
	_update_split_ghost()
	if not _countdown_hidden:
		var left := maxf(game1.get_countdown_left(), game2.get_countdown_left())
		if left > 0.0:
			shared_hud.show_countdown(str(maxi(1, int(ceil(left)))), _duo_hint)
		else:
			_countdown_hidden = true
			shared_hud.show_countdown("GO!", "冲过终点！")
			var timer := get_tree().create_timer(0.75, true, false, true)
			timer.timeout.connect(shared_hud.hide_countdown)


func _physics_process(_delta: float) -> void:
	# 共享相机必须与缆车同处物理帧：缆车位置在 _physics_process 写入且被物理插值平滑，
	# 相机若留在渲染帧会读到未插值坐标，两者插值因子不同 -> 缆车相对画面"游动"。
	if get_tree().paused:
		return
	if GameSession.duo_split == GameSession.SPLIT_SHARED:
		_update_shared_camera()
		_update_offscreen_markers()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if get_tree().paused:
			_on_resume_requested()
		else:
			_on_pause_requested()
		get_viewport().set_input_as_handled()


func _update_player_hud(slot: int, game: GameController) -> void:
	var state := game.get_player_state()
	shared_hud.update_run(
		slot,
		int(state.get("passengers", 0)),
		int(state.get("max_passengers", 0)),
		float(state.get("time_seconds", 0.0)),
		float(state.get("progress", 0.0)),
		str(state.get("status", ""))
	)


func _make_shared_visual() -> void:
	var p2_id := str(SaveManager.get_setting("cart_p2", "dove"))
	if GameSession.duo_split == GameSession.SPLIT_SHARED:
		# 不分屏时在 Game1 中放一辆真正的 P2 缆车副本：
		# 与 P1 同场景、同轮子、同乘客、同护甲/拖尾绘制，但不参与输入和物理。
		var p2_scene := CartCatalog.get_scene(p2_id)
		if p2_scene != null:
			_shared_p2_cart = p2_scene.instantiate() as CoasterController
			game1.get_node("World/Coasters").add_child(_shared_p2_cart)
			_shared_p2_cart.configure(game1.level, "p2")
			_shared_p2_cart.active = false
			_shared_p2_cart.set_process(false)
			_shared_p2_cart.set_physics_process(false)
			_shared_p2_cart.set_process_input(false)
			_shared_p2_cart.hide_mirror_collision()
			if game2.coaster != null:
				_shared_p2_cart.sync_visual_from(game2.coaster)
				_shared_p2_cart.active = true


func _make_split_ghost() -> void:
	if not GameSession.duo_show_ghost or GameSession.duo_split == GameSession.SPLIT_SHARED:
		return
	var p2_id := str(SaveManager.get_setting("cart_p2", "dove"))
	var p2_scene := CartCatalog.get_scene(p2_id)
	if p2_scene == null:
		return
	_split_p2_ghost = p2_scene.instantiate() as CoasterController
	game1.get_node("World/Coasters").add_child(_split_p2_ghost)
	_split_p2_ghost.configure(game1.level, "p2")
	_split_p2_ghost.active = false
	_split_p2_ghost.set_process(false)
	_split_p2_ghost.set_physics_process(false)
	_split_p2_ghost.set_process_input(false)
	_split_p2_ghost.hide_mirror_collision()
	_split_p2_ghost.z_index = 1
	_split_p2_ghost.modulate = Color(1, 1, 1, 0.32)
	if game2.coaster != null:
		_split_p2_ghost.sync_visual_from(game2.coaster)
	_split_p2_ghost.modulate = Color(0.55, 0.86, 1.0, 0.42)
	var p1_id := str(SaveManager.get_setting("cart_p1", "dove"))
	var p1_scene := CartCatalog.get_scene(p1_id)
	if p1_scene != null:
		_split_p1_ghost = p1_scene.instantiate() as CoasterController
		game2.get_node("World/Coasters").add_child(_split_p1_ghost)
		_split_p1_ghost.configure(game2.level, "p1")
		_split_p1_ghost.active = false
		_split_p1_ghost.set_process(false)
		_split_p1_ghost.set_physics_process(false)
		_split_p1_ghost.set_process_input(false)
		_split_p1_ghost.hide_mirror_collision()
		_split_p1_ghost.z_index = 1
		if game1.coaster != null:
			_split_p1_ghost.sync_visual_from(game1.coaster)
		_split_p1_ghost.modulate = Color(0.55, 0.86, 1.0, 0.42)


func _update_split_ghost() -> void:
	if _split_p2_ghost != null and game2.coaster != null:
		_split_p2_ghost.sync_visual_from(game2.coaster)
		_split_p2_ghost.modulate = Color(0.55, 0.86, 1.0, 0.42)
	if _split_p1_ghost != null and game1.coaster != null:
		_split_p1_ghost.sync_visual_from(game1.coaster)
		_split_p1_ghost.modulate = Color(0.55, 0.86, 1.0, 0.42)


func _update_shared_visual() -> void:
	if _shared_p2_cart != null and game2.coaster != null:
		_shared_p2_cart.sync_visual_from(game2.coaster)

func _update_shared_camera() -> void:
	if game1.coaster == null:
		return
	var p1 := game1.coaster.get_body_center()
	var p2 := game2.coaster.get_body_center() if game2.coaster != null else p1
	var p1_failed := bool(game1.get_player_state().get("failed", false))
	var p2_failed := bool(game2.get_player_state().get("failed", false))
	var target := (p1 + p2) * 0.5
	var target_zoom := 1.0
	if p1_failed and not p2_failed:
		# P1 归零：平滑移动到仍存活的 P2，并恢复正常视野大小。
		target = p2
		target_zoom = 1.0
	elif p2_failed and not p1_failed:
		target = p1
		target_zoom = 1.0
	else:
		var distance := p1.distance_to(p2)
		# 距离远时允许轻度扩大视野，但最多为正常范围的 1.5 倍（zoom >= 0.667）。
		target_zoom = clampf(720.0 / maxf(720.0, distance * 1.55), 0.667, 1.0)
	game1.camera.global_position = game1.camera.global_position.lerp(target, 0.16)
	game1.camera.zoom = game1.camera.zoom.lerp(Vector2(target_zoom, target_zoom), 0.10)


func _update_offscreen_markers() -> void:
	if game1.coaster == null:
		return
	var p2_world := game2.coaster.get_body_center() if game2.coaster != null else game1.coaster.get_body_center()
	marker_overlay.set_targets([
		{"world": game1.coaster.get_body_center(), "label": "P1", "color": Color(0.42, 0.82, 1.0)},
		{"world": p2_world, "label": "P2", "color": Color(1.0, 0.55, 0.38)},
	])


func _on_player_completed(result: Dictionary, slot: int) -> void:
	if slot < 0 or slot >= _results.size():
		return
	_results[slot] = result
	if not _results[0].is_empty() and not _results[1].is_empty():
		_finish_duo()


func _finish_duo() -> void:
	var p1: Dictionary = (_results[0].get("players", []) as Array)[0]
	var p2: Dictionary = (_results[1].get("players", []) as Array)[0]
	p1 = p1.duplicate(true)
	p2 = p2.duplicate(true)
	p1["slot"] = 0
	p2["slot"] = 1
	p1["name"] = "玩家 1"
	p2["name"] = "玩家 2"
	_normalize_finish_result(p1, game1)
	_normalize_finish_result(p2, game2)
	var winner := _decide_winner(p1, p2)
	var any_completed := bool(p1.get("completed", false)) or bool(p2.get("completed", false))
	var result := {
		"mode": GameSession.MODE_DUO,
		"level_id": game1.level.id,
		"level_name": game1.level.name,
		"level_subtitle": game1.level.subtitle,
		"completed": any_completed,
		"failed": not any_completed,
		"players": [p1, p2],
		"winner_slot": winner,
		"save_info": {},
		"level_starting_passengers": game1.coaster.starting_passengers,
		"is_new_best": false,
	}
	GameSession.complete_run(result)


func _normalize_finish_result(player: Dictionary, game: GameController) -> void:
	# 双人结束瞬间可能刚好越过终点但信号晚一帧，或超时先触发失败。
	if game == null or game.coaster == null or game.level == null:
		return
	if bool(player.get("completed", false)):
		return
	var reached := false
	if game.level.is_forward_course():
		reached = game.coaster.current_s >= game.level.finish_s - 8.0
	else:
		reached = game.coaster.current_s <= game.level.finish_s + 8.0
	if game.passengers > 0 and reached:
		player["completed"] = true
		player["failed"] = false
		player["passengers"] = game.passengers


func _decide_winner(p1: Dictionary, p2: Dictionary) -> int:
	var c1 := bool(p1.get("completed", false))
	var c2 := bool(p2.get("completed", false))
	if c1 and not c2:
		return 0
	if c2 and not c1:
		return 1
	if not c1 and not c2:
		return -1
	var passengers1 := int(p1.get("passengers", 0))
	var passengers2 := int(p2.get("passengers", 0))
	if passengers1 != passengers2:
		return 0 if passengers1 > passengers2 else 1
	var time1 := float(p1.get("time_seconds", 999999.0))
	var time2 := float(p2.get("time_seconds", 999999.0))
	return 0 if time1 <= time2 else 1


func _on_pause_requested() -> void:
	get_tree().paused = true
	shared_hud.set_paused(true)


func _on_resume_requested() -> void:
	get_tree().paused = false
	shared_hud.set_paused(false)


func _on_restart_requested() -> void:
	get_tree().paused = false
	GameSession.start_level(game1.level.id, GameSession.MODE_DUO)


func _on_quit_requested() -> void:
	get_tree().paused = false
	GameSession.return_to_level_select()

extends Node
## Regression checks for the 2026-10-28 fixes. Not shipped.

const DT := 1.0 / 60.0

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _make_level(level_id: String) -> LevelData:
	return LevelCatalog.get_level(level_id)


func _run() -> void:
	GameSession.suppress_editor_session = true
	await get_tree().process_frame
	await _test_seam_boundary()
	await _test_attach()
	await _test_swept_attach()
	await _test_attach_forward_sign()
	await _test_bird_return()
	await _test_trigger_radius()
	await _test_caterpillar_rotation()
	await _test_caterpillar_collision()
	await _test_body_offset()
	await _test_hud_swap()
	await _test_failure_reasons()
	await _test_continuous_damage()
	await _test_trigger_two_ends()
	_test_warning_uniform()
	await _test_open_global_end()
	_test_camera_bounds_margin()
	_test_selected_obstacle_path()
	await _test_editor_track_direction()
	await _test_developer_blank_loop()
	await _test_editor_returns_tested_level()
	await _test_run_anchor()
	await _test_obstacle_behavior()
	await _test_obstacle_flip_and_ferris()
	_test_obstacle_catalog()
	_test_catalogs()
	await _test_duo_view_order()
	print("\nFIX CHECKS: ", _checks - _failures.size(), " / ", _checks)
	for failure in _failures:
		print("  FAIL ", failure)
	AudioDirector.shutdown()
	await get_tree().process_frame
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _test_seam_boundary() -> void:
	var level := LevelData.from_dictionary({
		"id": "seam_test",
		"name": "seam_test",
		"track": {
			"start_angle_deg": 0.0,
			"pieces": [
				{"type": "straight", "length": 200.0},
				{"type": "straight", "length": 160.0, "origin": [400.0, 300.0], "heading_deg": 90.0},
			],
			"start_s": 0.0,
			"finish_s": 100.0,
		},
	})
	var track := level.track
	var coaster := load("res://scenes/carts/dove.tscn").instantiate() as CoasterController
	add_child(coaster)
	await get_tree().process_frame
	coaster.configure(level, "solo")
	coaster.set_physics_process(false)
	coaster.active = true
	coaster.air_drag = 0.0
	coaster.gravity_accel = 0.0
	coaster.rolling_friction = 0.0
	coaster.max_speed = 5000.0
	var seam: Dictionary = track.seams[0]
	var start_s := float(seam["start_s"])
	var end_s := float(seam["end_s"])
	coaster._airborne = false
	coaster.current_s = start_s
	coaster.current_speed = 900.0
	coaster._update_pose()
	coaster._physics_process(DT)
	_check(coaster.is_jumping(), "forward seam boundary launches")
	_check(coaster.current_s == start_s, "forward seam boundary stays at edge")
	coaster._airborne = false
	coaster.current_s = end_s
	coaster.current_speed = -900.0
	coaster._update_pose()
	coaster._physics_process(DT)
	_check(coaster.is_jumping(), "backward seam boundary launches")
	_check(coaster.current_s == end_s, "backward seam boundary stays at edge")
	_check(not coaster.is_jumping() or coaster.global_position.distance_to(track.sample_at(end_s)) < 1.0, "launch position is the real edge")
	coaster.queue_free()
	await get_tree().process_frame


func _test_attach() -> void:
	var level := _make_level("level_01")
	var track := level.track
	var coaster := load("res://scenes/carts/dove.tscn").instantiate() as CoasterController
	add_child(coaster)
	await get_tree().process_frame
	coaster.configure(level, "solo")
	coaster.set_physics_process(false)
	coaster.active = true
	var probe_s := 200.0
	var rail_point := track.sample_at(probe_s)
	var attached := false
	for offset: Vector2 in [Vector2(0, -14), Vector2(0, 14), Vector2(-14, 0), Vector2(14, 0)]:
		coaster._airborne = true
		coaster.current_s = probe_s
		coaster.current_speed = 0.0
		coaster.global_position = rail_point + offset
		coaster._air_velocity = Vector2.ZERO
		coaster._air_elapsed = 1.0
		for frame in 30:
			coaster._advance_flight(DT)
			if not coaster.is_jumping():
				attached = true
				break
		_check(attached, "attach from offset %s" % offset)
		attached = false
	coaster.queue_free()
	await get_tree().process_frame


func _test_swept_attach() -> void:
	var level := _make_level("level_01")
	var track := level.track
	var coaster := load("res://scenes/carts/dove.tscn").instantiate() as CoasterController
	add_child(coaster)
	await get_tree().process_frame
	coaster.configure(level, "solo")
	coaster.set_physics_process(false)
	coaster.active = true
	var probe_s := 400.0
	var rail_point := track.sample_at(probe_s)
	var tangent := track.tangent_at(probe_s)
	# 一帧移动超过 16px，起点和终点都在吸附半径外，但线段穿过轨道。
	coaster._airborne = true
	coaster.current_s = probe_s
	coaster.current_speed = 0.0
	coaster.global_position = rail_point - tangent * 30.0
	coaster._air_velocity = tangent * 3600.0
	coaster._air_elapsed = 1.0
	coaster._advance_flight(DT)
	_check(not coaster.is_jumping(), "swept attach catches a tunnelling rail crossing")
	# 吸附后继续行驶，不能无故再次脱离。
	if not coaster.is_jumping():
		coaster.current_speed = 300.0
		var stayed := true
		for frame in 90:
			coaster._physics_process(DT)
			if coaster.is_jumping():
				stayed = false
				break
		_check(stayed, "coaster stays on the rail after attaching")
	coaster.queue_free()
	await get_tree().process_frame


func _test_attach_forward_sign() -> void:
	# 每段连续轨道独立默认向右；只切换 B 这一段时 A 不受影响。
	var level := LevelData.from_dictionary({
		"id": "sign_test",
		"name": "sign_test",
		"track": {
			"start_angle_deg": 0.0,
			"pieces": [
				{"type": "straight", "length": 300.0},
				{"type": "straight", "length": 300.0, "origin": [600.0, 0.0], "heading_deg": 180.0},
			],
			"start_s": 0.0,
			"finish_s": 100.0,
		},
	})
	var track := level.track
	var runs := track.get_track_runs()
	var run0: Dictionary = runs[0]
	var run1: Dictionary = runs[1]
	var mid0 := (float(run0["start_s"]) + float(run0["end_s"])) * 0.5
	var mid1 := (float(run1["start_s"]) + float(run1["end_s"])) * 0.5
	var coaster := load("res://scenes/carts/dove.tscn").instantiate() as CoasterController
	add_child(coaster)
	await get_tree().process_frame
	coaster.configure(level, "solo")
	coaster.set_physics_process(false)
	coaster.active = true
	coaster.air_drag = 0.0
	coaster.gravity_accel = 0.0
	coaster.rolling_friction = 0.0

	var tangent0 := track.tangent_at(mid0)
	var tangent1 := track.tangent_at(mid1)
	var rail0 := track.sample_at(mid0)
	var rail1 := track.sample_at(mid1)
	_check(track.get_run_direction(0) == 1.0, "default run direction is right")
	_check(track.get_run_direction(1) == 1.0, "isolated run defaults to right independently")
	_check(coaster._forward_sign_at_s(mid0) == 1.0, "rightward run maps right key to +s")
	_check(coaster._forward_sign_at_s(mid1) == -1.0, "leftward run maps right key to -s (still world right)")
	coaster.current_s = mid0
	coaster.current_speed = -100.0
	coaster._track_forward_sign = 1.0
	Input.action_press("move_right")
	coaster._physics_process(DT)
	Input.action_release("move_right")
	_check(coaster.current_speed > -90.0, "counter brake quickly cancels residual reverse speed")
	coaster.current_speed = 0.0

	# 1) A→B 沿 B 的 +s（向左）落轨；默认向右，所以右键应减速朝右。
	coaster._airborne = true
	coaster.current_s = mid1
	coaster.current_speed = 0.0
	coaster.global_position = rail1
	coaster._air_velocity = tangent1 * 400.0
	coaster._air_elapsed = 1.0
	coaster._advance_flight(DT)
	_check(not coaster.is_jumping(), "A->B attach lands")
	_check(coaster._track_forward_sign == -1.0, "B uses default rightward mapping")
	var before_b := coaster.current_speed
	Input.action_press("move_right")
	coaster._physics_process(DT)
	Input.action_release("move_right")
	_check(coaster.current_speed < before_b, "right key brakes the leftward run toward world right")

	# 2) B→A 飞回 A：A 仍向右。
	coaster._airborne = true
	coaster.current_s = mid0
	coaster.current_speed = 0.0
	coaster.global_position = rail0
	coaster._air_velocity = -tangent0 * 400.0
	coaster._air_elapsed = 1.0
	coaster._advance_flight(DT)
	_check(not coaster.is_jumping(), "B->A attach lands")
	_check(coaster._track_forward_sign == 1.0, "A uses rightward mapping")
	var before_a := coaster.current_speed
	Input.action_press("move_right")
	coaster._physics_process(DT)
	Input.action_release("move_right")
	_check(coaster.current_speed > before_a, "right key still maps to world right on A")

	# 3) 第三次 A→B，从 B 反方向落轨：映射仍与第一次完全相同。
	coaster._airborne = true
	coaster.current_s = mid1
	coaster.current_speed = 0.0
	coaster.global_position = rail1
	coaster._air_velocity = -tangent1 * 400.0
	coaster._air_elapsed = 1.0
	coaster._advance_flight(DT)
	_check(not coaster.is_jumping(), "third A->B attach lands")
	_check(coaster._track_forward_sign == -1.0, "B mapping is identical regardless of landing direction")
	var before_third := coaster.current_speed
	Input.action_press("move_right")
	coaster._physics_process(DT)
	Input.action_release("move_right")
	_check(coaster.current_speed < before_third, "right key still maps to world right on third B landing")

	# 4) 只把 B 这一段切到向左：B 的右键应改为世界左（+s）。
	track.piece_directions[1] = -1.0
	coaster.configure(level, "solo")
	coaster.set_physics_process(false)
	coaster.active = true
	coaster.current_s = mid1
	coaster.current_speed = 0.0
	coaster._track_forward_sign = coaster._forward_sign_at_s(mid1)
	coaster._update_pose()
	_check(coaster._track_forward_sign == 1.0, "left B run maps right key to +s")
	var before_left := coaster.current_speed
	Input.action_press("move_right")
	coaster._physics_process(DT)
	Input.action_release("move_right")
	_check(coaster.current_speed > before_left, "right key accelerates world left after B direction toggle")
	coaster.queue_free()
	await get_tree().process_frame
	var left_level := LevelData.from_dictionary({
		"id": "left_data",
		"name": "left_data",
		"track": {
			"start_angle_deg": 0.0,
			"pieces": [{"type": "straight", "length": 100.0, "direction": -1}],
			"start_s": 0.0,
			"finish_s": 50.0,
		},
	})
	_check(left_level.track.get_run_direction(0) == -1.0, "per-run direction persists through level data")


func _test_bird_return() -> void:
	var level := _make_level("level_01")
	var bird := load("res://scenes/game/obstacles/bird.tscn").instantiate() as Obstacle
	add_child(bird)
	await get_tree().process_frame
	bird.configure({"s": 200.0, "offset": {"x": 0.0, "y": -60.0}}, level.track, 1.0)
	bird.trigger_two_ends = false
	bird.set_process(false)
	bird._start_trigger_cycle()
	var returned := false
	for frame in 900:
		bird._process(DT)
		if bird._returned_to_start or not bird._trigger_cycle_active:
			returned = true
			break
	_check(returned, "bird returns to start and ends trigger cycle")
	_check(bird.global_position.distance_to(bird._start_pos) < 1.0, "bird ends at start position")
	bird.queue_free()
	await get_tree().process_frame

	# 带减速段的往返：减速到 0 落在起点时也必须结束触发循环。
	var slow_bird := load("res://scenes/game/obstacles/bird.tscn").instantiate() as Obstacle
	add_child(slow_bird)
	await get_tree().process_frame
	slow_bird.configure({"s": 200.0, "offset": {"x": 0.0, "y": -60.0}}, level.track, 1.0)
	slow_bird.trigger_two_ends = false
	slow_bird.deceleration_time = 0.5
	slow_bird.set_process(false)
	slow_bird._start_trigger_cycle()
	var slow_returned := false
	for frame in 1200:
		slow_bird._process(DT)
		if slow_bird._returned_to_start or not slow_bird._trigger_cycle_active:
			slow_returned = true
			break
	_check(slow_returned, "bird with deceleration also returns")
	slow_bird.queue_free()
	await get_tree().process_frame


func _test_trigger_radius() -> void:
	var level := _make_level("level_01")
	var bird := load("res://scenes/game/obstacles/bird.tscn").instantiate() as Obstacle
	add_child(bird)
	await get_tree().process_frame
	var detector := bird.get_node("PlayerDetector/CollisionShape2D") as CollisionShape2D
	var scene_radius := (detector.shape as CircleShape2D).radius
	_check(is_equal_approx(scene_radius, 60.0), "bird scene detector is 60")
	bird.configure({"s": 200.0, "offset": {"x": 0.0, "y": -60.0}}, level.track, 1.0)
	_check(is_equal_approx((detector.shape as CircleShape2D).radius, 60.0), "configure keeps scene detector radius")
	var sanitized := LevelData._sanitize_obstacle({"prefab": "bird", "s": 1.0})
	_check(not sanitized.has("trigger_radius"), "level sanitize does not inject trigger_radius")
	bird.queue_free()
	await get_tree().process_frame


func _test_caterpillar_rotation() -> void:
	var level := _make_level("level_01")
	var caterpillar := load("res://scenes/game/obstacles/caterpillar.tscn").instantiate() as Obstacle
	add_child(caterpillar)
	await get_tree().process_frame
	caterpillar.configure({"s": 300.0, "offset": {"x": 0.0, "y": -20.0}}, level.track, 1.0)
	caterpillar.set_process(false)
	for frame in 60:
		caterpillar._process(DT)
	var root_deg := rad_to_deg(caterpillar.rotation)
	var visual_deg := rad_to_deg(caterpillar.visual.global_rotation)
	_check(absf(root_deg - 60.0) < 1.0, "caterpillar root rotates at rotation_speed")
	_check(absf(wrapf(visual_deg - root_deg, -180.0, 180.0)) < 0.5, "caterpillar texture does not double-rotate")
	_check(caterpillar.find_children("*", "CollisionPolygon2D", true, false).size() == 1, "caterpillar uses one arc collision polygon")
	caterpillar.queue_free()
	await get_tree().process_frame


func _test_caterpillar_collision() -> void:
	var level := _make_level("level_01")
	var caterpillar := load("res://scenes/game/obstacles/caterpillar.tscn").instantiate() as Obstacle
	add_child(caterpillar)
	await get_tree().process_frame
	caterpillar.configure({"s": 300.0, "offset": {"x": 0.0, "y": -20.0}}, level.track, 1.0)
	caterpillar.set_process(false)
	var coaster := load("res://scenes/carts/dove.tscn").instantiate() as CoasterController
	add_child(coaster)
	await get_tree().process_frame
	coaster.global_position = caterpillar.global_position + Vector2(140.0, -37.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var overlaps := caterpillar.get_overlapping_bodies()
	_check(overlaps.has(coaster), "caterpillar arc polygon overlaps a cart on its body")
	coaster.queue_free()
	caterpillar.queue_free()
	await get_tree().process_frame


func _test_body_offset() -> void:
	var level := _make_level("level_01")
	var coaster := load("res://scenes/carts/woma.tscn").instantiate() as CoasterController
	add_child(coaster)
	await get_tree().process_frame
	coaster.configure(level, "solo")
	var seats := coaster.get_node("PassengerSeats") as Node2D
	var collision := coaster.get_node("CollisionShape2D") as CollisionShape2D
	coaster.body_offset_y = 44.0
	coaster._apply_visual_settings()
	_check(is_equal_approx(coaster.body_sprite.position.y, 44.0), "body sprite follows body_offset_y")
	_check(is_equal_approx(seats.position.y, 44.0), "passenger seats follow body_offset_y")
	_check(is_equal_approx(collision.position.y, 49.0), "collision keeps its 5px relative offset")
	coaster.queue_free()
	await get_tree().process_frame


func _test_hud_swap() -> void:
	var hud := load("res://scenes/game/game_hud.tscn").instantiate() as GameHUD
	add_child(hud)
	await get_tree().process_frame
	var level := _make_level("level_01")
	hud.setup(level, GameSession.MODE_DUO)
	hud.set_player_cards_swapped(true)
	_check(hud.p2_card.get_index() == 0, "swapped HUD puts P2 first")
	_check(hud.center_box.get_index() == 1, "swapped HUD keeps center in the middle")
	_check(hud.p1_card.get_index() == 2, "swapped HUD puts P1 last")
	hud.set_player_cards_swapped(false)
	_check(hud.p1_card.get_index() == 0, "restored HUD puts P1 first")
	hud.queue_free()
	await get_tree().process_frame


func _test_failure_reasons() -> void:
	var probe := GameController.new()
	var messages_time: Dictionary = probe._fail_messages(GameController.FAIL_TIME)
	var messages_view: Dictionary = probe._fail_messages(GameController.FAIL_VIEW)
	var messages_pass: Dictionary = probe._fail_messages(GameController.FAIL_PASSENGERS)
	probe.free()
	_check(str(messages_time.get("title", "")).contains("时间"), "time failure text")
	_check(str(messages_view.get("title", "")).contains("视野"), "view failure text")
	_check(str(messages_pass.get("title", "")).contains("乘客"), "passenger failure text")

	GameSession.authored_level_data = {}
	GameSession.selected_level_id = "level_01"
	GameSession.set_mode(GameSession.MODE_SOLO)
	var game := load("res://scenes/game/game.tscn").instantiate() as GameController
	game.finish_delay_seconds = 99.0
	game.auto_route_to_result = false
	game.save_results = false
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.debug_skip_countdown()
	await get_tree().process_frame
	_check(not game._is_outside_camera_view(game.coaster.get_body_center()), "centered car is inside camera view")
	_check(game._is_outside_camera_view(game.coaster.get_body_center() + Vector2(0, 100000)), "far below car is outside camera view")
	game._fail_run(GameController.FAIL_TIME)
	_check(game._fail_reason == GameController.FAIL_TIME, "fail reason recorded")
	_check(game.hud.toast_label.text.contains("时间"), "time failure toast text")
	game.queue_free()
	await get_tree().process_frame


func _test_continuous_damage() -> void:
	var crate := load("res://scenes/game/obstacles/crate.tscn").instantiate() as Obstacle
	add_child(crate)
	await get_tree().process_frame
	crate.movement_mode = Obstacle.MODE_STATIC
	crate.global_position = Vector2.ZERO
	var coaster := load("res://scenes/carts/dove.tscn").instantiate() as CoasterController
	add_child(coaster)
	await get_tree().process_frame
	coaster.global_position = Vector2.ZERO
	var hits: Array = [0]
	crate.touched.connect(func(_obstacle: Obstacle, body: CoasterController) -> void:
		hits[0] += 1
		body.begin_invulnerability(0.3)
	)
	for frame in 4:
		await get_tree().physics_frame
	_check(not crate.get_overlapping_bodies().is_empty(), "obstacle overlaps coaster")
	for frame in 90:
		crate._process(DT)
		await get_tree().process_frame
	_check(hits[0] >= 2, "obstacle damages repeatedly while the coaster stays inside (hits=%d)" % hits[0])
	coaster.queue_free()
	crate.queue_free()
	await get_tree().process_frame


func _test_trigger_two_ends() -> void:
	var level := _make_level("level_01")
	var bird := load("res://scenes/game/obstacles/bird.tscn").instantiate() as Obstacle
	add_child(bird)
	await get_tree().process_frame
	bird.configure({"s": 200.0, "offset": {"x": 0.0, "y": -60.0}}, level.track, 1.0)
	bird.trigger_enabled = true
	bird.trigger_two_ends = true
	bird.set_process(false)
	bird._update_animation_state()
	_check((bird.visual as AnimatedSprite2D).animation == StringName(bird.idle_animation), "trigger obstacle idle uses idle animation")
	bird._start_two_end_cycle()
	bird._update_animation_state()
	_check((bird.visual as AnimatedSprite2D).animation == StringName(bird.move_animation), "trigger obstacle movement uses move animation")
	for frame in 300:
		bird._process(DT)
	_check(not bird._trigger_cycle_active, "two-end first move stops")
	_check(bird._two_end_at_end, "two-end first move stops at end")
	_check(bird.global_position.distance_to(bird._end_pos) < 1.0, "two-end first move position is end")
	bird._update_animation_state()
	_check((bird.visual as AnimatedSprite2D).animation == StringName(bird.idle_animation), "trigger obstacle stops on idle animation")
	bird._process(DT)
	_check(bird._two_end_armed, "two-end re-arms detection after stopping")
	bird._start_two_end_cycle()
	for frame in 300:
		bird._process(DT)
	_check(not bird._trigger_cycle_active, "two-end second move stops")
	_check(not bird._two_end_at_end, "two-end second move stops at start")
	_check(bird.global_position.distance_to(bird._start_pos) < 1.0, "two-end second move position is start")
	bird.queue_free()
	await get_tree().process_frame


func _test_warning_uniform() -> void:
	var renderer := TrackRenderer.new()
	var a := renderer._warning_offset(0.0, 1)
	var b := renderer._warning_offset(500.0, 1)
	_check(a.is_equal_approx(b) and not a.is_zero_approx(), "warning jitter is whole-piece, not a wave")
	renderer.free()


func _test_open_global_end() -> void:
	var level := LevelData.from_dictionary({
		"id": "open_end_test",
		"name": "open_end_test",
		"track": {
			"start_angle_deg": -90.0,
			"pieces": [{"type": "straight", "length": 300.0}],
			"start_s": 0.0,
			"finish_s": 50.0,
		},
	})
	var coaster := load("res://scenes/carts/dove.tscn").instantiate() as CoasterController
	add_child(coaster)
	await get_tree().process_frame
	coaster.configure(level, "solo")
	coaster.set_physics_process(false)
	coaster.active = true
	coaster.air_drag = 0.0
	coaster.gravity_accel = 0.0
	coaster.rolling_friction = 0.0
	coaster._airborne = false
	coaster.current_s = 295.0
	coaster.current_speed = 900.0
	coaster._update_pose()
	coaster._physics_process(DT)
	_check(coaster.is_jumping(), "isolated upward track can leave at the global end")
	coaster.queue_free()
	await get_tree().process_frame


func _test_camera_bounds_margin() -> void:
	var level := LevelData.from_dictionary({
		"id": "bounds_test",
		"name": "bounds_test",
		"track": {
			"start_angle_deg": 0.0,
			"pieces": [{"type": "straight", "length": 500.0}],
			"start_s": 0.0,
			"finish_s": 400.0,
		},
	})
	var editor := LevelEditor.new()
	editor._level = level
	editor._draft = {"obstacles": [{"prefab": "crate", "s": 400.0, "offset": {"x": 5000.0, "y": 5000.0}}]}
	editor._auto_expand_camera_bounds()
	var base := level.track.get_bounds(0.0)
	var expected := base.grow(120.0)
	_check(editor._level.camera_bounds.is_equal_approx(expected), "editor camera bounds ignore far obstacles")
	editor.free()


func _test_selected_obstacle_path() -> void:
	var level := _make_level("level_01")
	var editor := LevelEditor.new()
	editor._level = level
	editor._draft = {"obstacles": [{"prefab": "bird", "s": 200.0, "offset": {"x": 0.0, "y": -60.0}}]}
	editor._selected_kind = "obstacle"
	editor._selected_index = 0
	var info := editor._get_selected_obstacle_preview_info()
	_check(not info.is_empty(), "selected obstacle preview info exists")
	var path: PackedVector2Array = info.get("path", PackedVector2Array())
	var base: Vector2 = info.get("base", Vector2.ZERO)
	_check(path.size() >= 2, "selected obstacle has a motion path")
	_check(base.distance_to(Vector2.ZERO) > 1.0, "selected obstacle path base is on the track")
	editor._draft["obstacles"][0]["flip_x"] = true
	var flipped := editor._get_selected_obstacle_preview_info()
	var flipped_path: PackedVector2Array = flipped.get("path", PackedVector2Array())
	_check(flipped_path.size() == path.size(), "flipped preview keeps the same path samples")
	var original_end := path[path.size() - 1]
	var flipped_end := flipped_path[flipped_path.size() - 1]
	_check(absf(flipped_end.x + original_end.x) < 0.5 and absf(flipped_end.y - original_end.y) < 0.5, "flipped preview mirrors the motion path")
	editor.free()


func _test_editor_track_direction() -> void:
	GameSession.suppress_editor_session = true
	var editor := load("res://scenes/editor/level_editor.tscn").instantiate() as LevelEditor
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor.obstacle_prefab_option.item_count == 20, "workshop obstacle dropdown lists all 20 prefabs")
	_check(is_equal_approx(float(editor._placement_lengths["curve45"]), 120.0), "curve default length is 120")
	_check(is_equal_approx(float(editor._placement_lengths["straight"]), 240.0), "straight default length stays 240")
	var draft := {
		"track": {
			"start_angle_deg": 0.0,
			"pieces": [
				{"type": "straight", "length": 100.0},
				{"type": "straight", "length": 100.0, "origin": [300.0, 0.0], "heading_deg": 0.0},
			],
			"start_s": 0.0,
			"finish_s": 50.0,
		},
		"obstacles": [],
	}
	editor._draft = draft
	editor._level = LevelData.from_dictionary(draft)
	editor._selected_piece = 0
	editor._selected_kind = ""
	editor._selected_index = -1
	editor._refresh_inspector()
	_check(editor.track_direction_button.visible, "track direction button shows for selected track")
	_check(editor.track_direction_button.text.contains("右"), "track direction defaults to right")
	editor._toggle_track_direction()
	var pieces: Array = editor._draft["track"]["pieces"]
	_check(float(pieces[0].get("direction", 1.0)) == -1.0, "selected run flips to left")
	_check(float(pieces[1].get("direction", 1.0)) == 1.0, "isolated run keeps its own right direction")
	_check(editor._level.track.get_run_direction(0) == -1.0, "selected run direction is left")
	_check(editor._level.track.get_run_direction(1) == 1.0, "isolated run direction is still right")
	_check(editor.track_direction_button.text.contains("左"), "track direction button label flips to left")
	editor._selected_piece = 99
	editor._delete_piece()
	_check((editor._draft["track"]["pieces"] as Array).size() == 1, "deleting a stale piece index clamps instead of erroring")
	editor._selected_piece = -1
	editor._selected_kind = "obstacle"
	editor._selected_index = 0
	editor._refresh_inspector()
	_check(editor.flip_object_button.visible and not editor.track_direction_button.visible, "obstacle selection shows flip, not track direction")
	editor.queue_free()
	await get_tree().process_frame


func _test_developer_blank_loop() -> void:
	GameSession.suppress_editor_session = true
	GameSession.developer_mode = true
	var editor := load("res://scenes/editor/level_editor.tscn").instantiate() as LevelEditor
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(editor.new_button.visible, "developer workshop exposes new blank loop button")
	_check(editor.new_button.text.contains("空白环线"), "developer new button is labeled blank loop")
	editor._on_new_pressed()
	var draft := editor.debug_get_draft()
	var level_id := str(draft.get("id", ""))
	_check(level_id.begins_with("level_"), "developer new level uses a mainline level_XX id")
	var pieces: Array = draft.get("track", {}).get("pieces", [])
	_check(pieces.size() == 3 and str(pieces[0].get("type", "")) == "straight", "developer new level starts as three straight pieces")
	_check(editor._grid_enabled, "workshop grid is enabled by default")
	var level := LevelData.from_dictionary(draft)
	_check(level.track.is_valid(), "developer blank loop track is valid")
	_check(level.finish_s <= level.track.total_length + 0.01, "developer blank loop finish is on the track")
	_check(level.obstacles.is_empty(), "developer blank loop has no obstacles")
	GameSession.developer_mode = false
	editor.queue_free()
	await get_tree().process_frame


func _test_editor_returns_tested_level() -> void:
	GameSession.suppress_editor_session = true
	GameSession.developer_mode = true
	GameSession.editor_return_level_id = "level_02"
	var editor := load("res://scenes/editor/level_editor.tscn").instantiate() as LevelEditor
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(str(editor.debug_get_draft().get("id", "")) == "level_02", "editor restores the tested level instead of the first level")
	GameSession.editor_return_level_id = ""
	GameSession.developer_mode = false
	editor.queue_free()
	await get_tree().process_frame


func _test_run_anchor() -> void:
	var level := LevelData.from_dictionary({
		"id": "anchor_test",
		"name": "anchor_test",
		"track": {
			"start_angle_deg": 0.0,
			"pieces": [
				{"type": "straight", "length": 100.0, "origin": [0.0, 0.0], "heading_deg": 0.0},
				{"type": "straight", "length": 100.0, "origin": [100.0, 0.0], "heading_deg": 0.0, "direction": -1, "direction_anchor": true},
			],
			"start_s": 0.0,
			"finish_s": 150.0,
		},
	})
	var track := level.track
	_check(track.get_run_anchor_piece(0) == 1, "run anchor follows the first placed piece, not the array head")
	_check(track.get_run_direction(0) == -1.0, "run direction comes from the anchor piece")
	var coaster := load("res://scenes/carts/dove.tscn").instantiate() as CoasterController
	add_child(coaster)
	await get_tree().process_frame
	coaster.configure(level, "solo")
	_check(coaster._forward_sign_at_s(50.0) == -1.0, "run forward sign uses the anchor piece orientation")
	coaster.queue_free()
	await get_tree().process_frame


func _test_obstacle_behavior() -> void:
	var level := _make_level("level_01")
	var obstacle := load("res://scenes/game/obstacles/crate.tscn").instantiate() as Obstacle
	add_child(obstacle)
	await get_tree().process_frame
	obstacle.configure({"s": 200.0, "offset": {"x": 0.0, "y": -60.0}}, level.track)
	obstacle.start_wait_time = 0.2
	obstacle.end_wait_time = 0.7
	obstacle._moving_to_end = true
	_check(is_equal_approx(obstacle._current_wait_time(), 0.7), "end wait time is independent")
	obstacle._moving_to_end = false
	_check(is_equal_approx(obstacle._current_wait_time(), 0.2), "start wait time is independent")
	obstacle._moving_to_end = true

	obstacle.rotation_enabled = true
	obstacle.no_rotation_at_start = true
	obstacle.rotation_speed = 360.0
	obstacle.rotate_collision = true
	obstacle._progress = 0.0
	obstacle._apply_rotation(0.1)
	_check(is_zero_approx(obstacle.rotation), "no_rotation_at_start keeps initial angle")
	obstacle._progress = 0.5
	obstacle._apply_rotation(0.1)
	_check(absf(obstacle.rotation) > 0.01, "rotation resumes after leaving start")
	obstacle._progress = 0.0
	obstacle._apply_rotation(0.1)
	_check(is_zero_approx(obstacle.rotation), "rotation resets when returning to start")
	obstacle.rotation_enabled = false
	obstacle.no_rotation_at_start = false
	obstacle.rotate_collision = false

	obstacle.emitter_enabled = true
	obstacle.emitter_interval_min = 0.1
	obstacle.emitter_interval_max = 0.1
	obstacle.end_offset = Vector2(120.0, 0.0)
	obstacle._source_end_offset = obstacle.end_offset
	obstacle._reset_motion(obstacle.global_position)
	obstacle._emit_obstacle()
	_check(obstacle._emitter_alive.size() == 1, "emitter spawns an obstacle")
	var emitted: Obstacle = obstacle._emitter_alive[0]
	_check(emitted.visible and emitted._is_emitted, "emitted obstacle is active")
	emitted._progress = 1.0
	emitted._moving_to_end = true
	emitted._is_waiting = true
	emitted._wait_timer = 0.0
	emitted._handle_movement(DT)
	_check(emitted._emitted_off_playing and emitted.visible, "emitted obstacle plays off before recycling")
	emitted._handle_movement(1.0)
	_check(not emitted.visible and obstacle._emitter_pool.size() == 1, "emitted obstacle recycles after off animation")
	var spawned := obstacle._emitter_spawned
	obstacle._emit_obstacle()
	_check(obstacle._emitter_alive.size() == 1 and obstacle._emitter_spawned == spawned, "emitter reuses pooled obstacle")
	obstacle.emitter_enabled = false
	obstacle.interval_enabled = true
	obstacle._update_interval_phase(0.0)
	obstacle._update_interval_phase(1.1)
	_check(not obstacle._interval_phase_idle, "periodic mode alternates idle and off after one animation")
	obstacle.interval_enabled = false
	obstacle.trigger_mine = true
	obstacle._mine_state = Obstacle.MineState.WAITING
	obstacle._mine_timer = 0.2
	obstacle._update_trigger_mine(0.21)
	_check(obstacle._mine_state == Obstacle.MineState.IDLE, "trigger mine waits then plays idle")
	obstacle.trigger_mine_cooldown = 0.5
	obstacle._update_trigger_mine(1.1)
	_check(obstacle._mine_state == Obstacle.MineState.COOLDOWN, "trigger mine enters cooldown after idle")
	obstacle._update_trigger_mine(0.51)
	_check(obstacle._mine_state == Obstacle.MineState.OFF, "trigger mine returns to off after cooldown")
	var emitter := ObstacleBulletEmitter.new()
	emitter.bullet_scene = load("res://scenes/game/obstacles/cannonball_bullet.tscn")
	emitter.bullet_count = 3
	emitter.spread_enabled = true
	obstacle.add_child(emitter)
	var bullets_before := 0
	for child in get_children():
		if child is ObstacleBullet:
			bullets_before += 1
	emitter._fire(obstacle, null)
	var bullets_after := 0
	for child in get_children():
		if child is ObstacleBullet:
			bullets_after += 1
	_check(bullets_after - bullets_before == 3, "bullet emitter fires the configured count")
	obstacle.queue_free()
	await get_tree().process_frame

	var ghost_editor := LevelEditor.new()
	var visual := ghost_editor._obstacle_visual_info("hot_air_balloon")
	var texture := visual.get("texture", null) as Texture2D
	_check(texture != null and not texture.resource_path.ends_with("/crate.png"), "obstacle ghost uses the scene texture")
	var ghost_scale: Vector2 = visual.get("scale", Vector2.ONE)
	_check(ghost_scale.x > 1.0, "obstacle ghost keeps the scene visual scale")
	ghost_editor.free()


func _test_obstacle_flip_and_ferris() -> void:
	var level := _make_level("level_01")
	var ferris := load("res://scenes/game/obstacles/ferris_wheel.tscn").instantiate() as Obstacle
	add_child(ferris)
	await get_tree().process_frame
	ferris.configure({"s": 200.0, "offset": {"x": 0.0, "y": -60.0}}, level.track)
	_check(is_equal_approx(ferris.scale.x, 2.0) and is_equal_approx(ferris.scale.y, 2.0), "scene root scale survives flip application")
	ferris.apply_flip(true)
	_check(is_equal_approx(ferris.scale.x, -2.0) and is_equal_approx(ferris.scale.y, 2.0), "flip mirrors X without losing scene scale")
	ferris.apply_flip(false)
	_check(is_equal_approx(ferris.scale.x, 2.0), "unflip restores X scale")
	var rig := ferris.get_node_or_null("FerrisWheelVisual") as FerrisWheelVisual
	_check(rig != null, "ferris wheel visual rig exists")
	if rig != null:
		var slots := rig.get_node_or_null("CabinSlots") as Node2D
		_check(slots != null and slots.get_child_count() == 3, "ferris wheel exposes three cabin slots")
		var wheel := ferris.get_node_or_null("Frame") as Node2D
		var before_rotation := wheel.rotation if wheel != null else 0.0
		rig._process(0.1)
		_check(not is_equal_approx(wheel.rotation if wheel != null else 0.0, before_rotation), "ferris wheel rim rotates")
		var fixed_visual := ferris.get_node_or_null("Visual") as Node2D
		_check(is_zero_approx(fixed_visual.rotation), "ferris fixed visual does not rotate")
	_check(is_zero_approx(ferris.rotation), "ferris obstacle root itself does not rotate")
	ferris.queue_free()
	await get_tree().process_frame

	var caterpillar := load("res://scenes/game/obstacles/caterpillar.tscn").instantiate() as Obstacle
	add_child(caterpillar)
	await get_tree().process_frame
	caterpillar.configure({"s": 200.0, "offset": {"x": 0.0, "y": -60.0}}, level.track)
	caterpillar.apply_flip(true)
	caterpillar._apply_motion_flip()
	_check(is_equal_approx(caterpillar.scale.x, -1.0), "caterpillar flip mirrors root")
	_check(not (caterpillar.visual as AnimatedSprite2D).flip_h, "static caterpillar does not double-flip texture")
	caterpillar.queue_free()
	await get_tree().process_frame

	var crawler := load("res://scenes/game/obstacles/crate.tscn").instantiate() as Obstacle
	add_child(crawler)
	await get_tree().process_frame
	crawler.movement_mode = Obstacle.MODE_LINEAR
	crawler.flip_by_motion = true
	crawler.end_offset = Vector2(120.0, 0.0)
	crawler.configure({"s": 200.0, "offset": {"x": 0.0, "y": -60.0}}, level.track)
	crawler.set_process(false)
	crawler._moving_to_end = true
	crawler._apply_motion_flip()
	_check(not (crawler.visual as AnimatedSprite2D).flip_h, "normal motion flips texture only when moving left")
	crawler.apply_flip(true)
	crawler._moving_to_end = false
	crawler._apply_motion_flip()
	_check((crawler.visual as AnimatedSprite2D).flip_h, "flipped motion reverses texture flip direction")
	crawler.queue_free()
	await get_tree().process_frame

	var wave := load("res://scenes/game/obstacles/crate.tscn").instantiate() as Obstacle
	add_child(wave)
	await get_tree().process_frame
	wave.movement_mode = Obstacle.MODE_WAVE
	wave.end_offset = Vector2(120.0, 60.0)
	wave.configure({"s": 200.0, "offset": {"x": 0.0, "y": -60.0}}, level.track)
	var perp_before := wave._perp_dir
	wave.apply_flip(true)
	_check(is_equal_approx(wave._perp_dir.x, -perp_before.x) and is_equal_approx(wave._perp_dir.y, perp_before.y), "wave flip mirrors only horizontal trajectory")
	wave.queue_free()
	await get_tree().process_frame


func _test_obstacle_catalog() -> void:
	var expected := [
		"bird", "crate", "barrier", "hot_air_balloon", "ferris_wheel", "large_ferris_wheel", "caterpillar",
		"vine", "venus_flytrap", "snow_elf", "ice_crystal", "storm", "fan",
		"flying_bird", "flying_fish", "meteor", "dream_elf", "bubble", "cannonball", "dream_void",
	]
	_check(LevelEditor.TYPE_IDS == expected, "workshop obstacle order matches the requested order")
	_check(ObstacleDefinitionDB.get_prefab_ids() == expected, "obstacle database order matches the workshop")
	_check(LevelEditor.TYPE_LABELS.size() == expected.size(), "obstacle labels cover every prefab")
	var missing: Array[String] = []
	for prefab_id in expected:
		if ObstacleDefinitionDB.get_scene(str(prefab_id)) == null:
			missing.append(str(prefab_id))
	_check(missing.is_empty(), "all 20 obstacle scenes load: %s" % ", ".join(missing))


func _test_catalogs() -> void:
	var carts := CartCatalog.get_all()
	_check(carts.size() >= 9, "cart catalog includes the two new carts")
	_check(CartCatalog.get_profile("monster") != null and CartCatalog.get_profile("monster").display_name == "大海贼", "monster cart profile")
	_check(CartCatalog.get_profile("genius") != null and CartCatalog.get_profile("genius").display_name == "小天才", "genius cart profile")
	_check(CartCatalog.get_profile("monster").texture != null, "monster cart texture loaded")
	var fish_hint := CartCatalog.get_unlock_hint(CartCatalog.get_profile("fish"))
	_check("晴空乐园其二" in fish_hint, "cart unlock hint uses level title")
	var passengers := PassengerCatalog.get_all()
	_check(passengers.size() == 15, "passenger catalog includes passenger_1..15")
	var last := PassengerCatalog.get_profile("passenger_12")
	_check(last != null and last.texture != null, "passenger_12 profile and texture")
	var total_weight := 0.0
	for profile in passengers:
		total_weight += maxf(0.0, profile.spawn_weight)
	var expected_probability := maxf(0.0, last.spawn_weight) / maxf(0.001, total_weight)
	_check(absf(PassengerCatalog.get_spawn_probability("passenger_12") - expected_probability) < 0.001, "passenger spawn probability is weight based")


func _test_duo_view_order() -> void:
	GameSession.authored_level_data = {}
	GameSession.selected_level_id = "level_01"
	GameSession.set_mode(GameSession.MODE_DUO)
	GameSession.duo_split = GameSession.SPLIT_SIDE_BY_SIDE
	var duo := load("res://scenes/game/duo_game.tscn").instantiate() as DuoGameController
	add_child(duo)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(duo.view2.get_index() == 0, "P2 view is on the left")
	_check(duo.view1.get_index() == 1, "P1 view is on the right")
	_check(is_equal_approx(duo.game1.camera_limit_scale, 1.5), "split camera limit scale is 1.5x")
	_check(duo.game1.camera.limit_right < 100000, "split camera limit is finite (not fully open)")
	var view_half := duo.game1.get_viewport_rect().size.x * 0.5 / duo.game1.camera.zoom.x
	var expected_span := duo.game1._camera_bounds.size.x * 1.5 + view_half * 2.0
	var actual_span := float(duo.game1.camera.limit_right - duo.game1.camera.limit_left)
	_check(absf(actual_span - expected_span) < 4.0, "split camera span is 1.5x the level bounds")
	_check(not duo.game1._is_outside_camera_view(duo.game1.coaster.get_body_center()), "split camera sees centered car")
	_check(duo.game1._is_outside_camera_view(duo.game1.coaster.get_body_center() + Vector2(0, 100000)), "split camera view check catches far fall")
	duo.queue_free()
	await get_tree().process_frame

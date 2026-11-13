extends Node
## 无头自动测试入口（单轨重构版）。
## 运行：Godot_v4.5.1-stable_win64_console.exe --headless --path . res://tests/test_runner.tscn

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	GameSession.suppress_editor_session = true
	CommunityService.set_offline_mode(true)
	TelemetryService.set_remote_enabled(false)
	await get_tree().process_frame
	print("\n=== 乐园过山车 · 单轨重构测试 ===")
	print("Godot: %s" % Engine.get_version_info().get("string", "unknown"))

	await _test_autoloads()
	TelemetryService.set_backend(LocalTelemetryBackend.new("user://analytics/test_runner_events.jsonl"))
	await get_tree().process_frame
	TelemetryService.clear_events()
	await get_tree().process_frame
	_test_track_geometry()
	await _test_gameplay_movement()
	await _test_collision_and_failure()
	await _test_finish_and_save()
	await _test_editor()
	await _test_segmented_and_prefab()
	await _test_pause_and_duo()
	await _test_analytics_and_adaptive()
	_test_all_levels_serialize()
	await _test_community_plaza()
	_test_ugc_reclear()
	_test_plaza_pagination()
	await _test_touch_priority_and_telemetry_batching()
	await _test_cart_and_gate_visuals()
	await _test_ui_bindings()

	print("\n--------------------------------")
	if _failures.is_empty():
		print("全部通过：%d 项检查" % _checks)
	else:
		print("失败 %d / %d 项：" % [_failures.size(), _checks])
		for failure in _failures:
			print("  ✗ ", failure)
	print("=== 测试结束 ===\n")
	AudioDirector.shutdown()
	await get_tree().process_frame
	await get_tree().physics_frame
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _test_autoloads() -> void:
	print("\n[基础] 服务与关卡数据")
	_check(InputMap.has_action("move_left"), "输入动作 move_left 已注册")
	_check(InputMap.has_action("move_right"), "输入动作 move_right 已注册")
	_check(UITheme.theme != null, "UI 主题已构建")
	_check(LevelCatalog.get_level_count() >= 5, "关卡目录至少包含 5 关")
	var level := LevelCatalog.get_level("level_01")
	_check(level != null, "level_01 可加载")
	if level != null:
		_check(level.track != null and level.track.is_valid(), "单轨轨道几何有效")
		_check(level.track.total_length > 1000.0, "轨道总长度合理")
		_check(level.obstacles.size() > 0, "关卡包含障碍物")
		_check(level.start_s >= 0.0 and level.finish_s <= level.track.total_length, "起点/终点在轨道范围内")
	await get_tree().process_frame
	_check(SaveManager.is_ready, "存档服务已初始化")
	_check(SaveManager.get_storage_backend_id() == "local_file", "桌面/测试环境使用文件存档")
	_check(not WeChatStorage.new().is_available(), "非微信环境不启用 wx 存档")
	var fake_wx := FakeWxStore.new()
	var wx_backend := WeChatStorage.new()
	wx_backend._wx = fake_wx
	var wx_saved := {"ok": false}
	wx_backend.save_profile("unit_test", {"player_name": "微信测试"}, func(result: Dictionary) -> void:
		wx_saved["ok"] = bool(result.get("ok", false))
	)
	_check(bool(wx_saved["ok"]), "微信存档后端可写入本地存储")
	var wx_loaded := {"ok": false, "name": ""}
	wx_backend.load_profile("unit_test", func(result: Dictionary) -> void:
		wx_loaded["ok"] = bool(result.get("ok", false))
		wx_loaded["name"] = str((result.get("data", {}) as Dictionary).get("player_name", ""))
	)
	_check(bool(wx_loaded["ok"]) and str(wx_loaded["name"]) == "微信测试", "微信存档后端可跨会话读取")
	wx_backend.delete_profile("unit_test", func(_result: Dictionary) -> void: pass)
	_check(not fake_wx.data.has("cablecar.profile.unit_test"), "微信存档后端可删除键")
	_check(LeaderboardService.get_provider_id() == "local_real", "排行榜使用本地真实后端")


func _test_track_geometry() -> void:
	print("\n[轨道] 片段拼接与弧长采样")
	var track := TrackGeometry.new()
	track.pieces = [
		{"type": "straight", "length": 200.0},
		{"type": "arc", "radius": 100.0, "angle": -90.0},
		{"type": "straight", "length": 100.0},
	]
	track.build()
	_check(track.is_valid(), "轨道构建成功")
	_check(absf(track.total_length - (200.0 + PI * 100.0 * 0.5 + 100.0)) < 0.5, "弧长计算正确")
	_check(track.sample_at(0.0).distance_to(Vector2.ZERO) < 0.01, "起点位置正确")
	_check(track.sample_at(200.0).distance_to(Vector2(200, 0)) < 0.1, "直线段终点正确")
	_check(track.sample_at(track.total_length).distance_to(Vector2(300, -200)) < 0.5, "圆弧+直线终点正确")
	_check(track.tangent_at(0.0).dot(Vector2.RIGHT) > 0.99, "起点切线向右")
	_check(absf(track.nearest_s(Vector2(205, 5)) - 200.0) < 8.0, "最近点投影到直线段")

	var isolated := TrackGeometry.new()
	isolated.pieces = [
		{"type": "straight", "length": 200.0},
		{"type": "straight", "length": 160.0, "origin": [400.0, 300.0], "heading_deg": 90.0},
	]
	isolated.build()
	var isolated_start_angle := INF
	for endpoint: Dictionary in isolated.get_run_endpoints():
		if not bool(endpoint.get("end", true)) and Vector2(endpoint.get("point", Vector2.ZERO)).distance_to(Vector2(400, 300)) < 0.5:
			isolated_start_angle = float(endpoint.get("angle", INF))
	_check(absf(wrapf(isolated_start_angle - (-PI * 0.5), -PI, PI)) < 0.01, "孤立轨道起点切线来自轨道内部")

	var loop := TrackGeometry.new()
	loop.pieces = [{"type": "loop", "radius": 90.0, "angle": -360.0}]
	loop.build()
	_check(loop.is_valid(), "环圈轨道构建成功")
	_check(absf(loop.total_length - TAU * 90.0) < 0.5, "环圈弧长正确")
	_check(loop.sample_at(loop.total_length).distance_to(loop.sample_at(0.0)) < 1.0, "环圈首尾闭合")


func _test_gameplay_movement() -> void:
	print("\n[玩法] 左右驾驶与重力")
	SaveManager.set_storage_backend(LocalFileStorage.new(), "test_runner")
	await get_tree().process_frame
	GameSession.selected_level_id = "level_01"
	GameSession.set_mode(GameSession.MODE_SOLO)
	SaveManager.set_setting("cart_p1", "dove")
	var game_scene := load("res://scenes/game/game.tscn") as PackedScene
	var game := game_scene.instantiate() as GameController
	game.finish_delay_seconds = 99.0
	game.auto_route_to_result = false
	get_tree().root.add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.debug_skip_countdown()
	await get_tree().physics_frame

	var coaster := game.get_coaster()
	_check(coaster != null, "单轨过山车生成成功")
	if coaster == null:
		game.queue_free()
		return
	var source_scene := CartCatalog.get_scene(coaster.cart_id)
	var source: CoasterController = null
	if source_scene != null:
		source = source_scene.instantiate() as CoasterController
	var expected_max := source.max_speed if source != null else coaster.max_speed
	var expected_reverse := source.max_reverse_speed if source != null else coaster.max_reverse_speed
	if source != null:
		source.free()
	_check(is_equal_approx(coaster.max_speed, expected_max) and is_equal_approx(coaster.max_reverse_speed, expected_reverse), "场景修改的最高速度不会被关卡覆盖")
	var start_s := coaster.current_s
	Input.action_press("move_right")
	for index in 30:
		await get_tree().physics_frame
	Input.action_release("move_right")
	_check(coaster.current_s > start_s, "按右键沿轨道前进")
	_check(coaster.current_speed > 0.0, "前进速度为正")
	var speed_before_brake := coaster.current_speed
	Input.action_press("move_left")
	for index in 25:
		await get_tree().physics_frame
	Input.action_release("move_left")
	_check(coaster.current_speed < speed_before_brake, "按左键可刹车减速")
	# 回到起点后单独验证反向驾驶，避免长坡重力影响测试结果。
	coaster.current_s = start_s
	coaster.current_speed = 0.0
	coaster._update_pose()
	Input.action_press("move_left")
	for index in 30:
		await get_tree().physics_frame
	Input.action_release("move_left")
	_check(coaster.current_s < start_s, "按左键可沿轨道后退")
	_check(game.debug_get_run().get("passengers", 0) == 3, "乘客数量为 JSON 配置")
	_check(game.get_hud().get_displayed_passengers(0) == 3, "HUD 乘客数同步")

	game.queue_free()
	await get_tree().process_frame
	GameSession.last_result = {}


func _test_collision_and_failure() -> void:
	print("\n[玩法] 动态障碍与失败")
	GameSession.selected_level_id = "level_01"
	GameSession.set_mode(GameSession.MODE_SOLO)
	var game_scene := load("res://scenes/game/game.tscn") as PackedScene
	var game := game_scene.instantiate() as GameController
	game.finish_delay_seconds = 99.0
	game.auto_route_to_result = false
	get_tree().root.add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.debug_skip_countdown()
	await get_tree().physics_frame

	var crate_s := 0.0
	var crate_obstacle: Obstacle
	for obstacle in game.obstacles_root.get_children():
		if obstacle is Obstacle and (obstacle as Obstacle).obstacle_type == "crate":
			crate_obstacle = obstacle as Obstacle
			crate_s = crate_obstacle.get_track_s()
			break
	_check(crate_s > 0.0, "找到静态木箱障碍")
	if crate_s > 0.0 and crate_obstacle != null:
		# 障碍伤害与失败链路（Area2D 进入事件在无头物理步进下不稳定）。
		game.debug_apply_damage(1)
		await get_tree().process_frame
	var run := game.debug_get_run()
	_check(int(run.get("passengers", 99)) == 2, "障碍伤害扣除 1 位乘客")
	_check(game.get_hud().get_displayed_passengers(0) == 2, "碰撞后 HUD 同步")

	game.debug_apply_damage(2)
	await get_tree().process_frame
	run = game.debug_get_run()
	_check(int(run.get("passengers", -1)) == 0, "乘客归零")
	_check(bool(run.get("failed", false)), "乘客归零触发失败")

	game.queue_free()
	await get_tree().process_frame
	GameSession.last_result = {}


func _test_finish_and_save() -> void:
	print("\n[结算] 终点、存档与排行榜")
	SaveManager.set_storage_backend(LocalFileStorage.new(), "test_runner")
	await get_tree().process_frame
	SaveManager.reset_progress()
	SaveManager.set_player_name("测试员")
	GameSession.selected_level_id = "level_01"
	GameSession.set_mode(GameSession.MODE_SOLO)
	var game_scene := load("res://scenes/game/game.tscn") as PackedScene
	var game := game_scene.instantiate() as GameController
	game.finish_delay_seconds = 0.18
	game.auto_route_to_result = false
	get_tree().root.add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.debug_skip_countdown()
	await get_tree().physics_frame
	_check(game.gates_root.get_child_count() > 0, "终点触发区已生成")

	game.debug_set_s(game.level.finish_s - 8.0)
	Input.action_press("move_right")
	for index in 30:
		await get_tree().physics_frame
	Input.action_release("move_right")
	await get_tree().create_timer(0.4, true, false, true).timeout

	var result := GameSession.last_result
	_check(not result.is_empty(), "越过终点生成结算数据")
	_check(bool(result.get("completed", false)), "结算标记为通关")
	var players: Array = result.get("players", [])
	_check(players.size() == 1 and bool(players[0].get("completed", false)), "单人通关结果正确")
	if not players.is_empty():
		_check(int(players[0].get("stars", 0)) == 3, "满员通关获得三星")
	var best := SaveManager.get_level_best("level_01")
	_check(not best.is_empty(), "通关成绩写入本地存档")
	_check(int(best.get("passengers", 0)) == 3, "存档保存剩余乘客数")
	_check(SaveManager.is_level_cleared("level_01"), "存档记录通关状态")

	var fetch_state := {"done": false, "result": {}}
	LeaderboardService.fetch_scores("level_01", 10, func(fetch_result: Dictionary) -> void:
		fetch_state["done"] = true
		fetch_state["result"] = fetch_result
	)
	await get_tree().process_frame
	_check(bool(fetch_state["done"]), "排行榜接口可用")
	var entries: Array = fetch_state["result"].get("entries", [])
	var has_local := false
	for entry: Variant in entries:
		if entry is Dictionary and bool((entry as Dictionary).get("is_local", false)):
			has_local = true
	_check(has_local, "玩家最佳成绩并入排行榜")

	game.queue_free()
	await get_tree().process_frame
	GameSession.last_result = {}


func _test_editor() -> void:
	print("\n[编辑器] 轨道拼接、动态障碍、起终点与保存")
	DirAccess.remove_absolute("user://editor_last_session.json")
	var editor_scene := load("res://scenes/editor/level_editor.tscn") as PackedScene
	_check(editor_scene != null, "关卡编辑器场景可加载")
	if editor_scene == null:
		return
	var editor := editor_scene.instantiate() as LevelEditor
	get_tree().root.add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	var draft := editor.debug_get_draft()
	_check(str(draft.get("id", "")).begins_with("custom_"), "编辑器默认生成自定义关卡 id")
	_check(editor.debug_get_track_length() > 500.0, "编辑器轨道几何有效")
	_check(not editor.subtitle_row.visible, "玩家工坊隐藏关卡简介")
	var left_scroll := editor.get_node("UILayer/Root/ContentMargin/Workspace/LeftPanel/LeftScroll") as ScrollContainer
	var right_scroll := editor.get_node("UILayer/Root/ContentMargin/Workspace/RightPanel/Scroll") as ScrollContainer
	var touch_scroll_script := load("res://scripts/ui/touch_scroll.gd")
	_check(left_scroll.get_script() == touch_scroll_script, "工坊左栏支持拖动与惯性滚动")
	_check(right_scroll.get_script() == touch_scroll_script, "工坊右栏支持拖动与惯性滚动")
	var pieces_before := (draft.get("track", {}).get("pieces", []) as Array).size()
	editor._toggle_level_section()
	_check(not editor.level_title_edit.get_parent().visible and editor.camera_fit_button.visible, "收起关卡设置时标题隐藏、相机适配仍显示")
	editor._toggle_level_section()
	editor.subtitle_edit.text = "一二三四五六七八九十一二三四五六七八九十一二三四五六"
	editor._on_subtitle_changed()
	await get_tree().process_frame
	var normalized_subtitle := editor.subtitle_edit.text
	_check(normalized_subtitle.length() <= 24 and normalized_subtitle.split("\n").size() <= 3, "简介输入严格限制 24 字 / 3 行")
	editor.debug_add_piece("loop")
	await get_tree().process_frame
	draft = editor.debug_get_draft()
	var pieces_after := (draft.get("track", {}).get("pieces", []) as Array).size()
	_check(pieces_after == pieces_before + 1, "添加竖直环圈片段")

	editor.level_title_edit.text = "工坊测试关卡_%d" % Time.get_ticks_msec()
	var save_result := editor.debug_save()
	_check(bool(save_result.get("ok", false)), "自定义关卡保存成功")
	var saved_id := str(save_result.get("id", ""))
	if not saved_id.is_empty():
		_check(LevelCatalog.has_level(saved_id), "保存后关卡目录可读取自制关卡")
		var raw := LevelCatalog.get_raw_level(saved_id)
		_check(bool(raw.get("ok", false)), "可重新读取自制关卡 JSON")
		var loaded := LevelCatalog.get_level(saved_id)
		var final_obstacles := (draft.get("obstacles", []) as Array).size()
		_check(loaded != null and loaded.obstacles.size() == final_obstacles, "重新载入后动态障碍仍在")
		LevelCatalog.delete_user_level(saved_id)

	# 网格开启时，拖动起点/终点也必须吸附到网格（之前只有障碍吸附）。
	var snap_draft := {
		"track": {
			"start_angle_deg": 0.0,
			"pieces": [{"type": "straight", "length": 600.0}],
			"start_s": 60.0,
			"finish_s": 500.0,
		},
		"obstacles": [],
	}
	editor._draft = snap_draft.duplicate(true)
	editor._level = LevelData.from_dictionary(editor._draft)
	editor._grid_enabled = true
	editor._selected_kind = "start"
	editor._selected_index = -1
	editor._update_dragged_marker(Vector2(123.0, 0.0))
	_check(absf(float(editor._draft["track"]["start_s"]) - 120.0) < 0.01, "拖动起点时吸附到网格")
	editor._selected_kind = "finish"
	editor._update_dragged_marker(Vector2(483.0, 0.0))
	_check(absf(float(editor._draft["track"]["finish_s"]) - 480.0) < 0.01, "拖动终点时吸附到网格")
	editor._selected_kind = ""

	editor.queue_free()
	await get_tree().process_frame


func _test_analytics_and_adaptive() -> void:
	print("\n[大数据] 行为遥测、聚合分析与自适应难度")
	TelemetryService.clear_events()
	await get_tree().process_frame
	var level := LevelCatalog.get_level("level_01")
	_check(level != null, "分析测试关卡可加载")
	if level == null:
		return
	var runs := [
		{"completed": true, "passengers": 3, "time_seconds": 50.0, "stars": 3, "collisions": 2},
		{"completed": true, "passengers": 2, "time_seconds": 68.0, "stars": 2, "collisions": 1},
		{"completed": false, "passengers": 0, "time_seconds": 30.0, "stars": 0, "collisions": 3},
	]
	for run in runs:
		TelemetryService.begin_run(level, GameSession.MODE_SOLO, {"obstacle_speed_scale": 1.0, "engine_scale": 1.0})
		for index in int(run["collisions"]):
			TelemetryService.log_event("collision", {
				"level_id": "level_01",
				"obstacle_type": "bird" if index % 2 == 0 else "storm",
				"motion_type": "circle",
				"obstacle_s": 500.0,
				"s": 500.0,
				"track_progress": 0.25 + index * 0.1,
				"speed": 120.0,
			})
		TelemetryService.end_run(run)
	await get_tree().process_frame
	_check(TelemetryService.get_events().size() > 0, "遥测事件写入本地 JSONL")

	var dashboard_state := {"done": false, "result": {}}
	AnalyticsService.load_dashboard("", func(result: Dictionary) -> void:
		dashboard_state["done"] = true
		dashboard_state["result"] = result
	)
	await get_tree().process_frame
	_check(bool(dashboard_state["done"]), "分析服务返回聚合结果")
	var dashboard: Dictionary = dashboard_state["result"].get("dashboard", {})
	_check(int(dashboard.get("total_runs", 0)) == 3, "聚合运行次数正确")
	_check(int(dashboard.get("completed_runs", 0)) == 2, "聚合完赛次数正确")
	_check(int(dashboard.get("total_collisions", 0)) == 6, "聚合碰撞次数正确")
	_check(absf(float(dashboard.get("completion_rate", 0.0)) - 66.6667) < 0.1, "通关率计算正确")
	var type_stats: Array = dashboard.get("collision_types", [])
	_check(not type_stats.is_empty(), "碰撞类型统计存在")
	var bins: Array = dashboard.get("collision_bins", [])
	_check(bins.size() == 20 and _sum_array(bins) == 6, "碰撞热点分桶总数正确")

	var adaptive := AdaptiveDifficultyService.get_modifiers("level_01")
	_check(int(adaptive.get("samples", 0)) >= 3, "自适应算法读取最近样本")
	_check(float(adaptive.get("obstacle_speed_scale", 0.0)) >= 0.8 and float(adaptive.get("obstacle_speed_scale", 2.0)) <= 1.2, "动态障碍倍率在限制范围内")
	_check(float(adaptive.get("engine_scale", 0.0)) >= 0.9 and float(adaptive.get("engine_scale", 2.0)) <= 1.2, "引擎辅助倍率在限制范围内")
	_check(str(adaptive.get("label", "")).contains("自适应"), "自适应策略有可解释标签")

	var csv_state := {"done": false, "result": {}}
	AnalyticsService.export_csv("", func(result: Dictionary) -> void:
		csv_state["done"] = true
		csv_state["result"] = result
	)
	await get_tree().process_frame
	_check(bool(csv_state["done"]) and bool(csv_state["result"].get("ok", false)), "行为数据 CSV 导出成功")
	_check(int(csv_state["result"].get("count", 0)) >= 9, "CSV 包含全部事件行")

	var single_chart := AnalyticsChart.new()
	single_chart.size = Vector2(320, 180)
	single_chart.values = [2.0]
	single_chart.labels = ["单点"]
	single_chart.chart_type = "line"
	get_tree().root.add_child(single_chart)
	await get_tree().process_frame
	_check(single_chart.values.size() == 1, "折线图单点数据不崩溃")
	single_chart.queue_free()
	await get_tree().process_frame

	var analytics_scene := (load("res://scenes/ui/analytics.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(analytics_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.45, true, false, true).timeout
	var total_label := analytics_scene.get_node("%TotalRunsValue") as Label
	_check(total_label != null and total_label.text == "3", "分析看板渲染运行次数")
	var name_edit := analytics_scene.get_node("%PlayerNameEdit") as LineEdit
	_check(name_edit != null and name_edit.text == SaveManager.get_player_name(), "个人主页渲染昵称")
	analytics_scene.queue_free()
	await get_tree().process_frame

	TelemetryService.clear_events()
	await get_tree().process_frame


func _sum_array(values: Array) -> int:
	var total := 0
	for value: Variant in values:
		total += int(value)
	return total


func _test_segmented_and_prefab() -> void:
	print("\n[轨道/预制体] 分段轨道、自由放置与障碍预制体")
	var segmented := TrackGeometry.from_track_data({
		"start_angle_deg": 0.0,
		"pieces": [
			{"type": "straight", "length": 200.0},
			{"type": "straight", "length": 200.0, "origin": [500.0, 0.0], "heading_deg": 0.0},
		],
		"start_s": 10.0,
		"finish_s": 650.0,
	})
	_check(segmented.is_valid(), "分段轨道几何有效")
	_check(segmented.seams.size() == 1, "分段轨道生成接缝")
	if not segmented.seams.is_empty():
		_check(absf(float(segmented.seams[0].get("distance", 0.0)) - 300.0) < 0.1, "接缝空档距离正确")
		_check(absf(float(segmented.seams[0].get("start_s", 0.0)) - 200.0) < 0.1, "接缝弧长正确")
	segmented.break_piece(0)
	_check(segmented.is_piece_broken(0), "轨道片段可标记为断裂")

	var jump_data := {
		"id": "jump_test",
		"name": "跳轨测试",
		"track": {
			"start_angle_deg": 0.0,
			"pieces": [
				{"type": "straight", "length": 200.0},
				{"type": "straight", "length": 200.0, "origin": [400.0, 0.0], "heading_deg": 0.0},
			],
			"start_s": 10.0,
			"finish_s": 590.0,
		},
	}
	var jump_level := LevelData.from_dictionary(jump_data)
	var jump_coaster := (load("res://scenes/carts/dove.tscn") as PackedScene).instantiate() as CoasterController
	get_tree().root.add_child(jump_coaster)
	jump_coaster.configure(jump_level, "solo")
	jump_coaster.active = true
	jump_coaster.current_s = 199.0
	jump_coaster.current_speed = 300.0
	jump_coaster._physics_process(0.016)
	_check(jump_coaster.is_jumping(), "对齐的分段轨道会触发跳跃")
	jump_coaster.queue_free()

	var break_data := {
		"id": "break_test",
		"name": "断轨测试",
		"track": {
			"pieces": [{"type": "straight", "length": 240.0}],
			"start_s": 20.0,
			"finish_s": 200.0,
		},
	}
	var break_level := LevelData.from_dictionary(break_data)
	break_level.track.break_piece(0)
	var break_coaster := (load("res://scenes/carts/dove.tscn") as PackedScene).instantiate() as CoasterController
	get_tree().root.add_child(break_coaster)
	break_coaster.configure(break_level, "solo")
	break_coaster.active = true
	break_coaster.current_speed = 220.0
	break_coaster._physics_process(0.016)
	_check(break_coaster.is_jumping() and not break_coaster.run_failed, "断裂轨道让缆车脱轨而不是直接失败")
	break_coaster.queue_free()
	break_level.track.reset_breaks()
	_check(not break_level.track.is_piece_broken(0), "重新开始时断轨状态会复原")

	var fail_data := jump_data.duplicate(true)
	fail_data["track"]["pieces"][1]["origin"] = [700.0, 0.0]
	var fail_level := LevelData.from_dictionary(fail_data)
	var fail_coaster := (load("res://scenes/carts/dove.tscn") as PackedScene).instantiate() as CoasterController
	get_tree().root.add_child(fail_coaster)
	fail_coaster.configure(fail_level, "solo")
	fail_coaster.active = true
	fail_coaster.current_s = 199.0
	fail_coaster.current_speed = 300.0
	fail_coaster._physics_process(0.016)
	_check(fail_coaster.is_jumping(), "未对齐的空档先进入自由飞行")
	fail_coaster.queue_free()
	await get_tree().process_frame

	var obstacle_scene := ObstacleDefinitionDB.get_scene("bird")
	_check(obstacle_scene != null, "统一障碍可视化场景可加载")
	if obstacle_scene != null:
		var bird := obstacle_scene.instantiate() as Obstacle
		_check(bird.find_children("*", "CollisionShape2D", true, false).size() >= 2, "障碍场景内置多个碰撞形状")
		bird._reset_motion(Vector2(100, 100))
		bird._update_position()
		_check(bird.global_position.distance_to(Vector2(100, 100)) < 0.1, "CIRCULAR 从放置点开始而不是从右侧偏移开始")
		bird.queue_free()

	# 飞鸟必须是“触发后完整往返”，不能一端触发后停在天上等下一次检测。
	var flying_bird := (load("res://scenes/game/obstacles/flying_bird.tscn") as PackedScene).instantiate() as Obstacle
	get_tree().root.add_child(flying_bird)
	await get_tree().process_frame
	flying_bird.configure({"s": 100.0}, segmented, 1.0)
	_check(not flying_bird.trigger_two_ends, "飞鸟使用完整往返触发而不是两端停靠")
	flying_bird.set_process(false)
	flying_bird._start_trigger_cycle()
	for _frame in 600:
		flying_bird._process(1.0 / 60.0)
	_check(not flying_bird._trigger_cycle_active, "飞鸟触发后回到起点并结束往返")
	_check(flying_bird.global_position.distance_to(flying_bird._start_pos) < 1.0, "飞鸟往返结束停在起点")
	flying_bird.queue_free()

	# 远距离裁剪只按空间距离；热气球/陨石必须豁免，否则长轨迹会冻结在半空。
	_check(is_equal_approx(GameController.OBSTACLE_ACTIVE_RANGE, 1200.0), "障碍活动范围收敛到 1200px")
	var balloon_probe := (load("res://scenes/game/obstacles/hot_air_balloon.tscn") as PackedScene).instantiate() as Obstacle
	var meteor_probe := (load("res://scenes/game/obstacles/meteor.tscn") as PackedScene).instantiate() as Obstacle
	_check(balloon_probe.is_cull_exempt(), "热气球不受 1200px 裁剪")
	_check(meteor_probe.is_cull_exempt(), "陨石不受 1200px 裁剪")
	balloon_probe.free()
	meteor_probe.free()
	_check(PassengerCatalog.get_all().size() >= 4, "乘客纹理目录可扩展")

	var editor_scene := (load("res://scenes/editor/level_editor.tscn") as PackedScene).instantiate() as LevelEditor
	get_tree().root.add_child(editor_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var draft := editor_scene.debug_get_draft()
	var current_track := TrackGeometry.from_track_data(draft.get("track", {}))
	var end_point := current_track.sample_at(current_track.total_length)
	editor_scene.debug_place_track_at("straight", end_point + Vector2(320, 0))
	await get_tree().process_frame
	draft = editor_scene.debug_get_draft()
	var pieces: Array = draft.get("track", {}).get("pieces", [])
	var last_piece: Dictionary = pieces[pieces.size() - 1]
	_check(last_piece.has("origin"), "远离轨道末端放置生成分段轨道")
	var built := TrackGeometry.from_track_data(draft.get("track", {}))
	_check(built.seams.size() >= 1, "工坊放置的分段轨道有接缝")
	var new_end := built.sample_at(built.total_length)
	editor_scene.debug_place_track_at("straight", new_end + Vector2(30, 0))
	await get_tree().process_frame
	draft = editor_scene.debug_get_draft()
	pieces = draft.get("track", {}).get("pieces", [])
	last_piece = pieces[pieces.size() - 1]
	var snap_origin := Vector2.ZERO
	if last_piece.get("origin") is Array and (last_piece.get("origin") as Array).size() >= 2:
		snap_origin = Vector2(float(last_piece["origin"][0]), float(last_piece["origin"][1]))
	_check(last_piece.has("origin") and snap_origin.distance_to(new_end) < 200.0, "靠近轨道末端放置自动吸附连接")
	editor_scene.debug_place_obstacle_at(Vector2(0, 0))
	await get_tree().process_frame
	draft = editor_scene.debug_get_draft()
	var obstacles: Array = draft.get("obstacles", [])
	_check(obstacles.size() > 0 and str(obstacles[obstacles.size() - 1].get("prefab", "")) == "bird", "工坊放置预制体障碍")
	var curve_end := built.sample_at(built.total_length)
	editor_scene.debug_place_track_at("curve30", curve_end + Vector2(320, 0))
	await get_tree().process_frame
	draft = editor_scene.debug_get_draft()
	pieces = draft.get("track", {}).get("pieces", [])
	last_piece = pieces[pieces.size() - 1]
	_check(str(last_piece.get("type", "")) == "arc" and absf(float(last_piece.get("angle", 0.0))) == 30.0, "工坊可放置 30° 曲线")
	editor_scene.queue_free()
	await get_tree().process_frame


func _test_pause_and_duo() -> void:
	print("\n[双人/暂停] 全局冻结与分屏")
	await get_tree().create_timer(0.5, true).timeout
	_check(SceneRouter._overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "启动遮罩不拦截鼠标")
	GameSession.selected_level_id = "level_01"
	GameSession.set_mode(GameSession.MODE_SOLO)
	var game := (load("res://scenes/game/game.tscn") as PackedScene).instantiate() as GameController
	game.auto_route_to_result = false
	game.finish_delay_seconds = 99.0
	get_tree().root.add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.debug_skip_countdown()
	await get_tree().physics_frame
	Input.action_press("move_right")
	await get_tree().create_timer(0.22, true).timeout
	Input.action_release("move_right")
	var before_s := game.coaster.current_s
	var before_time := game.time_seconds
	var first_obstacle := game.obstacles_root.get_child(0) as Node2D if game.obstacles_root.get_child_count() > 0 else null
	var before_obstacle := first_obstacle.global_position if first_obstacle != null else Vector2.ZERO
	game._set_paused(true)
	await get_tree().create_timer(0.3, true).timeout
	_check(absf(game.coaster.current_s - before_s) < 0.01, "暂停后缆车不再移动")
	_check(absf(game.time_seconds - before_time) < 0.01, "暂停后计时不再增加")
	if first_obstacle != null:
		_check(first_obstacle.global_position.distance_to(before_obstacle) < 0.01, "暂停后障碍不再移动")
	game._set_paused(false)
	game.queue_free()
	await get_tree().process_frame

	GameSession.selected_level_id = "level_01"
	GameSession.set_mode(GameSession.MODE_DUO)
	GameSession.duo_split = GameSession.SPLIT_SIDE_BY_SIDE
	var duo := (load("res://scenes/game/duo_game.tscn") as PackedScene).instantiate() as DuoGameController
	get_tree().root.add_child(duo)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(duo.views.columns == 2, "左右分屏使用两列布局")
	_check(duo.game1.input_prefix == "p1" and duo.game2.input_prefix == "p2", "双人分屏分别绑定 P1/P2 输入")
	_check(not duo.game1.hud_layer.visible and not duo.game2.hud_layer.visible, "分屏内独立 HUD 已隐藏")
	_check(duo.shared_hud.p2_card.visible, "共享 HUD 显示第二位玩家")
	_check(duo.game1.get_node("World/Coasters").get_child_count() >= 2, "分屏内生成可选的对手残影")
	var ghost_found := false
	for ghost_child in duo.game1.get_node("World/Coasters").get_children():
		if ghost_child is CoasterController and ghost_child.modulate.a < 0.9:
			ghost_found = true
	_check(ghost_found, "对手残影为半透明")
	var multi_obstacle := (load("res://scenes/game/obstacles/bird.tscn") as PackedScene).instantiate() as Obstacle
	get_tree().root.add_child(multi_obstacle)
	multi_obstacle.configure({"s": 400.0}, duo.game1.level.track, 1.0)
	var extra_shape := CollisionShape2D.new()
	extra_shape.shape = CircleShape2D.new()
	(extra_shape.shape as CircleShape2D).radius = 10.0
	multi_obstacle.add_child(extra_shape)
	await get_tree().process_frame
	var collision_count := 0
	for child in multi_obstacle.get_children():
		if child is CollisionShape2D:
			collision_count += 1
	_check(collision_count >= 2, "障碍支持多个碰撞体")
	_check(not multi_obstacle.has_method("set_consumed"), "障碍被撞后不再进入 X 失效状态")
	multi_obstacle.queue_free()
	var winner_a := duo._decide_winner({"completed": true, "passengers": 3, "time_seconds": 20.0}, {"completed": true, "passengers": 2, "time_seconds": 10.0})
	_check(winner_a == 0, "双人成绩先比较剩余乘客")
	var winner_b := duo._decide_winner({"completed": true, "passengers": 2, "time_seconds": 10.0}, {"completed": true, "passengers": 2, "time_seconds": 9.0})
	_check(winner_b == 1, "乘客相同再比较用时")
	duo.queue_free()
	await get_tree().process_frame
	GameSession.set_mode(GameSession.MODE_SOLO)
	GameSession.duo_split = GameSession.SPLIT_SHARED
	var shared_duo := (load("res://scenes/game/duo_game.tscn") as PackedScene).instantiate() as DuoGameController
	get_tree().root.add_child(shared_duo)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(shared_duo.get_node("Views/View2").visible == false and shared_duo.get_node("MarkerOverlay").visible, "双人不分屏隐藏第二视口并启用边缘标记")
	_check(shared_duo.get("_shared_p2_cart") != null, "双人不分屏生成完整 P2 缆车")
	shared_duo.queue_free()
	await get_tree().process_frame
	GameSession.duo_split = GameSession.SPLIT_STACKED


func _test_all_levels_serialize() -> void:
	print("\n[UGC] 全部关卡可序列化为标准文档")
	var failures: Array[String] = []
	for summary in LevelCatalog.get_summaries():
		var level_id := str(summary.get("id", ""))
		var raw := LevelCatalog.get_raw_level(level_id)
		if not bool(raw.get("ok", false)):
			failures.append(level_id + " 读取失败")
			continue
		var document := UgcLevelDocument.make_upload_body(raw.get("data", {}), {
			"name": str(summary.get("name", level_id)).substr(0, 48),
			"author_name": "测试玩家",
			"author_id": "local_player",
			"platform": "windows",
		})
		if not bool(document.get("ok", false)):
			failures.append("%s：%s" % [level_id, str(document.get("error", "未知错误"))])
	_check(failures.is_empty(), "全部 %d 张关卡可序列化（失败 %d）" % [LevelCatalog.get_level_count(), failures.size()])
	for failure in failures.slice(0, 5):
		print("  ✗ ", failure)


func _test_community_plaza() -> void:
	print("\n[广场] 上传、审核、点赞、排行与排序")
	_check(CommunityService.MAX_LOCAL_UPLOADS == 3, "广场上传上限常量可访问")
	CommunityService.clear_all()
	var raw := LevelCatalog.get_raw_level("level_01")
	var data: Dictionary = (raw.get("data", {}) as Dictionary).duplicate(true)
	data["id"] = "custom_plaza_test"
	data["name"] = "广场测试关卡"
	data["custom"] = true
	data["source"] = "user"
	data["obstacles"] = [
		{"prefab": "crate", "s": 300.0, "offset": {"x": 87.0, "y": 64.0}, "flip_x": false},
	]
	var save_result := LevelCatalog.save_user_level(data)
	_check(bool(save_result.get("ok", false)), "广场测试关卡保存成功")
	var test_id := str(save_result.get("id", "custom_plaza_test"))
	var ugc_document := UgcLevelDocument.make_upload_body(data, {
		"name": "广场测试关卡",
		"author_name": "测试玩家",
		"author_id": "local_player",
		"platform": "windows",
	})
	_check(bool(ugc_document.get("ok", false)), "UGC 关卡可完整序列化")
	if bool(ugc_document.get("ok", false)):
		var roundtrip := UgcLevelDocument.from_json(UgcLevelDocument.to_json(ugc_document.get("body", {}).get("level_data", {})))
		_check(bool(roundtrip.get("ok", false)), "UGC 关卡 JSON 可反序列化并重新校验")
		var roundtrip_data: Dictionary = roundtrip.get("level_data", {})
		var offset_value: Variant = (roundtrip_data.get("obstacles", []) as Array)[0].get("offset")
		_check(offset_value is Dictionary, "UGC 障碍 offset 下载后保持 {x,y} 对象")
		var roundtrip_level := LevelData.from_dictionary(roundtrip_data)
		_check(roundtrip_level != null and (roundtrip_level.obstacles[0].get("offset") as Vector2) == Vector2(87.0, 64.0), "UGC 障碍偏移导入后不丢失")
		var legacy_data := roundtrip_data.duplicate(true)
		(legacy_data["obstacles"] as Array)[0]["offset"] = [87.0, 64.0]
		var legacy_level := LevelData.from_dictionary(legacy_data)
		_check(legacy_level != null and (legacy_level.obstacles[0].get("offset") as Vector2) == Vector2(87.0, 64.0), "旧数组 offset 仍可兼容导入")
		var legacy_ugc := UgcLevelDocument.validate_level(legacy_data)
		var legacy_ugc_obstacle: Dictionary = (legacy_ugc.get("level_data", {}).get("obstacles", []) as Array)[0]
		_check(bool(legacy_ugc.get("ok", false)) and legacy_ugc_obstacle.get("offset") is Dictionary, "旧数组 offset 经 UGC 归一化后变回对象")
	SaveManager.record_result({
		"level_id": test_id,
		"level_starting_passengers": 3,
		"passengers": 3,
		"time_seconds": 20.0,
		"completed": true,
		"stars": 3,
	})
	var post := {"ok": false, "result": {}}
	CommunityService.upload_level(test_id, "广场测试关卡", func(result: Dictionary) -> void:
		post["ok"] = bool(result.get("ok", false))
		post["result"] = result
	)
	_check(bool(post["ok"]), "通关后的自制关卡可上传广场")
	var entry: Dictionary = (post["result"] as Dictionary).get("entry", {})
	var entry_id := str(entry.get("id", ""))
	_check(not entry_id.is_empty(), "广场关卡生成唯一 id")
	# 重复上传必须被本地状态锁拒绝：上传成功已回写 server_id，再传同一关应直接失败。
	# 这是「重复上传 bug」已修复的自动化证据，无需真机通关重启即可验证。
	var repost := {"ok": true, "error": ""}
	CommunityService.upload_level(test_id, "广场测试关卡", func(result: Dictionary) -> void:
		repost["ok"] = bool(result.get("ok", false))
		repost["error"] = str(result.get("error", ""))
	)
	_check(not repost["ok"], "已上传关卡重复上传被拒绝")
	_check(str(repost["error"]).contains("已上传"), "重复上传返回已上传提示")
	var feed := {"entries": []}
	CommunityService.fetch_feed("latest", func(result: Dictionary) -> void:
		feed["entries"] = result.get("entries", [])
	)
	_check((feed["entries"] as Array).size() == 1, "广场最新列表包含上传关卡")
	var liked := CommunityService.toggle_like(entry_id)
	_check(bool(liked.get("ok", false)) and int(liked.get("likes", 0)) == 1, "广场点赞成功")
	CommunityService.submit_score(entry_id, 3, 18.5, true)
	var ranked := CommunityService.get_entry(entry_id)
	_check((ranked.get("scores", []) as Array).size() == 1, "广场关卡有独立排行榜")
	var plaza_scene := (load("res://scenes/ui/plaza.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(plaza_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var grid := plaza_scene.get_node("%CardGrid") as GridContainer
	_check(grid.get_child_count() > 0, "广场界面渲染关卡卡片")
	_check(grid.columns == 3, "广场在 1280 宽下自动排成三列")
	plaza_scene.call("_on_like_pressed", entry_id)
	await get_tree().process_frame
	var card_refs: Dictionary = (plaza_scene.get("_card_refs_by_id") as Dictionary).get(entry_id, {})
	_check(card_refs.get("likes") is Label, "点赞后卡片引用仍是 Label 而不是关卡摘要")
	var likes_label: Label = card_refs.get("likes") as Label
	_check(likes_label != null and likes_label.get_parent() is VBoxContainer, "点赞数量回到作者下方")
	_check((card_refs.get("best") as Label).text.begins_with("最佳通关"), "通关记录文案改为最佳通关")
	var first_card := grid.get_child(0) as Control
	var has_description := false
	var difficulty_text := ""
	for label in first_card.find_children("*", "Label", true, false):
		var text := (label as Label).text
		if text.begins_with("关卡简介"):
			has_description = true
		if text.length() == 5 and (text.contains("●") or text.contains("○")) and not text.contains("难度"):
			difficulty_text = text
	_check(not has_description, "广场卡片不再显示关卡简介")
	_check(difficulty_text.length() == 5, "广场卡片标题旁显示五个难度圆点")
	var card_has_withdraw := false
	for button in (grid.get_child(0) as Control).find_children("*", "Button", true, false):
		if (button as Button).text == "撤销上传":
			card_has_withdraw = true
	_check(not card_has_withdraw, "广场卡片不再显示撤销上传按钮")
	# 上传弹窗里已上传关卡应提供可点击的“撤销上传”，点击后出现二次确认。
	plaza_scene.call("_open_upload_dialog")
	await get_tree().process_frame
	var upload_panel: Control = plaza_scene.get("_upload_panel") as Control
	var withdraw_button: Button = null
	if upload_panel != null:
		for button in upload_panel.find_children("*", "Button", true, false):
			if (button as Button).text == "撤销上传":
				withdraw_button = button as Button
	_check(withdraw_button != null and not withdraw_button.disabled, "上传弹窗的已上传项可点击撤销")
	if withdraw_button != null:
		withdraw_button.pressed.emit()
		await get_tree().process_frame
		_check(plaza_scene.get("_withdraw_panel") != null, "撤销上传先弹出二次确认")
		plaza_scene.call("_withdraw_upload_confirmed", entry_id)
		await get_tree().process_frame
		await get_tree().create_timer(0.3).timeout
		_check(CommunityService.get_entry(entry_id).is_empty(), "确认后关卡从广场撤销")
	# 撤销后重新打开上传弹窗：上传成功时按钮应原地变成“撤销上传”，而不是禁用“已上传”。
	plaza_scene.call("_open_upload_dialog")
	await get_tree().process_frame
	var upload_panel_again: Control = plaza_scene.get("_upload_panel") as Control
	var upload_again: Button = null
	if upload_panel_again != null:
		for button in upload_panel_again.find_children("*", "Button", true, false):
			if (button as Button).text == "上传":
				upload_again = button as Button
	_check(upload_again != null and not upload_again.disabled, "撤销后可重新上传")
	if upload_again != null:
		upload_again.pressed.emit()
		await get_tree().process_frame
		_check(upload_again.text == "撤销上传" and not upload_again.disabled, "上传成功后按钮原地变为撤销上传")
	plaza_scene.call("_close_upload_dialog")
	await get_tree().process_frame
	plaza_scene.queue_free()
	await get_tree().process_frame
	CommunityService.clear_all()
	LevelCatalog.delete_user_level(test_id)


func _test_ugc_reclear() -> void:
	print("\n[广场] 修改后的自制关卡需要重新通关")
	CommunityService.clear_all()
	var raw := LevelCatalog.get_raw_level("level_01")
	var data: Dictionary = (raw.get("data", {}) as Dictionary).duplicate(true)
	data["id"] = "custom_reclear_test"
	data["name"] = "重传测试"
	data["custom"] = true
	data["source"] = "user"
	var saved := LevelCatalog.save_user_level(data)
	var level_id := str(saved.get("id", "custom_reclear_test"))
	_check(bool(saved.get("ok", false)), "重传测试关卡保存成功")
	SaveManager.record_result({
		"level_id": level_id,
		"level_starting_passengers": 3,
		"passengers": 3,
		"time_seconds": 12.0,
		"completed": true,
		"stars": 3,
	})
	var first := {"ok": false, "entry": {}}
	CommunityService.upload_level(level_id, "重传测试", func(result: Dictionary) -> void:
		first["ok"] = bool(result.get("ok", false))
		first["entry"] = result.get("entry", {})
	)
	_check(bool(first["ok"]), "修改前可正常上传")
	var entry_id := str((first["entry"] as Dictionary).get("id", ""))
	var modified := data.duplicate(true)
	modified["name"] = "重传测试-修改"
	LevelCatalog.save_user_level(modified)
	_check(LevelRepository.needs_reclear(level_id), "上传后修改会标记为需重新通关")
	if not entry_id.is_empty():
		CommunityService.withdraw_entry(entry_id, func(_result: Dictionary) -> void: pass)
	var retry := {"ok": true, "error": ""}
	CommunityService.upload_level(level_id, "重传测试-修改", func(result: Dictionary) -> void:
		retry["ok"] = bool(result.get("ok", false))
		retry["error"] = str(result.get("error", ""))
	)
	_check(not bool(retry["ok"]) and str(retry["error"]).contains("重新通关"), "修改后撤销上传不能立即重传")
	SaveManager.record_result({
		"level_id": level_id,
		"level_starting_passengers": 3,
		"passengers": 3,
		"time_seconds": 11.0,
		"completed": true,
		"stars": 3,
	})
	_check(not LevelRepository.needs_reclear(level_id), "重新通关后解除重传限制")
	var second := {"ok": false, "entry": {}}
	CommunityService.upload_level(level_id, "重传测试-修改", func(result: Dictionary) -> void:
		second["ok"] = bool(result.get("ok", false))
		second["entry"] = result.get("entry", {})
	)
	_check(bool(second["ok"]), "重新通关后可以再次上传")
	var second_id := str((second["entry"] as Dictionary).get("id", ""))
	if not second_id.is_empty():
		CommunityService.withdraw_entry(second_id, func(_result: Dictionary) -> void: pass)
	CommunityService.clear_all()
	LevelCatalog.delete_user_level(level_id)


func _test_plaza_pagination() -> void:
	print("\n[广场] 数百张关卡的分页加载")
	CommunityService.clear_all()
	for index in 26:
		CommunityService._entries.append({
			"id": "page_%02d" % index,
			"level_id": "page_%02d" % index,
			"name": "分页关卡 %d" % index,
			"author": "分页测试",
			"author_id": "local_player",
			"description": "",
			"likes": 0,
			"plays": 0,
			"clears": 0,
			"created_at": index,
			"review_status": "approved",
			"scores": [],
		})
	var first := {"entries": [], "total": 0, "has_more": false}
	CommunityService.fetch_feed("latest", func(result: Dictionary) -> void:
		first["entries"] = result.get("entries", [])
		first["total"] = result.get("total", 0)
		first["has_more"] = result.get("has_more", false)
	)
	_check((first["entries"] as Array).size() == CommunityService.PAGE_SIZE, "广场首批只加载一页，不一次性创建数百张卡片")
	_check(int(first["total"]) == 26 and bool(first["has_more"]), "广场返回总数与下一页标记")
	var second := {"entries": [], "has_more": true}
	CommunityService.fetch_feed_page("latest", 2, func(result: Dictionary) -> void:
		second["entries"] = result.get("entries", [])
		second["has_more"] = result.get("has_more", true)
	)
	_check((second["entries"] as Array).size() == 26 - CommunityService.PAGE_SIZE, "第二页只加载剩余关卡")
	_check(not bool(second["has_more"]), "最后一页不再显示加载更多")
	_check(CommunityService._entries.size() == 26, "分页追加后仍可按 id 查找已加载关卡")
	CommunityService.clear_all()
	# 最热必须按点赞优先，而不是播放量。
	for index in 3:
		CommunityService._entries.append({
			"id": "hot_%d" % index,
			"name": "热度 %d" % index,
			"author": "排序测试",
			"author_id": "local_player",
			"likes": [4, 0, 2][index],
			"plays": [0, 99, 10][index],
			"clears": 0,
			"created_at": index,
			"review_status": "approved",
			"scores": [],
		})
	var hot_result := {"entries": []}
	CommunityService.fetch_feed("hot", func(result: Dictionary) -> void:
		hot_result["entries"] = result.get("entries", [])
	)
	var hot_entries: Array = hot_result["entries"]
	_check(
		not hot_entries.is_empty() and str((hot_entries[0] as Dictionary).get("id", "")) == "hot_0",
		"最热排序优先按点赞量"
	)
	CommunityService.clear_all()


func _test_touch_priority_and_telemetry_batching() -> void:
	print("\n[性能/输入] 多指方向优先级与遥测批量落盘")
	var controls := TouchControls.new()
	get_tree().root.add_child(controls)
	controls.configure("solo")
	await get_tree().process_frame
	await get_tree().process_frame
	var pads := controls._buttons
	_check(pads.size() == 2, "单人虚拟按键使用两个独立触控板")
	var left_pos := pads[0].get_global_rect().get_center()
	var right_pos := pads[1].get_global_rect().get_center()
	controls._on_pointer_down(0, left_pos)
	_check(controls.get_active_action("solo") == "move_left", "按下左键后左方向生效")
	controls._on_pointer_down(1, right_pos)
	_check(controls.get_active_action("solo") == "move_right", "按住左键时再按右键，右键后按优先")
	_check(not Input.is_action_pressed("move_left") and Input.is_action_pressed("move_right"), "后按方向会释放上一方向，不产生轴抵消")
	controls._on_pointer_up(1)
	_check(controls.get_active_action("solo") == "", "松开当前右键后停止移动")
	controls._on_pointer_down(2, right_pos)
	controls._on_pointer_down(0, left_pos)
	_check(controls.get_active_action("solo") == "move_left", "再次按下左键会顶掉仍按住的右键")
	controls._on_pointer_up(0)
	_check(controls.get_active_action("solo") == "", "松开被顶掉的左键不会误恢复右键")
	controls._release_all()
	controls.queue_free()
	await get_tree().process_frame

	var temp_path := "user://analytics/test_batched_telemetry.jsonl"
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_path)
	var backend := LocalTelemetryBackend.new(temp_path)
	var queued := {"ok": false, "queued": false}
	backend.append_event({"type": "run_end", "value": 1}, func(result: Dictionary) -> void:
		queued["ok"] = bool(result.get("ok", false))
		queued["queued"] = bool(result.get("queued", false))
	)
	_check(bool(queued["queued"]) and backend.has_pending(), "遥测事件先进入内存队列")
	_check(not FileAccess.file_exists(temp_path), "碰撞事件不再同步创建/写入 JSONL 文件")
	var flushed := backend.flush_pending()
	_check(bool(flushed.get("ok", false)) and int(flushed.get("flushed", 0)) == 1, "批量落盘一次写入队列内事件")
	var loaded := {"done": false, "count": 0}
	backend.load_events(func(result: Dictionary) -> void:
		loaded["done"] = true
		loaded["count"] = (result.get("events", []) as Array).size()
	)
	_check(bool(loaded["done"]) and int(loaded["count"]) == 1, "落盘后分析服务可立即读取")
	for index in 3:
		backend.append_event({"type": "collision", "index": index}, func(_result: Dictionary) -> void: pass)
	var chunk := backend.flush_pending_chunk(2)
	_check(int(chunk.get("flushed", 0)) == 2 and int(chunk.get("remaining", 0)) == 1, "黑屏过渡按每帧 2 行分批落盘")
	backend.flush_pending()
	backend.clear_events(func(_result: Dictionary) -> void: pass)


func _test_cart_and_gate_visuals() -> void:
	print("\n[外观] 车轮层级、缆车预览调色与起终点朝向")
	var cart := (load("res://scenes/carts/dove.tscn") as PackedScene).instantiate() as CoasterController
	get_tree().root.add_child(cart)
	await get_tree().process_frame
	var wheel_layer := cart.get_node_or_null("WheelLayer") as CartWheelLayer
	_check(wheel_layer != null and wheel_layer.z_index == -1, "车轮层独立且位于 BGSprite/乘客之下")
	cart.wheel_count = 4
	_check(cart._wheel_positions(Vector2.RIGHT).size() == 4, "车轮数量支持 4 个")
	cart.wheel_count = 1
	_check(cart._wheel_positions(Vector2.RIGHT).size() == 1, "车轮数量支持 1 个")
	cart.queue_free()
	await get_tree().process_frame

	var genius := CartCatalog.get_profile("genius")
	_check(genius != null and not genius.background_modulate.is_equal_approx(Color.WHITE), "预览档案携带 BGSprite modulate")
	var left_level := LevelData.from_dictionary({
		"schema_version": 2,
		"id": "test_left_gate",
		"name": "左向测试",
		"track": {
			"start_angle_deg": 180.0,
			"pieces": [{"type": "straight", "length": 600.0, "direction": 1}],
			"start_s": 100.0,
			"finish_s": 500.0,
		},
		"obstacles": [],
		"theme": {},
	})
	var start_gate := (load("res://scenes/game/start_gate.tscn") as PackedScene).instantiate() as StartGate
	get_tree().root.add_child(start_gate)
	start_gate.configure(left_level)
	_check(start_gate.is_facing_left() and start_gate.scale.x < 0.0, "左向轨道镜像翻转起点纹理")
	_check((start_gate.get_node("CartStart") as Node2D).position.x < 0.0, "左向起点 CartStart 同步镜像")
	var left_cart_s := left_level.track.nearest_s(start_gate.get_cart_start_global_position())
	_check(left_cart_s > left_level.start_s + 100.0, "镜像后 CartStart 仍位于轨道前进方向")
	start_gate.queue_free()
	var finish_gate := (load("res://scenes/game/finish_gate.tscn") as PackedScene).instantiate() as FinishGate
	get_tree().root.add_child(finish_gate)
	finish_gate.configure(left_level)
	_check(finish_gate.is_facing_left() and finish_gate.scale.x < 0.0, "左向轨道镜像翻转终点纹理")
	finish_gate.queue_free()
	await get_tree().process_frame

	# 反向关卡：finish_s < start_s，实际行车方向是 -s，必须按“起点 -> 终点”翻转，
	# 不能只看几何切线，否则站台和 CartStart 会整个反 180°。
	var reverse_level := LevelData.from_dictionary({
		"schema_version": 2,
		"id": "test_reverse_gate",
		"name": "反向测试",
		"track": {
			"start_angle_deg": 0.0,
			"pieces": [{"type": "straight", "length": 600.0, "direction": 1}],
			"start_s": 500.0,
			"finish_s": 100.0,
		},
		"obstacles": [],
		"theme": {},
	})
	var reverse_start := (load("res://scenes/game/start_gate.tscn") as PackedScene).instantiate() as StartGate
	get_tree().root.add_child(reverse_start)
	reverse_start.configure(reverse_level)
	_check(reverse_start.is_facing_left() and reverse_start.scale.x < 0.0, "反向关卡起点按实际行车方向翻转纹理")
	var reverse_cart_s := reverse_level.track.nearest_s(reverse_start.get_cart_start_global_position())
	_check(reverse_cart_s < reverse_level.start_s - 100.0, "反向关卡 CartStart 朝向终点一侧")
	reverse_start.queue_free()
	var reverse_finish := (load("res://scenes/game/finish_gate.tscn") as PackedScene).instantiate() as FinishGate
	get_tree().root.add_child(reverse_finish)
	reverse_finish.configure(reverse_level)
	_check(reverse_finish.is_facing_left() and reverse_finish.scale.x < 0.0, "反向关卡终点按实际行车方向翻转纹理")
	reverse_finish.queue_free()
	await get_tree().process_frame


func _test_ui_bindings() -> void:
	print("\n[UI] 选关、排行榜、结算")
	GameSession.set_mode(GameSession.MODE_SOLO)
	_check(not DeveloperService.unlock("wrong-password"), "错误开发者密码被拒绝")
	_check(DeveloperService.unlock(DeveloperService.PASSWORD), "密码可解锁")
	DeveloperService.lock()
	_check(CartCatalog.get_all().size() >= 3, "缆车目录至少包含三种缆车")
	var fish_scene := load("res://scenes/carts/fish.tscn") as PackedScene
	var fish_cart: CoasterController = null
	if fish_scene != null:
		fish_cart = fish_scene.instantiate() as CoasterController
	_check(fish_cart != null and fish_cart.starting_passengers == 5 and fish_cart.max_passengers >= fish_cart.starting_passengers, "大肥鱼开局 5 位乘客")
	if fish_cart != null:
		fish_cart.free()
	var woma_scene := load("res://scenes/carts/woma.tscn") as PackedScene
	var woma_cart: CoasterController = null
	if woma_scene != null:
		woma_cart = woma_scene.instantiate() as CoasterController
	_check(woma_cart != null and woma_cart.evade_chance > 0.0, "小沃玛拥有免疫概率")
	if woma_cart != null:
		woma_cart.free()
	var dragon := (load("res://scenes/carts/dragon.tscn") as PackedScene).instantiate() as CoasterController
	_check(dragon != null and dragon.armor_enabled and not dragon.dash_enabled, "小奶龙拥有护甲")
	if dragon != null:
		dragon.queue_free()
	var tori := (load("res://scenes/carts/tori.tscn") as PackedScene).instantiate() as CoasterController
	_check(tori != null and tori.dash_enabled and not tori.armor_enabled, "小托莉拥有冲刺")
	if tori != null:
		tori.queue_free()
	var custom_card := (load("res://scenes/ui/level_card.tscn") as PackedScene).instantiate() as LevelCard
	get_tree().root.add_child(custom_card)
	custom_card.setup({
		"id": "custom_card_test",
		"name": "自制卡片测试",
		"subtitle": "不应显示的简介",
		"custom": true,
		"difficulty": 3,
	}, {}, 0, 0, false)
	await get_tree().process_frame
	_check(not custom_card.subtitle_label.visible, "自制关卡卡片隐藏简介")
	custom_card.queue_free()
	await get_tree().process_frame

	var level_select := (load("res://scenes/ui/level_select.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(level_select)
	await get_tree().process_frame
	await get_tree().process_frame
	var grid := level_select.get_node("%Grid") as GridContainer
	_check(grid.get_child_count() == LevelCatalog.get_builtin_count(), "选关界面只生成主线关卡卡片")
	var card: LevelCard = null
	for child in grid.get_children():
		if child is LevelCard and (child as LevelCard).level_id == "level_01":
			card = child as LevelCard
	_check(card != null, "选关界面找到 level_01")
	if card != null:
		_check(card.get_best_text().contains("丢 0 人"), "选关卡片展示本地最佳成绩")
	level_select.queue_free()
	await get_tree().process_frame
	# 广场关卡不在 LevelCatalog 中：结算页必须从本局下载数据取主题，不能查本地目录。
	var old_authored := GameSession.authored_level_data
	var old_selected := GameSession.selected_level_id
	var old_community := GameSession.community_entry_id
	var ugc_raw := LevelCatalog.get_raw_level("level_01")
	var ugc_data: Dictionary = (ugc_raw.get("data", {}) as Dictionary).duplicate(true)
	ugc_data["id"] = "ugc_missing_from_catalog"
	ugc_data["custom"] = true
	GameSession.authored_level_data = ugc_data
	GameSession.selected_level_id = "ugc_missing_from_catalog"
	GameSession.community_entry_id = "ugc_missing_from_catalog"
	var result_preview := (load("res://scenes/ui/result.tscn") as PackedScene).instantiate()
	result_preview.set("_level_id", "ugc_missing_from_catalog")
	var resolved_level: LevelData = result_preview.call("_resolve_level")
	_check(resolved_level != null and resolved_level.id == "ugc_missing_from_catalog", "结算页优先使用下载的 UGC 数据而不查本地目录")
	result_preview.free()
	GameSession.authored_level_data = old_authored
	GameSession.selected_level_id = old_selected
	GameSession.community_entry_id = old_community

	var touch_controls := TouchControls.new()
	get_tree().root.add_child(touch_controls)
	touch_controls.configure("duo")
	await get_tree().process_frame
	_check(touch_controls.get_child_count() >= 4, "双人虚拟按键创建两组按钮")
	touch_controls.queue_free()
	await get_tree().process_frame

	GameSession.selected_level_id = "level_01"
	var leaderboard := (load("res://scenes/ui/leaderboard.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(leaderboard)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(leaderboard.get_displayed_row_count() > 0, "排行榜界面渲染数据")
	_check(leaderboard.has_local_entry(), "排行榜高亮本地成绩")
	leaderboard.queue_free()
	await get_tree().process_frame

	# 模拟普通 Web（itch.io）：只读广场、无上传按钮、无虚拟按键。
	var old_web := PlatformConfig.is_web
	var old_wechat := PlatformConfig.is_wechat
	var old_upload := PlatformConfig.can_upload_ugc
	PlatformConfig.is_web = true
	PlatformConfig.is_wechat = false
	PlatformConfig.is_douyin = false
	PlatformConfig.can_upload_ugc = false
	var web_plaza := (load("res://scenes/ui/plaza.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(web_plaza)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not (web_plaza.get_node("%UploadButton") as Button).visible, "普通 Web 隐藏上传到广场按钮")
	_check(not TouchControls.is_touch_device(), "普通 Web 不创建虚拟按键")
	web_plaza.queue_free()
	await get_tree().process_frame
	PlatformConfig.is_web = old_web
	PlatformConfig.is_wechat = old_wechat
	PlatformConfig.can_upload_ugc = old_upload

	# Camera2D 在物理插值开启时必须显式使用物理帧，否则每次切场景都会打印覆盖警告。
	var game_instance := (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	var game_camera := game_instance.get_node("Camera2D") as Camera2D
	_check(game_camera.process_callback == Camera2D.CAMERA2D_PROCESS_PHYSICS, "游戏相机使用物理帧回调")
	game_instance.free()
	var editor_instance := (load("res://scenes/editor/level_editor.tscn") as PackedScene).instantiate()
	var editor_camera := editor_instance.get_node("Camera2D") as Camera2D
	_check(editor_camera.process_callback == Camera2D.CAMERA2D_PROCESS_PHYSICS, "工坊相机使用物理帧回调")
	editor_instance.free()

	# 触摸滚动：松手后速度应衰减但继续位移，而不是立刻停住。
	var touch_scroll := ScrollContainer.new()
	touch_scroll.set_script(load("res://scripts/ui/touch_scroll.gd"))
	touch_scroll.size = Vector2(420, 300)
	touch_scroll.position = Vector2(40, 40)
	get_tree().root.add_child(touch_scroll)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(400, 1800)
	touch_scroll.add_child(spacer)
	await get_tree().process_frame
	await get_tree().process_frame
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = touch_scroll.get_global_rect().get_center()
	press.pressed = true
	touch_scroll._input(press)
	for index in 5:
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = press.position + Vector2(0, -30.0 * float(index + 1))
		drag.relative = Vector2(0, -30)
		drag.velocity = Vector2(0, -700)
		touch_scroll._input(drag)
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = press.position + Vector2(0, -150)
	release.pressed = false
	touch_scroll._input(release)
	_check(bool(touch_scroll.get("_inertia_active")), "触摸松手后进入惯性滚动")
	var scroll_before := touch_scroll.scroll_vertical
	await get_tree().create_timer(0.25).timeout
	_check(touch_scroll.scroll_vertical > scroll_before, "惯性使列表继续滚动")
	_check((touch_scroll.get("_velocity") as Vector2).length() < 700.0, "阻尼让滚动速度逐渐衰减")
	touch_scroll.queue_free()
	await get_tree().process_frame

	var cleanup := LocalFileStorage.new()
	cleanup.delete_profile("test_runner", func(_result: Dictionary) -> void: pass)


class FakeWxStore:
	var data: Dictionary = {}

	func getStorageSync(key: String) -> Variant:
		return data.get(key, "")

	func setStorageSync(key: String, value: Variant) -> void:
		data[key] = value

	func removeStorageSync(key: String) -> void:
		data.erase(key)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  ✓ ", description)
	else:
		_failures.append(description)
		print("  ✗ ", description)

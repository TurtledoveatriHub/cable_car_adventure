extends Node
## 开发期截图工具。仅当命令行传入 `--capture <name>` 时运行。
## 示例：Godot_v4.5.1-stable_win64_console.exe --path . -- --capture menu

const OUTPUT_DIR := "res://.screenshots"

var _target: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--capture")
	if index < 0 or index + 1 >= args.size():
		return
	call_deferred("_run_capture", args[index + 1])


func _run_capture(capture_name: String) -> void:
	CommunityService.set_offline_mode(true)
	TelemetryService.set_remote_enabled(false)
	# 启动动画是 CanvasLayer 100 的全屏覆盖层；截图必须等它结束或主动隐藏，
	# 否则会把开场画面叠在 UI 截图上。
	BootCutscene.enabled = false
	BootCutscene.hide()
	await get_tree().process_frame
	await get_tree().process_frame
	var current := get_tree().current_scene
	# 直接在 tools/screenshot_agent.tscn 里运行时，current_scene 就是本节点；
	# 换一个空宿主作为 current_scene，后续流程截图切场景时才不会把截图器自己释放掉。
	if current == self:
		var host := Node.new()
		host.name = "ScreenshotHost"
		get_tree().root.add_child(host)
		get_tree().current_scene = host
		current = host
	if current != null:
		current.queue_free()
		await get_tree().process_frame

	match capture_name:
		"menu":
			await _capture_simple("res://scenes/ui/main_menu.tscn", "01_main_menu.png", 1.2)
		"settings":
			await _capture_settings()
		"pause":
			await _capture_pause()
		"dialog_unsaved":
			await _capture_dialog("unsaved")
		"dialog_delete":
			await _capture_dialog("delete")
		"levels":
			await _capture_simple("res://scenes/ui/level_select.tscn", "02_level_select.png", 1.0)
		"levels_duo":
			GameSession.set_mode(GameSession.MODE_DUO)
			GameSession.duo_split = GameSession.SPLIT_SIDE_BY_SIDE
			await _capture_simple("res://scenes/ui/level_select.tscn", "10_level_select_duo.png", 1.0)
		"editor":
			await _capture_simple("res://scenes/editor/level_editor.tscn", "03_level_editor.png", 1.4)
		"editor_preview":
			await _capture_editor_preview()
		"editor_obstacle":
			await _capture_editor_obstacle()
		"leaderboard":
			GameSession.selected_level_id = "level_01"
			await _capture_simple("res://scenes/ui/leaderboard.tscn", "04_leaderboard.png", 1.0)
		"game":
			await _capture_game("level_03", "05_game_loop.png")
		"duo_result":
			GameSession.set_mode(GameSession.MODE_DUO)
			GameSession.last_result = {
				"mode": GameSession.MODE_DUO,
				"level_id": "level_02",
				"level_name": "云端回环",
				"level_subtitle": "第一次竖直环圈",
				"completed": true,
				"failed": false,
				"players": [
					{"slot": 0, "name": "玩家 1", "passengers": 4, "time_seconds": 58.30, "completed": true, "failed": false, "stars": 3},
					{"slot": 1, "name": "玩家 2", "passengers": 3, "time_seconds": 63.82, "completed": true, "failed": false, "stars": 2},
				],
				"winner_slot": 0,
				"save_info": {},
				"level_starting_passengers": 4,
				"is_new_best": false,
			}
			await _capture_simple("res://scenes/ui/result.tscn", "13_duo_result.png", 1.2)
		"result":
			SaveManager.set_storage_backend(LocalFileStorage.new(), "screenshot_demo")
			await get_tree().process_frame
			SaveManager.reset_progress()
			SaveManager.record_result({
				"level_id": "level_02",
				"level_starting_passengers": 4,
				"passengers": 3,
				"time_seconds": 67.42,
				"completed": true,
				"stars": 2,
			})
			var result := {
				"mode": GameSession.MODE_SOLO,
				"level_id": "level_02",
				"level_name": "云端回环",
				"level_subtitle": "第一次竖直环圈",
				"completed": true,
				"failed": false,
				"players": [{
					"slot": 0,
					"name": "玩家 1",
					"passengers": 3,
					"time_seconds": 67.42,
					"completed": true,
					"failed": false,
					"stars": 2,
				}],
				"winner_slot": 0,
				"save_info": {"is_new_best": true},
				"level_starting_passengers": 4,
				"is_new_best": true,
			}
			GameSession.test_from_editor = false
			GameSession.last_result = result
			await _capture_simple("res://scenes/ui/result.tscn", "07_result_solo.png", 1.2)
		"duo":
			await _capture_duo(GameSession.SPLIT_SIDE_BY_SIDE, "11_duo_side_by_side.png")
		"duo_stacked":
			await _capture_duo(GameSession.SPLIT_STACKED, "12_duo_stacked.png")
		"plaza":
			await _capture_plaza()
		"analytics":
			await _capture_analytics()
		"flow_result":
			await _capture_flow_result()
		_:
			push_error("未知截图目标：%s" % capture_name)
			get_tree().quit(1)
			return

	# 先停音频、释放截图目标并等待物理 / 渲染线程清空，避免部分驱动在退出时崩溃。
	AudioDirector.shutdown()
	if is_instance_valid(_target):
		_target.queue_free()
		_target = null
	await get_tree().process_frame
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	get_tree().quit(0)


func _capture_pause() -> void:
	GameSession.start_level("level_01", GameSession.MODE_SOLO)
	await get_tree().create_timer(2.0).timeout
	var game := get_tree().current_scene
	if game != null:
		var hud: Node = game.get("hud") as Node
		if hud != null:
			game.set("paused", true)
			hud.call("set_paused", true)
			await get_tree().create_timer(0.4).timeout
			await _save_screenshot("20_pause.png")


func _capture_dialog(kind: String) -> void:
	_target = (load("res://scenes/editor/level_editor.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_target)
	await get_tree().create_timer(0.8).timeout
	if kind == "delete":
		var draft: Dictionary = _target.get("_draft")
		draft["id"] = "custom_dialog_preview"
		_target.call("_on_delete_level_pressed")
		await get_tree().create_timer(0.4).timeout
		await _save_screenshot("18_delete_dialog.png")
	else:
		_target.call("_show_unsaved_dialog")
		await get_tree().create_timer(0.4).timeout
		await _save_screenshot("19_unsaved_dialog.png")


func _capture_settings() -> void:
	_target = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_target)
	await get_tree().create_timer(0.6).timeout
	_target.call("_show_settings_dialog")
	await get_tree().create_timer(0.5).timeout
	await _save_screenshot("17_settings.png")


func _capture_simple(scene_path: String, file_name: String, wait_seconds: float) -> void:
	var packed := load(scene_path) as PackedScene
	_target = packed.instantiate()
	if _target is Control:
		(_target as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(_target)
	await get_tree().create_timer(wait_seconds).timeout
	await _save_screenshot(file_name)


func _capture_editor_preview() -> void:
	var packed := load("res://scenes/editor/level_editor.tscn") as PackedScene
	_target = packed.instantiate()
	get_tree().root.add_child(_target)
	await get_tree().process_frame
	await get_tree().process_frame
	var editor := _target
	editor.call("_start_track_placement", "curve45")
	var level: LevelData = editor.get("_level")
	if level != null and level.track != null:
		editor.set("_mouse_world", level.track.sample_at(level.track.total_length) + Vector2(-320, 160))
	editor.call("_update_overlay")
	await get_tree().create_timer(0.6).timeout
	await _save_screenshot("15_editor_preview.png")


func _capture_editor_obstacle() -> void:
	var packed := load("res://scenes/editor/level_editor.tscn") as PackedScene
	_target = packed.instantiate()
	get_tree().root.add_child(_target)
	await get_tree().process_frame
	await get_tree().process_frame
	var editor := _target
	var level: LevelData = editor.get("_level")
	var point := Vector2(400, 250)
	if level != null and level.track != null:
		point = level.track.sample_at(level.track.total_length * 0.55) + Vector2(-40, -20)
	editor.call("_set_placement", "obstacle")
	editor.set("_mouse_world", point)
	editor.call("_place_at", point)
	await get_tree().create_timer(0.8).timeout
	await _save_screenshot("16_editor_obstacle.png")


func _capture_game(level_id: String, file_name: String) -> void:
	GameSession.selected_level_id = level_id
	GameSession.set_mode(GameSession.MODE_SOLO)
	var packed := load("res://scenes/game/game.tscn") as PackedScene
	_target = packed.instantiate()
	get_tree().root.add_child(_target)
	await get_tree().process_frame
	await get_tree().process_frame
	var game := _target as GameController
	game.debug_skip_countdown()
	var loop_s := _find_first_loop_start(game.level)
	if loop_s > 100.0:
		game.debug_set_s(loop_s - 70.0)
		if game.get_coaster() != null:
			game.get_coaster().current_speed = 330.0
	Input.action_press("move_right")
	await get_tree().create_timer(0.85).timeout
	Input.action_release("move_right")
	await get_tree().create_timer(0.15).timeout
	await _save_screenshot(file_name)


func _find_first_loop_start(level: LevelData) -> float:
	if level == null or level.track == null:
		return -1.0
	for index in level.track.pieces.size():
		if str(level.track.pieces[index].get("type", "")) == "loop":
			return level.track.get_piece_start_s(index)
	return -1.0


func _capture_duo(split: String, file_name: String) -> void:
	GameSession.selected_level_id = "level_01"
	GameSession.set_mode(GameSession.MODE_DUO)
	GameSession.duo_split = split
	GameSession.duo_show_ghost = true
	var packed := load("res://scenes/game/duo_game.tscn") as PackedScene
	_target = packed.instantiate()
	get_tree().root.add_child(_target)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(3.8).timeout
	if _target is DuoGameController:
		var duo := _target as DuoGameController
		duo.game1.debug_set_s(120.0)
		duo.game2.debug_set_s(430.0)
	await get_tree().create_timer(0.35).timeout
	await _save_screenshot(file_name)


func _capture_plaza() -> void:
	SaveManager.set_storage_backend(LocalFileStorage.new(), "screenshot_plaza")
	await get_tree().process_frame
	SaveManager.reset_progress()
	CommunityService.clear_all()
	var created_ids: Array[String] = []
	for index in 3:
		var raw := LevelCatalog.get_raw_level("level_0%d" % (index + 1))
		var data: Dictionary = (raw.get("data", {}) as Dictionary).duplicate(true)
		data["id"] = "custom_screenshot_%d" % (index + 1)
		data["name"] = ["云端小环线", "夜航试炼", "星夜飞车"][index]
		data["custom"] = true
		var saved := LevelCatalog.save_user_level(data)
		var level_id := str(saved.get("id", ""))
		created_ids.append(level_id)
		SaveManager.record_result({
			"level_id": level_id,
			"level_starting_passengers": 3,
			"passengers": 3,
			"time_seconds": 44.0 + index * 7.0,
			"completed": true,
			"stars": 3 - index,
		})
		CommunityService.upload_level(level_id, str(data.get("name", "")), func(_result: Dictionary) -> void: pass)
	await get_tree().process_frame
	await _capture_simple("res://scenes/ui/plaza.tscn", "14_plaza.png", 1.2)
	for level_id in created_ids:
		LevelCatalog.delete_user_level(level_id)
	CommunityService.clear_all()


func _capture_analytics() -> void:
	TelemetryService.set_backend(LocalTelemetryBackend.new("user://analytics/capture_events.jsonl"))
	await get_tree().process_frame
	TelemetryService.clear_events()
	var level := LevelCatalog.get_level("level_02")
	for index in 6:
		TelemetryService.begin_run(level, GameSession.MODE_SOLO, {"obstacle_speed_scale": 1.0, "engine_scale": 1.0})
		var collisions := index % 3 + 1
		for collision_index in collisions:
			TelemetryService.log_event("collision", {
				"level_id": "level_02",
				"obstacle_type": ["bird", "storm", "fan"][collision_index % 3],
				"motion_type": ["circle", "oscillate_x", "oscillate_y"][collision_index % 3],
				"obstacle_s": 500.0 + collision_index * 200.0,
				"s": 650.0 + collision_index * 180.0,
				"track_progress": 0.12 + index * 0.11,
				"speed": 160.0 + index * 18.0,
			})
		TelemetryService.end_run({
			"completed": index != 4,
			"passengers": maxi(0, 4 - collisions),
			"time_seconds": 58.0 + index * 3.7,
			"stars": maxi(0, 3 - collisions),
			"collisions": collisions,
			"progress": 1.0 if index != 4 else 0.55,
		})
	await get_tree().process_frame
	await _capture_simple("res://scenes/ui/analytics.tscn", "08_analytics.png", 1.2)
	TelemetryService.clear_events()


func _capture_flow_result() -> void:
	# 端到端流程：真实加载游戏场景 -> 触发通关 -> 由 SceneRouter 自动进入结算。
	SaveManager.set_storage_backend(LocalFileStorage.new(), "flow_demo")
	await get_tree().process_frame
	SaveManager.reset_progress()
	GameSession.selected_level_id = "level_02"
	GameSession.set_mode(GameSession.MODE_SOLO)
	GameSession.test_from_editor = false
	var error := get_tree().change_scene_to_file("res://scenes/game/game.tscn")
	if error != OK:
		push_error("流程截图无法加载游戏场景：%d" % error)
		get_tree().quit(1)
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var game := get_tree().current_scene as GameController
	if game == null:
		push_error("流程截图未找到 GameController")
		get_tree().quit(1)
		return
	game.debug_skip_countdown()
	await get_tree().create_timer(0.3).timeout
	game.debug_finish_run()
	await get_tree().create_timer(3.2).timeout
	var current_path := ""
	if get_tree().current_scene != null:
		current_path = get_tree().current_scene.scene_file_path
	if not current_path.ends_with("result.tscn"):
		push_error("端到端流程未进入结算场景，当前场景：%s" % current_path)
		get_tree().quit(1)
		return
	print("[Flow] 自动进入结算场景：%s" % current_path)
	await _save_screenshot("09_flow_result.png")


func _save_screenshot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var absolute_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var path := absolute_dir.path_join(file_name)
	var error := image.save_png(path)
	if error != OK:
		push_error("截图保存失败：%s（错误码 %d）" % [path, error])
	else:
		print("[Screenshot] %s  %dx%d" % [path, image.get_width(), image.get_height()])

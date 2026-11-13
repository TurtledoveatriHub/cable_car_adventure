extends CanvasLayer
## 全局场景路由：统一淡入淡出、场景路径和返回逻辑。
## UI 只调用语义方法（去选关、去游戏、去结算），不拼接资源路径。

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const LEVEL_SELECT := "res://scenes/ui/level_select.tscn"
const LEADERBOARD := "res://scenes/ui/leaderboard.tscn"
const GAME := "res://scenes/game/game.tscn"
const DUO_GAME := "res://scenes/game/duo_game.tscn"
const RESULT := "res://scenes/ui/result.tscn"
const EDITOR := "res://scenes/editor/level_editor.tscn"
const ANALYTICS := "res://scenes/ui/analytics.tscn"
const PLAZA := "res://scenes/ui/plaza.tscn"

var _overlay: ColorRect
var _loading_label: Label
var _transitioning: bool = false
var _loading_active: bool = false
var _loading_time: float = 0.0


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = ColorRect.new()
	_overlay.name = "TransitionOverlay"
	_overlay.color = Color(0.06, 0.12, 0.18, 1.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	_loading_label = Label.new()
	_loading_label.name = "TransitionLabel"
	_loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_label.theme = UITheme.theme
	_loading_label.add_theme_font_override("font", UITheme.heavy_font)
	_loading_label.add_theme_font_size_override("font_size", 20)
	_loading_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.72, 0.88))
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 固定在右下角，作为转场提示，不遮挡关卡结算/加载主体。
	_loading_label.anchor_left = 1.0
	_loading_label.anchor_top = 1.0
	_loading_label.anchor_right = 1.0
	_loading_label.anchor_bottom = 1.0
	_loading_label.offset_left = -300.0
	_loading_label.offset_top = -58.0
	_loading_label.offset_right = -22.0
	_loading_label.offset_bottom = -22.0
	_loading_label.modulate.a = 0.0
	add_child(_loading_label)
	_overlay.modulate.a = 1.0
	await _fade_overlay(0.0, 0.35)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	set_process(true)


func _process(delta: float) -> void:
	if not _loading_active:
		return
	_loading_time += delta
	_loading_label.text = "缆车进站中" + " .".repeat(1 + int(_loading_time * 3.0) % 3)
	_loading_label.modulate.a = 0.55 + 0.45 * absf(sin(_loading_time * 3.2))


func goto_menu() -> void:
	_change_scene(MAIN_MENU)


func goto_level_select(mode: String = "") -> void:
	if not mode.is_empty():
		GameSession.set_mode(mode)
	_change_scene(LEVEL_SELECT)


func goto_leaderboard() -> void:
	_change_scene(LEADERBOARD)


func goto_editor() -> void:
	_change_scene(EDITOR)


func goto_analytics() -> void:
	_change_scene(ANALYTICS)


func goto_plaza() -> void:
	_change_scene(PLAZA)


func goto_game() -> void:
	if GameSession.selected_level_id.is_empty() and GameSession.authored_level_data.is_empty():
		push_warning("[SceneRouter] 未选择关卡，返回选关界面")
		goto_level_select()
		return
	_change_scene(DUO_GAME if GameSession.is_duo() else GAME)


func goto_result() -> void:
	if GameSession.last_result.is_empty():
		push_warning("[SceneRouter] 没有本局结果，返回选关界面")
		goto_level_select()
		return
	_change_scene(RESULT)


func restart_current_level() -> void:
	goto_game()


func _change_scene(scene_path: String) -> void:
	if _transitioning:
		return
	if not ResourceLoader.exists(scene_path):
		push_error("[SceneRouter] 场景不存在：%s" % scene_path)
		return
	_transitioning = true
	_overlay.visible = true
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_active = true
	_loading_time = 0.0
	_loading_label.modulate.a = 0.0
	await _fade_overlay(1.0, 0.20)
	# 黑屏已经是完全不透明；在这段时间里分批落盘，并保留一个最小展示窗口。
	var black_start := Time.get_ticks_msec()
	get_tree().paused = false
	# 存档和遥测都藏在不透明黑屏后；遥测按 24 行一帧分批。
	SaveManager.flush_now()
	await TelemetryService.flush_pending_chunked(24)
	var remaining := 0.12 - float(Time.get_ticks_msec() - black_start) / 1000.0
	if remaining > 0.0:
		await get_tree().create_timer(remaining, true, false, true).timeout
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("[SceneRouter] 切换场景失败：%s（错误码 %d）" % [scene_path, error])
		_transitioning = false
		_loading_active = false
		_loading_label.modulate.a = 0.0
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		await _fade_overlay(0.0, 0.2)
		_overlay.visible = false
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await _fade_overlay(0.0, 0.3)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	_loading_active = false
	_loading_label.modulate.a = 0.0
	_transitioning = false


func _fade_overlay(target_alpha: float, duration: float) -> void:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_overlay, "modulate:a", target_alpha, duration)
	await tween.finished

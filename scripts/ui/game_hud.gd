class_name GameHUD
extends Control
## 游戏内 HUD。只接收 GameController 推送的数值，不读取存档、不加载关卡。
## 单人显示全局计时；双人显示两位玩家各自的乘客、用时与进度。

signal pause_requested
signal resume_requested
signal restart_requested
signal quit_requested

@onready var p1_card: PanelContainer = $TopMargin/TopRow/P1Card
@onready var p1_meter: PassengerMeter = $TopMargin/TopRow/P1Card/P1VBox/P1Meter
@onready var p1_time_label: Label = $TopMargin/TopRow/P1Card/P1VBox/P1TimeLabel
@onready var p1_progress: ProgressBar = $TopMargin/TopRow/P1Card/P1VBox/P1Progress

@onready var p2_card: PanelContainer = $TopMargin/TopRow/P2Card
@onready var p2_meter: PassengerMeter = $TopMargin/TopRow/P2Card/P2VBox/P2Meter
@onready var p2_time_label: Label = $TopMargin/TopRow/P2Card/P2VBox/P2TimeLabel
@onready var p2_progress: ProgressBar = $TopMargin/TopRow/P2Card/P2VBox/P2Progress

@onready var center_box: VBoxContainer = $TopMargin/TopRow/CenterBox
@onready var level_label: Label = $TopMargin/TopRow/CenterBox/LevelLabel

@onready var mute_button: Button = $TopMargin/TopRow/ActionBox/MuteButton
@onready var pause_button: Button = $TopMargin/TopRow/ActionBox/PauseButton

@onready var countdown_layer: Control = $CountdownLayer
@onready var countdown_label: Label = $CountdownLayer/CountdownCenter/CountdownVBox/CountdownLabel
@onready var countdown_sub: Label = $CountdownLayer/CountdownCenter/CountdownVBox/CountdownSub
@onready var toast_panel: PanelContainer = $ToastLayer/ToastCenter/ToastPanel
@onready var toast_label: Label = $ToastLayer/ToastCenter/ToastPanel/ToastLabel

@onready var pause_overlay: Control = $PauseOverlay
@onready var pause_card: PanelContainer = $PauseOverlay/PauseCenter/PauseCard
@onready var resume_button: Button = $PauseOverlay/PauseCenter/PauseCard/PauseVBox/ResumeButton
@onready var restart_button: Button = $PauseOverlay/PauseCenter/PauseCard/PauseVBox/RestartButton
@onready var quit_button: Button = $PauseOverlay/PauseCenter/PauseCard/PauseVBox/QuitButton

var _is_duo: bool = false
var _time_limit_seconds: float = 0.0
var _toast_tween: Tween
var _countdown_tween: Tween
var _level_title_tween: Tween
var _countdown_value: String = ""


func _ready() -> void:
	theme = UITheme.theme
	pause_overlay.theme = UITheme.theme
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mute_button.pressed.connect(_on_mute_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	pause_overlay.visible = false
	toast_panel.visible = false
	countdown_layer.visible = false
	quit_button.text = "退出试玩" if GameSession.test_from_editor else "返回选关"
	_update_mute_button()


func setup(level: LevelData, mode: String, starting_passengers: int = -1, max_passengers: int = -1) -> void:
	if starting_passengers < 0:
		starting_passengers = 3
	if max_passengers < 0:
		max_passengers = 6
	_is_duo = mode == GameSession.MODE_DUO
	_time_limit_seconds = level.time_limit_seconds
	p2_card.visible = _is_duo
	if _level_title_tween != null and _level_title_tween.is_valid():
		_level_title_tween.kill()
	level_label.modulate.a = 1.0
	level_label.visible = not _is_duo
	p1_meter.set_values(starting_passengers, max_passengers, false)
	p1_time_label.text = "00:00:00"
	p1_progress.value = 0.0
	p2_progress.value = 0.0

	if _is_duo:
		p2_meter.set_values(starting_passengers, max_passengers, false)
		p2_time_label.text = "00:00:00"
	else:
		level_label.text = level.name
		_level_title_tween = create_tween()
		_level_title_tween.tween_interval(3.0)
		_level_title_tween.tween_property(level_label, "modulate:a", 0.0, 0.6)
		_level_title_tween.tween_callback(func() -> void: level_label.visible = false)

	toast_panel.visible = false
	pause_overlay.visible = false

## 左右分屏时画面左右互换：HUD 卡片也必须跟着换边，文字才不会和玩家对不上。
func set_player_cards_swapped(swapped: bool) -> void:
	if not _is_duo:
		return
	var row := p1_card.get_parent()
	if row == null:
		return
	if swapped:
		row.move_child(p2_card, 0)
		row.move_child(center_box, 1)
	else:
		row.move_child(p1_card, 0)
		row.move_child(center_box, 1)


func _format_timer(seconds: float) -> String:
	var display_seconds := maxf(0.0, seconds)
	if _time_limit_seconds > 0.0:
		display_seconds = minf(display_seconds, _time_limit_seconds)
	var elapsed := ScoreRules.format_timer_clock(display_seconds)
	if _time_limit_seconds > 0.0:
		return "%s/%s" % [elapsed, ScoreRules.format_timer_clock(_time_limit_seconds)]
	return elapsed


func update_run(
	slot: int,
	passengers: int,
	max_passengers: int,
	time_seconds: float,
	progress: float,
	_status: String
) -> void:
	var progress_value := clampf(progress, 0.0, 1.0) * 100.0
	if slot == 0:
		p1_meter.set_values(passengers, max_passengers)
		p1_progress.value = progress_value
		p1_time_label.text = _format_timer(time_seconds)
	elif slot == 1:
		p2_meter.set_values(passengers, max_passengers)
		p2_progress.value = progress_value
		p2_time_label.text = _format_timer(time_seconds)


func show_countdown(text_value: String, subtitle: String = "") -> void:
	countdown_layer.visible = true
	countdown_label.text = text_value
	if not subtitle.is_empty():
		countdown_sub.text = subtitle
	if text_value == _countdown_value:
		return
	_countdown_value = text_value
	countdown_label.pivot_offset = countdown_label.size * 0.5
	countdown_label.scale = Vector2(1.35, 1.35)
	countdown_label.modulate.a = 0.25
	if _countdown_tween != null and _countdown_tween.is_valid():
		_countdown_tween.kill()
	_countdown_tween = create_tween().set_parallel(true)
	_countdown_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_countdown_tween.tween_property(countdown_label, "scale", Vector2.ONE, 0.28)
	_countdown_tween.tween_property(countdown_label, "modulate:a", 1.0, 0.16)
	if text_value == "GO!":
		countdown_label.add_theme_color_override("font_color", UITheme.COLOR_YELLOW)
	else:
		countdown_label.add_theme_color_override("font_color", UITheme.COLOR_CREAM)


func hide_countdown() -> void:
	_countdown_value = ""
	if _countdown_tween != null and _countdown_tween.is_valid():
		_countdown_tween.kill()
	_countdown_tween = create_tween()
	_countdown_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_countdown_tween.tween_property(countdown_layer, "modulate:a", 0.0, 0.25)
	await _countdown_tween.finished
	countdown_layer.visible = false
	countdown_layer.modulate.a = 1.0


func show_toast(text_value: String, color: Color = UITheme.COLOR_CREAM, duration: float = 1.2) -> void:
	toast_label.text = text_value
	toast_label.add_theme_color_override("font_color", color)
	toast_panel.visible = true
	toast_panel.modulate.a = 0.0
	toast_panel.scale = Vector2(0.9, 0.9)
	toast_panel.pivot_offset = toast_panel.size * 0.5
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_property(toast_panel, "modulate:a", 1.0, 0.12)
	_toast_tween.parallel().tween_property(toast_panel, "scale", Vector2.ONE, 0.22)
	_toast_tween.tween_interval(duration)
	_toast_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.22)
	_toast_tween.tween_callback(func() -> void: toast_panel.visible = false)


func set_paused(paused: bool) -> void:
	if paused:
		pause_overlay.visible = true
		UIJuice.popup_in(pause_card)
		resume_button.grab_focus()
	else:
		UIJuice.popup_out(pause_card, func() -> void:
			pause_overlay.visible = false
		)
		pause_button.release_focus()


func _on_mute_pressed() -> void:
	AudioDirector.play_click()
	AudioDirector.toggle_music()
	quit_button.text = "退出试玩" if GameSession.test_from_editor else "返回选关"
	_update_mute_button()


func _update_mute_button() -> void:
	mute_button.text = "♪" if AudioDirector.music_enabled else "×"
	mute_button.tooltip_text = "关闭音乐" if AudioDirector.music_enabled else "开启音乐"


func _on_pause_pressed() -> void:
	AudioDirector.play_click()
	pause_requested.emit()


func _on_resume_pressed() -> void:
	AudioDirector.play_click()
	resume_requested.emit()


func _on_restart_pressed() -> void:
	AudioDirector.play_click()
	_close_pause_then(func() -> void: restart_requested.emit())


func _on_quit_pressed() -> void:
	AudioDirector.play_click()
	_close_pause_then(func() -> void: quit_requested.emit())


func _close_pause_then(action: Callable) -> void:
	UIJuice.popup_out(pause_card, func() -> void:
		pause_overlay.visible = false
		action.call()
	)


func get_displayed_passengers(slot: int) -> int:
	var meter := p1_meter if slot == 0 else p2_meter
	return meter.count


func get_displayed_timer_text() -> String:
	return p1_time_label.text

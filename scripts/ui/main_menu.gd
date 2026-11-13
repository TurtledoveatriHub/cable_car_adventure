extends Control

const SETTINGS_DIALOG_SCENE := preload("res://scenes/ui/settings_dialog.tscn")
## 主菜单：进入单人 / 关卡工坊 / 排行榜 / 个人主页 / 操作说明。
## 只读取 SaveManager 缓存与 LevelCatalog 摘要，不直接读取任何文件。

@onready var solo_button: Button = %SoloButton
@onready var duo_button: Button = %DuoButton
@onready var editor_button: Button = %EditorButton
@onready var leaderboard_button: Button = %LeaderboardButton
@onready var analytics_button: Button = %AnalyticsButton
@onready var howto_button: Button = %HowToButton
@onready var info_overlay: Control = %InfoOverlay
@onready var info_panel: PanelContainer = $InfoOverlay/Center/Panel
@onready var info_dim: ColorRect = $InfoOverlay/Dim
@onready var info_center: CenterContainer = $InfoOverlay/Center
@onready var close_info_button: Button = %CloseInfoButton
@onready var plaza_button: Button = %PlazaButton
@onready var sound_button: Button = %SoundButton
@onready var settings_button: Button = %SettingsButton
var _settings_overlay: Control
@onready var cleared_label: Label = %ClearedLabel
@onready var stars_label: Label = %StarsLabel
@onready var track_count_label: Label = %TrackCountLabel
@onready var next_level_label: Label = %NextLevelLabel

var _dev_dialog: Control
var _dev_password: LineEdit


func _ready() -> void:
	solo_button.pressed.connect(_on_solo_pressed)
	duo_button.pressed.connect(_on_duo_pressed)
	editor_button.pressed.connect(_on_editor_pressed)
	leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	analytics_button.pressed.connect(_on_analytics_pressed)
	howto_button.pressed.connect(_on_howto_pressed)
	plaza_button.pressed.connect(_on_plaza_pressed)
	close_info_button.pressed.connect(_hide_info)
	sound_button.pressed.connect(_on_sound_pressed)
	settings_button.pressed.connect(_show_settings_dialog)
	info_overlay.visible = false
	info_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_dim.gui_input.connect(_on_info_dim_input)
	if not SaveManager.data_changed.is_connected(_refresh_stats):
		SaveManager.data_changed.connect(_refresh_stats)
	_refresh_stats()
	call_deferred("_animate_right_card")
	call_deferred("_prewarm_cart_profiles")
	_update_sound_button()
	_apply_saved_audio_settings()
	call_deferred("_apply_display_mode", int(SaveManager.get_setting("display_mode", 0)), false)
	solo_button.grab_focus()


func _input(event: InputEvent) -> void:
	if info_overlay.visible and event.is_action_pressed("ui_cancel"):
		_hide_info()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_D:
		if not GameSession.developer_interface:
			return
		_show_dev_dialog()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if _dev_dialog != null and _dev_dialog.visible:
			_hide_dev_dialog()
			get_viewport().set_input_as_handled()
			return
		if info_overlay.visible:
			_hide_info()
			get_viewport().set_input_as_handled()


func _animate_right_card() -> void:
	UIJuice.reveal($Content/RootVBox/MainRow/RightCard)


func _prewarm_cart_profiles() -> void:
	await CartCatalog.prewarm_deferred(self)


func _show_dev_dialog() -> void:
	if _dev_dialog == null:
		_dev_dialog = Control.new()
		_dev_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
		_dev_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_dev_dialog)
		var dim := ColorRect.new()
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.color = Color(0.03, 0.08, 0.12, 0.62)
		_dev_dialog.add_child(dim)
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		_dev_dialog.add_child(center)
		var panel := PanelContainer.new()
		panel.theme_type_variation = &"PaperPanel"
		panel.custom_minimum_size = Vector2(470, 260)
		center.add_child(panel)
		UIJuice.popup_in(panel)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 24)
		margin.add_theme_constant_override("margin_right", 24)
		margin.add_theme_constant_override("margin_top", 20)
		margin.add_theme_constant_override("margin_bottom", 20)
		panel.add_child(margin)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		margin.add_child(box)
		var title := Label.new()
		title.theme_type_variation = &"HeadingLabel"
		title.text = "开发者入口"
		box.add_child(title)
		var hint := Label.new()
		hint.theme_type_variation = &"MutedLabel"
		hint.text = "输入密码后进入主线关卡编辑。"
		box.add_child(hint)
		_dev_password = LineEdit.new()
		_dev_password.secret = true
		_dev_password.placeholder_text = "password"
		_dev_password.custom_minimum_size = Vector2(0, 42)
		box.add_child(_dev_password)
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 8)
		box.add_child(buttons)
		var cancel := Button.new()
		cancel.theme_type_variation = &"GhostButton"
		cancel.text = "取消"
		cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cancel.pressed.connect(_hide_dev_dialog)
		buttons.add_child(cancel)
		var confirm := Button.new()
		confirm.theme_type_variation = &"PrimaryButton"
		confirm.text = "解锁"
		confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		confirm.pressed.connect(_on_dev_confirm)
		buttons.add_child(confirm)
	_dev_password.text = ""
	_dev_dialog.show()
	_dev_password.grab_focus()


func _show_settings_dialog() -> void:
	if _settings_overlay != null and is_instance_valid(_settings_overlay):
		_settings_overlay.call("show_animated")
		return
	_settings_overlay = SETTINGS_DIALOG_SCENE.instantiate() as Control
	add_child(_settings_overlay)
	_settings_overlay.show()


func _apply_saved_audio_settings() -> void:
	for bus_name in ["Master", "Music", "SFX"]:
		var key: String = {"Master": "master_volume", "Music": "music_volume", "SFX": "sfx_volume"}[bus_name]
		var value := float(SaveManager.get_setting(key, 70.0))
		var bus_index := AudioServer.get_bus_index(bus_name)
		if bus_index >= 0:
			AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(0.0001, value / 100.0)))


func _add_volume_row(parent: VBoxContainer, label_text: String, setting_key: String, bus_name: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.custom_minimum_size = Vector2(130, 0)
	label.text = label_text
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = Color(0.18, 0.24, 0.29, 0.35)
	track_style.corner_radius_top_left = 4
	track_style.corner_radius_top_right = 4
	track_style.corner_radius_bottom_left = 4
	track_style.corner_radius_bottom_right = 4
	track_style.content_margin_top = 3
	track_style.content_margin_bottom = 3
	slider.add_theme_stylebox_override("slider", track_style)
	var fill_style: StyleBoxFlat = track_style.duplicate()
	fill_style.bg_color = Color(0.95, 0.37, 0.34, 0.95)
	slider.add_theme_stylebox_override("grabber_area", fill_style)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_style)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = float(SaveManager.get_setting(setting_key, 70.0))
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(48, 0)
	value_label.text = "%d%%" % int(slider.value)
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = "%d%%" % int(value)
		SaveManager.set_setting(setting_key, value)
		var slider_bus_index := AudioServer.get_bus_index(bus_name)
		if slider_bus_index >= 0:
			AudioServer.set_bus_volume_db(slider_bus_index, linear_to_db(maxf(0.0001, value / 100.0)))
	)
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(0.0001, slider.value / 100.0)))


func _apply_display_mode(mode: int, allow_fullscreen: bool = false) -> void:
	SaveManager.set_setting("display_mode", mode)
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	window.content_scale_size = Vector2i(1280, 720)
	var can_fullscreen := allow_fullscreen and PlatformConfig.allow_fullscreen
	if mode == 0:
		if can_fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		# 使用 canvas_items 在目标分辨率上重新绘制 UI/文字；viewport 会把
		# 1280x720 低分辨率画面放大，导致全屏/等比例/铺满明显模糊。
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		return
	if can_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
	if mode == 1:
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	elif mode == 2:
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	else:
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND


func _hide_dev_dialog() -> void:
	if _dev_dialog != null:
		_dev_dialog.hide()


func _on_dev_confirm() -> void:
	if DeveloperService.unlock(_dev_password.text):
		GameSession.developer_mode = true
		_hide_dev_dialog()
		SceneRouter.goto_editor()
	else:
		_dev_password.text = ""
		_dev_password.placeholder_text = "密码错误，请重试"


func _refresh_stats() -> void:
	var mainline := LevelCatalog.get_builtin_summaries()
	var total_levels := mainline.size()
	var cleared := 0
	for summary in mainline:
		if SaveManager.is_level_cleared(str(summary.get("id", ""))):
			cleared += 1
	cleared_label.text = "%d / %d" % [cleared, total_levels]
	var stars := 0
	for summary in mainline:
		stars += SaveManager.get_level_stars(str(summary.get("id", "")))
	stars_label.visible = true
	stars_label.text = "%d / %d" % [stars, total_levels * 3]
	track_count_label.text = "%d 条主线 · %d 条自制" % [total_levels, LevelCatalog.get_user_summaries().size()]

	var next_level := _find_next_level()
	if next_level.is_empty():
		next_level_label.text = "所有轨道都已点亮，去刷新纪录吧。"
	else:
		next_level_label.text = "下一站：%s · %s" % [
			str(next_level.get("name", "")),
			str(next_level.get("subtitle", "")),
		]


func _find_next_level() -> Dictionary:
	for summary in LevelCatalog.get_summaries():
		if not SaveManager.is_level_cleared(str(summary.get("id", ""))):
			return summary
	return {}


func _on_solo_pressed() -> void:
	AudioDirector.play_click()
	SceneRouter.goto_level_select(GameSession.MODE_SOLO)


func _on_duo_pressed() -> void:
	AudioDirector.play_click()
	GameSession.load_duo_settings()
	SceneRouter.goto_level_select(GameSession.MODE_DUO)


func _on_editor_pressed() -> void:
	GameSession.developer_mode = false
	AudioDirector.play_click()
	SceneRouter.goto_editor()


func _on_leaderboard_pressed() -> void:
	AudioDirector.play_click()
	SceneRouter.goto_leaderboard()


func _on_analytics_pressed() -> void:
	AudioDirector.play_click()
	SceneRouter.goto_analytics()


func _on_plaza_pressed() -> void:
	AudioDirector.play_click()
	SceneRouter.goto_plaza()


func _on_howto_pressed() -> void:
	AudioDirector.play_click()
	info_overlay.visible = true
	info_overlay.modulate.a = 1.0
	UIJuice.popup_in(info_panel)
	close_info_button.grab_focus()


func _hide_info() -> void:
	AudioDirector.play_click()
	UIJuice.popup_out(info_panel, func() -> void:
		info_overlay.visible = false
	)
	solo_button.grab_focus()


func _on_info_dim_input(event: InputEvent) -> void:
	if not info_overlay.visible:
		return
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		_hide_info()


func _on_sound_pressed() -> void:
	AudioDirector.play_click()
	AudioDirector.toggle_music()
	_update_sound_button()


func _update_sound_button() -> void:
	sound_button.text = "♪" if AudioDirector.music_enabled else "×"
	sound_button.tooltip_text = "关闭音乐" if AudioDirector.music_enabled else "开启音乐"

extends Control
## 独立设置场景。所有控件样式由 UITheme 提供；虚拟按键页由独立 TouchConfig 场景负责。

const TOUCH_CONFIG_SCENE := preload("res://scenes/ui/touch_config.tscn")

@onready var panel: PanelContainer = $Center/Panel
@onready var dim: ColorRect = $Dim
@onready var center: CenterContainer = $Center
@onready var display_option: OptionButton = %DisplayOption
@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var master_value: Label = %MasterValue
@onready var music_value: Label = %MusicValue
@onready var sfx_value: Label = %SfxValue
@onready var touch_config_button: Button = %TouchConfigButton
@onready var close_button: Button = %CloseButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for item in ["全屏", "窗口", "等比例拉伸", "铺满屏幕"]:
		display_option.add_item(item)
	display_option.select(clampi(int(SaveManager.get_setting("display_mode", 0)), 0, 3))
	display_option.item_selected.connect(_on_display_mode_selected)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		display_option.add_theme_color_override(state, UITheme.COLOR_INK)
	display_option.get_popup().about_to_popup.connect(_hide_display_scrollbars)
	_hide_display_scrollbars()
	_bind_volume(master_slider, master_value, "master_volume", "Master")
	_bind_volume(music_slider, music_value, "music_volume", "Music")
	_bind_volume(sfx_slider, sfx_value, "sfx_volume", "SFX")
	touch_config_button.visible = TouchControls.is_touch_device()
	touch_config_button.pressed.connect(_open_touch_config)
	close_button.pressed.connect(_close_animated)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.gui_input.connect(_on_dim_input)
	_apply_display_mode(clampi(int(SaveManager.get_setting("display_mode", 0)), 0, 3), false)
	UIJuice.popup_in(panel)


func _bind_volume(slider: HSlider, value_label: Label, key: String, bus_name: String) -> void:
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = clampf(float(SaveManager.get_setting(key, 70.0)), 0.0, 100.0)
	value_label.text = "%d" % int(slider.value)
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = "%d" % int(value)
		SaveManager.set_setting(key, value)
		var bus_index := AudioServer.get_bus_index(bus_name)
		if bus_index >= 0:
			AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(0.0001, value / 100.0)))
	)


func show_animated() -> void:
	show()
	UIJuice.popup_in(panel)


func _hide_display_scrollbars() -> void:
	for scroll_bar in display_option.get_popup().find_children("*", "VScrollBar", true, false):
		scroll_bar.visible = false
		scroll_bar.modulate.a = 0.0
		scroll_bar.custom_minimum_size = Vector2.ZERO
	call_deferred("_hide_display_scrollbars_deferred")


func _hide_display_scrollbars_deferred() -> void:
	for scroll_bar in display_option.get_popup().find_children("*", "VScrollBar", true, false):
		scroll_bar.visible = false
		scroll_bar.modulate.a = 0.0
		scroll_bar.custom_minimum_size = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close_animated()
		get_viewport().set_input_as_handled()


func _on_dim_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		# 与点击“完成”一致：所有设置项在改动时已写入 SaveManager。
		_close_animated()


func _close_animated() -> void:
	UIJuice.popup_out(panel, func() -> void:
		panel.modulate.a = 1.0
		panel.scale = Vector2.ONE
		hide()
	)


func _open_touch_config() -> void:
	AudioDirector.play_click()
	var config := TOUCH_CONFIG_SCENE.instantiate() as TouchConfigScreen
	add_child(config)


func _on_display_mode_selected(index: int) -> void:
	_apply_display_mode(index, true)


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

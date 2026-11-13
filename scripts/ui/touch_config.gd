class_name TouchConfigScreen
extends Control
## 独立虚拟按键配置场景：单/双人切换、大小/透明度、拖拽位置。

signal closed

@onready var single_button: Button = %SingleButton
@onready var duo_button: Button = %DuoButton
@onready var size_slider: HSlider = %SizeSlider
@onready var opacity_slider: HSlider = %OpacitySlider
@onready var close_button: Button = %CloseButton

var _mode: String = "solo"
var _preview: TouchControls


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	single_button.pressed.connect(func() -> void: _set_mode("solo"))
	duo_button.pressed.connect(func() -> void: _set_mode("duo"))
	close_button.pressed.connect(_close)
	size_slider.min_value = 56.0
	size_slider.max_value = 150.0
	size_slider.step = 1.0
	opacity_slider.min_value = 0.15
	opacity_slider.max_value = 1.0
	opacity_slider.step = 0.01
	size_slider.value_changed.connect(_on_size_changed)
	opacity_slider.value_changed.connect(_on_opacity_changed)
	_build_preview("solo")


func _build_preview(mode: String) -> void:
	_mode = mode
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = TouchControls.new()
	add_child(_preview)
	move_child(_preview, 1)
	_preview.editable = true
	_preview.configure("solo" if mode == "solo" else "duo")
	var prefix := "touch_single_" if mode == "solo" else "touch_duo_"
	size_slider.set_value_no_signal(float(SaveManager.get_setting(prefix + "size", 96.0 if mode == "solo" else 82.0)))
	opacity_slider.set_value_no_signal(float(SaveManager.get_setting(prefix + "opacity", 0.72)))
	single_button.theme_type_variation = &"PrimaryButton" if mode == "solo" else &"SecondaryButton"
	duo_button.theme_type_variation = &"PrimaryButton" if mode == "duo" else &"SecondaryButton"


func _set_mode(mode: String) -> void:
	AudioDirector.play_click()
	_build_preview(mode)


func _on_size_changed(value: float) -> void:
	var prefix := "touch_single_" if _mode == "solo" else "touch_duo_"
	SaveManager.set_setting(prefix + "size", value)
	_get_tree_refresh()


func _on_opacity_changed(value: float) -> void:
	var prefix := "touch_single_" if _mode == "solo" else "touch_duo_"
	SaveManager.set_setting(prefix + "opacity", value)
	_get_tree_refresh()


func _get_tree_refresh() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.refresh()


func _close() -> void:
	AudioDirector.play_click()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()

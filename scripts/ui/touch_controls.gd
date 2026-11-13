class_name TouchControls
extends Control
## 移动端虚拟按键。只在触屏设备/Android 上创建；单人和双人分别读取
## SaveManager 中的触控尺寸、不透明度和纵向位置设置。
##
## 多指规则（和游戏内手感直接相关）：
## - 每个方向键用 touch index 绑定，天然支持左右手同时按两个键；
## - 同一玩家只保留“最后按下”的方向。右按住时再按左，右立即松开；
##   此后松开左不会自动恢复右，必须重新按下右才会响应（与需求一致）；
## - 不使用 Button，因为 Godot 的“触摸模拟鼠标”同一时刻只支持一根手指，
##   会导致第二个按键和 HUD 音量/暂停按钮失效。

const GROUP_NAME := "touch_controls"

var _mode: String = "solo"
var _buttons: Array[TouchPad] = []
var _actions: Array[String] = []
var editable: bool = false
var _drag_pad: TouchPad
var _drag_offset: Vector2 = Vector2.ZERO
var _dragging_id: int = -9999
var _touch_actions: Dictionary = {}
var _active_by_prefix: Dictionary = {}


static func is_touch_device() -> bool:
	if OS.has_feature("mobile") or PlatformConfig.is_wechat:
		return true
	# PC 默认不显示；只有开启调试开关才允许触屏 PC 显示虚拟按键。
	return GameSession.pc_debug_touch_controls


func configure(mode: String) -> void:
	_mode = mode
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group(GROUP_NAME)
	set_process_input(true)
	_build_buttons()
	resized.connect(refresh)
	call_deferred("refresh")


func _build_buttons() -> void:
	for child in get_children():
		child.queue_free()
	_buttons.clear()
	_actions.clear()
	_release_all()
	if _mode == "duo":
		_add_button("p1_left", "P1 后退", "←", 0)
		_add_button("p1_right", "P1 前进", "→", 1)
		_add_button("p2_left", "P2 后退", "←", 2)
		_add_button("p2_right", "P2 前进", "→", 3)
	else:
		_add_button("move_left", "后退", "←", 0)
		_add_button("move_right", "前进", "→", 1)


func _add_button(action: String, hint: String, glyph: String, index: int) -> void:
	var pad := TouchPad.new()
	pad.name = "TouchPad_%s" % action
	pad.setup(action, hint, glyph, 96.0)
	add_child(pad)
	_buttons.append(pad)
	_actions.append(action)
	pad.set_meta("index", index)


func refresh() -> void:
	var prefix := "touch_duo_" if _mode == "duo" else "touch_single_"
	var button_size := clampf(float(SaveManager.get_setting(prefix + "size", 96.0 if _mode == "solo" else 82.0)), 56.0, 150.0)
	var opacity := clampf(float(SaveManager.get_setting(prefix + "opacity", 0.72)), 0.15, 1.0)
	var vertical := clampf(float(SaveManager.get_setting(prefix + "y", 0.84)), 0.45, 0.96)
	var inset := clampf(float(SaveManager.get_setting(prefix + "inset", 0.06)), 0.02, 0.34)
	var viewport_size := size if size.x > 0.0 else get_viewport_rect().size
	var bottom := viewport_size.y * vertical
	var left_x := viewport_size.x * inset
	var right_x := viewport_size.x * (1.0 - inset) - button_size
	var saved_positions: Variant = SaveManager.get_setting(prefix + "positions", {})
	var use_saved_positions := saved_positions is Dictionary
	if _mode == "duo" and int(SaveManager.get_setting("touch_layout_version", 1)) < 2:
		use_saved_positions = false
	for index in _buttons.size():
		var pad := _buttons[index]
		pad.set_pad_size(button_size)
		pad.modulate.a = opacity
		var action := _actions[index]
		if use_saved_positions and (saved_positions as Dictionary).has(action):
			var saved: Array = saved_positions[action]
			if saved.size() >= 2:
				pad.position = Vector2(float(saved[0]) * viewport_size.x, float(saved[1]) * viewport_size.y)
				continue
		if _mode == "duo":
			# 左组 P1、右组 P2；每组内部左右横排。
			var group := int(index / 2.0)
			var slot := index % 2
			var gap := 12.0
			var group_width := button_size * 2.0 + gap
			var group_x := left_x if group == 0 else viewport_size.x * (1.0 - inset) - group_width
			pad.position = Vector2(group_x + slot * (button_size + gap), bottom - button_size)
		else:
			pad.position = Vector2(left_x if index == 0 else right_x, bottom - button_size)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_pointer_down(event.index, event.position)
		else:
			_on_pointer_up(event.index)
		return
	if event is InputEventScreenDrag:
		_on_pointer_drag(event.index, event.position)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_pointer_down(-1, event.position)
		else:
			_on_pointer_up(-1)
		return
	if event is InputEventMouseMotion and _dragging_id == -1:
		_on_pointer_drag(-1, event.position)


func _on_pointer_down(pointer_id: int, screen_position: Vector2) -> void:
	if get_tree().paused:
		return
	var pad := _pad_at(screen_position)
	if pad == null:
		return
	var local_position := get_global_transform_with_canvas().affine_inverse() * screen_position
	if editable:
		_drag_pad = pad
		_dragging_id = pointer_id
		_drag_offset = pad.position - local_position
		pad.move_to_front()
		get_viewport().set_input_as_handled()
		return
	_touch_actions[pointer_id] = pad.action
	_activate_action(pad.action)
	get_viewport().set_input_as_handled()


func _on_pointer_up(pointer_id: int) -> void:
	if editable:
		if _dragging_id == pointer_id and _drag_pad != null:
			_save_button_position(_drag_pad, _drag_pad.action)
			_drag_pad = null
			_dragging_id = -9999
			get_viewport().set_input_as_handled()
		return
	if not _touch_actions.has(pointer_id):
		return
	var action := str(_touch_actions[pointer_id])
	_touch_actions.erase(pointer_id)
	_release_action(action)
	get_viewport().set_input_as_handled()


func _on_pointer_drag(pointer_id: int, screen_position: Vector2) -> void:
	if not editable or _dragging_id != pointer_id or _drag_pad == null:
		return
	var local_position := get_global_transform_with_canvas().affine_inverse() * screen_position
	_drag_pad.position = (local_position + _drag_offset).clamp(
		Vector2.ZERO,
		Vector2(size.x - _drag_pad.size.x, size.y - _drag_pad.size.y)
	)
	get_viewport().set_input_as_handled()


func _pad_at(screen_position: Vector2) -> TouchPad:
	for index in range(_buttons.size() - 1, -1, -1):
		var pad := _buttons[index]
		if pad.visible and pad.get_global_rect().has_point(screen_position):
			return pad
	return null


func _activate_action(action: String) -> void:
	if not InputMap.has_action(action):
		return
	var prefix := _prefix_of(action)
	var previous := str(_active_by_prefix.get(prefix, ""))
	if previous == action:
		_set_pad_visual(action, true)
		return
	if not previous.is_empty():
		Input.action_release(previous)
		_set_pad_visual(previous, false)
	_active_by_prefix[prefix] = action
	Input.action_press(action)
	_set_pad_visual(action, true)


func _release_action(action: String) -> void:
	var prefix := _prefix_of(action)
	if str(_active_by_prefix.get(prefix, "")) != action:
		# 已被后按下的方向顶掉；这根手指抬起时不能影响当前方向。
		return
	_active_by_prefix.erase(prefix)
	if InputMap.has_action(action):
		Input.action_release(action)
	_set_pad_visual(action, false)


func _release_all() -> void:
	for prefix: Variant in _active_by_prefix.keys():
		var action := str(_active_by_prefix[prefix])
		if InputMap.has_action(action):
			Input.action_release(action)
		_set_pad_visual(action, false)
	_active_by_prefix.clear()
	_touch_actions.clear()


func _set_pad_visual(action: String, value: bool) -> void:
	for pad in _buttons:
		if pad.action == action:
			pad.active = value
			return


func _prefix_of(action: String) -> String:
	if action.begins_with("p1_"):
		return "p1"
	if action.begins_with("p2_"):
		return "p2"
	return "solo"


func _save_button_position(pad: TouchPad, action: String) -> void:
	var prefix := "touch_duo_" if _mode == "duo" else "touch_single_"
	var saved_value: Variant = SaveManager.get_setting(prefix + "positions", {})
	var saved: Dictionary = saved_value if saved_value is Dictionary else {}
	var viewport_size := size if size.x > 0.0 else get_viewport_rect().size
	saved[action] = [pad.position.x / maxf(1.0, viewport_size.x), pad.position.y / maxf(1.0, viewport_size.y)]
	SaveManager.set_setting(prefix + "positions", saved)
	if _mode == "duo":
		SaveManager.set_setting("touch_layout_version", 2)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()


func _exit_tree() -> void:
	_release_all()


func hide_controls() -> void:
	_release_all()
	for pad in _buttons:
		pad.hide()


## 测试 / 调试：读取某位玩家当前生效的方向动作。
func get_active_action(prefix: String = "solo") -> String:
	return str(_active_by_prefix.get(prefix, ""))

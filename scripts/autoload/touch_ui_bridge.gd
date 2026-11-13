extends Node
## 第二根手指的 UI 兜底。
##
## Godot 默认把第一根触摸转成鼠标事件，Button 只认鼠标；因此“左手按住方向键、
## 右手点暂停/音量”时第二根手指不会触发任何按钮。这里只接管 index > 0 的触摸，
## 交给最近的 Button 并手动补齐 button_down / pressed 语义；index 0 仍走引擎原生
## 鼠标模拟，不改变桌面与普通单指 UI 行为。

var _touch_buttons: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.index <= 0:
			return
		if event.pressed:
			_press_at(event.index, event.position)
		else:
			_release(event.index)
		return
	if event is InputEventScreenDrag and event.index > 0:
		_drag(event.index, event.position)


func _press_at(index: int, position: Vector2) -> void:
	var button := _find_button(get_tree().root, position)
	if button == null:
		return
	_touch_buttons[index] = {
		"button": button,
		"was_toggled": button.button_pressed,
	}
	button.set_pressed_no_signal(true)
	button.button_down.emit()
	button.grab_focus()
	get_viewport().set_input_as_handled()


func _release(index: int) -> void:
	if not _touch_buttons.has(index):
		return
	var state: Dictionary = _touch_buttons[index]
	_touch_buttons.erase(index)
	var button: Button = state.get("button")
	if button == null or not is_instance_valid(button):
		return
	button.button_up.emit()
	if button.toggle_mode:
		var new_state := not bool(state.get("was_toggled", false))
		button.set_pressed_no_signal(new_state)
		button.toggled.emit(new_state)
	else:
		button.set_pressed_no_signal(false)
	button.pressed.emit()
	get_viewport().set_input_as_handled()


func _drag(index: int, position: Vector2) -> void:
	if not _touch_buttons.has(index):
		return
	var state: Dictionary = _touch_buttons[index]
	var button: Button = state.get("button")
	if button == null or not is_instance_valid(button) or not button.visible:
		return
	if button.get_global_rect().has_point(position):
		get_viewport().set_input_as_handled()


func _find_button(node: Node, position: Vector2) -> Button:
	if not is_instance_valid(node):
		return null
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return null
	if node is Control:
		var control := node as Control
		if not control.is_visible_in_tree():
			return null
		if not control.get_global_rect().has_point(position):
			return null
	# 后绘制的子节点优先，保证弹窗按钮盖过背景按钮。
	var children := node.get_children()
	for child_index in range(children.size() - 1, -1, -1):
		var found := _find_button(children[child_index], position)
		if found != null:
			return found
	if node is OptionButton or node is MenuButton:
		return null
	if node is Button:
		var button := node as Button
		if not button.disabled and button.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return button
	return null

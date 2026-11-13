extends Node
## 集中注册输入动作，确保编辑器运行、无头测试和未来触摸层使用同一套动作名。
## 键盘是当前主输入；触摸 HUD 只需调用 Input.action_press/release 即可复用。

const DEADZONE := 0.25


func _ready() -> void:
	_install_actions()


func _install_actions() -> void:
	# 单人：方向键与 WASD 均可操作。
	_ensure_action("move_left", [KEY_LEFT, KEY_A])
	_ensure_action("move_right", [KEY_RIGHT, KEY_D])
	_ensure_action("move_up", [KEY_UP, KEY_W])
	_ensure_action("move_down", [KEY_DOWN, KEY_S])

	# 玩家 1 / 玩家 2 的独立动作，供本地双人使用。
	_ensure_action("p1_left", [KEY_LEFT])
	_ensure_action("p1_right", [KEY_RIGHT])
	_ensure_action("p1_up", [KEY_UP])
	_ensure_action("p1_down", [KEY_DOWN])
	_ensure_action("p2_left", [KEY_A])
	_ensure_action("p2_right", [KEY_D])
	_ensure_action("p2_up", [KEY_W])
	_ensure_action("p2_down", [KEY_S])

	# 全局快捷键。
	_ensure_action("pause", [KEY_ESCAPE, KEY_P])
	_ensure_action("restart_run", [KEY_R])
	_ensure_action("toggle_fullscreen", [KEY_F11])
	_ensure_action("toggle_mute", [KEY_M])


func _ensure_action(action_name: StringName, physical_keys: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, DEADZONE)
	else:
		InputMap.action_set_deadzone(action_name, DEADZONE)

	var existing_keys: Array[int] = []
	for event: InputEvent in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			existing_keys.append(int(event.physical_keycode))

	for keycode: int in physical_keys:
		if existing_keys.has(keycode):
			continue
		var input_event := InputEventKey.new()
		input_event.physical_keycode = keycode as Key
		input_event.unicode = 0
		InputMap.action_add_event(action_name, input_event)

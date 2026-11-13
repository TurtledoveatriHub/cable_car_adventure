extends Node
## 全局 UI 动效。作为 Autoload 使用，可在 Inspector 中调整参数。

@export_category("按钮悬停")
## 悬停时的最大缩放倍数。
@export var button_hover_scale: float = 1.06
## 悬停时的最大旋转角度（度）。
@export var button_hover_rotation_deg: float = 1.6
## 计算旋转强度时的参考边长；按钮越长，旋转越小。
@export var button_rotation_reference_size: float = 180.0
## 悬停放大动画时长。
@export var button_hover_in_duration: float = 0.14
## 移开复位动画时长。
@export var button_hover_out_duration: float = 0.18

@export_category("错峰出现")
## 页面内相邻按钮的默认错峰间隔。
@export var default_stagger_step: float = 0.06
## 错峰翻入的缩放起始值。
@export var stagger_start_scale: float = 0.92
## 单个按钮翻入时长。
@export var stagger_duration: float = 0.30
## 错峰淡入时长。
@export var stagger_fade_duration: float = 0.22

@export_category("弹窗")
## 弹窗打开/关闭时经过的峰值缩放。
@export var popup_peak_scale: float = 1.12
## 从 0 放大到峰值的时长。
@export var popup_open_duration: float = 0.22
## 到达峰值后的停顿。
@export var popup_hold_duration: float = 0.05
## 从峰值回落到 1.0 的时长。
@export var popup_settle_duration: float = 0.07
## 关闭时从当前值放大到峰值的时长。
@export var popup_close_peak_duration: float = 0.08
## 关闭时从峰值缩到 0 的时长。
@export var popup_close_duration: float = 0.2

@export_category("数字弹跳")
## 数字标签弹跳放大倍数。
@export var label_bounce_scale: float = 1.2
## 弹起时长。
@export var label_bounce_up_duration: float = 0.12
## 回落时长。
@export var label_bounce_down_duration: float = 0.22

const META_ATTACHED := "ui_juice_attached"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

var _popup_anims: Dictionary = {}


func attach_button(button: Button) -> void:
	if button == null or button is OptionButton or button.has_meta(META_ATTACHED):
		return
	if PlatformConfig.is_wechat and button is LevelCard:
		return
	button.set_meta(META_ATTACHED, true)
	button.pivot_offset = button.size * 0.5
	button.mouse_entered.connect(_on_hover.bind(button))
	button.mouse_exited.connect(_on_unhover.bind(button))
	button.resized.connect(func() -> void:
		button.pivot_offset = button.size * 0.5
	)


func _on_hover(button: Button) -> void:
	if not is_instance_valid(button) or button.disabled or not button.is_visible_in_tree():
		return
	var long_side := maxf(1.0, maxf(button.size.x, button.size.y))
	var factor := clampf(button_rotation_reference_size / long_side, 0.06, 1.0)
	var direction := 1.0 if button.get_index() % 2 == 0 else -1.0
	var tween := button.create_tween().set_parallel(true)
	tween.tween_property(button, "scale", Vector2(button_hover_scale, button_hover_scale), button_hover_in_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "rotation", deg_to_rad(button_hover_rotation_deg * factor * direction), button_hover_in_duration).set_trans(Tween.TRANS_BACK)


func _on_unhover(button: Button) -> void:
	if not is_instance_valid(button):
		return
	var tween := button.create_tween().set_parallel(true)
	tween.tween_property(button, "scale", Vector2.ONE, button_hover_out_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "rotation", 0.0, button_hover_out_duration).set_trans(Tween.TRANS_QUAD)


func stagger(container: Node, delay_step: float = -1.0) -> void:
	if container == null:
		return
	if delay_step < 0.0:
		delay_step = default_stagger_step
	var visible_index := 0
	for child in container.get_children():
		if not child is Control or not (child as Control).visible:
			continue
		var control := child as Control
		var target_alpha := control.modulate.a
		control.modulate.a = 0.0
		control.scale = Vector2.ONE if PlatformConfig.is_wechat else Vector2(stagger_start_scale, stagger_start_scale)
		control.pivot_offset = control.size * 0.5
		var tween := control.create_tween().set_parallel(true)
		tween.tween_property(control, "modulate:a", target_alpha, stagger_fade_duration).set_delay(visible_index * delay_step)
		if not PlatformConfig.is_wechat:
			tween.tween_property(control, "scale", Vector2.ONE, stagger_duration).set_delay(visible_index * delay_step).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		visible_index += 1


func page_in(root: Node, delay_step: float = -1.0) -> void:
	if root == null:
		return
	if delay_step < 0.0:
		delay_step = default_stagger_step
	var controls: Array[Dictionary] = []
	var order := 0
	for node in root.find_children("*", "", true, false):
		if node is OptionButton:
			continue
		if not (node is Button or node is LineEdit or node is TextEdit):
			continue
		var control := node as Control
		if control == null or not control.is_visible_in_tree() or control.has_meta("ui_popup_panel"):
			continue
		controls.append({
			"control": control,
			"priority": int(control.get_meta("stagger_priority", 0)),
			"order": order,
		})
		order += 1
	# 保持场景树顺序，只把带 stagger_priority 的组件提前；不改变鼠标输入层级。
	controls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := int(a["priority"])
		var pb := int(b["priority"])
		if pa != pb:
			return pa < pb
		return int(a["order"]) < int(b["order"])
	)
	var index := 0
	for item in controls:
		var control: Control = item["control"]
		var target_alpha := control.modulate.a
		control.pivot_offset = control.size * 0.5
		control.modulate.a = 0.0
		control.scale = Vector2.ONE if PlatformConfig.is_wechat else Vector2(stagger_start_scale, stagger_start_scale)
		var tween := control.create_tween().set_parallel(true)
		tween.tween_property(control, "modulate:a", target_alpha, stagger_fade_duration).set_delay(index * delay_step)
		if not PlatformConfig.is_wechat:
			tween.tween_property(control, "scale", Vector2.ONE, stagger_duration).set_delay(index * delay_step).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		index += 1


func reveal(control: Control) -> void:
	if control == null:
		return
	control.modulate.a = 0.0
	control.scale = Vector2(0.96, 0.96)
	control.pivot_offset = control.size * 0.5
	var tween := control.create_tween().set_parallel(true)
	tween.tween_property(control, "modulate:a", 1.0, 0.22)
	tween.tween_property(control, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func bounce_label(label: Label) -> void:
	if label == null or not is_instance_valid(label):
		return
	label.pivot_offset = label.size * 0.5
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector2(label_bounce_scale, label_bounce_scale), label_bounce_up_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE, label_bounce_down_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)


func popup_in(panel: Control) -> void:
	if panel == null:
		return
	if PlatformConfig.is_wechat:
		panel.set_meta("ui_popup_panel", true)
		panel.set_meta("popup_closing", false)
		panel.visible = true
		panel.scale = Vector2.ONE
		panel.modulate.a = 0.0
		var fade := panel.create_tween()
		fade.tween_property(panel, "modulate:a", 1.0, 0.12)
		return
	panel.set_meta("ui_popup_panel", true)
	panel.set_meta("popup_closing", false)
	panel.modulate.a = 1.0
	panel.scale = Vector2.ZERO
	panel.visible = false
	await panel.get_tree().process_frame
	if not is_instance_valid(panel):
		return
	panel.pivot_offset = panel.size * 0.5
	panel.visible = true
	_popup_anims[panel] = {"mode": "open", "time": 0.0}
	set_process(true)


func popup_out(panel: Control, callback: Callable = Callable()) -> void:
	if panel == null or bool(panel.get_meta("popup_closing", false)):
		return
	if PlatformConfig.is_wechat:
		panel.set_meta("popup_closing", true)
		var fade := panel.create_tween()
		fade.tween_property(panel, "modulate:a", 0.0, 0.12)
		fade.finished.connect(func() -> void:
			panel.set_meta("popup_closing", false)
			if callback.is_valid():
				callback.call()
		)
		return
	if _popup_anims.has(panel) and str((_popup_anims[panel] as Dictionary).get("mode", "")) == "close":
		return
	panel.set_meta("popup_closing", true)
	panel.pivot_offset = panel.size * 0.5
	_popup_anims[panel] = {"mode": "close", "time": 0.0, "callback": callback, "start_scale": panel.scale.x}
	set_process(true)


func _process(delta: float) -> void:
	if _popup_anims.is_empty():
		set_process(false)
		return
	var step := minf(delta, 1.0 / 60.0)
	for key: Variant in _popup_anims.keys():
		if key == null or not is_instance_valid(key):
			_popup_anims.erase(key)
			continue
		var panel := key as Control
		if panel == null:
			_popup_anims.erase(key)
			continue
		var anim: Dictionary = _popup_anims[key]
		panel.pivot_offset = panel.size * 0.5
		anim["time"] = float(anim.get("time", 0.0)) + step
		var value := float(anim["time"])
		if str(anim.get("mode", "open")) == "open":
			var open_end := popup_open_duration
			var hold_end := open_end + popup_hold_duration
			var settle_end := hold_end + popup_settle_duration
			if value <= open_end:
				panel.scale = Vector2.ONE * lerpf(0.0, popup_peak_scale, value / maxf(0.001, open_end))
			elif value <= hold_end:
				panel.scale = Vector2.ONE * popup_peak_scale
			elif value <= settle_end:
				panel.scale = Vector2.ONE * lerpf(popup_peak_scale, 1.0, (value - hold_end) / maxf(0.001, popup_settle_duration))
			else:
				panel.scale = Vector2.ONE
				_popup_anims.erase(key)
		else:
			var peak_end := popup_close_peak_duration
			var close_end := peak_end + popup_hold_duration + popup_close_duration
			if value <= peak_end:
				panel.scale = Vector2.ONE * lerpf(float(anim.get("start_scale", 1.0)), popup_peak_scale, minf(1.0, value / maxf(0.001, peak_end)))
			elif value <= peak_end + popup_hold_duration:
				panel.scale = Vector2.ONE * popup_peak_scale
			elif value <= close_end:
				var t := (value - peak_end - popup_hold_duration) / maxf(0.001, popup_close_duration)
				panel.scale = Vector2.ONE * lerpf(popup_peak_scale, 0.0, t)
			else:
				panel.scale = Vector2.ZERO
				panel.set_meta("popup_closing", false)
				_popup_anims.erase(key)
				var callback: Callable = anim.get("callback", Callable())
				if callback.is_valid():
					callback.call()
	set_process(not _popup_anims.is_empty())

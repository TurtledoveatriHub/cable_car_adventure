class_name PassengerMeter
extends Control
## HUD 中的乘客头像计量条。纯 UI 绘制，不处理存档或玩法状态。

## 头像半径
@export var head_radius: float = 16.0
## 头像间距
@export var head_spacing: float = 42.0
## 有乘客时的黄色笑脸颜色
@export var accent_color: Color = Color(1.0, 0.82, 0.25)

var count: int = 3
var max_slots: int = 6


func _ready() -> void:
	if custom_minimum_size.x <= 0.0:
		custom_minimum_size.x = head_radius * 2.0 + 2.0 + max_slots * head_spacing
	if custom_minimum_size.y <= 0.0:
		custom_minimum_size.y = head_radius * 2.0 + 8.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(new_count: int, new_max: int, animate: bool = true) -> void:
	var changed := new_count != count
	count = clampi(new_count, 0, 99)
	max_slots = clampi(new_max, 1, 12)
	if animate and changed:
		pivot_offset = size * 0.5
		scale = Vector2(1.08, 1.08)
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "scale", Vector2.ONE, 0.24)
	queue_redraw()


func _draw() -> void:
	var ink := Color(0.06, 0.12, 0.18)
	var lost_gray := Color(0.52, 0.55, 0.58)
	var line_width := maxf(1.2, head_radius * 0.10)
	var spacing := head_spacing
	if max_slots > 1:
		var available := size.x - head_radius * 2.0 - 4.0
		spacing = minf(head_spacing, maxf(head_radius * 2.0, available / float(max_slots - 1)))
	for index in max_slots:
		var x := head_radius + 2.0 + index * spacing
		var center := Vector2(x, size.y * 0.5)
		var active := index < count
		var face := accent_color if active else lost_gray
		# 统一的圆形阴影与深色描边。
		draw_circle(center + Vector2(0, 1.5), head_radius + 1.5, Color(0, 0, 0, 0.30))
		draw_circle(center, head_radius, face)
		draw_arc(center, head_radius, 0, TAU, 32, ink, line_width, true)
		var eye_x := head_radius * 0.34
		var eye_y := -head_radius * 0.08
		var eye_radius := maxf(0.9, head_radius * 0.105)
		if active:
			# 经典黄色笑脸：两个圆眼 + 上扬嘴弧。
			draw_circle(center + Vector2(-eye_x, eye_y), eye_radius, ink)
			draw_circle(center + Vector2(eye_x, eye_y), eye_radius, ink)
			draw_arc(
				center + Vector2(0, head_radius * 0.10),
				head_radius * 0.36, 0.24 * PI, 0.76 * PI, 12, ink, line_width, true
			)
			draw_circle(center + Vector2(-head_radius * 0.44, head_radius * 0.20), head_radius * 0.11, Color(1, 1, 1, 0.28))
		else:
			# 灰色哭脸：下弯眼、倒扣嘴弧和两滴眼泪。
			draw_arc(center + Vector2(-eye_x, eye_y - head_radius * 0.06), head_radius * 0.16, PI + 0.2, TAU - 0.2, 8, ink, line_width, true)
			draw_arc(center + Vector2(eye_x, eye_y - head_radius * 0.06), head_radius * 0.16, PI + 0.2, TAU - 0.2, 8, ink, line_width, true)
			draw_arc(
				center + Vector2(0, head_radius * 0.46),
				head_radius * 0.30, PI + 0.25, TAU - 0.25, 12, ink, line_width, true
			)

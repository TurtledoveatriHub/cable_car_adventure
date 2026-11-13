class_name LevelPreview
extends Control
## 选关卡片上的迷你过山车环线预览。纯绘制，不参与布局与交互。

## 预览强调色
@export var accent: Color = Color(0.95, 0.37, 0.36)
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 选关界面有大量预览卡；微信端关闭持续动画，避免几十个 Control 每帧重绘。
	if PlatformConfig.is_wechat:
		set_process(false)
	else:
		set_process(true)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func set_accent(color: Color) -> void:
	accent = color
	queue_redraw()


func _draw() -> void:
	if size.x <= 10.0 or size.y <= 10.0:
		return
	var ink := Color(0.11, 0.2, 0.28, 0.72)
	var center := Vector2(size.x * 0.56, size.y * 0.54)
	var radius := minf(size.x, size.y) * 0.32
	# 完整环线，小车绕整圆运动，不再跨过左侧缺口。
	draw_arc(center, radius, 0, TAU, 48, Color(ink, 0.45), 5.0, true)
	draw_arc(center, radius, 0, TAU, 48, Color(1, 1, 1, 0.35), 1.3, true)
	# 连接轨道。
	draw_line(center + Vector2(-radius, 0), Vector2(0, size.y * 0.78), Color(ink, 0.42), 4.0, true)
	draw_line(center + Vector2(radius, 0), Vector2(size.x, size.y * 0.68), Color(ink, 0.42), 4.0, true)
	# 小车沿完整圆周运动。
	var angle := fmod(_time * 0.9, 1.0) * TAU
	var cart_pos := center + Vector2(cos(angle), sin(angle)) * radius
	draw_rect(Rect2(cart_pos - Vector2(7, 5), Vector2(14, 10)), accent)
	draw_rect(Rect2(cart_pos - Vector2(7, 5), Vector2(14, 10)), ink, false, 1.5)
	# 小旗与云。
	draw_line(Vector2(size.x - 26, size.y * 0.38), Vector2(size.x - 26, size.y * 0.68), Color(ink, 0.35), 2.0, true)
	var flag := PackedVector2Array([
		Vector2(size.x - 26, size.y * 0.38),
		Vector2(size.x - 6, size.y * 0.43),
		Vector2(size.x - 26, size.y * 0.5),
	])
	draw_colored_polygon(flag, Color(accent, 0.75))

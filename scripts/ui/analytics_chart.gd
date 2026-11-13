class_name AnalyticsChart
extends Control
## 分析看板图表：纯 Control 绘制折线图 / 柱状图，不依赖外部图表库。

## 图表标题
@export var chart_title: String = "图表"
## 图表类型：line / bar
@export var chart_type: String = "line"
## 图表或预览的强调色
@export var accent: Color = Color(0.95, 0.37, 0.36)
## 数值后缀，例如 % 或 秒
@export var value_suffix: String = ""

var values: Array[float] = []
var labels: Array[String] = []
var _empty_text: String = "暂无数据"


func _ready() -> void:
	custom_minimum_size = Vector2(0, 180)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_title(title: String) -> void:
	chart_title = title
	queue_redraw()


func set_line_series(new_values: Array[float], new_labels: Array[String] = [], suffix: String = "") -> void:
	chart_type = "line"
	values = new_values.duplicate()
	labels = new_labels.duplicate()
	value_suffix = suffix
	queue_redraw()


func set_bar_series(new_labels: Array[String], new_values: Array[float], suffix: String = "") -> void:
	chart_type = "bar"
	labels = new_labels.duplicate()
	values = new_values.duplicate()
	value_suffix = suffix
	queue_redraw()


func set_empty_text(text: String) -> void:
	_empty_text = text
	queue_redraw()


func _draw() -> void:
	var title_font := UITheme.heavy_font if UITheme != null and UITheme.heavy_font != null else ThemeDB.fallback_font
	var body_font := UITheme.body_font if UITheme != null and UITheme.body_font != null else ThemeDB.fallback_font
	draw_string(title_font, Vector2(4, 22), chart_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.106, 0.196, 0.282))
	if values.is_empty():
		draw_string(body_font, Vector2(size.x * 0.5 - 50.0, size.y * 0.55), _empty_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.39, 0.49, 0.57))
		return
	var left := 40.0
	var right := size.x - 12.0
	var top := 38.0
	var bottom := size.y - 30.0
	if right - left < 30.0 or bottom - top < 30.0:
		return
	var max_value := 0.001
	for value in values:
		max_value = maxf(max_value, value)
	var bar_width := (right - left) / maxf(1.0, float(values.size()))
	if chart_type == "bar":
		bar_width *= 0.62
	# 网格与纵轴刻度。
	for step in 4:
		var ratio := float(step) / 3.0
		var y := bottom - (bottom - top) * ratio
		draw_line(Vector2(left, y), Vector2(right, y), Color(0.106, 0.196, 0.282, 0.11), 1.0)
		draw_string(body_font, Vector2(2, y + 4), _format_value(max_value * ratio), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.39, 0.49, 0.57))
	# 数据。
	if chart_type == "line":
		_draw_line_chart(left, right, top, bottom, max_value, body_font)
	else:
		_draw_bar_chart(left, right, top, bottom, max_value, bar_width, body_font)


func _draw_line_chart(left: float, right: float, top: float, bottom: float, max_value: float, font: Font) -> void:
	var count := values.size()
	var usable_width := right - left
	var points := PackedVector2Array()
	for index in count:
		var x := left if count <= 1 else left + usable_width * float(index) / float(count - 1)
		var y := bottom - (bottom - top) * clampf(values[index] / max_value, 0.0, 1.0)
		points.append(Vector2(x, y))
	# 填充区域。
	if points.size() >= 2:
		var fill := points.duplicate()
		fill.append(Vector2(points[points.size() - 1].x, bottom))
		fill.append(Vector2(points[0].x, bottom))
		draw_colored_polygon(fill, Color(accent, 0.12))
		draw_polyline(points, accent, 2.8, true)
	for index in points.size():
		draw_circle(points[index], 3.0, accent)
		if count <= 8 or index == 0 or index == count - 1:
			draw_string(font, points[index] + Vector2(-8, -10), _format_value(values[index]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.106, 0.196, 0.282, 0.8))
	if not labels.is_empty():
		draw_string(font, Vector2(left, size.y - 8), labels[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.39, 0.49, 0.57))
		draw_string(font, Vector2(right - 90, size.y - 8), labels[labels.size() - 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.39, 0.49, 0.57))


func _draw_bar_chart(
	left: float,
	right: float,
	top: float,
	bottom: float,
	max_value: float,
	bar_width: float,
	font: Font
) -> void:
	var slot := (right - left) / maxf(1.0, float(values.size()))
	for index in values.size():
		var height := (bottom - top) * clampf(values[index] / max_value, 0.0, 1.0)
		var x := left + slot * float(index) + (slot - bar_width) * 0.5
		var rect := Rect2(x, bottom - height, bar_width, maxf(1.0, height))
		draw_rect(rect, Color(accent, 0.82))
		draw_rect(rect, Color(0.106, 0.196, 0.282, 0.5), false, 1.0)
		if values[index] > 0.0:
			draw_string(font, Vector2(x + 2, bottom - height - 5), str(int(round(values[index]))) + value_suffix, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.106, 0.196, 0.282, 0.85))
		if index < labels.size() and not labels[index].is_empty():
			draw_string(font, Vector2(x + bar_width * 0.5 - 12, size.y - 8), labels[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.39, 0.49, 0.57))


func _format_value(value: float) -> String:
	if value >= 100.0:
		return "%.0f" % value
	if value >= 10.0:
		return "%.1f" % value
	return "%.2f" % value

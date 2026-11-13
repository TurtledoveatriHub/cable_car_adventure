class_name TouchPad
extends Control
## 多指触控方向键。刻意不使用 Button：Godot 的触摸转鼠标只支持一根手指，
## 第二个手指按在同一帧时无法同时驱动两个 Button。这里由 TouchControls 统一
## 按 touch index 路由，保证移动键、HUD 按钮可以同时响应。

var action: String = ""
var hint: String = ""
var glyph: String = "→"
var pad_size: float = 96.0
var active: bool = false:
	set(value):
		if active == value:
			return
		active = value
		queue_redraw()

var _bg_style: StyleBoxFlat
var _active_style: StyleBoxFlat


func setup(action_name: String, hint_text: String, glyph_text: String, size_px: float) -> void:
	action = action_name
	hint = hint_text
	glyph = glyph_text
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(size_px, size_px)
	size = custom_minimum_size
	set_pad_size(size_px)
	_build_styles()


func set_pad_size(size_px: float) -> void:
	pad_size = maxf(48.0, size_px)
	custom_minimum_size = Vector2(pad_size, pad_size)
	size = Vector2(pad_size, pad_size)
	queue_redraw()


func _build_styles() -> void:
	_bg_style = StyleBoxFlat.new()
	_bg_style.bg_color = Color(0.055, 0.145, 0.20, 0.66)
	_bg_style.border_color = Color(0.92, 0.98, 1.0, 0.48)
	_bg_style.set_border_width_all(2)
	_bg_style.set_corner_radius_all(int(pad_size * 0.30))
	_bg_style.shadow_color = Color(0.02, 0.07, 0.1, 0.30)
	_bg_style.shadow_size = 8
	_bg_style.shadow_offset = Vector2(0, 4)
	_active_style = _bg_style.duplicate() as StyleBoxFlat
	_active_style.bg_color = Color(1.0, 0.79, 0.25, 0.94)
	_active_style.border_color = Color(1.0, 0.96, 0.78, 1.0)
	_active_style.shadow_color = Color(1.0, 0.65, 0.12, 0.40)
	_active_style.shadow_size = 14


func _draw() -> void:
	if _bg_style == null:
		_build_styles()
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_active_style if active else _bg_style, rect)
	if active:
		draw_circle(size * 0.5, pad_size * 0.34, Color(1.0, 1.0, 1.0, 0.10))
	var font: Font = UITheme.heavy_font if UITheme != null and UITheme.heavy_font != null else ThemeDB.fallback_font
	var color := UITheme.COLOR_INK if active else Color(0.94, 0.99, 1.0, 0.92)
	var glyph_size := int(pad_size * 0.40)
	draw_string(
		font,
		Vector2(0, size.y * 0.49 + glyph_size * 0.34),
		glyph,
		HORIZONTAL_ALIGNMENT_CENTER,
		size.x,
		glyph_size,
		color
	)
	if not hint.is_empty():
		var small_font: Font = UITheme.body_font if UITheme != null and UITheme.body_font != null else ThemeDB.fallback_font
		draw_string(
			small_font,
			Vector2(0, size.y - pad_size * 0.13),
			hint,
			HORIZONTAL_ALIGNMENT_CENTER,
			size.x,
			maxi(9, int(pad_size * 0.115)),
			Color(color, 0.72)
		)

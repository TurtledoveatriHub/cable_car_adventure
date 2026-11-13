class_name DuoOffscreenMarkers
extends Control
## 双人“不分屏”模式的视野边缘箭头：当一方的缆车离开相机视野时，
## 在屏幕边缘持续指向该玩家的大致方向。

var _camera: Camera2D
var _targets: Array[Dictionary] = []


func configure(camera: Camera2D) -> void:
	_camera = camera
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_targets(targets: Array[Dictionary]) -> void:
	_targets = targets
	queue_redraw()


func _process(_delta: float) -> void:
	if visible and not _targets.is_empty():
		queue_redraw()


func _draw() -> void:
	if _camera == null:
		return
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size
	var center := _camera.get_screen_center_position()
	var zoom := maxf(0.01, _camera.zoom.x)
	var visible_rect := Rect2(
		center - viewport_size * 0.5 / zoom,
		viewport_size / zoom
	)
	for target in _targets:
		var world: Vector2 = target.get("world", Vector2.ZERO)
		var screen := (world - center) * zoom + viewport_size * 0.5
		var color: Color = target.get("color", Color.WHITE)
		var label := str(target.get("label", ""))
		if visible_rect.has_point(world):
			# 视野内也持续显示 P1/P2 小箭头，用于区分两辆车。
			var tag_pos := screen + Vector2(0, -54)
			draw_colored_polygon(PackedVector2Array([
				tag_pos + Vector2(0, 8), tag_pos + Vector2(-6, -1), tag_pos + Vector2(6, -1)
			]), Color(color, 0.95))
			draw_string(ThemeDB.fallback_font, tag_pos + Vector2(-10, -6), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.08, 0.12, 0.18, 0.9))
			continue
		var clamped := Vector2(
			clampf(screen.x, 34.0, viewport_size.x - 34.0),
			clampf(screen.y, 34.0, viewport_size.y - 34.0)
		)
		var dir := (screen - viewport_size * 0.5).normalized()
		if dir.length_squared() < 0.001:
			dir = Vector2.UP
		var tip := clamped + dir * 18.0
		var side := Vector2(-dir.y, dir.x) * 10.0
		draw_colored_polygon(PackedVector2Array([
			tip, clamped - dir * 8.0 + side, clamped - dir * 8.0 - side
		]), Color(color, 0.92))
		draw_circle(clamped - dir * 20.0, 15.0, Color(0.08, 0.12, 0.18, 0.75))
		draw_string(ThemeDB.fallback_font, clamped - dir * 20.0 + Vector2(-5, 5), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

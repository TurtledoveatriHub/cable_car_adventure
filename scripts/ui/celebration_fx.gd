class_name CelebrationFx
extends Control
## 结算/胜利界面的轻量彩纸动画。使用 Control 原生绘制，无外部素材。

## 是否播放彩纸
@export var active: bool = true
## 彩纸数量
@export var piece_count: int = 52
## 基础下落速度
@export var fall_speed: float = 80.0

var _pieces: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 20240531
	_create_pieces()
	set_process(active)


func set_active(value: bool) -> void:
	active = value
	set_process(value)
	visible = value
	queue_redraw()


func _create_pieces() -> void:
	_pieces.clear()
	for index in piece_count:
		var x := _rng.randf_range(0.0, maxf(1.0, size.x))
		_pieces.append({
			"x": x,
			"y": _rng.randf_range(-size.y, size.y),
			"speed": _rng.randf_range(0.55, 1.5) * fall_speed,
			"sway": _rng.randf_range(8.0, 32.0),
			"phase": _rng.randf_range(0.0, TAU),
			"spin": _rng.randf_range(-3.0, 3.0),
			"angle": _rng.randf_range(0.0, TAU),
			"size": _rng.randf_range(5.0, 11.0),
			"color": [
				Color(0.95, 0.37, 0.36),
				Color(1.0, 0.82, 0.25),
				Color(0.18, 0.77, 0.71),
				Color(0.19, 0.52, 0.76),
				Color(1.0, 0.96, 0.84),
			][index % 5],
		})


func _process(delta: float) -> void:
	_time += delta
	if size.x > 1.0 and _pieces.is_empty():
		_create_pieces()
	for piece in _pieces:
		piece["y"] = float(piece["y"]) + float(piece["speed"]) * delta
		piece["angle"] = float(piece["angle"]) + float(piece["spin"]) * delta
		if float(piece["y"]) > size.y + 20.0:
			piece["y"] = -20.0
			piece["x"] = _rng.randf_range(0.0, maxf(1.0, size.x))
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	for piece in _pieces:
		var x := float(piece["x"]) + sin(_time * 1.4 + float(piece["phase"])) * float(piece["sway"])
		var center := Vector2(x, float(piece["y"]))
		var angle := float(piece["angle"])
		var half := float(piece["size"]) * 0.5
		var width := half
		var height := half * 0.55
		var points := PackedVector2Array([
			center + Vector2(cos(angle), sin(angle)) * width + Vector2(-sin(angle), cos(angle)) * height,
			center + Vector2(cos(angle), sin(angle)) * width + Vector2(sin(angle), -cos(angle)) * height,
			center - Vector2(cos(angle), sin(angle)) * width + Vector2(sin(angle), -cos(angle)) * height,
			center - Vector2(cos(angle), sin(angle)) * width + Vector2(-sin(angle), cos(angle)) * height,
		])
		draw_colored_polygon(points, piece["color"])

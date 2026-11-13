class_name PopButton
extends Button
## 菜单按钮的轻微缩放与悬停音效，让键盘/鼠标操作更有手感。

## 悬停时的缩放比例
@export var hover_scale: float = 1.025
## 是否播放悬停音效
@export var play_hover_sound: bool = true

var _tween: Tween
var _hovered: bool = false


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	resized.connect(_update_pivot)
	_update_pivot()


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _on_mouse_entered() -> void:
	_hovered = true
	_tween_scale(Vector2(hover_scale, hover_scale))
	if play_hover_sound:
		AudioDirector.play_move()


func _on_mouse_exited() -> void:
	_hovered = false
	if not has_focus():
		_tween_scale(Vector2.ONE)


func _on_focus_entered() -> void:
	_tween_scale(Vector2(hover_scale, hover_scale))


func _on_focus_exited() -> void:
	if not _hovered:
		_tween_scale(Vector2.ONE)


func _tween_scale(target: Vector2) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", target, 0.16)

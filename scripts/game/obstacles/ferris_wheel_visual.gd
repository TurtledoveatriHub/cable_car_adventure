class_name FerrisWheelVisual
extends Node2D
## 摩天轮：Frame 是轮盘并旋转；Visual 是固定摩天轮纹理，不旋转。
## CabinSlots 下的每个 Slot（Area2D）绕场景原点公转，Slot 的 Sprite2D 与 CollisionShape2D 一起跟随。

## 吊厢纹理；Slot 下已有 Sprite2D 时不会再创建。
@export var cabin_texture: Texture2D
## 吊厢横向帧数；0 表示按纹理宽高比自动推断（四帧横排图填 4）。
@export_range(0, 16, 1) var cabin_frame_columns: int = 0
## 吊厢帧动画速度（帧/秒）。
@export_range(0.0, 30.0, 0.5) var cabin_animation_fps: float = 4.0
## 轮盘角速度（度/秒）；吊厢使用同一个角速度。
@export var rotation_speed_deg: float = 30.0

var _angle: float = 0.0
var _wheel: Node2D
var _slots: Array[Area2D] = []
var _base_positions: Array[Vector2] = []
var _cabins: Array[Sprite2D] = []
var _cabin_frames: int = 1
var _cabin_frame_time: float = 0.0


func _ready() -> void:
	_wheel = get_parent().get_node_or_null("Frame") as Node2D
	var slot_root := get_node_or_null("CabinSlots") as Node2D
	if slot_root == null:
		return
	_cabin_frames = _resolve_cabin_frames()
	for child in slot_root.get_children():
		var slot := child as Area2D
		if slot == null:
			continue
		_slots.append(slot)
		_base_positions.append(slot.position)
		slot.rotation = 0.0
		slot.body_entered.connect(_on_slot_body_entered)
		if cabin_texture == null:
			continue
		var cabin: Sprite2D = null
		for slot_child in slot.get_children():
			if slot_child is Sprite2D:
				cabin = slot_child as Sprite2D
				break
		if cabin == null:
			cabin = Sprite2D.new()
			cabin.scale = slot.scale
			cabin.rotation = 0.0
			slot.add_child(cabin)
		cabin.texture = cabin_texture
		cabin.hframes = _cabin_frames
		cabin.vframes = 1
		cabin.frame = 0
		_cabins.append(cabin)


func _process(delta: float) -> void:
	_cabin_frame_time += delta
	if _cabin_frames > 1 and cabin_animation_fps > 0.0:
		var next_frame := int(_cabin_frame_time * cabin_animation_fps) % _cabin_frames
		for cabin in _cabins:
			if is_instance_valid(cabin):
				cabin.frame = next_frame
	_angle += deg_to_rad(rotation_speed_deg) * delta
	if _wheel != null:
		_wheel.rotation = _angle
	for index in _slots.size():
		var slot := _slots[index]
		var base_position := _base_positions[index]
		slot.position = Vector2.from_angle(base_position.angle() + _angle) * base_position.length()
		slot.rotation = 0.0


func _resolve_cabin_frames() -> int:
	if cabin_frame_columns > 0:
		return cabin_frame_columns
	if cabin_texture == null or cabin_texture.get_height() <= 0:
		return 1
	var columns := int(float(cabin_texture.get_width()) / float(cabin_texture.get_height()))
	return maxi(1, columns)


func _on_slot_body_entered(body: Node2D) -> void:
	var obstacle := get_parent() as Obstacle
	if obstacle != null:
		obstacle._on_body_entered(body)

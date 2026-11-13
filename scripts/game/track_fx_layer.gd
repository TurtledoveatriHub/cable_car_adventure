class_name TrackFxLayer
extends Node2D
## 轨道动态效果层：只重绘预警/断裂片段，避免整条轨道每帧重建。

var target: Node
var kind: int = 0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# 预警层由 track_renderer._process 在渲染帧写 position（抖动偏移），
	# 参与物理插值会得到错误的插值历史；本层只做重绘，关闭插值无视觉损失。
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _draw() -> void:
	if target != null:
		target.draw_fx(self, kind)

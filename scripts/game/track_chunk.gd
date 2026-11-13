class_name TrackChunk
extends Node2D
## 轨道分块绘制层。
##
## 存在的唯一理由：整条轨道如果画在一个 CanvasItem 上，它的 AABB 会覆盖整个关卡，
## 与视口永远相交，于是每一帧都要把全部顶点命令重新提交给 GPU——即便玩家只看得到
## 屏幕中间那一小段。把轨道按弧长切块后，块外的 CanvasItem 置为不可见即可完全跳过
## 命令提交（Godot 的节点级裁剪只到 CanvasItem 粒度，救不了单个巨型 item）。
##
## 本层不持有任何几何数据，绘制内容全部委托回 TrackRenderer.draw_chunk()，
## 与 TrackFxLayer 的委托方式保持一致。

var target: TrackRenderer
var chunk_index: int = -1
var start_s: float = 0.0
var end_s: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# 块自身从不移动，只切换 visible；位置恒定时插值无意义，显式关闭避免继承歧义。
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _draw() -> void:
	if target != null and chunk_index >= 0:
		target.draw_chunk(self, chunk_index)

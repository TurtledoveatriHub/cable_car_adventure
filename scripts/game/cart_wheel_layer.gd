class_name CartWheelLayer
extends Node2D
## 独立车轮层：z_index=-1 相对缆车根节点，位于 BGSprite / 乘客之下，
## 但高于轨道本体（缆车根节点 z_index=8，轨道为 0）。

var cart: CoasterController


func _draw() -> void:
	if cart != null:
		cart.draw_wheels(self)

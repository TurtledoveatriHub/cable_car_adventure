class_name PassengerProfile
extends Resource
## 乘客样式资源。新增乘客时复制一个 .tres 并设置 id、名称、纹理即可。

## 稳定 id
@export var id: String = "passenger_1"
## 工坊下拉显示名称
@export var display_name: String = "乘客 1"
## 纹理
@export var texture: Texture2D
## 随机出现权重；实际概率 = 本权重 / 所有乘客权重之和。0 表示不会随机出现。
@export_range(0.0, 100.0, 0.1) var spawn_weight: float = 1.0

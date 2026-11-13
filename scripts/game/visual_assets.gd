@tool
class_name VisualAssets
extends Resource
## 轨道与站台的美术资源槽，由 VisualRegistry 加载。

@export_group("轨道")
## 整段轨道贴图，沿轨道重复铺设
@export var track_texture: Texture2D
## 贴图法向高度
@export var track_texture_height: float = 8.0
## 轨道贴图横向像素宽度（64×8 素材为 64）
@export var track_texture_width: float = 64.0
## 轨道绘制宽度相对贴图高度的缩放；1.0 为正常宽度
@export var track_width_scale: float = 1.0
## 轨道贴图整体亮度
@export var track_brightness: float = 1.0

@export_group("起终点")
## 起点站台贴图
@export var start_gate_texture: Texture2D
## 终点牌贴图
@export var finish_gate_texture: Texture2D

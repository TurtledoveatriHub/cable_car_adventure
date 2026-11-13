@tool
extends Node
## 全局可替换美术资源入口。
## 正式美术可在 assets/visuals/visual_assets.tres 中拖入，无需修改玩法脚本。

const RESOURCE_PATH := "res://assets/visuals/visual_assets.tres"

var assets: VisualAssets


func _ready() -> void:
	assets = load(RESOURCE_PATH) as VisualAssets
	if assets == null:
		assets = VisualAssets.new()
		push_warning("[VisualRegistry] 未找到 %s，使用程序化占位美术" % RESOURCE_PATH)


func get_assets() -> VisualAssets:
	if assets == null:
		assets = load(RESOURCE_PATH) as VisualAssets
	if assets == null:
		assets = VisualAssets.new()
	return assets

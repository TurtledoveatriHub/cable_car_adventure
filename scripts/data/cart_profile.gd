class_name CartProfile
extends Resource
## 缆车 UI 数据快照：由 CartCatalog 从缆车场景的 CoasterController 读取。
## 真正的玩法参数只存在于 CoasterController 场景，本资源只服务选关/解锁/弹窗展示。

@export_category("身份")
## 稳定 id
@export var id: String = "dove"
## 显示名称
@export var display_name: String = "小斑鸠"
## 选关/弹窗显示的车身贴图
@export var texture: Texture2D
## 选关/弹窗显示的车身背景贴图
@export var background_texture: Texture2D
## 车身贴图裁剪区域
@export var body_region: Rect2 = Rect2()
## 背景贴图裁剪区域
@export var background_region: Rect2 = Rect2()
## 车身节点 modulate（选关预览与关卡内保持一致）
@export var body_modulate: Color = Color.WHITE
## 背景节点 modulate（部分缆车复用同一贴图，靠颜色区分）
@export var background_modulate: Color = Color.WHITE
## 车身相对根节点位置
@export var body_position: Vector2 = Vector2.ZERO
## 背景相对根节点位置
@export var background_position: Vector2 = Vector2.ZERO
## 车身缩放
@export var body_scale: Vector2 = Vector2.ONE
## 背景缩放
@export var background_scale: Vector2 = Vector2.ONE
## 简短特性说明
@export var description: String = "均衡的初始缆车"

@export_category("解锁")
## 解锁条件：需要通关的关卡 id；空字符串表示默认解锁
@export var unlock_level_id: String = ""
## 上传到广场的自制关卡数量要求；0 表示不限制
@export var unlock_uploads: int = 0
## 累计星星要求；0 表示不限制
@export var unlock_stars: int = 0

extends Node
## 平台性能与显示配置。集中管理 Web/微信/移动端/桌面端差异，避免散落的 if web。

var is_web: bool = false
var is_mobile: bool = false
var is_wechat: bool = false
## 抖音小游戏：与微信一样运行在 web 特性下，靠导出特性或全局 tt 接口区分。
var is_douyin: bool = false
## 是否允许 UGC 上传。普通 Web（含 itch.io）为 false，只保留广场只读与工坊本地创作；
## PC / 安卓 / 微信 / 抖音为 true。UI 统一读这一个开关，不再散落 if is_web。
var can_upload_ugc: bool = true
## 是否允许调用 DisplayServer.window_set_mode；Web/微信/移动端一律 false。
var allow_fullscreen: bool = false

## 渲染帧率上限；0 表示不限制（桌面端保持原始）。
var max_fps: int = 0
## 允许的最大设备像素比；微信由 godot-loader.js 实际应用，此值用于统一配置记录。
var max_device_pixel_ratio: float = 0.0
## 背景重绘频率（Hz）；0 表示每帧重绘。
var background_render_hz: float = 0.0
## HUD 刷新频率（Hz）；0 表示每帧刷新。
var hud_update_hz: float = 0.0
## 是否启用背景景深模糊；Web/微信关闭，仅保留单次采样的雾化/去饱和。
var atmosphere_blur_enabled: bool = true
## 背景粒子数量缩放（雪、雨、星光等）。
var background_particle_scale: float = 1.0
## 是否启用全屏大气后处理（BackBufferCopy + Shader）。微信端关闭，改为纯色雾化。
var atmosphere_pass_enabled: bool = true
## 障碍视觉/动画刷新频率（Hz）；0 表示跟随帧率。碰撞检测不受影响。
var obstacle_visual_hz: float = 0.0
## 障碍持续接触检测频率（Hz）；0 表示每帧。首次碰撞仍由 Area2D 信号即时触发。
var obstacle_contact_hz: float = 0.0
## 陨石拖尾/火星密度缩放。
var meteor_fx_scale: float = 1.0
## 关卡内是否允许高成本全屏反馈（大范围泛光、强震动叠加）。
var level_fullscreen_fx: bool = true


## 后端与遥测统一使用的小写平台标识。
## 微信单独返回 wechat，方便后端区分正式 msgSecCheck 审核链路。
func get_platform_id() -> String:
	if is_wechat:
		return "wechat"
	if is_douyin:
		return "douyin"
	if is_web:
		return "web"
	match OS.get_name().to_lower():
		"windows", "android", "ios", "linux", "macos":
			return OS.get_name().to_lower()
		_:
			return "unknown"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_web = OS.has_feature("web")
	is_mobile = OS.has_feature("mobile")
	if is_web:
		# 不能用 OS.has_feature("wechat")：Web/WeChat 共用同一个导出预设，
		# itch.io 等普通 Web 也会带上该 feature；微信又禁止 eval，不能用 eval 探测。
		# 微信模板在 game.js 启动前写入 window.__cableCarPlatform，这里只读标记。
		var platform_marker := ""
		var window_object: Variant = JavaScriptBridge.get_interface("window")
		if window_object != null:
			platform_marker = str(window_object.__cableCarPlatform)
		is_wechat = platform_marker == "wechat"
		is_douyin = platform_marker == "douyin"
	# 上传权限：普通 Web（非微信、非抖音，含 itch.io）禁止上传；其余端保留完整上传下载。
	can_upload_ugc = not is_web or is_wechat or is_douyin
	if is_wechat:
		max_fps = 60
		# 保持清晰度：DPR 1.5；性能靠 30Hz 背景/障碍、关闭全屏后处理和屏幕外裁剪。
		max_device_pixel_ratio = 1.5
		# 微信 WebView 的 draw call / 大画布重绘是主要瓶颈，而不是逻辑帧。
		# 背景/障碍视觉保持 30Hz（不再降到 15Hz），玩法逻辑与碰撞仍按物理帧。
		background_render_hz = 30.0
		hud_update_hz = 12.0
		atmosphere_blur_enabled = false
		atmosphere_pass_enabled = false
		background_particle_scale = 0.4
		obstacle_visual_hz = 30.0
		obstacle_contact_hz = 20.0
		meteor_fx_scale = 0.6
		level_fullscreen_fx = false
		allow_fullscreen = false
	elif is_web:
		max_fps = 60
		max_device_pixel_ratio = 1.5
		background_render_hz = 30.0
		hud_update_hz = 12.0
		atmosphere_blur_enabled = false
		# Web 也跳过全屏 BackBufferCopy；雾化直接画在背景里。
		atmosphere_pass_enabled = false
		background_particle_scale = 0.5
		obstacle_visual_hz = 30.0
		obstacle_contact_hz = 20.0
		meteor_fx_scale = 0.65
		level_fullscreen_fx = true
		allow_fullscreen = false
	elif is_mobile:
		# Android/iOS 原生渲染保持完整画质，仅限制帧率。
		max_fps = 60
		max_device_pixel_ratio = 0.0
		background_render_hz = 0.0
		hud_update_hz = 0.0
		atmosphere_blur_enabled = true
		atmosphere_pass_enabled = true
		background_particle_scale = 1.0
		obstacle_visual_hz = 0.0
		obstacle_contact_hz = 0.0
		meteor_fx_scale = 1.0
		level_fullscreen_fx = true
		allow_fullscreen = false
	else:
		max_fps = 0
		max_device_pixel_ratio = 0.0
		background_render_hz = 0.0
		hud_update_hz = 0.0
		atmosphere_blur_enabled = true
		atmosphere_pass_enabled = true
		background_particle_scale = 1.0
		obstacle_visual_hz = 0.0
		obstacle_contact_hz = 0.0
		meteor_fx_scale = 1.0
		level_fullscreen_fx = true
		allow_fullscreen = true
	if max_fps > 0:
		Engine.max_fps = max_fps

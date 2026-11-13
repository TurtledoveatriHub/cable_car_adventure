class_name SkyBackdrop
extends Control
## 程序化天空/乐园背景。菜单、选关、排行榜和游戏内共用。
## 游戏内把 camera_x 传给本节点即可获得分层视差，不依赖任何外部图片素材。

## 天空顶部颜色
@export var top_color: Color = Color(0.42, 0.82, 0.96)
## 天空底部颜色
@export var bottom_color: Color = Color(1.0, 0.95, 0.74)
## 远山颜色
@export var far_mountain_color: Color = Color(0.5, 0.84, 0.82)
## 近山颜色
@export var near_mountain_color: Color = Color(0.18, 0.72, 0.66)
## 阳光与装饰强调色
@export var accent_color: Color = Color(1.0, 0.78, 0.25)
## 游戏内模式会减少前景装饰
@export var game_mode: bool = false
## 游戏内相机水平坐标，用于视差
@export var camera_x: float = 0.0
## 菜单背景的缓慢自动滚动速度
@export var auto_scroll_speed: float = 6.0

@export_category("大气透视 / 景深")
## 背景雾化颜色（建议使用与当前关卡天空接近的浅灰蓝）
@export var atmosphere_haze_color: Color = Color(0.70, 0.80, 0.88)
## 雾化强度；0 表示不雾化，越小越通透
@export_range(0.0, 0.35, 0.01) var atmosphere_haze_strength: float = 0.10
## 背景去饱和比例；0 表示保持原色，越大越灰
@export_range(0.0, 0.6, 0.01) var atmosphere_desaturation: float = 0.14
## 背景压暗比例；0 表示不压暗
@export_range(0.0, 0.5, 0.01) var atmosphere_darken: float = 0.06
## 背景模糊半径（像素）；0 表示关闭景深模糊
@export_range(0.0, 6.0, 0.1) var atmosphere_blur_radius: float = 1.2

## 大背景 id；paradise 使用现有程序化乐园
var background_id: String = "paradise"
var _background_texture: Texture2D
var _style_tint: Color = Color(1, 1, 1, 0)
var _style_alpha: float = 0.0
var _style_id: String = "sky"
var _atmosphere_copy: BackBufferCopy
var _atmosphere_overlay: ColorRect
var _atmosphere_material: ShaderMaterial

var _time: float = 0.0
var _auto_scroll: float = 0.0
var _redraw_accum: float = 0.0

# ---- 天空渐变缓存 ----
## 渐变与地平线光晕都只随 Y 变化、在 X 方向是常量，因此可以烘成一张「1 × 高度」的纹理，
## 绘制时横向拉伸即可——横向拉伸不会损失任何信息，而内存只占约 3KB。
## 原先每帧（30Hz）要画 72 条色带 + 10 条光晕 = 82 次 draw_rect，是背景绘制里最重的一块，
## 缓存后降为 1 次 draw_texture_rect。
var _sky_gradient_texture: ImageTexture
## 缓存键：高度 + 上下渐变色。apply_theme 改写配色时键自动失效并重建。
var _sky_gradient_key: String = ""
const SKY_BAND_COUNT := 72
const SKY_GLOW_COUNT := 10


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_setup_atmosphere()


func _process(delta: float) -> void:
	_time += delta
	_auto_scroll += delta * auto_scroll_speed
	if _atmosphere_copy != null:
		_atmosphere_copy.visible = game_mode
	if _atmosphere_overlay != null:
		_atmosphere_overlay.visible = game_mode
		_sync_atmosphere()
	var render_hz := PlatformConfig.background_render_hz
	if render_hz <= 0.0:
		queue_redraw()
	else:
		_redraw_accum += delta
		if _redraw_accum >= 1.0 / render_hz:
			_redraw_accum = 0.0
			queue_redraw()


func _setup_atmosphere() -> void:
	if not PlatformConfig.atmosphere_pass_enabled:
		# 微信/Web：不做全屏 BackBufferCopy + Shader 采样。
		return
	var shader := load("res://scripts/ui/background_atmosphere.gdshader") as Shader
	if shader == null:
		return
	_atmosphere_copy = BackBufferCopy.new()
	_atmosphere_copy.name = "AtmosphereCopy"
	_atmosphere_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(_atmosphere_copy)
	_atmosphere_material = ShaderMaterial.new()
	_atmosphere_material.shader = shader
	_atmosphere_overlay = ColorRect.new()
	_atmosphere_overlay.name = "AtmosphereOverlay"
	_atmosphere_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_atmosphere_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atmosphere_overlay.color = Color.WHITE
	_atmosphere_overlay.material = _atmosphere_material
	add_child(_atmosphere_overlay)
	_atmosphere_copy.visible = game_mode
	_atmosphere_overlay.visible = game_mode
	_sync_atmosphere()


func _sync_atmosphere() -> void:
	if _atmosphere_material == null:
		return
	var blur := atmosphere_blur_radius if PlatformConfig.atmosphere_blur_enabled else 0.0
	_atmosphere_material.set_shader_parameter("blur_radius", blur)
	_atmosphere_material.set_shader_parameter("desaturation", atmosphere_desaturation)
	_atmosphere_material.set_shader_parameter("haze_color", atmosphere_haze_color)
	_atmosphere_material.set_shader_parameter("haze_strength", atmosphere_haze_strength)
	_atmosphere_material.set_shader_parameter("darken", atmosphere_darken)


## 从关卡 JSON 的 theme 字段应用配色。
func apply_theme(theme_data: Dictionary, new_background_id: String = "paradise") -> void:
	background_id = new_background_id if not new_background_id.is_empty() else "paradise"
	_style_id = str(theme_data.get("id", "sky"))
	if not ["sky", "sunset", "night", "gray"].has(_style_id):
		_style_id = "sky"
	_background_texture = null
	_style_alpha = 0.0
	if LevelData.BACKGROUNDS.has(background_id):
		var path := str(LevelData.BACKGROUNDS[background_id].get("texture", ""))
		if not path.is_empty():
			var variant_path := path.get_basename() + "_" + _style_id + ".png"
			if ResourceLoader.exists(variant_path):
				_background_texture = load(variant_path) as Texture2D
			else:
				_background_texture = load(path) as Texture2D
				_style_alpha = clampf(float(theme_data.get("tint_alpha", 0.30)), 0.0, 0.85)
	_style_tint = _parse_color(theme_data.get("tint", ""), top_color)
	top_color = _parse_color(theme_data.get("sky_top", ""), top_color)
	bottom_color = _parse_color(theme_data.get("sky_bottom", ""), bottom_color)
	far_mountain_color = _parse_color(theme_data.get("mountain_far", ""), far_mountain_color)
	near_mountain_color = _parse_color(theme_data.get("mountain_near", ""), near_mountain_color)
	accent_color = _parse_color(theme_data.get("accent", ""), accent_color)
	queue_redraw()


func _parse_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	var text := str(value)
	return Color.from_string(text, fallback) if not text.is_empty() else fallback


func _draw() -> void:
	var width := size.x
	var height := size.y
	if width <= 0.0 or height <= 0.0:
		return
	if _background_texture != null:
		var texture_size := _background_texture.get_size()
		if texture_size.x > 0.0 and texture_size.y > 0.0:
			var cover_scale := maxf(width / texture_size.x, height / texture_size.y)
			var draw_size := texture_size * cover_scale
			var draw_pos := Vector2((width - draw_size.x) * 0.5, (height - draw_size.y) * 0.5)
			draw_texture_rect(_background_texture, Rect2(draw_pos, draw_size), false)
		if _style_alpha > 0.0:
			draw_rect(Rect2(0, 0, width, height), Color(_style_tint.r, _style_tint.g, _style_tint.b, _style_alpha))
		_draw_background_effects(width, height)
		_draw_cheap_haze(width, height)
		return
	_draw_sky(width, height)
	_draw_sun(width, height)
	_draw_clouds(width, height)
	_draw_mountains(width, height)
	_draw_theme_park(width, height)
	_draw_foreground(width, height)
	_draw_cheap_haze(width, height)


## 无后处理时的近似大气透视：单个半透明矩形，成本远低于全屏 shader。
func _draw_cheap_haze(width: float, height: float) -> void:
	if not game_mode or PlatformConfig.atmosphere_pass_enabled:
		return
	draw_rect(
		Rect2(0, 0, width, height),
		Color(atmosphere_haze_color.r, atmosphere_haze_color.g, atmosphere_haze_color.b, atmosphere_haze_strength * 0.55)
	)


func _draw_background_effects(width: float, height: float) -> void:
	# Every background gets visible ambient motion; density/colour changes per scene.
	match background_id:
		"snow":
			for index in int(150.0 * PlatformConfig.background_particle_scale):
				var x := fmod(float(index * 137) + _time * (12.0 + float(index % 7) * 5.0), width)
				var y := fmod(float(index * 83) + _time * (24.0 + float(index % 5) * 8.0), height)
				draw_circle(Vector2(x, y), 1.2 + float(index % 3) * 0.8, Color(0.96, 0.99, 1.0, 0.72))
		"clouds":
			for index in int(12.0 * PlatformConfig.background_particle_scale):
				var x := fmod(float(index * 190) + _time * (9.0 + index * 1.3), width + 420.0) - 210.0
				var y := 70.0 + index * 47.0
				_draw_soft_ellipse(Vector2(x, y), Vector2(165, 34), Color(1, 0.99, 0.95, 0.16))
		"dream":
			for index in int(80.0 * PlatformConfig.background_particle_scale):
				var x := float((index * 191) % 1280)
				var y := float((index * 73) % 420) + 20.0
				var twinkle := 0.25 + 0.75 * absf(sin(_time * 1.8 + index))
				draw_circle(Vector2(x, y), 1.5 + float(index % 3), Color(1, 0.92, 0.62, 0.55 * twinkle))
			var meteor_x := fmod(_time * 90.0, width + 400.0) - 200.0
			draw_line(Vector2(meteor_x, 80), Vector2(meteor_x + 90, 130), Color(1, 0.88, 0.65, 0.45), 2.0, true)
		"forest":
			for index in int(42.0 * PlatformConfig.background_particle_scale):
				var x := float((index * 211) % 1280) + sin(_time * 0.4 + index) * 18.0
				var y := 280.0 + float((index * 97) % 360) + cos(_time * 0.5 + index * 1.7) * 12.0
				var pulse := 0.3 + 0.7 * absf(sin(_time * 1.2 + index * 0.7))
				draw_circle(Vector2(x, y), 2.0 + float(index % 2), Color(1, 0.86, 0.28, 0.60 * pulse))
			for index in 3:
				var mist_x := fmod(_time * 5.0 + index * 430.0, width + 500.0) - 250.0
				_draw_soft_ellipse(Vector2(mist_x, 520.0 + index * 55.0), Vector2(260, 28), Color(0.85, 0.95, 0.85, 0.055))
		"paradise":
			for index in 6:
				var x := fmod(float(index * 250) + _time * (5.0 + index * 1.7), width + 240.0) - 120.0
				_draw_soft_ellipse(Vector2(x, 105.0 + index * 46.0), Vector2(100, 20), Color(1, 1, 1, 0.16))
			for index in 3:
				var bx := fmod(float(index * 390) + _time * 12.0, width + 260.0) - 130.0
				var by := 210.0 + index * 75.0 + sin(_time * 0.7 + index) * 14.0
				draw_circle(Vector2(bx, by), 8.0, Color(0.95, 0.42, 0.34, 0.72))
				draw_line(Vector2(bx, by + 8.0), Vector2(bx, by + 26.0), Color(0.75, 0.75, 0.68, 0.55), 1.5)


func _draw_soft_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 24:
		var angle := TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)


func _draw_sky(width: float, height: float) -> void:
	var texture := _get_sky_gradient_texture(height)
	if texture != null:
		# 纹理高度 == 绘制高度，纵向 1:1 无插值；横向是常量色，拉伸不损失信息。
		draw_texture_rect(texture, Rect2(0, 0, width, height), false)
		return
	# 兜底：无法创建纹理时仍按原逐条绘制，保证画面不缺失。
	_draw_sky_bands(width, height)


## 原逐条绘制路径，保留作为纹理创建失败时的兜底。
func _draw_sky_bands(width: float, height: float) -> void:
	var band_height := height / float(SKY_BAND_COUNT)
	for index in SKY_BAND_COUNT:
		var ratio := float(index) / float(SKY_BAND_COUNT - 1)
		var color := top_color.lerp(bottom_color, pow(ratio, 0.82))
		draw_rect(Rect2(0, index * band_height, width, band_height + 1.0), color)
	# 靠近地平线的暖色光晕。
	for index in SKY_GLOW_COUNT:
		var glow_ratio := float(index) / float(SKY_GLOW_COUNT)
		var glow_rect := Rect2(0, height * (0.54 + glow_ratio * 0.22), width, height * 0.04)
		draw_rect(glow_rect, Color(1.0, 0.92, 0.62, 0.025 * (1.0 - glow_ratio)))


## 取（必要时重建）天空渐变缓存纹理。键含高度与上下渐变色，配色变化时自动失效。
func _get_sky_gradient_texture(height: float) -> ImageTexture:
	if height <= 0.0:
		return null
	var pixel_height := int(ceilf(height))
	var key := "%d|%s|%s" % [pixel_height, top_color.to_html(), bottom_color.to_html()]
	if _sky_gradient_texture != null and _sky_gradient_key == key:
		return _sky_gradient_texture
	var image := Image.create_empty(1, pixel_height, false, Image.FORMAT_RGBA8)
	if image == null:
		return null
	var band_height := float(pixel_height) / float(SKY_BAND_COUNT)
	# 逐行合成：先取该行所属色带的底色，再把覆盖到它的暖色光晕按 alpha 依次叠加。
	# 这与原先「先画 72 条色带、再画 10 条半透明光晕」的结果在数学上等价。
	var glow_top := float(pixel_height) * 0.54
	var glow_band := float(pixel_height) * 0.22
	var glow_height := float(pixel_height) * 0.04
	for y in pixel_height:
		var band_index := clampi(int(floorf(float(y) / band_height)), 0, SKY_BAND_COUNT - 1)
		var ratio := float(band_index) / float(SKY_BAND_COUNT - 1)
		var color := top_color.lerp(bottom_color, pow(ratio, 0.82))
		for glow_index in SKY_GLOW_COUNT:
			var glow_ratio := float(glow_index) / float(SKY_GLOW_COUNT)
			var glow_y := glow_top + glow_ratio * glow_band
			if float(y) >= glow_y and float(y) < glow_y + glow_height:
				var glow_color := Color(1.0, 0.92, 0.62, 0.025 * (1.0 - glow_ratio))
				color = glow_color.lerp(color, 1.0 - glow_color.a)
		image.set_pixel(0, y, color)
	var created := ImageTexture.create_from_image(image)
	if created == null:
		return null
	_sky_gradient_texture = created
	_sky_gradient_key = key
	return created


func _draw_sun(width: float, height: float) -> void:
	var scroll := _auto_scroll + camera_x * 0.015
	var sun_position := Vector2(width * 0.8 - fmod(scroll, width * 0.2), height * 0.21)
	for index in 5:
		var radius := 54.0 + index * 22.0
		draw_circle(sun_position, radius, Color(1.0, 0.9, 0.5, 0.035))
	draw_circle(sun_position, 43.0, accent_color)
	draw_circle(sun_position, 35.0, Color(1.0, 0.94, 0.66))
	for ray in 12:
		var angle := TAU * float(ray) / 12.0 + _time * 0.04
		draw_line(
			sun_position + Vector2(cos(angle), sin(angle)) * 52.0,
			sun_position + Vector2(cos(angle), sin(angle)) * 66.0,
			Color(1.0, 0.92, 0.58, 0.42),
			3.0,
			true
		)


func _draw_clouds(width: float, _height: float) -> void:
	var scroll := _auto_scroll * 0.7 + camera_x * 0.055
	var cloud_specs := [
		Vector2(90, 132),
		Vector2(360, 88),
		Vector2(690, 164),
		Vector2(1030, 104),
		Vector2(1220, 220),
	]
	for index in cloud_specs.size():
		var base: Vector2 = cloud_specs[index]
		var wrapped_x := fmod(base.x - scroll + index * 143.0, width + 360.0) - 180.0
		var cloud_position := Vector2(wrapped_x, base.y + sin(_time * 0.25 + index) * 4.0)
		var cloud_scale := 0.7 + float(index % 3) * 0.18
		_draw_cloud(cloud_position, cloud_scale, 0.72 if game_mode else 0.92)


func _draw_cloud(cloud_center: Vector2, cloud_scale: float, alpha: float) -> void:
	var white := Color(1.0, 1.0, 0.98, alpha)
	var shadow := Color(0.86, 0.95, 0.98, alpha * 0.7)
	draw_circle(cloud_center + Vector2(-35, 8) * cloud_scale, 24.0 * cloud_scale, shadow)
	draw_circle(cloud_center + Vector2(0, 0) * cloud_scale, 34.0 * cloud_scale, white)
	draw_circle(cloud_center + Vector2(34, 6) * cloud_scale, 25.0 * cloud_scale, white)
	draw_circle(cloud_center + Vector2(-12, -16) * cloud_scale, 22.0 * cloud_scale, white)
	draw_circle(cloud_center + Vector2(15, -13) * cloud_scale, 18.0 * cloud_scale, white)
	draw_circle(cloud_center + Vector2(48, 11) * cloud_scale, 16.0 * cloud_scale, shadow)


func _draw_mountains(width: float, height: float) -> void:
	var scroll_far := _auto_scroll * 0.18 + camera_x * 0.055
	_draw_ridge(
		width,
		height,
		height * 0.68,
		scroll_far,
		far_mountain_color.lightened(0.1),
		0.0042,
		0.12
	)
	var scroll_near := _auto_scroll * 0.3 + camera_x * 0.11
	_draw_ridge(
		width,
		height,
		height * 0.78,
		scroll_near,
		near_mountain_color,
		0.0056,
		0.3
	)


func _draw_ridge(
	width: float,
	height: float,
	base_y: float,
	offset: float,
	color: Color,
	frequency: float,
	alpha: float
) -> void:
	var points := PackedVector2Array()
	points.append(Vector2(-40, height))
	for x in range(-40, int(width) + 60, 14):
		var sample := float(x) + offset
		var y := base_y
		y += sin(sample * frequency) * 30.0
		y += sin(sample * frequency * 2.37 + 1.6) * 16.0
		y += sin(sample * frequency * 0.47) * 22.0
		points.append(Vector2(x, y))
	points.append(Vector2(width + 40, height))
	draw_colored_polygon(points, Color(color, alpha + 0.18))
	# 山顶亮边：draw_multiline 每两个相邻点构成一条独立线段，
	# 与原先逐段 draw_line 的线段集合、颜色、线宽、抗锯齿完全一致，只是合并成一次绘制指令。
	var ridge_lines := PackedVector2Array()
	for index in range(1, points.size() - 1):
		if absf(points[index].y - points[index - 1].y) > 0.8:
			ridge_lines.append(points[index])
			ridge_lines.append(points[index - 1])
	if ridge_lines.size() >= 2:
		draw_multiline(ridge_lines, Color(1, 1, 1, 0.07), 2.0, true)


func _draw_theme_park(width: float, height: float) -> void:
	# 游戏内隐去远景乐园设施，避免与三条可碰撞轨道产生视觉混淆。
	if game_mode:
		return
	var parallax := _auto_scroll * 0.42 + camera_x * 0.2
	_draw_ferris_wheel(Vector2(170.0 - fmod(parallax, 300.0), height * 0.63), 78.0)
	_draw_background_loop(Vector2(width * 0.66 - fmod(parallax, 400.0), height * 0.63), 105.0)
	# 远处帐篷和旗杆。
	var tent_x := 520.0 - fmod(parallax * 1.2, 700.0)
	_draw_tent(Vector2(tent_x, height * 0.82), 46.0, Color(0.95, 0.37, 0.36))
	_draw_tent(Vector2(tent_x + 98, height * 0.83), 34.0, Color(0.2, 0.66, 0.84))


func _draw_ferris_wheel(center: Vector2, radius: float) -> void:
	var ink := Color(0.14, 0.25, 0.34, 0.62)
	var rim := Color(0.94, 0.98, 1.0, 0.48)
	var leg_spread := radius * 0.8
	draw_line(center, center + Vector2(-leg_spread, radius * 0.85), ink, 4.0, true)
	draw_line(center, center + Vector2(leg_spread, radius * 0.85), ink, 4.0, true)
	draw_arc(center, radius, 0, TAU, 48, ink, 4.0, true)
	draw_arc(center, radius - 5.0, 0, TAU, 48, rim, 1.5, true)
	var wheel_rotation := _time * 0.16
	for index in 12:
		var angle := wheel_rotation + TAU * float(index) / 12.0
		var end := center + Vector2(cos(angle), sin(angle)) * (radius - 4.0)
		draw_line(center, end, Color(ink, 0.45), 1.5, true)
	for index in 8:
		var angle := wheel_rotation + TAU * float(index) / 8.0
		var cabin_position := center + Vector2(cos(angle), sin(angle)) * radius
		draw_circle(cabin_position, 6.0, Color(1.0, 0.82, 0.3, 0.8))
		draw_arc(cabin_position, 6.0, 0, TAU, 12, ink, 1.5, true)
	draw_circle(center, 9.0, Color(1.0, 0.95, 0.8, 0.9))
	draw_arc(center, 9.0, 0, TAU, 18, ink, 2.0, true)


func _draw_background_loop(center: Vector2, radius: float) -> void:
	var ink := Color(0.19, 0.29, 0.39, 0.38)
	var highlight := Color(0.9, 0.97, 1.0, 0.32)
	# 竖直回环轨道。
	draw_arc(center + Vector2(0, -radius * 0.5), radius, -PI * 0.92, PI * 0.92, 64, ink, 7.0, true)
	draw_arc(center + Vector2(0, -radius * 0.5), radius, -PI * 0.92, PI * 0.92, 64, highlight, 2.0, true)
	draw_line(center + Vector2(-radius, -radius * 0.5), center + Vector2(-radius * 2.5, radius * 0.9), ink, 5.0, true)
	draw_line(center + Vector2(radius, -radius * 0.5), center + Vector2(radius * 2.5, radius * 0.9), ink, 5.0, true)
	draw_line(center + Vector2(-radius * 2.5, radius * 0.9), center + Vector2(radius * 2.5, radius * 0.9), ink, 4.0, true)
	var cart_angle := _time * 0.9
	var orbit_center := center + Vector2(0, -radius * 0.5)
	var cart_pos := orbit_center + Vector2(cos(cart_angle), sin(cart_angle)) * radius
	draw_rect(Rect2(cart_pos - Vector2(7, 5), Vector2(14, 10)), Color(0.95, 0.37, 0.36, 0.75))
	draw_rect(Rect2(cart_pos - Vector2(7, 5), Vector2(14, 10)), Color(ink, 0.6), false, 1.5)


func _draw_tent(base: Vector2, half_width: float, color: Color) -> void:
	var ink := Color(0.14, 0.25, 0.34, 0.58)
	var points := PackedVector2Array([
		base + Vector2(-half_width, 0),
		base + Vector2(0, -half_width * 1.45),
		base + Vector2(half_width, 0),
	])
	draw_colored_polygon(points, Color(color, 0.72))
	draw_polyline(
		PackedVector2Array([points[0], points[1], points[2], points[0]]),
		ink,
		2.5,
		true
	)
	draw_line(base + Vector2(0, -half_width * 1.45), base + Vector2(0, -half_width * 1.7), ink, 2.0, true)
	var flag := PackedVector2Array([
		base + Vector2(0, -half_width * 1.7),
		base + Vector2(half_width * 0.45, -half_width * 1.55),
		base + Vector2(0, -half_width * 1.4),
	])
	draw_colored_polygon(flag, Color(1, 0.82, 0.25, 0.75))


func _draw_foreground(width: float, height: float) -> void:
	# 底部地面和草坡，给菜单内容提供稳定的视觉底座。
	var ground_points := PackedVector2Array([
		Vector2(0, height),
		Vector2(0, height * 0.88),
		Vector2(width * 0.16, height * 0.9),
		Vector2(width * 0.3, height * 0.875),
		Vector2(width * 0.52, height * 0.9),
		Vector2(width * 0.72, height * 0.87),
		Vector2(width * 0.88, height * 0.9),
		Vector2(width, height * 0.86),
		Vector2(width, height),
	])
	draw_colored_polygon(ground_points, near_mountain_color.darkened(0.12))
	var edge := ground_points.duplicate()
	edge.remove_at(0)
	edge.remove_at(edge.size() - 1)
	draw_polyline(edge, near_mountain_color.darkened(0.38), 4.0, true)

	if game_mode:
		return

	# 菜单装饰：气球、灌木和路灯。
	_draw_balloons(Vector2(width * 0.91, height * 0.78))
	_draw_bush(Vector2(width * 0.06, height * 0.9), 1.2)
	_draw_bush(Vector2(width * 0.56, height * 0.915), 0.85)
	_draw_lamp(Vector2(width * 0.83, height * 0.88))


func _draw_balloons(anchor: Vector2) -> void:
	var colors := [Color(0.95, 0.37, 0.36), Color(1.0, 0.82, 0.25), Color(0.18, 0.66, 0.84)]
	for index in 3:
		var offset := Vector2((index - 1) * 24.0, -40.0 - absf(index - 1) * 11.0)
		var bob := sin(_time * 0.8 + index) * 4.0
		var string_end := anchor + Vector2((index - 1) * 4.0, 0)
		draw_line(anchor, anchor + offset + Vector2(0, bob - 8), Color(0.2, 0.3, 0.36, 0.45), 1.6, true)
		draw_circle(anchor + offset + Vector2(0, bob), 17.0, colors[index])
		draw_circle(anchor + offset + Vector2(-5, bob - 6), 5.0, Color(1, 1, 1, 0.28))
		draw_line(string_end, anchor + offset + Vector2(0, bob - 8), Color(0.2, 0.3, 0.36, 0.45), 1.6, true)


func _draw_bush(base: Vector2, bush_scale: float) -> void:
	var dark := near_mountain_color.darkened(0.38)
	draw_circle(base + Vector2(-18, -12) * bush_scale, 24.0 * bush_scale, near_mountain_color.darkened(0.22))
	draw_circle(base + Vector2(10, -18) * bush_scale, 28.0 * bush_scale, near_mountain_color.darkened(0.12))
	draw_circle(base + Vector2(34, -8) * bush_scale, 18.0 * bush_scale, near_mountain_color.darkened(0.25))
	draw_circle(base + Vector2(-2, -8) * bush_scale, 3.0 * bush_scale, dark)
	draw_circle(base + Vector2(18, -14) * bush_scale, 2.5 * bush_scale, dark)


func _draw_lamp(base: Vector2) -> void:
	var ink := Color(0.16, 0.27, 0.35, 0.75)
	draw_line(base + Vector2(0, 0), base + Vector2(0, -120), ink, 5.0, true)
	draw_arc(base + Vector2(0, -120), 22.0, PI * 0.1, PI * 0.9, 12, ink, 4.0, true)
	draw_circle(base + Vector2(0, -100), 9.0, Color(1.0, 0.9, 0.56, 0.9))
	draw_circle(base + Vector2(0, -100), 20.0, Color(1.0, 0.9, 0.56, 0.08))

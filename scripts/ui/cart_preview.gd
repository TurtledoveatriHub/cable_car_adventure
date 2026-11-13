class_name CartPreview
extends Control
## 缆车选择预览：先画 BGSprite，再画 BodySprite，保持它们在场景里的相对位置。

@export_category("预览")
## 未解锁缆车的灰色剪影颜色
@export var locked_silhouette_color: Color = Color(0.28, 0.31, 0.34, 0.72)

var profile: CartProfile
var locked: bool = false
var _silhouette_cache: Dictionary = {}


func setup(value: CartProfile, is_locked: bool = false) -> void:
	profile = value
	locked = is_locked
	queue_redraw()


func _draw() -> void:
	if profile == null:
		return
	var body_region := profile.body_region
	var background_region := profile.background_region
	if body_region.size.x <= 0.0 and profile.texture != null:
		body_region = Rect2(Vector2.ZERO, profile.texture.get_size())
	var body_scale := profile.body_scale
	if body_scale.x <= 0.0:
		body_scale = Vector2.ONE
	var fit := minf(size.x / maxf(1.0, body_region.size.x * body_scale.x), size.y / maxf(1.0, body_region.size.y * body_scale.y))
	var center := size * 0.5
	if profile.background_texture != null and background_region.size.x > 0.0:
		var bg_scale := profile.background_scale
		if bg_scale.x <= 0.0:
			bg_scale = Vector2.ONE
		var bg_size := background_region.size * bg_scale * fit
		var bg_center := center + (profile.background_position - profile.body_position) * fit
		if locked:
			_draw_silhouette(profile.background_texture, Rect2(bg_center - bg_size * 0.5, bg_size), background_region)
		else:
			draw_texture_rect_region(
				profile.background_texture,
				Rect2(bg_center - bg_size * 0.5, bg_size),
				background_region,
				profile.background_modulate
			)
	if profile.texture != null and body_region.size.x > 0.0:
		var body_size := body_region.size * body_scale * fit
		if locked:
			_draw_silhouette(profile.texture, Rect2(center - body_size * 0.5, body_size), body_region)
		else:
			draw_texture_rect_region(
				profile.texture,
				Rect2(center - body_size * 0.5, body_size),
				body_region,
				profile.body_modulate
			)

func _draw_silhouette(source: Texture2D, destination: Rect2, region: Rect2) -> void:
	if source == null:
		return
	var key := "%s:%s" % [source.get_instance_id(), region]
	var texture: Texture2D = _silhouette_cache.get(key, null) as Texture2D
	if texture == null:
		var image := source.get_image()
		if image == null:
			return
		image = image.duplicate()
		image.convert(Image.FORMAT_RGBA8)
		if region.size.x > 0.0 and region.size.y > 0.0:
			image = image.get_region(Rect2i(region))
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				image.set_pixel(x, y, Color(locked_silhouette_color.r, locked_silhouette_color.g, locked_silhouette_color.b, pixel.a * locked_silhouette_color.a))
		texture = ImageTexture.create_from_image(image)
		_silhouette_cache[key] = texture
	draw_texture_rect(texture, destination, false)

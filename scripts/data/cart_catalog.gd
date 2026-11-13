class_name CartCatalog
extends RefCounted
## 缆车目录：每种缆车是独立场景；目录只读取场景根节点的导出参数用于 UI。

static var _profile_cache: Dictionary = {}

const SCENE_PATHS := {
	"dove": "res://scenes/carts/dove.tscn",
	"fish": "res://scenes/carts/fish.tscn",
	"genius": "res://scenes/carts/genius.tscn",
	"monster": "res://scenes/carts/monster.tscn",
	"dragon": "res://scenes/carts/dragon.tscn",
	"frog": "res://scenes/carts/frog.tscn",
	"tori": "res://scenes/carts/tori.tscn",
	"woma": "res://scenes/carts/woma.tscn",
	"immortal": "res://scenes/carts/immortal.tscn",
}


static func get_scene(cart_id: String) -> PackedScene:
	var path := str(SCENE_PATHS.get(cart_id, ""))
	return load(path) as PackedScene if not path.is_empty() else null


static func get_all() -> Array[CartProfile]:
	var profiles: Array[CartProfile] = []
	for cart_id in SCENE_PATHS.keys():
		var profile := get_profile(str(cart_id))
		if profile != null:
			profiles.append(profile)
	return profiles


## 主菜单空闲时逐帧预热缆车档案，避免第一次打开个人主页/选关时集中加载九个场景。
static func prewarm_deferred(host: Node) -> void:
	for cart_id in SCENE_PATHS.keys():
		if not is_instance_valid(host) or host.is_queued_for_deletion():
			return
		if not _profile_cache.has(str(cart_id)):
			get_profile(str(cart_id))
		await host.get_tree().process_frame


static func get_profile(cart_id: String) -> CartProfile:
	if _profile_cache.has(cart_id):
		return _profile_cache[cart_id] as CartProfile
	var scene := get_scene(cart_id)
	if scene == null:
		return null
	var cart := scene.instantiate() as CoasterController
	if cart == null:
		return null
	var profile := CartProfile.new()
	profile.id = cart.cart_id
	profile.display_name = cart.display_name
	var body := cart.get_node_or_null("BodySprite") as Sprite2D
	var background := cart.get_node_or_null("BGSprite") as Sprite2D
	profile.texture = body.texture if body != null else null
	profile.background_texture = background.texture if background != null else null
	profile.body_region = _sprite_region(body)
	profile.background_region = _sprite_region(background)
	profile.body_modulate = body.modulate if body != null else Color.WHITE
	profile.background_modulate = background.modulate if background != null else Color.WHITE
	profile.body_position = body.position if body != null else Vector2.ZERO
	profile.background_position = background.position if background != null else Vector2.ZERO
	profile.body_scale = body.scale if body != null else Vector2.ONE
	profile.background_scale = background.scale if background != null else Vector2.ONE
	profile.description = cart.description
	profile.unlock_level_id = cart.unlock_level_id
	profile.unlock_uploads = cart.unlock_uploads
	profile.unlock_stars = cart.unlock_stars
	cart.free()
	_profile_cache[cart_id] = profile
	return profile


static func _sprite_region(sprite: Sprite2D) -> Rect2:
	if sprite == null or sprite.texture == null:
		return Rect2()
	if sprite.region_enabled:
		return sprite.region_rect
	return Rect2(Vector2.ZERO, sprite.texture.get_size())


static func is_unlocked(profile: CartProfile) -> bool:
	if profile == null:
		return false
	if bool(SaveManager.get_setting("unlock_all_carts", false)):
		return true
	if not profile.unlock_level_id.is_empty() and not SaveManager.is_level_cleared(profile.unlock_level_id):
		return false
	if profile.unlock_uploads > 0 and CommunityService.get_user_upload_count() < profile.unlock_uploads:
		return false
	if profile.unlock_stars > 0 and SaveManager.get_total_stars() < profile.unlock_stars:
		return false
	return true


static func get_unlock_hint(profile: CartProfile) -> String:
	if profile == null:
		return ""
	var hints: Array[String] = []
	if not profile.unlock_level_id.is_empty():
		var level_title := profile.unlock_level_id
		var summary := LevelCatalog.get_summary(profile.unlock_level_id)
		if not summary.is_empty():
			level_title = str(summary.get("name", level_title))
		hints.append("通关“%s”" % level_title)
	if profile.unlock_uploads > 0:
		hints.append("上传 %d 张自制关卡" % profile.unlock_uploads)
	if profile.unlock_stars > 0:
		hints.append("获取 %d 颗星星" % profile.unlock_stars)
	return "、".join(hints) if not hints.is_empty() else "默认解锁"

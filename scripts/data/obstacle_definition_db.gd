class_name ObstacleDefinitionDB
extends RefCounted
## 障碍 prefab id -> 独立的障碍场景。

const SCENE_PATHS := {
	"bird": "res://scenes/game/obstacles/bird.tscn",
	"crate": "res://scenes/game/obstacles/crate.tscn",
	"barrier": "res://scenes/game/obstacles/barrier.tscn",
	"hot_air_balloon": "res://scenes/game/obstacles/hot_air_balloon.tscn",
	"ferris_wheel": "res://scenes/game/obstacles/ferris_wheel.tscn",
	"large_ferris_wheel": "res://scenes/game/obstacles/large_ferris_wheel.tscn",
	"caterpillar": "res://scenes/game/obstacles/caterpillar.tscn",
	"vine": "res://scenes/game/obstacles/vine.tscn",
	"venus_flytrap": "res://scenes/game/obstacles/venus_flytrap.tscn",
	"snow_elf": "res://scenes/game/obstacles/snow_elf.tscn",
	"ice_crystal": "res://scenes/game/obstacles/ice_crystal.tscn",
	"storm": "res://scenes/game/obstacles/storm.tscn",
	"fan": "res://scenes/game/obstacles/fan.tscn",
	"flying_bird": "res://scenes/game/obstacles/flying_bird.tscn",
	"flying_fish": "res://scenes/game/obstacles/flying_fish.tscn",
	"meteor": "res://scenes/game/obstacles/meteor.tscn",
	"dream_elf": "res://scenes/game/obstacles/dream_elf.tscn",
	"bubble": "res://scenes/game/obstacles/bubble.tscn",
	"cannonball": "res://scenes/game/obstacles/cannonball.tscn",
	"dream_void": "res://scenes/game/obstacles/dream_void.tscn",
}


static func get_scene(prefab_id: String) -> PackedScene:
	var path := str(SCENE_PATHS.get(prefab_id, ""))
	if path.is_empty():
		return null
	return load(path) as PackedScene


static func get_prefab_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in SCENE_PATHS.keys():
		ids.append(str(key))
	return ids

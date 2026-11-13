class_name PassengerCatalog
extends RefCounted
## 乘客样式目录。

const PATHS: Array[String] = [
	"res://assets/passengers/passenger_1.tres",
	"res://assets/passengers/passenger_2.tres",
	"res://assets/passengers/passenger_3.tres",
	"res://assets/passengers/passenger_4.tres",
	"res://assets/passengers/passenger_5.tres",
	"res://assets/passengers/passenger_6.tres",
	"res://assets/passengers/passenger_7.tres",
	"res://assets/passengers/passenger_8.tres",
	"res://assets/passengers/passenger_9.tres",
	"res://assets/passengers/passenger_10.tres",
	"res://assets/passengers/passenger_11.tres",
	"res://assets/passengers/passenger_12.tres",
	"res://assets/passengers/passenger_13.tres",
	"res://assets/passengers/passenger_14.tres",
	"res://assets/passengers/passenger_15.tres",
]


static func get_all() -> Array[PassengerProfile]:
	var profiles: Array[PassengerProfile] = []
	for path in PATHS:
		var profile := load(path) as PassengerProfile
		if profile != null:
			profiles.append(profile)
	return profiles


static func get_profile(passenger_id: String) -> PassengerProfile:
	for profile in get_all():
		if profile.id == passenger_id:
			return profile
	return get_all()[0] if not get_all().is_empty() else null


static func random_profile() -> PassengerProfile:
	var profiles := get_all()
	if profiles.is_empty():
		return null
	var total_weight := 0.0
	for profile in profiles:
		total_weight += maxf(0.0, profile.spawn_weight)
	if total_weight <= 0.0:
		return profiles[randi_range(0, profiles.size() - 1)]
	var roll := randf() * total_weight
	for profile in profiles:
		roll -= maxf(0.0, profile.spawn_weight)
		if roll <= 0.0:
			return profile
	return profiles[profiles.size() - 1]


## 某个乘客在随机池中的实际概率（0~1），供编辑器/调试显示。
static func get_spawn_probability(passenger_id: String) -> float:
	var profiles := get_all()
	var total_weight := 0.0
	var target_weight := 0.0
	for profile in profiles:
		var weight := maxf(0.0, profile.spawn_weight)
		total_weight += weight
		if profile.id == passenger_id:
			target_weight = weight
	return target_weight / total_weight if total_weight > 0.0 else 0.0


static func random_texture() -> Texture2D:
	var profile := random_profile()
	return profile.texture if profile != null else null


## 随机纹理，尽量排除本轮已使用过的纹理，避免同一关卡乘客重复。
static func random_texture_excluding(exclude: Array[Texture2D]) -> Texture2D:
	for _attempt in 64:
		var profile := random_profile()
		if profile != null and profile.texture != null and not exclude.has(profile.texture):
			return profile.texture
	return null

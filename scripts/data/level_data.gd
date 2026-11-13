class_name LevelData
extends RefCounted
## 单轨关卡模型。轨道由轨道片段拼接，障碍/起终点都通过“轨道弧长 s”定位。
## 运行数据全部来自外部 JSON；脚本内不保存任何具体关卡内容。

const SCHEMA_VERSION := 2
const CART_ANCHOR_OFFSET := Vector2(0.0, 24.0)
const DEFAULT_THEME := {
	"sky_top": "#68cdf2",
	"sky_bottom": "#fff1b8",
	"mountain_far": "#80d8d2",
	"mountain_near": "#2ec4b6",
	"track": "#2f4b68",
	"track_highlight": "#b9d6e5",
	"accent": "#ff6b5b",
}
## 四种风格在 UI/轨道中的基础色；天空、地面和远景的实际色调由
## `tools/generate_backgrounds.py` 的 STYLE_GRADES / apply_style 逐背景生成。
const THEME_PRESETS := {
	"sky": {
		"label": "晴空",
		"tint": "#fff0c8", "tint_alpha": 0.10,
		"sky_top": "#68cdf2", "sky_bottom": "#fff1b8",
		"mountain_far": "#80d8d2", "mountain_near": "#2ec4b6",
		"track": "#2f4b68", "track_highlight": "#b9d6e5", "accent": "#ff6b5b",
	},
	"sunset": {
		"label": "黄昏",
		"tint": "#6f2d66", "tint_alpha": 0.32,
		"sky_top": "#f7a072", "sky_bottom": "#ffe6a7",
		"mountain_far": "#c98f9b", "mountain_near": "#75556f",
		"track": "#4a3048", "track_highlight": "#f4d3b8", "accent": "#ff8a5b",
	},
	"night": {
		"label": "星夜",
		"tint": "#07152f", "tint_alpha": 0.55,
		"sky_top": "#172a4f", "sky_bottom": "#315c7a",
		"mountain_far": "#29465c", "mountain_near": "#172d3b",
		"track": "#0d1b2a", "track_highlight": "#8ecae6", "accent": "#ffb703",
	},
	"gray": {
		"label": "灰白",
		"tint": "#56616a", "tint_alpha": 0.42,
		"sky_top": "#b8bdc3", "sky_bottom": "#eef0f2",
		"mountain_far": "#9aa1a8", "mountain_near": "#6d747b",
		"track": "#30363d", "track_highlight": "#e2e6ea", "accent": "#d95d4f",
	},
}
const VALID_MOTIONS := ["static", "oscillate_x", "oscillate_y", "circle", "ellipse"]

var schema_version: int = SCHEMA_VERSION
var id: String = ""
var name: String = ""
var subtitle: String = ""
var description: String = ""
var difficulty: int = 1
var source: String = "builtin"
var custom: bool = false

var track_data: Dictionary = {}
var track: TrackGeometry
var start_s: float = 60.0
var finish_s: float = 3000.0
var camera_bounds: Rect2 = Rect2()
var par_time: float = 60.0

## 关卡开局倒计时（秒）。关卡可调玩法参数只保留倒计时与 camera_bounds。
var countdown_seconds: float = 3.0
## 关卡时间限制（秒）；0 表示无限。超时直接失败。
var time_limit_seconds: float = 0.0
## 背景大场景：paradise / snow / clouds / dream
var background_id: String = "paradise"

var theme: Dictionary = DEFAULT_THEME.duplicate(true)
var obstacles: Array[Dictionary] = []
var analytics_tags: Array[String] = []

var raw: Dictionary = {}
var validation_errors: Array[String] = []


static func from_dictionary(data: Dictionary) -> LevelData:
	var level := LevelData.new()
	level.raw = data.duplicate(true)
	level.schema_version = int(data.get("schema_version", SCHEMA_VERSION))
	level.id = str(data.get("id", ""))
	level.name = str(data.get("name", "未命名关卡"))
	level.subtitle = str(data.get("subtitle", ""))
	level.description = str(data.get("description", ""))
	level.difficulty = clampi(int(data.get("difficulty", 1)), 1, 5)
	level.par_time = float(data.get("par_time", 60.0))
	level.countdown_seconds = clampf(float(data.get("countdown_seconds", 3.0)), 0.5, 10.0)
	level.time_limit_seconds = maxf(0.0, float(data.get("time_limit_seconds", 0.0)))
	level.background_id = str(data.get("background_id", "paradise"))
	level.source = str(data.get("source", "builtin"))
	level.custom = bool(data.get("custom", level.source == "user"))

	var theme_value: Variant = data.get("theme", {})
	if theme_value is Dictionary:
		level.theme = DEFAULT_THEME.duplicate(true).merged(theme_value, true)

	var track_value: Variant = data.get("track", {})
	if track_value is Dictionary:
		level.track_data = (track_value as Dictionary).duplicate(true)
		level.track = TrackGeometry.from_track_data(level.track_data)
		level.start_s = float(level.track_data.get("start_s", 60.0))
		level.finish_s = float(level.track_data.get("finish_s", level.track.total_length - 100.0 if level.track != null else 3000.0))
		level.camera_bounds = _sanitize_camera_bounds(data.get("camera_bounds", null), level.track)
	else:
		level.track = TrackGeometry.new()
		level.track.error_message = "缺少 track 对象"
		level.camera_bounds = Rect2(0, 0, 1280, 720)

	var obstacle_list: Variant = data.get("obstacles", [])
	if obstacle_list is Array:
		for item: Variant in obstacle_list:
			if item is Dictionary:
				level.obstacles.append(_sanitize_obstacle(item as Dictionary))

	var tags_value: Variant = data.get("analytics_tags", [])
	if tags_value is Array:
		for tag: Variant in tags_value:
			level.analytics_tags.append(str(tag))

	level.validation_errors = level._collect_validation_errors()
	return level


static func _sanitize_obstacle(data: Dictionary) -> Dictionary:
	var clean := data.duplicate(true)
	clean["flip_x"] = bool(clean.get("flip_x", false))
	clean["type"] = str(clean.get("type", "bird"))
	clean["s"] = float(clean.get("s", 0.0))
	clean["damage"] = maxi(1, int(clean.get("damage", 1)))
	clean["radius"] = maxf(10.0, float(clean.get("radius", 26.0)))
	var offset_value: Variant = clean.get("offset", {})
	if offset_value is Dictionary:
		clean["offset"] = Vector2(float(offset_value.get("x", 0.0)), float(offset_value.get("y", 0.0)))
	elif offset_value is Vector2:
		clean["offset"] = offset_value
	elif offset_value is Array and (offset_value as Array).size() >= 2:
		# 兼容旧 UGC 数据：早期序列化把 offset 写成了 [x, y]。
		clean["offset"] = Vector2(float((offset_value as Array)[0]), float((offset_value as Array)[1]))
	else:
		clean["offset"] = Vector2.ZERO
	var motion_value: Variant = clean.get("motion", {})
	if motion_value is Dictionary:
		var motion: Dictionary = (motion_value as Dictionary).duplicate(true)
		motion["type"] = str(motion.get("type", "static"))
		motion["speed"] = maxf(0.0, float(motion.get("speed", 1.2)))
		motion["phase"] = float(motion.get("phase", 0.0))
		var amp_value: Variant = motion.get("amplitude", {})
		if amp_value is Dictionary:
			motion["amplitude"] = Vector2(float(amp_value.get("x", 0.0)), float(amp_value.get("y", 0.0)))
		elif amp_value is Vector2:
			motion["amplitude"] = amp_value
		elif amp_value is Array and (amp_value as Array).size() >= 2:
			# 兼容旧 UGC 数据：早期序列化把 amplitude 写成了 [x, y]。
			motion["amplitude"] = Vector2(float((amp_value as Array)[0]), float((amp_value as Array)[1]))
		else:
			motion["amplitude"] = Vector2(40.0, 30.0)
		clean["motion"] = motion
	else:
		clean["motion"] = {
			"type": "static",
			"amplitude": Vector2.ZERO,
			"speed": 0.0,
			"phase": 0.0,
		}
	var raw_offsets: Variant = clean.get("collision_offsets", [])
	var offsets: Array[Vector2] = []
	if raw_offsets is Array:
		for item: Variant in raw_offsets:
			if item is Vector2:
				offsets.append(item)
			elif item is Dictionary:
				offsets.append(Vector2(float(item.get("x", 0.0)), float(item.get("y", 0.0))))
			elif item is Array and (item as Array).size() >= 2:
				offsets.append(Vector2(float((item as Array)[0]), float((item as Array)[1])))
	if offsets.is_empty():
		offsets.append(Vector2.ZERO)
	clean["collision_offsets"] = offsets
	var raw_radii: Variant = clean.get("collision_radii", [])
	var radii: Array[float] = []
	if raw_radii is Array:
		for item: Variant in raw_radii:
			radii.append(maxf(4.0, float(item)))
	if radii.is_empty():
		radii.append(float(clean.get("radius", 26.0)))
	clean["collision_radii"] = radii
	clean["interval_enabled"] = bool(clean.get("interval_enabled", false))
	clean["interval_period"] = maxf(0.2, float(clean.get("interval_period", 2.0)))
	clean["interval_active"] = clampf(float(clean.get("interval_active", 1.2)), 0.05, clean["interval_period"])
	clean["trigger_enabled"] = bool(clean.get("trigger_enabled", false))
	# 触发范围以障碍场景的 PlayerDetector 为准；旧关卡里的 trigger_radius 不再保留。
	clean.erase("trigger_radius")
	return clean


static func _sanitize_camera_bounds(value: Variant, track_geometry: TrackGeometry) -> Rect2:
	var fallback := Rect2(0, 0, 1280, 720)
	if track_geometry != null and track_geometry.is_valid():
		fallback = track_geometry.get_bounds(120.0)
	if value is Rect2:
		var rect := value as Rect2
		if rect.size.x > 64.0 and rect.size.y > 64.0:
			return rect
	elif value is Dictionary:
		var dict := value as Dictionary
		var rect := Rect2(
			float(dict.get("x", fallback.position.x)),
			float(dict.get("y", fallback.position.y)),
			float(dict.get("w", dict.get("width", fallback.size.x))),
			float(dict.get("h", dict.get("height", fallback.size.y)))
		)
		if rect.size.x > 64.0 and rect.size.y > 64.0:
			return rect
	elif value is Array and (value as Array).size() >= 4:
		var arr := value as Array
		var rect := Rect2(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
		if rect.size.x > 64.0 and rect.size.y > 64.0:
			return rect
	return fallback


func validate() -> Array[String]:
	return _collect_validation_errors()


func is_valid() -> bool:
	return validation_errors.is_empty()


func _collect_validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty():
		errors.append("缺少关卡 id")
	if name.is_empty():
		errors.append("缺少关卡名称")
	if track == null or not track.is_valid():
		errors.append("轨道无效：%s" % (track.error_message if track != null else "未构建"))
		return errors
	if track.total_length < 400.0:
		errors.append("轨道总长度至少 400 px")
	if start_s < 0.0 or start_s > track.total_length:
		errors.append("起点 start_s 不在轨道范围内")
	if finish_s < 0.0 or finish_s > track.total_length:
		errors.append("终点 finish_s 不在轨道范围内")
	if absf(finish_s - start_s) < 100.0:
		errors.append("起点与终点距离至少 100 px")
	if par_time <= 0.0:
		errors.append("par_time 必须大于 0")

	for index in obstacles.size():
		var obstacle := obstacles[index]
		var obstacle_s := float(obstacle.get("s", -1.0))
		if obstacle_s < 0.0 or obstacle_s > track.total_length:
			errors.append("障碍物 #%d 的 s 不在轨道范围内" % index)
		if not obstacle.has("prefab"):
			var motion: Dictionary = obstacle.get("motion", {})
			if not VALID_MOTIONS.has(str(motion.get("type", "static"))):
				errors.append("障碍物 #%d 的运动类型无效" % index)
			if float(obstacle.get("radius", 0.0)) < 8.0:
				errors.append("障碍物 #%d 的碰撞半径过小" % index)


	return errors


static func get_theme_preset(theme_id: String) -> Dictionary:
	var preset: Dictionary = (THEME_PRESETS.get(theme_id, THEME_PRESETS["sky"]) as Dictionary).duplicate(true)
	preset["id"] = theme_id
	preset.erase("label")
	return preset


## 五个大背景；同目录下的 `<background>_<style>.png` 是四套逐背景色调变体。
const BACKGROUNDS := {
	"paradise": {"label": "乐园", "texture": "res://assets/visuals/backgrounds/paradise.png"},
	"forest": {"label": "森林", "texture": "res://assets/visuals/backgrounds/forest.png"},
	"snow": {"label": "雪山", "texture": "res://assets/visuals/backgrounds/snow.png"},
	"clouds": {"label": "云层", "texture": "res://assets/visuals/backgrounds/clouds.png"},
	"dream": {"label": "梦境", "texture": "res://assets/visuals/backgrounds/dream.png"},
}


static func get_background_ids() -> Array[String]:
	return ["paradise", "forest", "snow", "clouds", "dream"]


static func get_theme_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in THEME_PRESETS.keys():
		ids.append(str(key))
	return ids


func get_theme_color(key: String, fallback: Color = Color.WHITE) -> Color:
	var raw_value := str(theme.get(key, ""))
	return Color.from_string(raw_value, fallback) if not raw_value.is_empty() else fallback


func get_start_position() -> Vector2:
	return track.sample_at(start_s) if track != null else Vector2.ZERO


func get_finish_position() -> Vector2:
	return track.sample_at(finish_s) if track != null else Vector2.ZERO


func is_forward_course() -> bool:
	return finish_s >= start_s


func get_track_length() -> float:
	return track.total_length if track != null else 0.0


func get_obstacle_motion_label(index: int) -> String:
	if index < 0 or index >= obstacles.size():
		return "无"
	var motion: Dictionary = obstacles[index].get("motion", {})
	match str(motion.get("type", "static")):
		"oscillate_x":
			return "左右移动"
		"oscillate_y":
			return "上下移动"
		"circle":
			return "圆周运动"
		"ellipse":
			return "椭圆运动"
		_:
			return "静止"


func get_summary() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"subtitle": subtitle,
		"description": description,
		"difficulty": difficulty,
		"par_time": par_time,
		"source": source,
		"custom": custom,
		"accent": str(theme.get("accent", "#ff6b5b")),
		"track_length": get_track_length(),
	}

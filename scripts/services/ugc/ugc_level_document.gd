class_name UgcLevelDocument
extends RefCounted
## UGC 关卡序列化 / 反序列化。
##
## 上传前把编辑器草稿整理成前后端一致的 JSON；下载后再次校验并交给
## LevelData 做玩法层校验。服务端会做同样的白名单与边界校验，客户端这一步
## 主要用于尽早报错、避免把损坏数据带进游戏。

const SCHEMA_VERSION := 2
const MAX_BYTES := 2 * 1024 * 1024
const MAX_PIECES := 300
const MAX_OBSTACLES := 500
const MAX_TRACK_LENGTH := 120000.0
const MIN_TRACK_LENGTH := 400.0

const PREFABS := [
	"bird", "crate", "barrier", "hot_air_balloon", "ferris_wheel",
	"large_ferris_wheel", "caterpillar", "vine", "venus_flytrap",
	"snow_elf", "ice_crystal", "storm", "fan", "flying_bird", "flying_fish",
	"meteor", "dream_elf", "bubble", "cannonball", "dream_void",
]
const BACKGROUNDS := ["paradise", "forest", "snow", "clouds", "dream"]
const MOTIONS := ["static", "oscillate_x", "oscillate_y", "circle", "ellipse"]
const COLOR_KEYS := [
	"sky_top", "sky_bottom", "mountain_far", "mountain_near",
	"track", "track_highlight", "accent", "tint",
]


## 编辑器保存后的原始 JSON -> 上传请求体。metadata 包含 name / author_id 等。
static func make_upload_body(raw_level: Dictionary, metadata: Dictionary) -> Dictionary:
	var validation := validate_level(raw_level)
	if not bool(validation.get("ok", false)):
		return validation
	var level_data: Dictionary = (validation.get("level_data", {}) as Dictionary).duplicate(true)
	var name := _text(metadata.get("name", level_data.get("name", "")), "", false)
	if name.is_empty():
		return _failure("关卡名称不能为空")
	if name.length() > 48:
		return _failure("关卡名称不能超过 48 个字符")
	var author_name := _text(metadata.get("author_name", "游客"), "游客", false)
	if author_name.is_empty():
		author_name = "游客"
	if author_name.length() > 24:
		return _failure("作者昵称不能超过 24 个字符")
	var author_id := str(metadata.get("author_id", "local_player")).strip_edges()
	if not _valid_id(author_id):
		return _failure("作者 id 格式无效")
	var platform := str(metadata.get("platform", PlatformConfig.get_platform_id())).strip_edges()
	if platform.is_empty():
		platform = "unknown"
	var description := _text(metadata.get("description", level_data.get("description", "")), "", true)
	if description.length() > 200:
		return _failure("关卡简介不能超过 200 个字符")
	level_data["name"] = name
	level_data["description"] = description
	level_data["custom"] = true
	level_data["source"] = "community"
	var body := {
		"name": name,
		"author_name": author_name,
		"author_id": author_id,
		"platform": platform,
		"description": description,
		"level_data": level_data,
	}
	var size := _byte_size(body)
	if size > MAX_BYTES:
		return _failure("关卡文件超过 2MB 上限")
	return {"ok": true, "body": body, "size": size, "error": ""}


## 校验完整关卡对象。返回规范化后的 level_data 和 LevelData 实例。
static func validate_level(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return _failure("关卡数据根节点必须是对象")
	var source: Dictionary = raw
	var normalized := _normalize_level(source)
	if normalized.is_empty():
		return _failure("关卡轨道或障碍数据无效")
	var serialized := JSON.stringify(normalized)
	if serialized.to_utf8_buffer().size() > MAX_BYTES:
		return _failure("关卡文件超过 2MB 上限")
	var probe := (normalized as Dictionary).duplicate(true)
	probe["id"] = str(probe.get("id", "ugc_preview"))
	if str(probe["id"]).is_empty():
		probe["id"] = "ugc_preview"
	if str(probe.get("name", "")).is_empty():
		probe["name"] = "未命名关卡"
	var level := LevelData.from_dictionary(probe)
	if level == null or not level.is_valid():
		var message := "关卡玩法校验失败"
		if level != null and not level.validation_errors.is_empty():
			message += "：" + "；".join(level.validation_errors)
		return _failure(message)
	return {"ok": true, "level_data": normalized, "level": level, "error": ""}


## 详情接口返回的 entry -> 完整关卡。
static func import_detail(entry: Dictionary) -> Dictionary:
	var result := validate_level(entry.get("level_data", {}))
	if not bool(result.get("ok", false)):
		return result
	var level_data: Dictionary = (result.get("level_data", {}) as Dictionary).duplicate(true)
	var entry_id := str(entry.get("id", ""))
	if not entry_id.is_empty():
		level_data["id"] = entry_id
	level_data["custom"] = true
	level_data["source"] = "community"
	return {
		"ok": true,
		"level_data": level_data,
		"level": LevelData.from_dictionary(level_data),
		"error": "",
	}


static func to_json(level_data: Dictionary, pretty: bool = true) -> String:
	return JSON.stringify(level_data, "\t" if pretty else "", false)


static func from_json(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _failure("JSON 解析失败：第 %d 行 %s" % [json.get_error_line(), json.get_error_message()])
	if not json.data is Dictionary:
		return _failure("JSON 根节点必须是对象")
	return validate_level(json.data)


static func _normalize_level(source: Dictionary) -> Dictionary:
	var track := _normalize_track(source.get("track", {}))
	if track.is_empty():
		return {}
	var total_length := float(track.get("total_length", 0.0))
	track.erase("total_length")
	var obstacles: Array[Dictionary] = []
	var raw_obstacles: Variant = source.get("obstacles", [])
	if raw_obstacles is Array:
		if (raw_obstacles as Array).size() > MAX_OBSTACLES:
			return {}
		for index in (raw_obstacles as Array).size():
			var obstacle := _normalize_obstacle((raw_obstacles as Array)[index], total_length)
			if obstacle.is_empty():
				return {}
			obstacles.append(obstacle)
	else:
		return {}

	var normalized := {
		"schema_version": SCHEMA_VERSION,
		"id": _text(source.get("id", ""), "", false),
		"name": _text(source.get("name", "未命名关卡"), "未命名关卡", false),
		"subtitle": _text(source.get("subtitle", ""), "", true),
		"description": _text(source.get("description", ""), "", true),
		"difficulty": clampi(int(source.get("difficulty", 1)), 1, 5),
		"par_time": clampf(_num(source.get("par_time"), 60.0), 1.0, 3600.0),
		"countdown_seconds": clampf(_num(source.get("countdown_seconds"), 3.0), 0.5, 10.0),
		"time_limit_seconds": clampf(_num(source.get("time_limit_seconds"), 0.0), 0.0, 86400.0),
		"background_id": str(source.get("background_id", "paradise")),
		"custom": true,
		"source": "community",
		"track": track,
		"obstacles": obstacles,
		"analytics_tags": [],
	}
	if not BACKGROUNDS.has(str(normalized["background_id"])):
		normalized["background_id"] = "paradise"
	var theme := _normalize_theme(source.get("theme", {}))
	if not theme.is_empty():
		normalized["theme"] = theme
	var camera := _normalize_camera(source.get("camera_bounds", null))
	if not camera.is_empty():
		normalized["camera_bounds"] = camera
	var raw_tags: Variant = source.get("analytics_tags", [])
	if raw_tags is Array:
		var tags: Array[String] = []
		for tag: Variant in (raw_tags as Array).slice(0, 16):
			var clean := _text(tag, "", false)
			if not clean.is_empty():
				tags.append(clean.substr(0, 32))
		normalized["analytics_tags"] = tags
	return normalized


static func _normalize_track(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var track: Dictionary = raw
	var raw_pieces: Variant = track.get("pieces", [])
	if not raw_pieces is Array or (raw_pieces as Array).is_empty():
		return {}
	if (raw_pieces as Array).size() > MAX_PIECES:
		return {}
	var start_angle := clampf(_num(track.get("start_angle_deg"), 0.0), -3600.0, 3600.0)
	var heading := deg_to_rad(start_angle)
	var current := Vector2.ZERO
	var have_point := false
	var total := 0.0
	var pieces: Array[Dictionary] = []
	for index in (raw_pieces as Array).size():
		var raw_piece: Variant = (raw_pieces as Array)[index]
		if not raw_piece is Dictionary:
			return {}
		var piece: Dictionary = raw_piece
		var type := str(piece.get("type", "straight"))
		if type == "curve":
			type = "arc"
		if type != "straight" and type != "arc" and type != "loop":
			return {}
		var output := {"type": type}
		var origin: Variant = _point(piece.get("origin", null))
		if origin != null:
			var origin_point := origin as Vector2
			if have_point:
				total += current.distance_to(origin_point)
			current = origin_point
			have_point = true
			output["origin"] = [_round(origin_point.x), _round(origin_point.y)]
			var heading_deg := clampf(_num(piece.get("heading_deg"), 0.0), -3600.0, 3600.0)
			output["heading_deg"] = _round(heading_deg)
			heading = deg_to_rad(heading_deg)
		elif not have_point:
			have_point = true
			current = Vector2.ZERO
		var direction := 1.0 if _num(piece.get("direction"), 1.0) >= 0.0 else -1.0
		output["direction"] = direction
		if bool(piece.get("direction_anchor", false)):
			output["direction_anchor"] = true
		var break_after := clampf(_num(piece.get("break_after"), 0.0), 0.0, 60.0)
		if break_after > 0.0:
			output["break_after"] = _round(break_after)
		if type == "straight":
			var length := clampf(_num(piece.get("length"), 240.0), 0.0, 100000.0)
			output["length"] = _round(length)
			current += Vector2(length, 0.0).rotated(heading)
			total += length
		else:
			var radius := clampf(_num(piece.get("radius"), 90.0 if type == "loop" else 120.0), 4.0, 10000.0)
			var angle := clampf(_num(piece.get("angle"), -360.0 if type == "loop" else -90.0), -3600.0, 3600.0)
			if type == "arc" and absf(angle) < 0.01:
				angle = -90.0
			output["radius"] = _round(radius)
			output["angle"] = _round(angle)
			var radians := deg_to_rad(angle)
			var local := Vector2(radius * sin(radians), radius * (1.0 - cos(radians)))
			current += local.rotated(heading)
			heading += radians
			total += radius * absf(radians)
		pieces.append(output)
	if total < MIN_TRACK_LENGTH or total > MAX_TRACK_LENGTH:
		return {}
	var result := {
		"start_angle_deg": _round(start_angle),
		"pieces": pieces,
		"start_s": 0.0,
		"finish_s": 0.0,
	}
	# 使用游戏同一套 TrackGeometry 取得精确弧长；近似值只用于早期长度拦截。
	var geometry := TrackGeometry.from_track_data(result)
	if geometry == null or not geometry.is_valid():
		return {}
	var exact_length := geometry.total_length
	if exact_length < MIN_TRACK_LENGTH or exact_length > MAX_TRACK_LENGTH:
		return {}
	var start_s := clampf(_num(track.get("start_s"), 60.0), 0.0, exact_length)
	var finish_s := clampf(_num(track.get("finish_s"), exact_length - 100.0), 0.0, exact_length)
	if absf(finish_s - start_s) < 100.0:
		return {}
	result["start_s"] = _round(start_s)
	result["finish_s"] = _round(finish_s)
	result["total_length"] = exact_length
	return result


static func _normalize_obstacle(raw: Variant, total_length: float) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var source: Dictionary = raw
	var prefab := str(source.get("prefab", source.get("type", "")))
	if not PREFABS.has(prefab):
		return {}
	var obstacle := {
		"prefab": prefab,
		"s": clampf(_num(source.get("s"), 0.0), 0.0, total_length),
		"offset": _point_object(source.get("offset", null)),
		"flip_x": bool(source.get("flip_x", false)),
	}
	var motion_value: Variant = source.get("motion", null)
	if motion_value is Dictionary:
		var motion: Dictionary = motion_value
		var motion_type := str(motion.get("type", "static"))
		if MOTIONS.has(motion_type):
			obstacle["motion"] = {
				"type": motion_type,
				"amplitude": _point_object(motion.get("amplitude", null)),
				"speed": clampf(_num(motion.get("speed"), 0.0), 0.0, 100.0),
				"phase": clampf(_num(motion.get("phase"), 0.0), -1000.0, 1000.0),
			}
	if source.has("radius"):
		obstacle["radius"] = clampf(_num(source.get("radius"), 26.0), 8.0, 2000.0)
	if source.has("damage"):
		obstacle["damage"] = clampi(int(source.get("damage", 1)), 1, 99)
	if source.get("collision_offsets", null) is Array:
		var offsets: Array = []
		for item: Variant in (source.get("collision_offsets") as Array).slice(0, 8):
			offsets.append(_point_object(item))
		obstacle["collision_offsets"] = offsets
	if source.get("collision_radii", null) is Array:
		var radii: Array[float] = []
		for item: Variant in (source.get("collision_radii") as Array).slice(0, 8):
			radii.append(clampf(_num(item, 26.0), 4.0, 2000.0))
		obstacle["collision_radii"] = radii
	if source.has("interval_enabled"):
		obstacle["interval_enabled"] = bool(source.get("interval_enabled", false))
		var period := clampf(_num(source.get("interval_period"), 2.0), 0.2, 60.0)
		obstacle["interval_period"] = period
		obstacle["interval_active"] = clampf(_num(source.get("interval_active"), 1.2), 0.05, period)
	if source.has("trigger_enabled"):
		obstacle["trigger_enabled"] = bool(source.get("trigger_enabled", false))
	if source.has("clockwise"):
		obstacle["clockwise"] = bool(source.get("clockwise", false))
	return obstacle


static func _normalize_theme(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var theme: Dictionary = raw
	var clean := {}
	for key in COLOR_KEYS:
		var value := str(theme.get(key, ""))
		if _is_hex_color(value):
			clean[key] = value.to_lower()
	if theme.has("tint_alpha"):
		clean["tint_alpha"] = clampf(_num(theme.get("tint_alpha"), 0.0), 0.0, 1.0)
	if theme.has("id"):
		clean["id"] = _text(theme.get("id"), "", false).substr(0, 24)
	return clean


static func _normalize_camera(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var camera: Dictionary = raw
	var width := _num(camera.get("w", camera.get("width")), 0.0)
	var height := _num(camera.get("h", camera.get("height")), 0.0)
	if width < 64.0 or height < 64.0:
		return {}
	return {
		"x": _round(_num(camera.get("x"), 0.0)),
		"y": _round(_num(camera.get("y"), 0.0)),
		"w": _round(width),
		"h": _round(height),
	}


static func _point(value: Variant) -> Variant:
	if value is Vector2:
		return value
	if value is Array and (value as Array).size() >= 2:
		return Vector2(_num((value as Array)[0], 0.0), _num((value as Array)[1], 0.0))
	if value is Dictionary:
		return Vector2(_num((value as Dictionary).get("x"), 0.0), _num((value as Dictionary).get("y"), 0.0))
	return null


## 障碍偏移必须输出对象；LevelData 只接受 Dictionary/Vector2，
## 输出数组会在导入时被当成 Vector2.ZERO，表现为障碍向右/向轨道偏移。
static func _point_object(value: Variant) -> Dictionary:
	var point: Variant = _point(value)
	if point == null:
		return {"x": 0.0, "y": 0.0}
	var vector := point as Vector2
	return {"x": _round(vector.x), "y": _round(vector.y)}


static func _text(value: Variant, fallback: String, multiline: bool) -> String:
	var text := str(value) if value != null else fallback
	var clean := ""
	for index in text.length():
		var code := text.unicode_at(index)
		if code == 10 and multiline:
			clean += "\n"
		elif code >= 32 and code != 127:
			clean += text[index]
	return clean.strip_edges()


static func _num(value: Variant, fallback: float) -> float:
	if value == null:
		return fallback
	var number := float(value)
	if number != number or absf(number) == INF:
		return fallback
	return number


static func _round(value: float) -> float:
	return snappedf(value, 0.001)


static func _is_hex_color(value: String) -> bool:
	if value.length() != 7 or not value.begins_with("#"):
		return false
	for index in range(1, 7):
		var code := value.unicode_at(index)
		var valid := (code >= 48 and code <= 57) or (code >= 65 and code <= 70) or (code >= 97 and code <= 102)
		if not valid:
			return false
	return true


static func _valid_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		var valid := (code >= 48 and code <= 57) \
			or (code >= 65 and code <= 90) \
			or (code >= 97 and code <= 122) \
			or code == 95 or code == 45 or code == 46
		if not valid:
			return false
	return true


static func _byte_size(data: Dictionary) -> int:
	return JSON.stringify(data).to_utf8_buffer().size()


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "body": {}, "size": 0, "level_data": {}, "level": null, "error": message}

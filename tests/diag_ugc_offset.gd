extends Node
## 临时诊断脚本：对比本地关卡、上传 body、服务端 detail 与 LevelData 的障碍 offset。

const API_BASE := "http://127.0.0.1:3100"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	ApiClient.set_base_url(API_BASE)
	var raw := LevelCatalog.get_raw_level("level_01")
	var data: Dictionary = (raw.get("data", {}) as Dictionary).duplicate(true)
	data["id"] = "custom_diag_offset"
	data["name"] = "偏移诊断"
	data["custom"] = true
	data["source"] = "user"
	data["obstacles"] = [
		{"prefab": "crate", "s": 300.0, "offset": {"x": 87.0, "y": 64.0}, "flip_x": false},
		{"prefab": "bird", "s": 500.0, "offset": {"x": -41.0, "y": -23.0}, "flip_x": false},
	]
	var local_offset: Dictionary = data["obstacles"][0]["offset"]
	print("LOCAL raw track.start_angle_deg=", data["track"].get("start_angle_deg"),
		" track.start_s=", data["track"].get("start_s"),
		" obstacle.s=", data["obstacles"][0]["s"],
		" offset_type=", type_string(typeof(local_offset)),
		" offset=", local_offset)

	var document := UgcLevelDocument.make_upload_body(data, {
		"name": "偏移诊断",
		"author_name": "诊断",
		"author_id": "SW-123456",
		"platform": "windows",
	})
	print("BODY ok=", document.get("ok"), " error=", document.get("error"))
	var body: Dictionary = document.get("body", {})
	var body_level: Dictionary = body.get("level_data", {})
	print("BODY track.start_angle_deg=", body_level["track"].get("start_angle_deg"),
		" track.start_s=", body_level["track"].get("start_s"),
		" obstacle.s=", body_level["obstacles"][0].get("s"),
		" offset_type=", type_string(typeof(body_level["obstacles"][0].get("offset"))),
		" offset=", body_level["obstacles"][0].get("offset"))

	var upload_state := {"done": false, "result": {}}
	ApiClient.post_json("/api/ugc/upload", body, func(result: Dictionary) -> void:
		upload_state["done"] = true
		upload_state["result"] = result
	)
	while not bool(upload_state["done"]):
		await get_tree().process_frame
	var upload: Dictionary = upload_state["result"]
	print("UPLOAD ok=", upload.get("ok"), " status=", upload.get("status"), " error=", upload.get("error"))
	var entry_id := str((upload.get("data", {}) as Dictionary).get("id", ""))
	if entry_id.is_empty():
		get_tree().quit(1)
		return

	var detail_state := {"done": false, "result": {}}
	ApiClient.get_json("/api/ugc/detail/%s" % entry_id, {}, func(result: Dictionary) -> void:
		detail_state["done"] = true
		detail_state["result"] = result
	)
	while not bool(detail_state["done"]):
		await get_tree().process_frame
	var detail: Dictionary = detail_state["result"]
	var detail_entry: Dictionary = (detail.get("data", {}) as Dictionary).get("entry", {})
	var detail_level: Dictionary = detail_entry.get("level_data", {})
	print("DETAIL ok=", detail.get("ok"), " status=", detail.get("status"), " error=", detail.get("error"))
	print("DETAIL track.start_angle_deg=", detail_level["track"].get("start_angle_deg"),
		" track.start_s=", detail_level["track"].get("start_s"),
		" obstacle.s=", detail_level["obstacles"][0].get("s"),
		" offset_type=", type_string(typeof(detail_level["obstacles"][0].get("offset"))),
		" offset=", detail_level["obstacles"][0].get("offset"))

	var imported := LevelData.from_dictionary(detail_level)
	if imported != null:
		print("LEVELDATA valid=", imported.is_valid(),
			" obstacle0.offset=", imported.obstacles[0].get("offset"),
			" obstacle0.s=", imported.obstacles[0].get("s"),
			" track_length=", imported.track.total_length)
		print("LEVELDATA track sample at s=", imported.track.sample_at(float(imported.obstacles[0].get("s"))))

	var delete_state := {"done": false}
	ApiClient.delete_json("/api/ugc/%s" % entry_id, {"author_id": "SW-123456"}, func(_result: Dictionary) -> void:
		delete_state["done"] = true
	)
	while not bool(delete_state["done"]):
		await get_tree().process_frame
	get_tree().quit(0)

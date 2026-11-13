class_name RemoteLeaderboardProvider
extends LeaderboardProvider
## 可直接配置的云端排行榜 HTTP 适配器。
## endpoint / api_key 配置后即可连接自建 API 或微信云开发 HTTP 网关；
## 未配置时保持占位错误路径，LeaderboardService 会自动回退本地数据。

var endpoint: String = ""
var api_key: String = ""
var auth_token: String = ""
var season_id: String = "s1"
var request_timeout: float = 12.0
var is_enabled: bool = false


func get_provider_id() -> String:
	return "remote_http" if is_enabled and not endpoint.is_empty() else "remote_stub"


func get_display_name() -> String:
	return "云端排行榜" if is_enabled and not endpoint.is_empty() else "云端排行榜（待配置）"


func fetch_scores(request: Dictionary, callback: Callable) -> void:
	if not is_enabled or endpoint.is_empty():
		callback.call({"ok": false, "entries": [], "error": "云端排行榜尚未配置 endpoint / api_key"})
		return
	var level_id := str(request.get("level_id", "")).uri_encode()
	var limit := maxi(1, int(request.get("limit", 10)))
	var path := "/v1/leaderboards/%s?limit=%d&season=%s" % [level_id, limit, season_id.uri_encode()]
	_request("GET", path, {}, func(result: Dictionary) -> void:
		if not bool(result.get("ok", false)):
			callback.call({"ok": false, "entries": [], "error": str(result.get("error", "云端排行榜读取失败"))})
			return
		var payload: Dictionary = result.get("payload", {})
		var entries: Array[Dictionary] = []
		for item: Variant in payload.get("entries", []):
			if item is Dictionary:
				entries.append((item as Dictionary).duplicate(true))
		callback.call({
			"ok": true,
			"entries": entries,
			"my_rank": int(payload.get("my_rank", 0)),
			"error": "",
		})
	)


func submit_score(entry: Dictionary, callback: Callable) -> void:
	if not is_enabled or endpoint.is_empty():
		callback.call({"ok": false, "error": "云端排行榜尚未配置"})
		return
	var level_id := str(entry.get("level_id", "")).uri_encode()
	_request("POST", "/v1/leaderboards/%s/scores" % level_id, entry, func(result: Dictionary) -> void:
		callback.call({
			"ok": bool(result.get("ok", false)),
			"error": str(result.get("error", "")),
		})
	)


func _request(method: String, path: String, body: Dictionary, callback: Callable) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		callback.call({"ok": false, "error": "无法获取场景树"})
		return
	var request := HTTPRequest.new()
	request.timeout = request_timeout
	tree.root.add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if not api_key.is_empty():
		headers.append("X-Api-Key: %s" % api_key)
	if not auth_token.is_empty():
		headers.append("Authorization: Bearer %s" % auth_token)
	var body_text := JSON.stringify(body) if not body.is_empty() else ""
	var method_enum := HTTPClient.METHOD_GET
	match method:
		"POST": method_enum = HTTPClient.METHOD_POST
		"PUT": method_enum = HTTPClient.METHOD_PUT
		"DELETE": method_enum = HTTPClient.METHOD_DELETE
	var error := request.request(endpoint.rstrip("/") + path, headers, method_enum, body_text)
	if error != OK:
		request.queue_free()
		callback.call({"ok": false, "error": "网络请求创建失败：%d" % error})
		return
	request.request_completed.connect(func(result: int, response_code: int, _response_headers: PackedStringArray, response_body: PackedByteArray) -> void:
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			callback.call({"ok": false, "error": "网络连接失败"})
			return
		if response_code < 200 or response_code >= 300:
			callback.call({"ok": false, "error": "HTTP %d" % response_code})
			return
		var parsed: Variant = JSON.parse_string(response_body.get_string_from_utf8())
		if not parsed is Dictionary:
			callback.call({"ok": false, "error": "云端返回格式错误"})
			return
		callback.call({"ok": true, "payload": parsed})
	)

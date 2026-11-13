extends Node
## 全局 HTTP 客户端。所有 UGC / 遥测请求都从这里发出，UI 不直接创建 HTTPRequest。
##
## 后端地址只改这一处：
## - 当前 IP 联调：http://8.134.212.65:3000
## - 本地联调：http://127.0.0.1:3000
## - 备案域名就绪后：https://你的域名（微信正式版必须 HTTPS 且加入 request 合法域名）
@export var base_url: String = "http://8.134.212.65:3000"
## 单次请求超时（秒）。上传 2MB 关卡时不要低于 15 秒。
@export var request_timeout: float = 18.0

const JSON_HEADERS := ["Accept: application/json", "Content-Type: application/json"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_base_url(value: String) -> void:
	base_url = value.strip_edges().trim_suffix("/")


func is_configured() -> bool:
	return not base_url.strip_edges().is_empty()


func get_json(path: String, query: Dictionary, callback: Callable) -> void:
	request_json(HTTPClient.METHOD_GET, _build_url(path, query), {}, callback)


func post_json(path: String, body: Dictionary, callback: Callable) -> void:
	request_json(HTTPClient.METHOD_POST, _build_url(path, {}), body, callback)


func delete_json(path: String, body: Dictionary, callback: Callable) -> void:
	request_json(HTTPClient.METHOD_DELETE, _build_url(path, {}), body, callback)


func request_json(method: int, url: String, body: Dictionary, callback: Callable) -> void:
	if not callback.is_valid():
		return
	if not is_configured():
		callback.call({"ok": false, "status": 0, "data": {}, "error": "后端地址未配置"})
		return
	var request := HTTPRequest.new()
	request.timeout = request_timeout
	request.accept_gzip = true
	request.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(request)
	var headers := PackedStringArray(JSON_HEADERS)
	var body_text := JSON.stringify(body) if not body.is_empty() else ""
	var error := request.request(url, headers, method, body_text)
	if error != OK:
		request.queue_free()
		callback.call({
			"ok": false,
			"status": 0,
			"data": {},
			"error": "网络请求创建失败（错误码 %d）" % error,
		})
		return
	request.request_completed.connect(func(
		result: int,
		response_code: int,
		_response_headers: PackedStringArray,
		response_body: PackedByteArray
	) -> void:
		if is_instance_valid(request):
			request.queue_free()
		var parsed: Variant = {}
		var raw_text := response_body.get_string_from_utf8()
		if not raw_text.is_empty():
			var json := JSON.new()
			if json.parse(raw_text) == OK:
				parsed = json.data
		if result != HTTPRequest.RESULT_SUCCESS:
			callback.call({
				"ok": false,
				"status": response_code,
				"data": parsed,
				"error": _request_error_text(result),
			})
			return
		var data: Dictionary = parsed if parsed is Dictionary else {}
		var server_error := str(data.get("detail", data.get("error", "")))
		var ok := response_code >= 200 and response_code < 300 and bool(data.get("ok", true))
		callback.call({
			"ok": ok,
			"status": response_code,
			"data": data,
			"error": "" if ok else (server_error if not server_error.is_empty() else _status_text(response_code)),
		})
	)


func _build_url(path: String, query: Dictionary) -> String:
	var url := base_url.strip_edges().trim_suffix("/") + path
	if query.is_empty():
		return url
	var parts := PackedStringArray()
	for key: Variant in query.keys():
		var value: Variant = query[key]
		if value == null:
			continue
		parts.append("%s=%s" % [str(key).uri_encode(), str(value).uri_encode()])
	if parts.is_empty():
		return url
	return url + "?" + "&".join(parts)


func _request_error_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "无法连接服务器，请检查网络或后端地址"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "无法解析服务器地址"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "服务器连接中断"
		HTTPRequest.RESULT_TIMEOUT:
			return "请求超时，请稍后重试"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "HTTPS 证书校验失败"
		_:
			return "网络请求失败（错误码 %d）" % result


func _status_text(status: int) -> String:
	match status:
		400:
			return "请求参数无效"
		401:
			return "登录状态失效"
		403:
			return "没有权限执行该操作"
		404:
			return "关卡不存在"
		413:
			return "上传内容超过大小限制"
		429:
			return "操作太频繁，请稍后重试"
		500, 502, 503:
			return "服务器暂时不可用"
		_:
			return "服务器返回 HTTP %d" % status

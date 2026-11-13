class_name RemoteTelemetryReporter
extends RefCounted
## 把关键遥测事件异步上报到 /api/telemetry。
## 只上报进入自制关卡、通关/死亡等少量事件，避免每帧生成网络请求。

var enabled: bool = true

## 串行队列：碰撞可能在同一秒连续发生，不能让每个事件各建一个 HTTPRequest。
const MAX_QUEUE := 128
var _queue: Array[Dictionary] = []
var _in_flight: bool = false


func report(event_type: String, event: Dictionary, callback: Callable = Callable()) -> void:
	if not enabled or not ApiClient.is_configured():
		if callback.is_valid():
			callback.call({"ok": false, "error": "遥测上报未启用"})
		return
	if _queue.size() >= MAX_QUEUE:
		# 极端连撞时丢弃最旧的非结算事件，优先保证 run_end 送达。
		var drop_index := 0
		for index in _queue.size():
			if str(_queue[index].get("event_type", "")) != "run_end":
				drop_index = index
				break
		_queue.remove_at(drop_index)
	var payload: Dictionary = event.duplicate(true)
	payload.erase("event_id")
	payload["player_id"] = SaveManager.get_player_id()
	payload["client_version"] = str(ProjectSettings.get_setting("application/config/version", ""))
	_queue.append({
		"event_type": event_type,
		"event": event,
		"payload": payload,
		"callback": callback,
	})
	_drain_queue()


func _drain_queue() -> void:
	if _in_flight or _queue.is_empty():
		return
	var item: Dictionary = _queue.pop_front()
	_in_flight = true
	var event: Dictionary = item["event"]
	var body := {
		"event_id": str(event.get("event_id", "")),
		"event_type": str(item["event_type"]),
		"platform": PlatformConfig.get_platform_id(),
		"level_id": str(event.get("level_id", "")),
		"level_name": str(event.get("level_name", "")),
		"mode": str(event.get("mode", "solo")),
		"custom": bool(event.get("custom", false)),
		"ts": float(event.get("ts", Time.get_unix_time_from_system())),
		"payload": item["payload"],
	}
	ApiClient.post_json("/api/telemetry", body, func(result: Dictionary) -> void:
		_in_flight = false
		if not bool(result.get("ok", false)):
			push_warning("[Telemetry] 远端上报失败：%s" % str(result.get("error", "未知错误")))
		var callback: Callable = item.get("callback", Callable())
		if callback.is_valid():
			callback.call(result)
		_drain_queue()
	)

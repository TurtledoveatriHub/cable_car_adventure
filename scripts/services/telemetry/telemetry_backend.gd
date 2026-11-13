class_name TelemetryBackend
extends RefCounted
## 行为遥测后端接口。当前使用本地 JSONL，未来可替换为 Kafka/HTTP 批量上报。
## callback 约定：
##   append_event -> {"ok": bool, "error": String}
##   load_events -> {"ok": bool, "events": Array[Dictionary], "error": String}
##   clear_events -> {"ok": bool, "error": String}


func get_backend_id() -> String:
	return "abstract"


## 批量后端可覆写；内存/远端后端默认没有待落盘数据。
func has_pending() -> bool:
	return false


func flush_pending() -> Dictionary:
	return {"ok": true, "flushed": 0, "error": ""}


func flush_pending_chunk(_max_lines: int = 32) -> Dictionary:
	return flush_pending()


func append_event(_event: Dictionary, callback: Callable) -> void:
	callback.call({"ok": false, "error": "遥测后端未实现"})


func load_events(callback: Callable) -> void:
	callback.call({"ok": false, "events": [], "error": "遥测后端未实现"})


func clear_events(callback: Callable) -> void:
	callback.call({"ok": false, "error": "遥测后端未实现"})

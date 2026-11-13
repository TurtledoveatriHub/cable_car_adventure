class_name LocalTelemetryBackend
extends TelemetryBackend
## 本地 JSONL 遥测后端。每行一个事件，便于后期导入 pandas / PySpark。
## 只有该文件和 TelemetryService 允许触碰遥测文件。

const DEFAULT_PATH := "user://analytics/events.jsonl"
## 内存中最多缓存的 JSONL 行数；超过上限丢弃最旧事件，保证回调不做同步 I/O。
const MAX_PENDING_LINES := 256

var _path: String
## 关键：碰撞等玩法事件只进入内存队列，绝不在物理/输入回调里同步打开文件。
## Web / 微信的虚拟文件系统一次 flush 可能阻塞数百毫秒，这是关卡内碰撞卡顿的主因。
var _pending_lines: PackedStringArray = []


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


func get_backend_id() -> String:
	return "local_jsonl"


func get_path() -> String:
	return _path


func append_event(event: Dictionary, callback: Callable) -> void:
	_pending_lines.append(JSON.stringify(event, "", false))
	# 极端情况下只丢弃最旧的内存事件，也绝不在玩法回调里触发文件 I/O。
	while _pending_lines.size() > MAX_PENDING_LINES:
		_pending_lines.remove_at(0)
	callback.call({"ok": true, "queued": true, "error": ""})


func has_pending() -> bool:
	return not _pending_lines.is_empty()


## 批量落盘。返回后 _pending_lines 只有在写入成功时才会清空。
func flush_pending() -> Dictionary:
	return flush_pending_chunk(_pending_lines.size())


## 分批落盘：关卡结束的黑屏过渡里每次只写一小段，避免一帧长时间阻塞。
func flush_pending_chunk(max_lines: int = 32) -> Dictionary:
	if _pending_lines.is_empty() or max_lines <= 0:
		return {"ok": true, "flushed": 0, "remaining": _pending_lines.size(), "error": ""}
	var count := mini(max_lines, _pending_lines.size())
	var dir_error := DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "flushed": 0, "remaining": _pending_lines.size(), "error": "无法创建遥测目录（错误码 %d）" % dir_error}
	var file := FileAccess.open(_path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "flushed": 0, "remaining": _pending_lines.size(), "error": "无法写入遥测文件（错误码 %d）" % FileAccess.get_open_error()}
	file.seek_end()
	for index in count:
		file.store_line(_pending_lines[index])
	file.flush()
	file.close()
	_pending_lines = _pending_lines.slice(count)
	return {"ok": true, "flushed": count, "remaining": _pending_lines.size(), "error": ""}


func load_events(callback: Callable) -> void:
	# 读取前先落盘，保证同一帧写入的事件也能被分析服务看到。
	var flush_result := flush_pending()
	if not bool(flush_result.get("ok", false)):
		callback.call({"ok": false, "events": [], "error": str(flush_result.get("error", "遥测落盘失败"))})
		return
	if not FileAccess.file_exists(_path):
		callback.call({"ok": true, "events": [], "error": ""})
		return
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		callback.call({"ok": false, "events": [], "error": "无法读取遥测文件（错误码 %d）" % FileAccess.get_open_error()})
		return
	var events: Array[Dictionary] = []
	var line_number := 0
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		line_number += 1
		if line.is_empty():
			continue
		var json := JSON.new()
		if json.parse(line) != OK:
			push_warning("[Telemetry] 忽略损坏的第 %d 行：%s" % [line_number, json.get_error_message()])
			continue
		if json.data is Dictionary:
			events.append((json.data as Dictionary).duplicate(true))
	file.close()
	callback.call({"ok": true, "events": events, "error": ""})


func clear_events(callback: Callable) -> void:
	# 丢弃尚未落盘的事件，否则清空后定时 flush 会再次创建文件。
	_pending_lines.clear()
	if not FileAccess.file_exists(_path):
		callback.call({"ok": true, "error": ""})
		return
	var delete_error := DirAccess.remove_absolute(_path)
	callback.call({"ok": delete_error == OK, "error": "" if delete_error == OK else "删除遥测文件失败（错误码 %d）" % delete_error})

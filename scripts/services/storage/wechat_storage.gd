class_name WeChatStorage
extends StorageBackend
## 微信小游戏存档后端。
##
## 微信的 WXMEMFS 在部分真机/开发者工具版本上对 rename/目录同步不稳定，
## 主线进度写入 user:// 后重启会丢失。这里直接使用 wx.setStorageSync：
## 数据量只有几 KB，同步写入足够快，且由微信保证跨启动持久化。

const KEY_PREFIX := "cablecar.profile."

var _wx: Variant = null
var _fallback := LocalFileStorage.new()


func _init() -> void:
	if not OS.has_feature("web"):
		return
	var window_object: Variant = JavaScriptBridge.get_interface("window")
	if window_object == null or str(window_object.__cableCarPlatform) != "wechat":
		return
	_wx = JavaScriptBridge.get_interface("wx")


func is_available() -> bool:
	return _wx != null


func get_backend_id() -> String:
	return "wechat_storage"


func get_display_name() -> String:
	return "微信本地存储"


func load_profile(profile_id: String, callback: Callable) -> void:
	if not is_available():
		callback.call({"ok": false, "exists": false, "data": {}, "error": "微信存储不可用"})
		return
	var text := _read_text(profile_id)
	if text.is_empty():
		# 兼容旧版本已经写入 user:// 的存档：迁移一次到微信本地存储。
		_fallback.load_profile(profile_id, func(file_result: Dictionary) -> void:
			if bool(file_result.get("ok", false)) and bool(file_result.get("exists", false)):
				var old_data: Variant = file_result.get("data", {})
				if old_data is Dictionary:
					save_profile(profile_id, old_data, func(_save_result: Dictionary) -> void: pass)
					callback.call(file_result)
					return
			callback.call({"ok": true, "exists": false, "data": {}, "error": ""})
		)
		return
	var json := JSON.new()
	if json.parse(text) != OK:
		callback.call({
			"ok": false,
			"exists": true,
			"data": {},
			"error": "微信存档 JSON 损坏：第 %d 行 %s" % [json.get_error_line(), json.get_error_message()],
		})
		return
	if not json.data is Dictionary:
		callback.call({"ok": false, "exists": true, "data": {}, "error": "微信存档根节点不是对象"})
		return
	callback.call({"ok": true, "exists": true, "data": json.data, "error": ""})


func save_profile(profile_id: String, data: Dictionary, callback: Callable) -> void:
	if not is_available():
		callback.call({"ok": false, "error": "微信存储不可用"})
		return
	_wx.setStorageSync(_key(profile_id), JSON.stringify(data, "\t", false))
	callback.call({"ok": true, "error": ""})


func delete_profile(profile_id: String, callback: Callable) -> void:
	if not is_available():
		callback.call({"ok": false, "error": "微信存储不可用"})
		return
	_wx.removeStorageSync(_key(profile_id))
	callback.call({"ok": true, "error": ""})


func _read_text(profile_id: String) -> String:
	var value: Variant = _wx.getStorageSync(_key(profile_id))
	if value is String:
		return (value as String).strip_edges()
	return ""


func _key(profile_id: String) -> String:
	var safe_id := profile_id.validate_filename().to_lower()
	if safe_id.is_empty():
		safe_id = "local_player"
	return KEY_PREFIX + safe_id

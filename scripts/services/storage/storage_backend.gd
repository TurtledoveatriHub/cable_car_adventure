class_name StorageBackend
extends RefCounted
## 存档后端接口。
## 本地文件、云端数据库或微信云开发都实现这三个异步方法即可无缝替换。
##
## callback 约定：
##   load_profile -> callback.call({"ok": bool, "exists": bool, "data": Dictionary, "error": String})
##   save_profile -> callback.call({"ok": bool, "error": String})
##   delete_profile -> callback.call({"ok": bool, "error": String})


func get_backend_id() -> String:
	return "abstract"


func get_display_name() -> String:
	return "未配置存储"


func load_profile(_profile_id: String, callback: Callable) -> void:
	push_error("StorageBackend.load_profile 未实现")
	callback.call({"ok": false, "exists": false, "data": {}, "error": "后端未实现"})


func save_profile(_profile_id: String, _data: Dictionary, callback: Callable) -> void:
	push_error("StorageBackend.save_profile 未实现")
	callback.call({"ok": false, "error": "后端未实现"})


func delete_profile(_profile_id: String, callback: Callable) -> void:
	push_error("StorageBackend.delete_profile 未实现")
	callback.call({"ok": false, "error": "后端未实现"})

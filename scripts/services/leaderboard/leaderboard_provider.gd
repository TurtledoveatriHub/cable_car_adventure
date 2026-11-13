class_name LeaderboardProvider
extends RefCounted
## 排行榜数据源接口。
## 查询 request 的稳定契约：
## {
##   "level_id": String,
##   "level_name": String,
##   "difficulty": int,
##   "par_time": float,
##   "limit": int,
##   "player_name": String
## }
## callback 约定：
##   { "ok": bool, "entries": Array[Dictionary], "error": String }
## entry 字段：player_name, passengers, time_seconds, is_local(optional)
##
## 未来接入真实后端时，只需实现该接口并通过
## LeaderboardService.set_provider() 注入即可。


func get_provider_id() -> String:
	return "abstract"


func get_display_name() -> String:
	return "未配置排行榜"


func fetch_scores(_request: Dictionary, callback: Callable) -> void:
	push_error("LeaderboardProvider.fetch_scores 未实现")
	callback.call({"ok": false, "entries": [], "error": "排行榜后端未实现"})


func submit_score(_entry: Dictionary, callback: Callable) -> void:
	push_error("LeaderboardProvider.submit_score 未实现")
	callback.call({"ok": false, "error": "排行榜后端未实现"})

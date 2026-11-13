class_name ScoreRules
extends RefCounted
## 所有成绩比较规则的唯一来源。
## 排名优先级：丢失乘客数（升序） > 通关用时（升序）。


## 判断 candidate 是否优于 incumbent。
## 空字典代表“暂无成绩”，任何有效成绩都优于它。
static func is_better(candidate: Dictionary, incumbent: Dictionary) -> bool:
	if candidate.is_empty():
		return false
	if incumbent.is_empty():
		return true
	if not bool(candidate.get("completed", true)):
		return false
	if not bool(incumbent.get("completed", true)):
		return true

	var candidate_lost := get_lost_passengers(candidate)
	var incumbent_lost := get_lost_passengers(incumbent)
	if candidate_lost != incumbent_lost:
		return candidate_lost < incumbent_lost

	var candidate_time := float(candidate.get("time_seconds", INF))
	var incumbent_time := float(incumbent.get("time_seconds", INF))
	return candidate_time < incumbent_time


## 排行榜排序：丢失乘客少的在前；相同则用时短的在前。
static func compare_entries(a: Dictionary, b: Dictionary) -> bool:
	var a_lost := get_lost_passengers(a)
	var b_lost := get_lost_passengers(b)
	if a_lost != b_lost:
		return a_lost < b_lost
	var a_time := float(a.get("time_seconds", INF))
	var b_time := float(b.get("time_seconds", INF))
	if not is_equal_approx(a_time, b_time):
		return a_time < b_time
	return str(a.get("player_name", "")) < str(b.get("player_name", ""))


## 将秒数格式化为 00:00.00。
static func format_time(seconds: float) -> String:
	var safe_seconds := maxf(0.0, seconds)
	var total_centiseconds := int(round(safe_seconds * 100.0))
	var minutes := int(total_centiseconds / 6000.0)
	var secs := int(total_centiseconds / 100.0) % 60
	var centis := total_centiseconds % 100
	return "%02d:%02d.%02d" % [minutes, secs, centis]


## 关卡内 HUD 的正向计时：分:秒:百分秒，例如 03:00:00。
static func format_timer_clock(seconds: float) -> String:
	var safe_seconds := maxf(0.0, seconds)
	var total_centiseconds := int(round(safe_seconds * 100.0))
	var minutes := int(total_centiseconds / 6000.0)
	var secs := int(total_centiseconds / 100.0) % 60
	var centis := total_centiseconds % 100
	return "%02d:%02d:%02d" % [minutes, secs, centis]


## 简易用时分段，例如 1:02，用于排行榜紧凑行。
static func format_time_short(seconds: float) -> String:
	var safe_seconds := maxf(0.0, seconds)
	var total_seconds := int(round(safe_seconds))
	return "%d:%02d" % [int(total_seconds / 60.0), total_seconds % 60]


## 丢失乘客数；旧成绩没有该字段时用开局人数推导。
static func get_lost_passengers(entry: Dictionary) -> int:
	if entry.has("lost_passengers"):
		return maxi(0, int(entry.get("lost_passengers", 0)))
	var starting := int(entry.get("level_starting_passengers", entry.get("starting_passengers", 0)))
	var passengers := int(entry.get("passengers", 0))
	return maxi(0, starting - passengers) if starting > 0 else 0


## 将成绩转换为存档 / 排行榜共用的标准字典。
static func make_entry(
	level_id: String,
	passengers: int,
	time_seconds: float,
	player_name: String = "游客",
	completed: bool = true,
	starting_passengers: int = 0,
	cart_id: String = "dove",
	cart_name: String = ""
) -> Dictionary:
	var lost := maxi(0, starting_passengers - passengers) if starting_passengers > 0 else 0
	return {
		"level_id": level_id,
		"player_name": player_name,
		"passengers": passengers,
		"lost_passengers": lost,
		"level_starting_passengers": starting_passengers,
		"time_seconds": snappedf(time_seconds, 0.01),
		"completed": completed,
		"cart_id": cart_id,
		"cart_name": cart_name,
	}

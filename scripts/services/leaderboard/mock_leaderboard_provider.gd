class_name MockLeaderboardProvider
extends LeaderboardProvider
## 本地假排行榜数据源。
## 数据按关卡 id 确定性生成，因此每次查询一致，同时会自动并入玩家最佳成绩。

const FAKE_NAMES: Array[String] = [
	"轨道小王子",
	"棉花糖",
	"风之子",
	"蛋挞骑士",
	"云朵驾驶员",
	"像素企鹅",
	"落日飞车",
	"咕噜噜",
	"海盐汽水",
	"不晕车",
	"红鼻子",
	"晚风",
	"纸飞机",
	"橘子汽水",
]

var _submitted_entries: Dictionary = {}


func get_provider_id() -> String:
	return "local_real"


func get_display_name() -> String:
	return "本地样例榜单"


func fetch_scores(request: Dictionary, callback: Callable) -> void:
	var level_id := str(request.get("level_id", ""))
	var limit := maxi(1, int(request.get("limit", 10)))
	var entries: Array[Dictionary] = []
	for submitted: Variant in _submitted_entries.get(level_id, []):
		if submitted is Dictionary:
			entries.append((submitted as Dictionary).duplicate(true))
	entries.sort_custom(ScoreRules.compare_entries)
	if entries.size() > limit:
		entries.resize(limit)
	callback.call({"ok": true, "entries": entries, "error": ""})


func submit_score(entry: Dictionary, callback: Callable) -> void:
	var level_id := str(entry.get("level_id", ""))
	if level_id.is_empty():
		callback.call({"ok": false, "error": "成绩缺少 level_id"})
		return
	var list: Array = _submitted_entries.get(level_id, [])
	list.append(entry.duplicate(true))
	_submitted_entries[level_id] = list
	callback.call({"ok": true, "error": ""})

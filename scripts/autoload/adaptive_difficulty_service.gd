extends Node
## 基于历史行为数据的自适应难度算法。
## 输入：最近若干次 run_end 事件（剩余乘客、是否完赛、用时、碰撞次数）。
## 输出：动态障碍速度倍率、引擎辅助倍率与可解释标签。
## 这是毕业设计中的“算法模块”，同时不改变关卡原始数据。

const WINDOW_SIZE := 8
const EWMA_ALPHA := 0.35


## 返回当前关卡的自适应参数。
func get_modifiers(level_id: String) -> Dictionary:
	var samples := _recent_samples(level_id)
	if samples.is_empty():
		return {
			"skill_score": 0.5,
			"samples": 0,
			"obstacle_speed_scale": 1.0,
			"engine_scale": 1.0,
			"label": "自适应 · 等待数据",
		}

	var skill := 0.5
	var used := 0
	for sample in samples:
		var performance := _performance_of(sample)
		skill = performance if used == 0 else lerpf(skill, performance, EWMA_ALPHA)
		used += 1
	var confidence := clampf(float(used) / 4.0, 0.3, 1.0)
	var raw_scale := lerpf(0.85, 1.15, skill)
	var obstacle_scale := 1.0 + (raw_scale - 1.0) * confidence
	var raw_engine := lerpf(1.12, 0.96, skill)
	var engine_scale := 1.0 + (raw_engine - 1.0) * confidence
	var label := "自适应 · 标准"
	if used >= 2 and skill < 0.42:
		label = "自适应 · 轻松"
	elif used >= 2 and skill > 0.68:
		label = "自适应 · 挑战"
	return {
		"skill_score": snappedf(skill, 0.001),
		"samples": used,
		"obstacle_speed_scale": snappedf(clampf(obstacle_scale, 0.8, 1.2), 0.001),
		"engine_scale": snappedf(clampf(engine_scale, 0.9, 1.2), 0.001),
		"label": "%s（%d 局）" % [label, used],
	}


func _recent_samples(level_id: String) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	for event in TelemetryService.get_events():
		if str(event.get("type", "")) != "run_end":
			continue
		if not level_id.is_empty() and str(event.get("level_id", "")) != level_id:
			continue
		runs.append(event)
	runs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("ts", 0.0)) < float(b.get("ts", 0.0))
	)
	if runs.size() > WINDOW_SIZE:
		runs = runs.slice(runs.size() - WINDOW_SIZE, runs.size())
	return runs


func _performance_of(event: Dictionary) -> float:
	var starting := maxf(1.0, float(event.get("starting_passengers", 3)))
	var passengers := maxf(0.0, float(event.get("passengers", 0)))
	var passenger_score := clampf(passengers / starting, 0.0, 1.0)
	var completed := 1.0 if bool(event.get("completed", false)) else 0.0
	var par_time := maxf(1.0, float(event.get("par_time", 60.0)))
	var run_time := maxf(0.01, float(event.get("time_seconds", par_time)))
	var time_score := clampf(par_time / run_time, 0.0, 1.0) if completed > 0.0 else 0.0
	var collisions := maxf(0.0, float(event.get("collisions", 0)))
	var collision_score := 1.0 - clampf(collisions / 6.0, 0.0, 1.0)
	return clampf(0.45 * passenger_score + 0.25 * completed + 0.15 * time_score + 0.15 * collision_score, 0.0, 1.0)


## 只读解释信息，供分析看板 / 文档展示。
func explain(level_id: String) -> Dictionary:
	var samples := _recent_samples(level_id)
	return {
		"level_id": level_id,
		"sample_count": samples.size(),
		"formula": "0.45*乘客保留率 + 0.25*完赛 + 0.15*时间得分 + 0.15*(1-碰撞惩罚)",
		"smoothing": "EWMA alpha=0.35, window=8",
		"modifiers": get_modifiers(level_id),
	}

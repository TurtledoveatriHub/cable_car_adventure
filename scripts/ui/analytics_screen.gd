extends Control
## 个人主页：展示昵称、本地档案 ID、收藏进度与个人最佳，不展示遥测技术信息。

@onready var back_button: Button = %BackButton
@onready var player_name_edit: LineEdit = %PlayerNameEdit
@onready var edit_name_button: Button = %EditNameButton
@onready var avatar_label: Label = %AvatarLabel
@onready var player_id_label: Label = %PlayerIdLabel
@onready var joined_label: Label = %JoinedLabel
@onready var total_runs_value: Label = %TotalRunsValue
@onready var completion_rate_value: Label = %CompletionRateValue
@onready var avg_lost_value: Label = %AvgPassengersValue
@onready var avg_time_value: Label = %AvgTimeValue
@onready var mainline_label: Label = %MainlineProgressLabel
@onready var stars_label: Label = %StarsProfileLabel
@onready var cart_unlock_label: Label = %CartUnlockLabel
@onready var custom_label: Label = %CustomLevelsLabel
@onready var cart_label: Label = %CartProfileLabel
@onready var recent_label: Label = %RecentLabel


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	edit_name_button.pressed.connect(_save_player_name)
	player_name_edit.text_submitted.connect(func(_value: String) -> void: _save_player_name())
	_load_profile()
	# 先用占位符让页面立即可交互，数据在淡入完成后再计算。
	total_runs_value.text = "…"
	completion_rate_value.text = "…"
	avg_lost_value.text = "…"
	avg_time_value.text = "…"
	call_deferred("_load_personal_stats_deferred")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _load_profile() -> void:
	var player_name := SaveManager.get_player_name()
	player_name_edit.text = player_name
	avatar_label.text = player_name.substr(0, 1) if not player_name.is_empty() else "鸽"
	player_id_label.text = "ID：%s" % SaveManager.get_player_id()
	var created_at := SaveManager.get_player_created_at()
	joined_label.text = "加入时间：%s" % (Time.get_date_string_from_unix_time(created_at) if created_at > 0 else "—")


func _save_player_name() -> void:
	SaveManager.set_player_name(player_name_edit.text)
	AudioDirector.play_click()
	_load_profile()


func _load_personal_stats_deferred() -> void:
	# 等转场淡入完成再统计；页面上的基础昵称/关卡进度已经先显示。
	await get_tree().create_timer(0.35, true, false, true).timeout
	_load_personal_stats()


func _load_personal_stats() -> void:
	var mainline_total := 0
	var mainline_cleared := 0
	var custom_count := 0
	var total_stars := 0
	var local_attempts := 0
	var recent: Array[Dictionary] = []
	for summary: Dictionary in LevelCatalog.get_summaries():
		var level_id := str(summary.get("id", ""))
		var is_custom := bool(summary.get("custom", false))
		var progress := SaveManager.get_level_progress(level_id)
		var attempts := int(progress.get("attempts", 0))
		local_attempts += attempts
		if is_custom:
			custom_count += 1
		else:
			mainline_total += 1
			if SaveManager.is_level_cleared(level_id):
				mainline_cleared += 1
			total_stars += SaveManager.get_level_stars(level_id)
		if attempts > 0:
			recent.append({
				"name": str(summary.get("name", level_id)),
				"stars": SaveManager.get_level_stars(level_id),
				"cleared": SaveManager.is_level_cleared(level_id),
				"last_played": int(progress.get("last_played_at", 0)),
			})

	mainline_label.text = "主线关卡　%d / %d" % [mainline_cleared, mainline_total]
	stars_label.text = "收集星星　%d / %d" % [total_stars, mainline_total * 3]
	custom_label.text = "自制关卡　%d 张" % custom_count
	var cart_id := str(SaveManager.get_setting("cart_p1", "dove"))
	var cart := CartCatalog.get_profile(cart_id)
	cart_label.text = "常用缆车　%s" % (cart.display_name if cart != null else "小鸽子")
	var unlocked_carts: Array[String] = []
	for available in CartCatalog.get_all():
		if CartCatalog.is_unlocked(available):
			unlocked_carts.append(available.display_name)
	cart_unlock_label.text = "已解锁缆车　%d / %d　·　%s" % [
		unlocked_carts.size(),
		CartCatalog.get_all().size(),
		"、".join(unlocked_carts),
	]
	recent.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("last_played", 0)) > int(b.get("last_played", 0))
	)
	if recent.is_empty():
		recent_label.text = "还没有旅程记录。去主线或关卡工坊开始第一趟吧。"
	else:
		var lines: Array[String] = []
		for index in mini(3, recent.size()):
			var item: Dictionary = recent[index]
			var state := "已通关" if bool(item.get("cleared", false)) else "挑战中"
			lines.append("%s　·　%s　·　★ %d" % [str(item.get("name", "")), state, int(item.get("stars", 0))])
		recent_label.text = "\n".join(lines)

	# 本地统计只用于个人页的冒险次数/通关率，复用内存缓存，避免二次读 JSONL。
	AnalyticsService.load_dashboard_cached("", func(result: Dictionary) -> void:
		if not is_inside_tree():
			return
		if not bool(result.get("ok", false)):
			total_runs_value.text = str(local_attempts)
			return
		var dashboard: Dictionary = result.get("dashboard", {})
		var total_runs := int(dashboard.get("total_runs", 0))
		total_runs_value.text = str(maxi(total_runs, local_attempts))
		completion_rate_value.text = "%.1f%%" % float(dashboard.get("completion_rate", 0.0))
		avg_lost_value.text = "%.1f" % float(dashboard.get("avg_lost_passengers", 0.0))
		avg_time_value.text = ScoreRules.format_time(float(dashboard.get("avg_time", 0.0)))
	)


func _on_back_pressed() -> void:
	AudioDirector.play_click()
	SceneRouter.goto_menu()

extends Control
## 结算界面：只展示 GameSession.last_result 与 SaveManager 的只读最佳成绩。
## 不在这里写存档；写档与排行榜提交已由 GameController 在游戏结束时完成。

@onready var backdrop: SkyBackdrop = $BackdropLayer/SkyBackdrop
@onready var confetti: CelebrationFx = $CelebrationFx
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var winner_label: Label = %WinnerLabel
@onready var new_best_badge: PanelContainer = %NewBestBadge
@onready var best_label: Label = %BestLabel
@onready var single_stats: HBoxContainer = %SingleStats
@onready var duo_stats: HBoxContainer = %DuoStats
@onready var passengers_value: Label = %PassengersValue
@onready var time_value: Label = %TimeValue
@onready var stars_value: Label = %StarsValue
@onready var p1_name: Label = %P1Name
@onready var p1_result: Label = %P1Result
@onready var p1_stats: Label = %P1Stats
@onready var p1_stars: Label = %P1Stars
@onready var p2_name: Label = %P2Name
@onready var p2_result: Label = %P2Result
@onready var p2_stats: Label = %P2Stats
@onready var p2_stars: Label = %P2Stars
@onready var retry_button: Button = %RetryButton
@onready var next_button: Button = %NextButton
@onready var levels_button: Button = %LevelsButton
@onready var leaderboard_button: Button = %LeaderboardButton
@onready var editor_button: Button = %EditorButton
@onready var panel: PanelContainer = %ResultPanel

var _result: Dictionary = {}
var _mode: String = GameSession.MODE_SOLO
var _level_id: String = ""


func _ready() -> void:
	UIJuice.popup_in(panel)
	_result = GameSession.last_result.duplicate(true)
	if _result.is_empty():
		push_warning("[ResultScreen] 没有结算数据，返回选关")
		SceneRouter.goto_level_select(GameSession.mode)
		return
	_mode = str(_result.get("mode", GameSession.MODE_SOLO))
	_level_id = str(_result.get("level_id", ""))

	retry_button.pressed.connect(_on_retry_pressed)
	next_button.pressed.connect(_on_next_pressed)
	levels_button.pressed.connect(_on_levels_pressed)
	levels_button.visible = not GameSession.test_from_editor
	levels_button.text = "返回选关"
	leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	editor_button.pressed.connect(_on_editor_pressed)
	editor_button.visible = GameSession.test_from_editor
	if GameSession.test_from_editor:
		editor_button.text = "返回工坊"
	_populate()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_levels_pressed()
		get_viewport().set_input_as_handled()


## 广场关卡不在 LevelCatalog 里，主题必须从本局下载的 authored_level_data 读取；
## 否则结算页会拿 ugc_xxx 去查本地目录并打印“关卡不存在”。
func _resolve_level() -> LevelData:
	if not GameSession.authored_level_data.is_empty():
		return LevelData.from_dictionary(GameSession.authored_level_data)
	return LevelCatalog.get_level(_level_id)


func _populate() -> void:
	var level_summary := LevelCatalog.get_summary(_level_id)
	var level_name := str(level_summary.get("name", _result.get("level_name", "关卡")))
	subtitle_label.text = "%s　·　%s" % [
		level_name,
		"本地双人竞速" if _mode == GameSession.MODE_DUO else "单人闯关",
	]
	var level := _resolve_level()
	if level != null:
		backdrop.apply_theme(level.theme, level.background_id)

	var players: Array = _result.get("players", [])
	var primary: Dictionary = players[0] if not players.is_empty() else {}
	var completed := bool(primary.get("completed", false))
	var any_completed := false
	for player_data: Variant in players:
		if player_data is Dictionary and bool((player_data as Dictionary).get("completed", false)):
			any_completed = true
			break

	if _mode == GameSession.MODE_DUO:
		_setup_duo(players, any_completed)
	else:
		_setup_single(primary, completed, any_completed)

	# 新纪录与最佳成绩。
	new_best_badge.visible = bool(_result.get("is_new_best", false))
	var best := SaveManager.get_level_best(_level_id)
	if best.is_empty():
		best_label.text = "本关尚无通关记录"
	else:
		best_label.text = "本关最佳　%d 位丢失乘客　·　%s" % [
			ScoreRules.get_lost_passengers(best),
			ScoreRules.format_time(float(best.get("time_seconds", 0.0))),
		]

	# 下一关。
	next_button.visible = false
	if any_completed and not bool(_result.get("authored", false)):
		var next_summary := _find_next_level(_level_id)
		if not next_summary.is_empty():
			next_button.visible = true
			next_button.text = "下一关 · %s" % str(next_summary.get("name", ""))

	confetti.set_active(any_completed)
	retry_button.grab_focus()


func _setup_single(primary: Dictionary, completed: bool, any_completed: bool) -> void:
	single_stats.visible = true
	duo_stats.visible = false
	winner_label.visible = false
	var starting := int(_result.get("level_starting_passengers", 3))
	if completed:
		if int(primary.get("passengers", 0)) >= starting:
			title_label.text = "全员到站！"
		else:
			title_label.text = "成功通关！"
		title_label.add_theme_color_override("font_color", UITheme.COLOR_CORAL)
	else:
		title_label.text = "挑战失败"
		title_label.add_theme_color_override("font_color", UITheme.COLOR_MUTED)
	passengers_value.text = "%d" % maxi(0, starting - int(primary.get("passengers", 0)))
	time_value.text = ScoreRules.format_time(float(primary.get("time_seconds", 0.0)))
	var is_custom_level := bool(LevelCatalog.get_summary(_level_id).get("custom", false))
	var stars := int(primary.get("stars", 0))
	stars_value.get_parent().get_parent().visible = not is_custom_level
	stars_value.text = "★".repeat(stars) + "☆".repeat(3 - stars) if not is_custom_level else ""
	stars_value.add_theme_color_override("font_color", UITheme.COLOR_YELLOW if stars > 0 else UITheme.COLOR_MUTED)
	if not any_completed:
		confetti.set_active(false)


func _setup_duo(players: Array, any_completed: bool) -> void:
	var is_custom_level := bool(LevelCatalog.get_summary(_level_id).get("custom", false))
	single_stats.visible = false
	duo_stats.visible = true
	winner_label.visible = true
	var winner_slot := int(_result.get("winner_slot", -1))
	if not any_completed:
		title_label.text = "双人挑战失败"
		title_label.add_theme_color_override("font_color", UITheme.COLOR_MUTED)
		winner_label.text = "两辆列车都没能保住乘客"
	else:
		title_label.text = "竞速结束！"
		title_label.add_theme_color_override("font_color", UITheme.COLOR_CORAL)
		winner_label.text = "P%d 获胜" % (winner_slot + 1) if winner_slot >= 0 else "本轮无人完赛"

	for index in 2:
		var player_data: Dictionary = players[index] if index < players.size() else {}
		var is_winner := int(player_data.get("slot", index)) == winner_slot and bool(player_data.get("completed", false))
		var name_label := p1_name if index == 0 else p2_name
		var result_label := p1_result if index == 0 else p2_result
		var stats_label := p1_stats if index == 0 else p2_stats
		var stars_label := p1_stars if index == 0 else p2_stars
		var slot := int(player_data.get("slot", index))
		name_label.text = "玩家 %d" % (slot + 1)
		if is_winner:
			name_label.text += "　· 冠军"
		if bool(player_data.get("completed", false)):
			result_label.text = "抵达终点"
			result_label.add_theme_color_override("font_color", Color(0.12, 0.5, 0.3))
		else:
			var fail_text := str(player_data.get("fail_text", ""))
			result_label.text = fail_text if not fail_text.is_empty() else "乘客归零"
			result_label.add_theme_color_override("font_color", UITheme.COLOR_CORAL_DARK)
		stats_label.text = ScoreRules.format_time(float(player_data.get("time_seconds", 0.0)))
		var stars := int(player_data.get("stars", 0))
		stars_label.visible = not is_custom_level
		stars_label.text = "★".repeat(stars) + "☆".repeat(3 - stars) if not is_custom_level else ""


func _animate_in() -> void:
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.94, 0.94)
	panel.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.38)
	tween.tween_property(panel, "modulate:a", 1.0, 0.24)


func _find_next_level(current_id: String) -> Dictionary:
	var summaries := LevelCatalog.get_summaries()
	for index in summaries.size():
		if str(summaries[index].get("id", "")) == current_id and index + 1 < summaries.size():
			return summaries[index + 1]
	return {}


func _on_retry_pressed() -> void:
	AudioDirector.play_click()
	var community_id := str(_result.get("community_entry_id", ""))
	if not community_id.is_empty():
		var entry := CommunityService.get_entry(community_id)
		if not entry.is_empty():
			GameSession.start_community_level(community_id, entry.get("level_data", {}))
			return
	if bool(_result.get("authored", false)) and not GameSession.authored_level_data.is_empty():
		GameSession.start_authored_level(GameSession.authored_level_data)
	else:
		GameSession.start_level(_level_id, _mode)


func _on_next_pressed() -> void:
	AudioDirector.play_click()
	var next_summary := _find_next_level(_level_id)
	if next_summary.is_empty():
		return
	GameSession.start_level(str(next_summary.get("id", "")), _mode)


func _on_levels_pressed() -> void:
	AudioDirector.play_click()
	if GameSession.test_from_editor:
		GameSession.return_to_editor()
	else:
		GameSession.return_to_level_select()


func _on_leaderboard_pressed() -> void:
	AudioDirector.play_click()
	GameSession.selected_level_id = _level_id
	SceneRouter.goto_leaderboard()


func _on_editor_pressed() -> void:
	AudioDirector.play_click()
	GameSession.return_to_editor()

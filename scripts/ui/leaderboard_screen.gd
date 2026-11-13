extends Control
## 排行榜界面。只通过 LeaderboardService 查询，不直接发起网络请求。
## 当前显示 玩家真实成绩。

@onready var back_button: Button = %BackButton
@onready var refresh_button: Button = %RefreshButton
@onready var level_picker: OptionButton = %LevelPicker
@onready var rows_container: VBoxContainer = %Rows
@onready var loading_label: Label = %LoadingLabel
@onready var error_label: Label = %ErrorLabel
@onready var provider_label: Label = %ProviderLabel
@onready var selected_level_label: Label = %SelectedLevelLabel

var _level_ids: Array[String] = []
var _current_level_id: String = ""
var _request_token: int = 0


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	level_picker.item_selected.connect(_on_level_selected)
	provider_label.text = "数据源：%s · 接口可替换为云端" % LeaderboardService.get_provider_name()
	_fill_level_picker()
	_load_current_level()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _fill_level_picker() -> void:
	level_picker.clear()
	_level_ids.clear()
	var summaries := LevelCatalog.get_summaries()
	for index in summaries.size():
		var summary: Dictionary = summaries[index]
		if bool(summary.get("custom", false)):
			continue
		var level_id := str(summary.get("id", ""))
		_level_ids.append(level_id)
		level_picker.add_item(str(summary.get("name", level_id)), _level_ids.size() - 1)
	if GameSession.selected_level_id in _level_ids:
		level_picker.select(_level_ids.find(GameSession.selected_level_id))
	elif not _level_ids.is_empty():
		level_picker.select(0)


func _load_current_level() -> void:
	if _level_ids.is_empty():
		_show_error("没有可用关卡。")
		return
	var selected := level_picker.selected
	if selected < 0 or selected >= _level_ids.size():
		selected = 0
	_current_level_id = _level_ids[selected]
	selected_level_label.text = str(LevelCatalog.get_summary(_current_level_id).get("name", _current_level_id))
	_request_token += 1
	var token := _request_token
	loading_label.visible = true
	loading_label.text = "正在读取轨道成绩…"
	error_label.visible = false
	_clear_rows()

	LeaderboardService.fetch_scores(_current_level_id, 10, func(result: Dictionary) -> void:
		if token != _request_token or not is_inside_tree():
			return
		_on_scores_loaded(result)
	)


func _on_scores_loaded(result: Dictionary) -> void:
	loading_label.visible = false
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("error", "排行榜加载失败")))
		return
	error_label.visible = false
	var entries: Array = result.get("entries", [])
	if entries.is_empty():
		_show_error("这一关还没有成绩，去创造第一条纪录吧。")
		return
	for index in entries.size():
		_add_row(entries[index], index)
	UIJuice.stagger(rows_container)


func _add_row(entry_data: Dictionary, index: int) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 54)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var is_local := bool(entry_data.get("is_local", false))
	var background := Color(1.0, 0.9, 0.62, 0.92) if is_local else Color(1, 1, 1, 0.5)
	var border := UITheme.COLOR_CORAL if is_local else Color(0.106, 0.196, 0.282, 0.12)
	panel.add_theme_stylebox_override("panel", _make_row_style(background, border, 12, 2 if is_local else 1))
	rows_container.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var rank_box := CenterContainer.new()
	rank_box.custom_minimum_size = Vector2(58, 0)
	row.add_child(rank_box)
	var rank_label := Label.new()
	rank_label.text = str(int(entry_data.get("rank", index + 1)))
	rank_label.add_theme_font_override("font", UITheme.title_font)
	rank_label.add_theme_font_size_override("font_size", 24)
	rank_label.add_theme_color_override("font_color", _rank_color(index))
	rank_box.add_child(rank_label)

	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(name_box)
	var name_label := Label.new()
	name_label.text = str(entry_data.get("player_name", "无名车手"))
	name_label.add_theme_font_size_override("font_size", 19)
	name_label.add_theme_color_override("font_color", UITheme.COLOR_INK)
	name_box.add_child(name_label)
	if is_local:
		var me_label := Label.new()
		me_label.text = "这是你 · 本地最佳"
		me_label.add_theme_font_size_override("font_size", 12)
		me_label.add_theme_color_override("font_color", UITheme.COLOR_CORAL_DARK)
		name_box.add_child(me_label)

	var cart_box := CenterContainer.new()
	cart_box.custom_minimum_size = Vector2(140, 0)
	row.add_child(cart_box)
	var cart_label := Label.new()
	var cart_name := str(entry_data.get("cart_name", ""))
	var cart_id := str(entry_data.get("cart_id", ""))
	if cart_name.is_empty() and not cart_id.is_empty():
		var cart_profile := CartCatalog.get_profile(cart_id)
		cart_name = cart_profile.display_name if cart_profile != null else cart_id
	if cart_name.is_empty():
		cart_name = "—"
	cart_label.text = cart_name
	cart_label.add_theme_font_size_override("font_size", 16)
	cart_label.add_theme_color_override("font_color", UITheme.COLOR_INK_SOFT)
	cart_box.add_child(cart_label)

	var passenger_box := CenterContainer.new()
	passenger_box.custom_minimum_size = Vector2(140, 0)
	row.add_child(passenger_box)
	var passenger_label := Label.new()
	passenger_label.text = "%d 位" % ScoreRules.get_lost_passengers(entry_data)
	passenger_label.add_theme_font_size_override("font_size", 17)
	passenger_label.add_theme_color_override("font_color", UITheme.COLOR_INK_SOFT)
	passenger_box.add_child(passenger_label)

	var time_box := CenterContainer.new()
	time_box.custom_minimum_size = Vector2(130, 0)
	row.add_child(time_box)
	var time_label := Label.new()
	time_label.text = ScoreRules.format_time(float(entry_data.get("time_seconds", 0.0)))
	time_label.add_theme_font_size_override("font_size", 17)
	time_label.add_theme_color_override("font_color", UITheme.COLOR_INK_SOFT)
	time_box.add_child(time_label)


## 供自动测试读取榜单行数。
func get_displayed_row_count() -> int:
	return rows_container.get_child_count()


## 供自动测试确认玩家本地最佳是否进入榜单。
func has_local_entry() -> bool:
	for child in rows_container.get_children():
		for label in child.find_children("*", "Label", true, false):
			if label is Label and (label as Label).text.contains("本地最佳"):
				return true
	return false


func _rank_color(index: int) -> Color:
	match index:
		0:
			return Color(0.95, 0.65, 0.08)
		1:
			return Color(0.45, 0.55, 0.62)
		2:
			return Color(0.72, 0.42, 0.22)
		_:
			return UITheme.COLOR_INK_SOFT


func _make_row_style(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12
	box.content_margin_right = 16
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	return box


func _clear_rows() -> void:
	for child in rows_container.get_children():
		child.queue_free()


func _show_error(message: String) -> void:
	loading_label.visible = false
	error_label.visible = true
	error_label.text = message


func _on_level_selected(_index: int) -> void:
	AudioDirector.play_click()
	_load_current_level()


func _on_refresh_pressed() -> void:
	AudioDirector.play_click()
	_load_current_level()


func _on_back_pressed() -> void:
	AudioDirector.play_click()
	SceneRouter.goto_menu()

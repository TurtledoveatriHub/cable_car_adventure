extends Control
## 关卡广场：线上最新 / 最热 / 随机、点赞、收藏、上传、试玩。
## 列表只拿摘要；点“试玩”时才向 /api/ugc/detail/:id 拉取完整关卡。

@onready var back_button: Button = %BackButton
@onready var latest_button: Button = %LatestButton
@onready var hot_button: Button = %HotButton
@onready var random_button: Button = %RandomButton
@onready var favorite_button: Button = %FavoriteButton
@onready var mine_button: Button = %MineButton
@onready var refresh_button: Button = %RefreshButton
@onready var upload_button: Button = %UploadButton
@onready var card_grid: GridContainer = %CardGrid
@onready var scroll: ScrollContainer = %Scroll
@onready var empty_label: Label = %EmptyLabel
@onready var status_label: Label = %StatusLabel
@onready var feed_footer: Control = %FeedFooter
@onready var feed_info_label: Label = %FeedInfoLabel
@onready var load_more_button: Button = %LoadMoreButton

const CARD_MIN_WIDTH := 360.0
const MAX_COLUMNS := 4
const CARD_TITLE_MAX_WIDTH := 160.0
const AUTO_LOAD_DISTANCE := 240.0

var _sort_mode: String = "latest"
## entry_id -> 本张卡片上的 Label/Button 引用；不能混存关卡摘要。
var _card_refs_by_id: Dictionary = {}
var _feed_generation: int = 0
var _feed_page: int = 1
var _feed_total: int = 0
var _feed_has_more: bool = false
var _loading_more: bool = false
var _busy: bool = false
var _upload_overlay: Control
var _upload_panel: PanelContainer
var _withdraw_overlay: Control
var _withdraw_panel: PanelContainer


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	latest_button.pressed.connect(_set_sort.bind("latest"))
	hot_button.pressed.connect(_set_sort.bind("hot"))
	random_button.pressed.connect(_set_sort.bind("random"))
	favorite_button.pressed.connect(_set_sort.bind("favorite"))
	mine_button.pressed.connect(_set_sort.bind("mine"))
	refresh_button.pressed.connect(_refresh_feed)
	upload_button.pressed.connect(_open_upload_dialog)
	load_more_button.pressed.connect(_load_more)
	card_grid.resized.connect(_update_grid_columns)
	scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_value_changed)
	# 多端权限：普通 Web（含 itch.io）隐藏上传入口，只保留广场只读浏览。
	upload_button.visible = PlatformConfig.can_upload_ugc
	if not CommunityService.changed.is_connected(_on_community_changed):
		CommunityService.changed.connect(_on_community_changed)
	_update_grid_columns()
	_refresh_feed()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _withdraw_overlay != null and is_instance_valid(_withdraw_overlay):
			_dismiss_withdraw_dialog()
		elif _upload_overlay != null and is_instance_valid(_upload_overlay):
			_close_upload_dialog()
		else:
			_on_back_pressed()
		get_viewport().set_input_as_handled()


func _set_sort(mode: String) -> void:
	_sort_mode = mode
	latest_button.set_pressed_no_signal(mode == "latest")
	hot_button.set_pressed_no_signal(mode == "hot")
	random_button.set_pressed_no_signal(mode == "random")
	favorite_button.set_pressed_no_signal(mode == "favorite")
	mine_button.set_pressed_no_signal(mode == "mine")
	_refresh_feed()


func _refresh_feed() -> void:
	_feed_generation += 1
	var generation := _feed_generation
	_feed_page = 1
	_feed_total = 0
	_feed_has_more = false
	_loading_more = false
	_update_feed_footer()
	_set_status("正在加载广场…")
	empty_label.visible = false
	CommunityService.fetch_feed(_sort_mode, func(result: Dictionary) -> void:
		if generation != _feed_generation:
			return
		var entries: Array = result.get("entries", [])
		var error := str(result.get("error", ""))
		_build_cards(entries)
		_apply_feed_meta(result)
		if not error.is_empty():
			_set_status(error, true)
		else:
			_set_status("")
	)


func _on_community_changed() -> void:
	# 只刷新当前已经建好的卡片引用，不重新请求整个列表。
	for entry_id: Variant in _card_refs_by_id.keys():
		_update_card(str(entry_id))


func _build_cards(entries: Array) -> void:
	_card_refs_by_id.clear()
	for child in card_grid.get_children():
		# 先从网格移除再排队释放，避免刷新时旧卡片与新卡片同时参与布局。
		card_grid.remove_child(child)
		child.queue_free()
	empty_label.visible = entries.is_empty()
	if entries.is_empty():
		empty_label.text = "广场内还没有关卡。\n在创意工坊制作并通关后，点“上传关卡”即可发布。"
		_update_feed_footer()
		return
	_append_cards(entries)
	UIJuice.stagger(card_grid, 0.025)
	scroll.scroll_vertical = 0


func _append_cards(entries: Array, animate_new: bool = false) -> void:
	for item: Variant in entries:
		if not item is Dictionary:
			continue
		var entry: Dictionary = item
		var entry_id := str(entry.get("id", ""))
		if entry_id.is_empty() or _card_refs_by_id.has(entry_id):
			continue
		var card := _make_card(entry)
		card_grid.add_child(card)
		# 追加分页时只让新卡片淡入，避免整页重新播放错峰动画。
		if animate_new:
			UIJuice.reveal(card)
	empty_label.visible = _card_refs_by_id.is_empty()
	_update_grid_columns()
	_update_feed_footer()


func _apply_feed_meta(result: Dictionary) -> void:
	_feed_page = int(result.get("page", 1))
	_feed_total = maxi(int(result.get("total", _card_refs_by_id.size())), _card_refs_by_id.size())
	_feed_has_more = bool(result.get("has_more", false))
	_loading_more = false
	_update_feed_footer()


func _load_more() -> void:
	if _loading_more or not _feed_has_more:
		return
	_loading_more = true
	_update_feed_footer()
	var generation := _feed_generation
	var next_page := _feed_page + 1
	CommunityService.fetch_feed_page(_sort_mode, next_page, func(result: Dictionary) -> void:
		if generation != _feed_generation:
			return
		_loading_more = false
		if not bool(result.get("ok", false)):
			_set_status(str(result.get("error", "加载更多失败")), true)
			_update_feed_footer()
			return
		_append_cards(result.get("entries", []), true)
		_apply_feed_meta(result)
	)


func _on_scroll_value_changed(_value: float) -> void:
	if not _feed_has_more or _loading_more:
		return
	var bar := scroll.get_v_scroll_bar()
	if bar.max_value <= 0.0:
		return
	if bar.value >= bar.max_value - bar.page - AUTO_LOAD_DISTANCE:
		_load_more()


func _update_feed_footer() -> void:
	var shown := _card_refs_by_id.size()
	# 没有下一页时整条 footer 隐藏，避免在浅色背景上留下低对比度文字。
	feed_footer.visible = _feed_has_more
	if not _feed_has_more:
		return
	var total := maxi(_feed_total, shown)
	feed_info_label.text = "已显示 %d / %d" % [shown, total]
	load_more_button.disabled = _loading_more
	load_more_button.text = "加载中…" if _loading_more else "加载更多"


func _update_grid_columns() -> void:
	var available := card_grid.size.x
	if available <= 1.0:
		available = maxf(1.0, size.x - 68.0)
	var gap := float(card_grid.get_theme_constant("h_separation"))
	var columns := int(floor((available + gap) / (CARD_MIN_WIDTH + gap)))
	columns = clampi(columns, 1, MAX_COLUMNS)
	if card_grid.columns != columns:
		card_grid.columns = columns


func _make_card(entry: Dictionary) -> Control:
	var entry_id := str(entry.get("id", ""))
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"PaperPanel"
	panel.custom_minimum_size = Vector2(CARD_MIN_WIDTH, 204)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = 3
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)
	# 标题 + 紧凑难度圆点；圆点紧贴标题右侧，只占 4px 间隔。
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 4)
	info.add_child(title_row)
	var name_label := Label.new()
	name_label.theme_type_variation = &"HeadingLabel"
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.text = str(entry.get("name", "无名关卡"))
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var measured_title := UITheme.heavy_font.get_string_size(
		name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20
	).x
	name_label.custom_minimum_size = Vector2(
		minf(measured_title + 2.0, CARD_TITLE_MAX_WIDTH), 0
	)
	title_row.add_child(name_label)
	var difficulty := clampi(int(entry.get("difficulty", 1)), 1, 5)
	var difficulty_label := Label.new()
	difficulty_label.theme_type_variation = &"MutedLabel"
	difficulty_label.add_theme_font_size_override("font_size", 14)
	difficulty_label.text = "●".repeat(difficulty) + "○".repeat(5 - difficulty)
	difficulty_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	difficulty_label.size_flags_vertical = Control.SIZE_SHRINK_END
	difficulty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(difficulty_label)
	var title_spacer := Control.new()
	title_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(title_spacer)
	var author_label := Label.new()
	author_label.theme_type_variation = &"MutedLabel"
	author_label.text = "关卡作者：%s　·　%s" % [
		str(entry.get("author", "游客")),
		_platform_label(str(entry.get("platform", "unknown"))),
	]
	author_label.clip_text = true
	author_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(author_label)
	# 点赞回到作者下方；不再显示关卡简介。
	var likes_label := Label.new()
	likes_label.theme_type_variation = &"MutedLabel"
	likes_label.text = "点赞数量：%d" % int(entry.get("likes", 0))
	likes_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(likes_label)
	var plays_label := Label.new()
	plays_label.theme_type_variation = &"MutedLabel"
	plays_label.text = "游玩次数：%d" % int(entry.get("plays", 0))
	info.add_child(plays_label)
	var clears_label := Label.new()
	clears_label.theme_type_variation = &"MutedLabel"
	clears_label.text = "通关次数：%d" % int(entry.get("clears", 0))
	info.add_child(clears_label)
	var best := Label.new()
	best.theme_type_variation = &"MutedLabel"
	best.text = _format_best(entry)
	info.add_child(best)
	var buttons := VBoxContainer.new()
	buttons.custom_minimum_size = Vector2(108, 0)
	buttons.add_theme_constant_override("separation", 6)
	row.add_child(buttons)
	var play_button := Button.new()
	play_button.theme_type_variation = &"SecondaryButton"
	play_button.text = "试玩"
	play_button.disabled = _busy
	play_button.pressed.connect(_on_play_pressed.bind(entry_id))
	buttons.add_child(play_button)
	var like_button := Button.new()
	like_button.theme_type_variation = &"GhostButton"
	like_button.text = "取消点赞" if CommunityService.is_liked(entry_id) else "点赞"
	like_button.pressed.connect(_on_like_pressed.bind(entry_id))
	buttons.add_child(like_button)
	var favorite := Button.new()
	favorite.theme_type_variation = &"GhostButton"
	favorite.text = "取消收藏" if CommunityService.is_favorited(entry_id) else "收藏"
	favorite.pressed.connect(_on_favorite_pressed.bind(entry_id))
	buttons.add_child(favorite)
	_card_refs_by_id[entry_id] = {
		"likes": likes_label,
		"plays": plays_label,
		"clears": clears_label,
		"best": best,
		"like_button": like_button,
		"favorite_button": favorite,
	}
	return panel


func _format_best(entry: Dictionary) -> String:
	var scores: Array = entry.get("scores", [])
	if scores.is_empty():
		return "最佳通关：暂无记录"
	var top: Dictionary = scores[0]
	return "最佳通关：%s · 丢 %d 人" % [
		ScoreRules.format_time(float(top.get("time_seconds", 0.0))),
		ScoreRules.get_lost_passengers(top),
	]


func _update_card(entry_id: String) -> void:
	var refs: Dictionary = _card_refs_by_id.get(entry_id, {})
	var entry := CommunityService.get_entry(entry_id)
	if refs.is_empty() or entry.is_empty():
		return
	if not refs.get("likes") is Label:
		return
	(refs["likes"] as Label).text = "点赞数量：%d" % int(entry.get("likes", 0))
	(refs["plays"] as Label).text = "游玩次数：%d" % int(entry.get("plays", 0))
	(refs["clears"] as Label).text = "通关次数：%d" % int(entry.get("clears", 0))
	(refs["best"] as Label).text = _format_best(entry)
	(refs["like_button"] as Button).text = "取消点赞" if CommunityService.is_liked(entry_id) else "点赞"
	(refs["favorite_button"] as Button).text = "取消收藏" if CommunityService.is_favorited(entry_id) else "收藏"


func _on_play_pressed(entry_id: String) -> void:
	if _busy:
		return
	_busy = true
	_set_status("正在下载关卡…")
	CommunityService.fetch_detail(entry_id, func(result: Dictionary) -> void:
		_busy = false
		if not bool(result.get("ok", false)):
			_set_status(str(result.get("error", "关卡下载失败")), true)
			return
		var level_data: Dictionary = result.get("level_data", {})
		if level_data.is_empty():
			_set_status("服务器返回的关卡为空", true)
			return
		AudioDirector.play_click()
		CommunityService.record_play(entry_id)
		GameSession.start_community_level(entry_id, level_data)
	)


func _on_like_pressed(entry_id: String) -> void:
	AudioDirector.play_click()
	CommunityService.toggle_like(entry_id)
	_update_card(entry_id)


func _on_favorite_pressed(entry_id: String) -> void:
	AudioDirector.play_click()
	CommunityService.toggle_favorite(entry_id)
	_update_card(entry_id)


# ---------- 撤销上传二次确认 ----------

func _confirm_withdraw_upload(_level_id: String, display_name: String, entry_id: String) -> void:
	AudioDirector.play_click()
	if _withdraw_overlay != null and is_instance_valid(_withdraw_overlay):
		_withdraw_overlay.queue_free()
	_withdraw_overlay = Control.new()
	_withdraw_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_withdraw_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_withdraw_overlay)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.08, 0.12, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			_dismiss_withdraw_dialog()
	)
	_withdraw_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_withdraw_overlay.add_child(center)
	_withdraw_panel = PanelContainer.new()
	_withdraw_panel.theme_type_variation = &"PaperPanel"
	_withdraw_panel.custom_minimum_size = Vector2(470, 230)
	center.add_child(_withdraw_panel)
	UIJuice.popup_in(_withdraw_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_withdraw_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.theme_type_variation = &"HeadingLabel"
	title.text = "撤销上传"
	box.add_child(title)
	var hint := Label.new()
	hint.theme_type_variation = &"MutedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "确定撤销「%s」的上传吗？\n撤销后该关卡会从广场下架，本地自制关卡仍会保留。" % display_name
	box.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var cancel := Button.new()
	cancel.theme_type_variation = &"GhostButton"
	cancel.text = "取消"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_dismiss_withdraw_dialog)
	buttons.add_child(cancel)
	var confirm := Button.new()
	confirm.theme_type_variation = &"DangerButton"
	confirm.text = "撤销上传"
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(_withdraw_upload_confirmed.bind(entry_id))
	buttons.add_child(confirm)


func _withdraw_upload_confirmed(entry_id: String) -> void:
	CommunityService.withdraw_entry(entry_id, func(result: Dictionary) -> void:
		if not bool(result.get("ok", false)):
			_set_status(str(result.get("error", "撤销失败")), true)
			_dismiss_withdraw_dialog()
			return
		_set_status("已撤销上传")
		_close_upload_dialog()
		_refresh_feed()
	)


func _dismiss_withdraw_dialog() -> void:
	if _withdraw_panel != null and is_instance_valid(_withdraw_panel):
		UIJuice.popup_out(_withdraw_panel, func() -> void:
			if _withdraw_overlay != null and is_instance_valid(_withdraw_overlay):
				_withdraw_overlay.queue_free()
			_withdraw_overlay = null
			_withdraw_panel = null
		)
	else:
		if _withdraw_overlay != null and is_instance_valid(_withdraw_overlay):
			_withdraw_overlay.queue_free()
		_withdraw_overlay = null
		_withdraw_panel = null


# ---------- 上传关卡弹窗 ----------

func _open_upload_dialog() -> void:
	if _withdraw_overlay != null and is_instance_valid(_withdraw_overlay):
		_withdraw_overlay.queue_free()
		_withdraw_overlay = null
		_withdraw_panel = null
	if _upload_overlay != null and is_instance_valid(_upload_overlay):
		_upload_overlay.queue_free()
	_upload_overlay = Control.new()
	_upload_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_upload_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_upload_overlay)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.08, 0.12, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			_close_upload_dialog()
	)
	_upload_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_upload_overlay.add_child(center)
	_upload_panel = PanelContainer.new()
	_upload_panel.theme_type_variation = &"PaperPanel"
	_upload_panel.custom_minimum_size = Vector2(720, 520)
	center.add_child(_upload_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_upload_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var title := Label.new()
	title.theme_type_variation = &"HeadingLabel"
	title.text = "上传到关卡广场"
	box.add_child(title)
	var hint := Label.new()
	hint.theme_type_variation = &"MutedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "只有亲自通关的自制关卡才能上传；每个账号最多 3 张。上传后由服务器审核，审核通过才会出现在广场。"
	box.add_child(hint)
	var count_label := Label.new()
	count_label.theme_type_variation = &"MutedLabel"
	count_label.text = "当前已上传：%d / %d" % [CommunityService.get_user_upload_count(), CommunityService.MAX_LOCAL_UPLOADS]
	box.add_child(count_label)
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(0, 300)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(list_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	list_scroll.add_child(list)
	var summaries := LevelCatalog.get_user_summaries()
	if summaries.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"MutedLabel"
		empty.text = "还没有自制关卡。先在关卡工坊拼接并通关一条轨道。"
		list.add_child(empty)
	var uploads_full := CommunityService.get_user_upload_count() >= CommunityService.MAX_LOCAL_UPLOADS
	for summary in summaries:
		var level_id := str(summary.get("id", ""))
		var row := PanelContainer.new()
		row.theme_type_variation = &"PaperPanel"
		var row_margin := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			row_margin.add_theme_constant_override("margin_" + side, 10)
		row.add_child(row_margin)
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		row_margin.add_child(hbox)
		var labels := VBoxContainer.new()
		labels.size_flags_horizontal = 3
		hbox.add_child(labels)
		var name_label := Label.new()
		name_label.text = str(summary.get("name", "未命名关卡"))
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.add_theme_color_override("font_color", UITheme.COLOR_INK)
		labels.add_child(name_label)
		var state_label := Label.new()
		state_label.theme_type_variation = &"MutedLabel"
		var cleared := SaveManager.is_level_cleared(level_id)
		# 重启后状态同步：本地已有 server_id 即视为已上传，按钮改为可点击的“撤销上传”。
		var server_id := str(LevelRepository.get_upload_mark(level_id).get("server_id", ""))
		var already_uploaded := not server_id.is_empty()
		var needs_reclear := LevelRepository.needs_reclear(level_id)
		state_label.text = (
			"已上传到广场，可撤销" if already_uploaded
			else ("关卡已修改，请重新通关" if needs_reclear
			else ("已通关，可上传" if cleared else "需要先通关该关卡"))
		)
		labels.add_child(state_label)
		var upload := Button.new()
		upload.custom_minimum_size = Vector2(104, 38)
		if already_uploaded:
			# 卡片上不再放“撤销上传”，统一收进上传弹窗，避免广场卡片按钮过多。
			upload.theme_type_variation = &"DangerButton"
			upload.text = "撤销上传"
			upload.disabled = false
		else:
			upload.theme_type_variation = &"SecondaryButton"
			upload.text = "上传"
			upload.disabled = uploads_full or not cleared or needs_reclear
		# 统一走一个入口：上传成功后按钮原地变为可点击的“撤销上传”，无需重开弹窗。
		upload.pressed.connect(_on_upload_row_pressed.bind(level_id, name_label.text, state_label, upload))
		hbox.add_child(upload)
		list.add_child(row)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var close := Button.new()
	close.theme_type_variation = &"GhostButton"
	close.text = "关闭"
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(_close_upload_dialog)
	buttons.add_child(close)
	UIJuice.popup_in(_upload_panel)


func _on_upload_row_pressed(
	level_id: String,
	display_name: String,
	state_label: Label,
	button: Button
) -> void:
	var server_id := str(LevelRepository.get_upload_mark(level_id).get("server_id", ""))
	if not server_id.is_empty():
		_confirm_withdraw_upload(level_id, display_name, server_id)
		return
	_upload_from_dialog(level_id, display_name, state_label, button)


func _upload_from_dialog(level_id: String, display_name: String, state_label: Label, button: Button) -> void:
	button.disabled = true
	state_label.text = "正在上传…"
	CommunityService.upload_level(level_id, display_name, func(result: Dictionary) -> void:
		# 上传期间用户可能关闭弹窗；回调里先确认行内控件仍然有效。
		if not is_instance_valid(button) or not is_instance_valid(state_label):
			_set_status("已上传到广场" if bool(result.get("ok", false)) else str(result.get("error", "上传失败")), not bool(result.get("ok", false)))
			_refresh_feed()
			return
		if not bool(result.get("ok", false)):
			state_label.text = str(result.get("error", "上传失败"))
			state_label.add_theme_color_override("font_color", UITheme.COLOR_CORAL_DARK)
			button.disabled = false
			_set_status(state_label.text, true)
			return
		var entry: Dictionary = result.get("entry", {})
		var review_status := str(entry.get("review_status", "approved"))
		state_label.text = (
			"已提交审核，可撤销" if review_status == "pending"
			else "已上传到广场，可撤销"
		)
		state_label.add_theme_color_override("font_color", UITheme.COLOR_CORAL_DARK)
		button.text = "撤销上传"
		button.theme_type_variation = &"DangerButton"
		button.disabled = false
		_set_status(state_label.text)
		_refresh_feed()
	)


func _close_upload_dialog() -> void:
	if _withdraw_overlay != null and is_instance_valid(_withdraw_overlay):
		_dismiss_withdraw_dialog()
	if _upload_panel != null and is_instance_valid(_upload_panel):
		UIJuice.popup_out(_upload_panel, func() -> void:
			if _upload_overlay != null and is_instance_valid(_upload_overlay):
				_upload_overlay.queue_free()
			_upload_overlay = null
			_upload_panel = null
		)
	else:
		if _upload_overlay != null and is_instance_valid(_upload_overlay):
			_upload_overlay.queue_free()
		_upload_overlay = null
		_upload_panel = null


func _on_back_pressed() -> void:
	AudioDirector.play_click()
	SceneRouter.goto_menu()


func _set_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	status_label.visible = not message.is_empty()
	status_label.add_theme_color_override("font_color", UITheme.COLOR_CORAL_DARK if is_error else UITheme.COLOR_MUTED)


func _platform_label(platform_id: String) -> String:
	match platform_id:
		"windows":
			return "PC"
		"android":
			return "安卓"
		"ios":
			return "iOS"
		"web":
			return "网页"
		"wechat":
			return "微信"
		"linux":
			return "Linux"
		"macos":
			return "macOS"
		_:
			return "未知平台"

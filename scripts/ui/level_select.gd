extends Control
## 关卡选择：内置关卡 + 自制关卡，读取 LevelCatalog / SaveManager。
## 卡片只负责展示与发出选择信号，不接触任何文件。

const LEVEL_CARD_SCENE := preload("res://scenes/ui/level_card.tscn")
const CART_UNLOCK_SCENE := preload("res://scenes/ui/cart_unlock_popup.tscn")
const TOUCH_SCROLL_SCRIPT := preload("res://scripts/ui/touch_scroll.gd")
const CART_NAME_FONT_SIZE := 22
const CART_DESC_FONT_SIZE := 12
const CART_LOCK_FONT_SIZE := 12

@onready var grid: GridContainer = %Grid
@onready var back_button: Button = %BackButton
@onready var all_button: Button = %AllButton
@onready var custom_button: Button = %CustomButton
@onready var unlock_all_button: Button = %UnlockAllButton
@onready var reset_button: Button = %ResetButton
@onready var stats_label: Label = %StatsLabel
@onready var mode_hint: Label = %ModeHint
@onready var empty_label: Label = %EmptyLabel
@onready var duo_settings: HBoxContainer = %DuoSettings
@onready var side_by_side_button: Button = %SideBySideButton
@onready var stacked_button: Button = %StackedButton
@onready var shared_button: Button = %SharedButton
@onready var ghost_check: Button = %GhostCheck

var _cart_panel: PanelContainer
var _cart_picker_panel: PanelContainer
var _cart_box: VBoxContainer
var _cart_popup: Control
var _cart_scroll: ScrollContainer
var _cart_touch_moved: float = 0.0

var _mode: String = GameSession.MODE_SOLO
var _cards: Array[LevelCard] = []
var _show_custom: bool = false
var _unlock_all_for_testing: bool = false
var _unlock_queue: Array[CartProfile] = []
var _unlock_popup: PopupPanel


func _ready() -> void:
	_mode = GameSession.mode
	GameSession.load_duo_settings()
	AudioDirector.set_background_music("paradise")
	back_button.pressed.connect(_on_back_pressed)
	all_button.pressed.connect(_on_mainline_pressed)
	custom_button.pressed.connect(_on_custom_pressed)
	unlock_all_button.pressed.connect(_on_unlock_all_pressed)
	reset_button.pressed.connect(_on_reset_progress_pressed)
	var show_debug_buttons := GameSession.show_unlock_debug_buttons
	unlock_all_button.visible = show_debug_buttons
	reset_button.visible = show_debug_buttons
	side_by_side_button.pressed.connect(_set_split.bind(GameSession.SPLIT_SIDE_BY_SIDE))
	stacked_button.pressed.connect(_set_split.bind(GameSession.SPLIT_STACKED))
	shared_button.pressed.connect(_set_split.bind(GameSession.SPLIT_SHARED))
	ghost_check.toggled.connect(_on_ghost_toggled)
	_update_duo_settings()
	_build_cart_panel()
	_update_filter_buttons()
	_refresh_cart_boxes()
	_populate_cards()
	_update_header()
	if not _cards.is_empty():
		_cards[0].grab_focus()
	call_deferred("_check_cart_unlock_popups")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _cart_popup != null:
			_close_cart_picker()
		else:
			_on_back_pressed()
		get_viewport().set_input_as_handled()


func _check_cart_unlock_popups() -> void:
	var seen_value: Variant = SaveManager.get_setting("seen_cart_unlocks", [])
	var seen: Array = seen_value if seen_value is Array else []
	if not seen.has("dove"):
		seen.append("dove")
		SaveManager.set_setting("seen_cart_unlocks", seen)
	_unlock_queue.clear()
	for profile in CartCatalog.get_all():
		if not seen.has(profile.id) and CartCatalog.is_unlocked(profile):
			_unlock_queue.append(profile)
	if not _unlock_queue.is_empty():
		_show_next_unlock_popup()


func _show_next_unlock_popup() -> void:
	if _unlock_queue.is_empty():
		return
	if _unlock_popup != null and is_instance_valid(_unlock_popup):
		_unlock_popup.queue_free()
	var profile: CartProfile = _unlock_queue[0]
	_mark_cart_seen(profile.id)
	_unlock_popup = CART_UNLOCK_SCENE.instantiate() as CartUnlockPopup
	add_child(_unlock_popup)
	_unlock_popup.setup(profile)
	_unlock_popup.closed.connect(_on_unlock_popup_closed)
	_unlock_popup.popup_centered(Vector2i(620, 560))


func _mark_cart_seen(cart_id: String) -> void:
	var seen_value: Variant = SaveManager.get_setting("seen_cart_unlocks", [])
	var seen: Array = seen_value if seen_value is Array else []
	if not seen.has(cart_id):
		seen.append(cart_id)
	SaveManager.set_setting("seen_cart_unlocks", seen)


func _on_unlock_popup_closed() -> void:
	if _unlock_queue.is_empty():
		return
	_unlock_queue.pop_front()
	if _unlock_popup != null and is_instance_valid(_unlock_popup):
		_unlock_popup.queue_free()
	_unlock_popup = null
	call_deferred("_show_next_unlock_popup")


func _populate_cards() -> void:
	for card in _cards:
		if is_instance_valid(card):
			card.queue_free()
	_cards.clear()
	for child in grid.get_children():
		child.queue_free()

	var summaries: Array[Dictionary] = []
	for summary in LevelCatalog.get_summaries():
		if bool(summary.get("custom", false)) == _show_custom:
			summaries.append(summary)
	empty_label.visible = summaries.is_empty()
	if summaries.is_empty():
		empty_label.text = "还没有自制关卡。\n去“关卡工坊”拼接第一条轨道吧。" if _show_custom else "主线关卡目录加载失败：\n%s" % LevelCatalog.last_error
		return

	for index in summaries.size():
		var summary: Dictionary = summaries[index]
		var level_id := str(summary.get("id", ""))
		var card := LEVEL_CARD_SCENE.instantiate() as LevelCard
		grid.add_child(card)
		card.setup(
			summary,
			SaveManager.get_level_best(level_id),
			SaveManager.get_level_stars(level_id),
			index,
			_mode == GameSession.MODE_DUO
		)
		var unlocked := true
		if not _show_custom:
			unlocked = _unlock_all_for_testing or index == 0
			if index > 0:
				unlocked = unlocked or SaveManager.is_level_cleared(str(summaries[index - 1].get("id", "")))
		card.set_locked(not unlocked)
		card.chosen.connect(_on_level_chosen)
		_cards.append(card)


func _build_cart_panel() -> void:
	_cart_panel = PanelContainer.new()
	_cart_panel.theme_type_variation = &"PaperPanel"
	_cart_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_cart_panel.offset_left = -322.0
	_cart_panel.offset_top = -246.0
	_cart_panel.offset_right = -24.0
	_cart_panel.offset_bottom = -62.0
	if _mode == GameSession.MODE_DUO:
		_cart_panel.offset_top = -330.0
		_cart_panel.offset_bottom = -74.0
	add_child(_cart_panel)
	_cart_box = VBoxContainer.new()
	_cart_box.add_theme_constant_override("separation", 8)
	_cart_panel.add_child(_cart_box)
	var title := Label.new()
	title.theme_type_variation = &"MutedLabel"
	title.text = "当前缆车（点击更换）"
	_cart_box.add_child(title)
	_refresh_cart_boxes()


func _refresh_cart_boxes() -> void:
	if _cart_box == null:
		return
	for child in _cart_box.get_children():
		if child is Button:
			child.queue_free()
	var slots: Array[int] = []
	slots.append(0)
	if _mode == GameSession.MODE_DUO:
		slots.append(1)
	for slot in slots:
		var cart_id := str(SaveManager.get_setting("cart_p%d" % (slot + 1), "dove"))
		var profile := CartCatalog.get_profile(cart_id)
		if profile == null or not CartCatalog.is_unlocked(profile):
			profile = CartCatalog.get_profile("dove")
		var button := Button.new()
		button.set_meta("stagger_priority", -10)
		button.custom_minimum_size = Vector2(0, 84)
		button.theme_type_variation = &"SecondaryButton"
		button.pressed.connect(_open_cart_picker.bind(slot))
		var content := MarginContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("margin_left", 8)
		content.add_theme_constant_override("margin_right", 8)
		content.add_theme_constant_override("margin_top", 8)
		content.add_theme_constant_override("margin_bottom", 8)
		button.add_child(content)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 10)
		content.add_child(row)
		var preview := CartPreview.new()
		preview.custom_minimum_size = Vector2(64, 64)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.setup(profile)
		row.add_child(preview)
		var labels := VBoxContainer.new()
		labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
		labels.add_theme_constant_override("separation", 1)
		row.add_child(labels)
		var name_label := Label.new()
		name_label.text = "P%d · %s" % [slot + 1, profile.display_name]
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.add_theme_color_override("font_color", UITheme.COLOR_INK)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		labels.add_child(name_label)
		var hint_label := Label.new()
		hint_label.text = "点击更换缆车"
		hint_label.add_theme_font_size_override("font_size", 12)
		hint_label.add_theme_color_override("font_color", UITheme.COLOR_MUTED)
		hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		labels.add_child(hint_label)
		_cart_box.add_child(button)


func _open_cart_picker(slot: int) -> void:
	AudioDirector.play_click()
	if _cart_popup != null and is_instance_valid(_cart_popup):
		_cart_popup.queue_free()
	_cart_popup = Control.new()
	_cart_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cart_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cart_popup)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.08, 0.12, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_cart_dim_input)
	_cart_popup.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cart_popup.add_child(center)
	_cart_picker_panel = PanelContainer.new()
	_cart_picker_panel.theme_type_variation = &"PaperPanel"
	_cart_picker_panel.custom_minimum_size = Vector2(473, 506)
	center.add_child(_cart_picker_panel)
	var scroll := ScrollContainer.new()
	scroll.set_script(TOUCH_SCROLL_SCRIPT)
	scroll.custom_minimum_size = Vector2(418, 429)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.scroll_deadzone = 12
	scroll.follow_focus = true
	_cart_scroll = scroll
	_cart_picker_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(396, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	var title := Label.new()
	title.theme_type_variation = &"HeadingLabel"
	title.text = "P%d 选择缆车" % (slot + 1)
	box.add_child(title)
	for profile in CartCatalog.get_all():
		var unlocked := CartCatalog.is_unlocked(profile)
		var button := Button.new()
		button.theme_type_variation = &"SecondaryButton"
		button.custom_minimum_size = Vector2(0, 106)
		button.disabled = not unlocked
		button.pressed.connect(_select_cart.bind(slot, profile.id))
		button.add_child(_make_cart_option_content(profile, unlocked))
		box.add_child(button)
	UIJuice.popup_in(_cart_picker_panel)


func _make_cart_option_content(profile: CartProfile, unlocked: bool) -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var icon := CartPreview.new()
	icon.custom_minimum_size = Vector2(54, 54)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.setup(profile, not unlocked)
	row.add_child(icon)
	var labels := VBoxContainer.new()
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.add_theme_constant_override("separation", 1)
	row.add_child(labels)
	var name_label := Label.new()
	name_label.text = profile.display_name
	name_label.add_theme_font_size_override("font_size", CART_NAME_FONT_SIZE)
	name_label.add_theme_color_override("font_color", UITheme.COLOR_INK)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = profile.description
	desc_label.add_theme_font_size_override("font_size", CART_DESC_FONT_SIZE)
	desc_label.add_theme_color_override("font_color", UITheme.COLOR_MUTED)
	desc_label.custom_minimum_size = Vector2(0, 34)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.max_lines_visible = 2
	desc_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(desc_label)
	if not unlocked:
		var lock_label := Label.new()
		lock_label.text = "锁定 · " + CartCatalog.get_unlock_hint(profile)
		lock_label.add_theme_font_size_override("font_size", CART_LOCK_FONT_SIZE)
		lock_label.add_theme_color_override("font_color", UITheme.COLOR_MUTED)
		lock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		labels.add_child(lock_label)
	return margin


func _input(event: InputEvent) -> void:
	if _cart_popup == null:
		return
	if event is InputEventScreenDrag:
		_cart_touch_moved += absf(event.relative.x) + absf(event.relative.y)
		if _cart_scroll != null:
			_cart_scroll.scroll_vertical -= int(event.relative.y)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_cart_touch_moved = 0.0
		else:
			if _cart_touch_moved > 18.0:
				get_viewport().set_input_as_handled()
			_cart_touch_moved = 0.0


func _on_cart_dim_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		_close_cart_picker()


func _close_cart_picker() -> void:
	if _cart_popup == null:
		return
	UIJuice.popup_out(_cart_picker_panel, _cart_popup.queue_free)
	_cart_popup = null
	_cart_scroll = null

func _select_cart(slot: int, cart_id: String) -> void:
	SaveManager.set_setting("cart_p%d" % (slot + 1), cart_id)
	_close_cart_picker()
	_refresh_cart_boxes()


func _update_header() -> void:
	var total_levels := 0
	var cleared := 0
	var stars := 0
	for summary in LevelCatalog.get_summaries():
		if bool(summary.get("custom", false)):
			continue
		total_levels += 1
		var level_id := str(summary.get("id", ""))
		if SaveManager.is_level_cleared(level_id):
			cleared += 1
		stars += SaveManager.get_level_stars(level_id)
	stats_label.text = "主线已通关 %d / %d　·　星星 %d / %d" % [cleared, total_levels, stars, total_levels * 3]
	mode_hint.text = "← 刹车/后退　·　→ 加速前进　·　成绩写入本地最佳" if _mode == GameSession.MODE_SOLO else "左右/上下分屏　·　先比丢失乘客，再比用时"
	duo_settings.visible = _mode == GameSession.MODE_DUO
	ghost_check.set_pressed_no_signal(GameSession.duo_show_ghost)
	ghost_check.text = "显示对手残影：%s" % ("开" if GameSession.duo_show_ghost else "关")
	ghost_check.visible = _mode == GameSession.MODE_DUO


func _update_filter_buttons() -> void:
	all_button.set_pressed_no_signal(not _show_custom)
	custom_button.set_pressed_no_signal(_show_custom)
	unlock_all_button.set_pressed_no_signal(_unlock_all_for_testing)


func _on_mainline_pressed() -> void:
	if _show_custom:
		_show_custom = false
		AudioDirector.play_click()
		_update_filter_buttons()
		_populate_cards()
		_update_header()


func _on_custom_pressed() -> void:
	if not _show_custom:
		_show_custom = true
		AudioDirector.play_click()
		_update_filter_buttons()
		_populate_cards()
		_update_header()


func _on_reset_progress_pressed() -> void:
	AudioDirector.play_click()
	SaveManager.reset_progress()
	_unlock_all_for_testing = false
	_populate_cards()
	_update_filter_buttons()
	_update_header()


func _on_unlock_all_pressed() -> void:
	_unlock_all_for_testing = not _unlock_all_for_testing
	SaveManager.set_setting("unlock_all_carts", _unlock_all_for_testing)
	AudioDirector.play_click()
	_update_filter_buttons()
	_refresh_cart_boxes()
	_populate_cards()
	_update_header()


func _on_level_chosen(level_id: String) -> void:
	if level_id.is_empty():
		return
	GameSession.start_level(level_id, _mode)


func _on_ghost_toggled(pressed: bool) -> void:
	GameSession.duo_show_ghost = pressed
	SaveManager.set_setting("duo_show_ghost", pressed)
	ghost_check.text = "显示对手残影：%s" % ("开" if pressed else "关")
	ghost_check.visible = _mode == GameSession.MODE_DUO


func _update_duo_settings() -> void:
	side_by_side_button.set_pressed_no_signal(GameSession.duo_split == GameSession.SPLIT_SIDE_BY_SIDE)
	stacked_button.set_pressed_no_signal(GameSession.duo_split == GameSession.SPLIT_STACKED)
	shared_button.set_pressed_no_signal(GameSession.duo_split == GameSession.SPLIT_SHARED)


func _set_split(split: String) -> void:
	AudioDirector.play_click()
	GameSession.set_duo_split(split)
	_update_duo_settings()


func _on_back_pressed() -> void:
	AudioDirector.play_click()
	SceneRouter.goto_menu()

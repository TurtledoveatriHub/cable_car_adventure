class_name LevelEditor
extends Node2D

const EDITOR_SESSION_PATH := "user://editor_last_session.json"
## 数据驱动关卡编辑器：
## - 轨道片段拼接（直线 / 左弯 / 右弯 / 竖直环圈）
## - 障碍物与乘客放置（基于轨道弧长 s + 偏移）
## - 起终点选择、对象拖动、参数编辑、保存为 user://levels/*.json
## 文件读写全部委托 LevelCatalog / LevelRepository。

const TYPE_IDS := [
	"bird", "crate", "barrier", "hot_air_balloon", "ferris_wheel", "large_ferris_wheel", "caterpillar",
	"vine", "venus_flytrap", "snow_elf", "ice_crystal", "storm", "fan",
	"flying_bird", "flying_fish", "meteor", "dream_elf", "bubble", "cannonball", "dream_void",
]
const TYPE_LABELS := [
	"海鸥", "木箱", "路障", "热气球", "小摩天轮", "大摩天轮", "毛毛虫",
	"松树", "捕蝇草", "雪精灵", "冰晶", "雷云", "风车",
	"飞鸟", "飞鱼", "陨石", "梦精灵", "泡泡", "炮弹", "梦虚",
]
const PREFAB_LABELS := {
	"bird": "海鸥", "crate": "木箱", "barrier": "路障",
	"hot_air_balloon": "热气球", "ferris_wheel": "小摩天轮", "large_ferris_wheel": "大摩天轮", "caterpillar": "毛毛虫",
	"vine": "松树", "venus_flytrap": "捕蝇草", "snow_elf": "雪精灵", "cannonball": "炮弹",
	"ice_crystal": "冰晶", "storm": "雷云", "fan": "风车",
	"flying_bird": "飞鸟", "flying_fish": "飞鱼", "meteor": "陨石",
	"dream_elf": "梦精灵", "bubble": "泡泡", "dream_void": "梦虚",
}
const MOTION_IDS := ["static", "oscillate_x", "oscillate_y", "circle", "ellipse"]
const MOTION_LABELS := ["静止", "左右移动", "上下移动", "圆周运动", "椭圆运动"]

@onready var track_view: TrackRenderer = $World/TrackView
@onready var overlay: EditorOverlay = $World/Overlay
@onready var camera: Camera2D = $Camera2D
@onready var backdrop: SkyBackdrop = $BackdropLayer/SkyBackdrop
@onready var subtitle_edit: TextEdit = %SubtitleEdit
@onready var status_label: Label = %StatusLabel
@onready var level_stats_label: Label = %LevelStatsLabel
@onready var template_picker: OptionButton = %TemplatePicker
@onready var difficulty_spin: SpinBox = %DifficultySpin
@onready var par_spin: SpinBox = %ParSpin
@onready var theme_option: OptionButton = %ThemeOption
@onready var background_option: OptionButton = %BackgroundOption
@onready var camera_fit_button: Button = %CameraFitButton
@onready var grid_toggle: Button = %GridToggle
@onready var level_title_edit: LineEdit = %LevelTitleEdit
@onready var motion_preview_check: Button = %MotionPreviewCheck
@onready var left_vbox: VBoxContainer = %LeftVBox
@onready var place_toggle: Button = %PlaceToggle
@onready var level_toggle: Button = %LevelToggle
@onready var collapse_button: Button = %CollapseButton
@onready var left_panel: PanelContainer = $UILayer/Root/ContentMargin/Workspace/LeftPanel
@onready var right_panel: PanelContainer = $UILayer/Root/ContentMargin/Workspace/RightPanel
@onready var level_grid: GridContainer = %LevelGrid
@onready var subtitle_row: HBoxContainer = %SubtitleRow
@onready var place_length_spin: SpinBox = %PlaceLengthSpin
@onready var place_break_spin: SpinBox = %PlaceBreakSpin
@onready var break_mode_check: Button = %BreakModeCheck
@onready var flip_button: Button = %FlipButton
@onready var rotate_left_button: Button = %RotateLeftButton
@onready var rotate_right_button: Button = %RotateRightButton
@onready var delete_level_button: Button = %DeleteLevelButton
@onready var undo_button: Button = %UndoButton
@onready var delete_selection_button: Button = %DeleteSelectionButton
@onready var flip_object_button: Button = %FlipObjectButton
@onready var track_direction_button: Button = %TrackDirectionButton
@onready var redo_button: Button = %RedoButton
@onready var title_label: Label = %Title
@onready var load_title: Label = %LoadTitle
@onready var new_button: Button = %NewButton
@onready var load_template_button: Button = %LoadTemplateButton
@onready var prefab_toggle: Button = %PrefabToggle
@onready var prefab_row: HBoxContainer = %PrefabRow
@onready var place_grid: GridContainer = %PlaceGrid
@onready var cancel_placement_button: Button = %CancelPlacementButton
@onready var obstacle_prefab_option: OptionButton = %ObstaclePrefabOption

var _draft: Dictionary = {}
var _level: LevelData
var _selected_piece: int = 0
var _selected_kind: String = ""
var _selected_index: int = -1
var _placement_mode: String = ""
var _dragging: bool = false
var _panning: bool = false
var _syncing_ui: bool = false
var _mouse_world: Vector2 = Vector2.ZERO
var _obstacle_prefab_id: String = "bird"
var _track_kind: String = "straight"
var _placement_flip: bool = false
var _placement_rotation: float = 0.0

## 工坊默认放置长度（像素）：直线 240，所有曲线 120，圆环 960。
const DEFAULT_STRAIGHT_LENGTH := 240.0
const DEFAULT_CURVE_LENGTH := 120.0
const DEFAULT_LOOP_LENGTH := 960.0
## 各轨道类型首次选中时的默认长度；修改这里即可统一调整工坊默认值。
var _placement_lengths: Dictionary = {
	"straight": DEFAULT_STRAIGHT_LENGTH,
	"curve15": DEFAULT_CURVE_LENGTH,
	"curve30": DEFAULT_CURVE_LENGTH,
	"curve45": DEFAULT_CURVE_LENGTH,
	"curve60": DEFAULT_CURVE_LENGTH,
	"loop": DEFAULT_LOOP_LENGTH,
}
var _placement_breaks: Dictionary = {
	"straight": false, "curve15": false, "curve30": false, "curve45": false, "curve60": false, "loop": false,
}
var _preview_root: Node2D
var _obstacle_ghost: Sprite2D
var _ghost_visual_cache: Dictionary = {}
var _obstacle_scale_cache: Dictionary = {}
var _placement_snap: Dictionary = {}
var _grid_enabled: bool = true
const GRID_SIZE: float = 60.0
var _developer_mode: bool = false
var _delete_overlay: Control
var _delete_panel: PanelContainer
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _restoring_history: bool = false
var _dirty: bool = false
var _unsaved_overlay: Control
var _unsaved_panel: PanelContainer
var _place_expanded: bool = true
var _prefab_expanded: bool = true
var _level_expanded: bool = true
var _prefab_body: VBoxContainer
var _touch_points: Dictionary = {}
var _touch_last_distance: float = 0.0
var _touch_last_mid: Vector2 = Vector2.ZERO
var _touch_place_pending: bool = false
var _touch_place_world: Vector2 = Vector2.ZERO


func _ready() -> void:
	var intro_root := get_node_or_null("UILayer/Root") as Control
	if intro_root != null:
		intro_root.modulate.a = 0.0
		call_deferred("_play_editor_intro")
	# 编辑器通过代码加入场景树时也强制继承全局 UI 主题。
	_developer_mode = GameSession.developer_mode
	# 玩家工坊不再开放“关卡简介”；开发者界面保留该字段。
	subtitle_row.visible = _developer_mode
	if _developer_mode:
		title_label.text = "开发者关卡"
		load_title.text = "载入主线关卡"
		new_button.visible = true
		new_button.text = "新建空白环线"
	get_tree().root.theme = UITheme.theme
	var ui_root := get_node_or_null("UILayer/Root") as Control
	if ui_root != null:
		ui_root.theme = UITheme.theme
	_build_prefab_options()
	_build_theme_options()
	_build_background_options()
	_build_preview_layer()
	_connect_ui()
	grid_toggle.button_pressed = true
	_on_grid_toggled(true)
	_reorder_left_panel()
	var right_vbox := get_node_or_null("UILayer/Root/ContentMargin/Workspace/RightPanel/Scroll/RightVBox") as VBoxContainer
	if right_vbox != null:
		var history := undo_button.get_parent() as Control
		var fit_index := camera_fit_button.get_index()
		right_vbox.move_child(history, fit_index + 1)
		right_vbox.move_child(delete_selection_button, fit_index + 2)
		# “轨道前进方向”与“翻转当前选中对象”共用删除按钮上方的位置。
		right_vbox.move_child(track_direction_button, delete_selection_button.get_index())
		right_vbox.move_child(flip_object_button, delete_selection_button.get_index())
		var bottom_hbox := get_node_or_null("UILayer/Root/BottomBar/HBox") as HBoxContainer
		if bottom_hbox != null:
			level_stats_label.reparent(bottom_hbox, false)
			level_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# 删除当前关卡放在右侧“删除选中对象”下方。
		delete_level_button.custom_minimum_size = Vector2(0, 36)
		delete_level_button.remove_theme_font_size_override("font_size")
		delete_level_button.text = "删除当前关卡"
		right_vbox.move_child(delete_level_button, delete_selection_button.get_index() + 1)
		if cancel_placement_button.get_parent() != right_vbox:
			cancel_placement_button.reparent(right_vbox, false)
		right_vbox.move_child(cancel_placement_button, camera_fit_button.get_index() + 1)
	_refresh_template_picker()
	var return_loaded := false
	var return_id := str(GameSession.editor_return_level_id)
	if not return_id.is_empty() and bool(LevelCatalog.get_raw_level(return_id).get("ok", false)):
		_load_template(return_id, true)
		GameSession.editor_return_level_id = ""
		return_loaded = true
		_set_status("已返回试玩关卡")
	var restored := false
	if not return_loaded and not _developer_mode:
		restored = _load_editor_session()
	if not return_loaded and not restored:
		var fallback_id := str(GameSession.selected_level_id)
		if not _developer_mode and fallback_id.is_empty():
			fallback_id = str(SaveManager.get_setting("editor_last_level_id", ""))
		if not _developer_mode and fallback_id.begins_with("custom_") and bool(LevelCatalog.get_raw_level(fallback_id).get("ok", false)):
			_load_template(fallback_id, true)
		else:
			_create_default_draft()
	elif not return_loaded and restored:
		_refresh_editor(true)
		_refresh_template_picker()
		_update_delete_level_button()
		_set_status("已恢复上次编辑的关卡")
	_refresh_history_buttons()
	if _developer_mode and not return_loaded:
		_load_template("level_01", true)
	call_deferred("_fit_view")
	set_process_unhandled_input(true)


func _build_prefab_options() -> void:
	obstacle_prefab_option.clear()
	for index in TYPE_IDS.size():
		var prefab_id: String = str(TYPE_IDS[index])
		obstacle_prefab_option.add_item(str(PREFAB_LABELS.get(prefab_id, prefab_id)))
		obstacle_prefab_option.set_item_metadata(index, prefab_id)
	obstacle_prefab_option.select(0)
	_obstacle_prefab_id = TYPE_IDS[0]


func _play_editor_intro() -> void:
	var intro_root := get_node_or_null("UILayer/Root") as Control
	if intro_root == null:
		return
	intro_root.modulate.a = 1.0
	var left := get_node_or_null("UILayer/Root/ContentMargin/Workspace/LeftPanel")
	var right := get_node_or_null("UILayer/Root/ContentMargin/Workspace/RightPanel")
	if left != null:
		UIJuice.page_in(left)
	if right != null:
		UIJuice.page_in(right)


func _reorder_left_panel() -> void:
	var left := prefab_row.get_parent()
	if left == null:
		return
	var load_title_node := get_node_or_null("UILayer/Root/ContentMargin/Workspace/LeftPanel/LeftScroll/LeftVBox/LoadTitle") as Control
	var insert_at := load_title_node.get_index() if load_title_node != null else new_button.get_index() + 1
	_prefab_body = VBoxContainer.new()
	_prefab_body.name = "PrefabBody"
	_prefab_body.add_theme_constant_override("separation", 6)
	left.add_child(_prefab_body)
	left.move_child(_prefab_body, insert_at)
	for node in [prefab_row, place_grid, motion_preview_check]:
		if node != null:
			node.reparent(_prefab_body, false)
	# toggle button 放在 body 前面
	left.move_child(prefab_toggle, insert_at)
	left.move_child(_prefab_body, insert_at + 1)


func _toggle_place_section() -> void:
	_place_expanded = not _place_expanded
	place_toggle.text = ("v " if _place_expanded else "> ") + "放置缆线"
	for child in left_vbox.get_children():
		if child == place_toggle or child == prefab_toggle or child == _prefab_body:
			continue
		# 载入/新建/删除关卡属于独立区域，不跟随“放置缆线”折叠。
		if child == load_title or child == template_picker or child == load_template_button or child == new_button or child == delete_level_button:
			continue
		child.visible = _place_expanded


func _toggle_prefab_section() -> void:
	_prefab_expanded = not _prefab_expanded
	prefab_toggle.text = ("v " if _prefab_expanded else "> ") + "放置预制体（障碍 / 乘客）"
	if _prefab_body != null:
		_prefab_body.visible = _prefab_expanded


func _toggle_all_panels() -> void:
	var collapsed := left_panel.visible
	left_panel.visible = not collapsed
	right_panel.visible = not collapsed
	collapse_button.text = "展开设置" if collapsed else "整体收起"


func _toggle_level_section() -> void:
	_level_expanded = not _level_expanded
	level_toggle.text = ("v " if _level_expanded else "> ") + "关卡设置"
	level_title_edit.get_parent().visible = _level_expanded
	subtitle_row.visible = _level_expanded and _developer_mode
	level_grid.visible = _level_expanded


func _build_preview_layer() -> void:
	_preview_root = Node2D.new()
	_preview_root.name = "ObstaclePreviews"
	_preview_root.z_index = 6
	$World.add_child(_preview_root)
	$World.move_child(_preview_root, 1)
	_obstacle_ghost = Sprite2D.new()
	_obstacle_ghost.name = "ObstacleGhost"
	_obstacle_ghost.z_index = 9
	_obstacle_ghost.visible = false
	$World.add_child(_obstacle_ghost)
	$World.move_child(_obstacle_ghost, 2)


func _refresh_obstacle_previews() -> void:
	if _preview_root == null:
		return
	for child in _preview_root.get_children():
		child.queue_free()
	if _level == null or _level.track == null or not _level.track.is_valid():
		return
	for index in _draft.get("obstacles", []).size():
		var data: Dictionary = _draft["obstacles"][index]
		var prefab_id := str(data.get("prefab", "bird"))
		var scene := ObstacleDefinitionDB.get_scene(prefab_id)
		if scene == null:
			continue
		var preview := scene.instantiate() as Obstacle
		if preview == null:
			continue
		preview.name = "Preview_%d" % index
		preview.monitoring = false
		preview.monitorable = false
		preview.collision_layer = 0
		_preview_root.add_child(preview)
		preview.monitoring = false
		preview.monitorable = false
		preview.collision_layer = 0
		preview.configure(data, _level.track, 1.0)
		preview.apply_flip(bool(data.get("flip_x", false)))
		preview.set_motion_preview_enabled(motion_preview_check.button_pressed)
		_set_preview_idle_frame(preview)


func _set_preview_idle_frame(preview: Obstacle) -> void:
	var animated := preview.get_node_or_null("Visual") as AnimatedSprite2D
	if animated == null or animated.sprite_frames == null:
		return
	if animated.sprite_frames.has_animation(&"idle"):
		animated.animation = &"idle"
		animated.frame = 0
		animated.pause()


func _record_undo() -> void:
	if _restoring_history or _syncing_ui:
		return
	_dirty = true
	_undo_stack.append(_draft.duplicate(true))
	if _undo_stack.size() > 60:
		_undo_stack.pop_front()
	_redo_stack.clear()
	_refresh_history_buttons()


func _undo() -> void:
	if _undo_stack.is_empty():
		_set_status("没有可撤销的操作")
		return
	_redo_stack.append(_draft.duplicate(true))
	_dirty = true
	_restoring_history = true
	_draft = _undo_stack.pop_back()
	_selected_kind = ""
	_selected_index = -1
	_restoring_history = false
	_refresh_editor(false)
	_refresh_history_buttons()
	_set_status("已撤销")


func _redo() -> void:
	if _redo_stack.is_empty():
		_set_status("没有可重做的操作")
		return
	_dirty = true
	_undo_stack.append(_draft.duplicate(true))
	_dirty = true
	_restoring_history = true
	_draft = _redo_stack.pop_back()
	_selected_kind = ""
	_selected_index = -1
	_restoring_history = false
	_refresh_editor(false)
	_refresh_history_buttons()
	_set_status("已重做")


func _refresh_history_buttons() -> void:
	undo_button.disabled = _undo_stack.is_empty()
	redo_button.disabled = _redo_stack.is_empty()


func _on_motion_preview_toggled(enabled: bool) -> void:
	motion_preview_check.text = "运动预览：" + ("开" if enabled else "关")
	_dragging = false
	if _preview_root == null:
		return
	if enabled:
		for child in _preview_root.get_children():
			if child.has_method("set_motion_preview_enabled"):
				child.set_motion_preview_enabled(true)
	else:
		# 关闭预览时重建，让障碍回到放置时的 base position，而不是停在运动中的位置。
		_refresh_obstacle_previews()


func _update_obstacle_ghost() -> void:
	if _obstacle_ghost == null:
		return
	var ghost_world := _grid_snap(_mouse_world) if _grid_enabled else _mouse_world
	var show_obstacle := _placement_mode == "obstacle"
	_obstacle_ghost.visible = show_obstacle
	if show_obstacle:
		var info := _obstacle_visual_info(_obstacle_prefab_id)
		var visual_offset: Vector2 = info.get("offset", Vector2.ZERO)
		var visual_scale: Vector2 = info.get("scale", Vector2.ONE)
		_obstacle_ghost.texture = info.get("texture", null) as Texture2D
		_obstacle_ghost.scale = visual_scale
		_obstacle_ghost.position = ghost_world + visual_offset
		_obstacle_ghost.rotation = float(info.get("rotation", 0.0))
		_obstacle_ghost.flip_h = _placement_flip
		_obstacle_ghost.modulate = Color(1.0, 0.82, 0.25, 0.58)


## 放置幽灵使用障碍场景真实的 Visual 纹理/缩放，而不是按 id 猜资源。
func _obstacle_visual_info(prefab_id: String) -> Dictionary:
	if _ghost_visual_cache.has(prefab_id):
		return _ghost_visual_cache[prefab_id]
	var info := {}
	var scene := ObstacleDefinitionDB.get_scene(prefab_id)
	if scene != null:
		var probe := scene.instantiate()
		var visual := probe.get_node_or_null("Visual") as Node2D
		if visual is AnimatedSprite2D:
			var animated := visual as AnimatedSprite2D
			if animated.sprite_frames != null:
				var animation := &"idle"
				if not animated.sprite_frames.has_animation(animation):
					var names := animated.sprite_frames.get_animation_names()
					animation = StringName(names[0]) if not names.is_empty() else StringName("idle")
				if animated.sprite_frames.has_animation(animation):
					info["texture"] = animated.sprite_frames.get_frame_texture(animation, 0)
		elif visual is Sprite2D:
			info["texture"] = (visual as Sprite2D).texture
		info["root_scale"] = maxf(absf(probe.scale.x), absf(probe.scale.y))
		if visual != null:
			info["scale"] = probe.scale * visual.scale
			info["offset"] = probe.scale * visual.position
			info["rotation"] = visual.rotation
		probe.free()
	if not info.has("texture"):
		push_error("Obstacle preview '%s' 缺少 Visual 纹理" % prefab_id)
	_ghost_visual_cache[prefab_id] = info
	return info


func _build_background_options() -> void:
	background_option.clear()
	for index in LevelData.get_background_ids().size():
		var background_id: String = LevelData.get_background_ids()[index]
		var label := str(LevelData.BACKGROUNDS[background_id].get("label", background_id))
		background_option.add_item(label)
		background_option.set_item_metadata(index, background_id)
	background_option.item_selected.connect(_on_background_selected)


func _build_theme_options() -> void:
	theme_option.clear()
	for index in LevelData.get_theme_ids().size():
		var theme_id: String = LevelData.get_theme_ids()[index]
		var preset: Dictionary = LevelData.THEME_PRESETS[theme_id]
		theme_option.add_item(str(preset.get("label", theme_id)))
		theme_option.set_item_metadata(index, theme_id)


func _connect_ui() -> void:
	%BackButton.pressed.connect(_on_back_pressed)
	%SaveButton.pressed.connect(_on_save_pressed)
	%TestButton.pressed.connect(_on_test_pressed)
	%StraightButton.pressed.connect(_start_track_placement.bind("straight"))
	%Curve15Button.pressed.connect(_start_track_placement.bind("curve15"))
	%Curve30Button.pressed.connect(_start_track_placement.bind("curve30"))
	%Curve45Button.pressed.connect(_start_track_placement.bind("curve45"))
	%Curve60Button.pressed.connect(_start_track_placement.bind("curve60"))
	%LoopButton.pressed.connect(_start_track_placement.bind("loop"))
	%FlipButton.pressed.connect(_toggle_flip)
	%RotateLeftButton.pressed.connect(_rotate_placement.bind(-90.0))
	%RotateRightButton.pressed.connect(_rotate_placement.bind(90.0))
	%LoadTemplateButton.pressed.connect(_on_load_template_pressed)
	%NewButton.pressed.connect(_on_new_pressed)
	obstacle_prefab_option.item_selected.connect(_on_obstacle_prefab_selected)
	theme_option.item_selected.connect(_on_theme_selected)
	camera_fit_button.pressed.connect(_on_camera_fit_pressed)
	grid_toggle.toggled.connect(_on_grid_toggled)
	level_title_edit.text_changed.connect(_on_name_changed)
	motion_preview_check.toggled.connect(_on_motion_preview_toggled)
	place_toggle.pressed.connect(_toggle_place_section)
	%PrefabToggle.pressed.connect(_toggle_prefab_section)
	level_toggle.pressed.connect(_toggle_level_section)
	collapse_button.pressed.connect(_toggle_all_panels)
	place_length_spin.value_changed.connect(_on_place_length_changed)
	break_mode_check.toggled.connect(_on_place_break_toggled)
	%PlaceObstacleButton.pressed.connect(_set_placement.bind("obstacle"))
	%SetStartButton.pressed.connect(_set_placement.bind("start"))
	%SetFinishButton.pressed.connect(_set_placement.bind("finish"))
	%CancelPlacementButton.pressed.connect(_cancel_placement)
	%DeleteLevelButton.pressed.connect(_on_delete_level_pressed)
	%UndoButton.pressed.connect(_undo)
	%RedoButton.pressed.connect(_redo)
	%DeleteSelectionButton.pressed.connect(_delete_selection)
	%FlipObjectButton.pressed.connect(_flip_selected_object)
	%TrackDirectionButton.pressed.connect(_toggle_track_direction)
	subtitle_edit.text_changed.connect(_on_subtitle_changed)
	difficulty_spin.value_changed.connect(_on_level_field_changed)
	par_spin.value_changed.connect(_on_level_field_changed)


func _refresh_template_picker() -> void:
	template_picker.clear()
	var custom_index := 0
	var source_summaries: Array = []
	if _developer_mode:
		for summary in LevelCatalog.get_summaries():
			if not bool(summary.get("custom", false)):
				source_summaries.append(summary)
	else:
		source_summaries = LevelCatalog.get_user_summaries()
	for summary in source_summaries:
		var prefix := "主线" if _developer_mode else "自制"
		template_picker.add_item("%s · %s" % [prefix, str(summary.get("name", "未命名"))])
		template_picker.set_item_metadata(custom_index, str(summary.get("id", "")))
		custom_index += 1
	if template_picker.item_count == 0:
		template_picker.add_item("暂无主线关卡" if _developer_mode else "暂无自制关卡")
		template_picker.set_item_metadata(0, "")
		template_picker.disabled = true
		return
	template_picker.disabled = false
	for index in template_picker.item_count:
		if str(template_picker.get_item_metadata(index)) == str(_draft.get("id", "")):
			template_picker.select(index)
			return
	template_picker.select(0)


func _save_editor_session() -> void:
	if _developer_mode or _draft.is_empty() or GameSession.suppress_editor_session:
		return
	var session_name := str(_draft.get("name", ""))
	if session_name.begins_with("工坊测试关卡") or session_name.begins_with("测试关卡"):
		return
	var payload := {
		"version": 1,
		"draft": _draft,
		"selected_piece": _selected_piece,
		"saved_at": int(Time.get_unix_time_from_system()),
	}
	var file := FileAccess.open(EDITOR_SESSION_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload, "\t", false))
	file.flush()
	file.close()


func _load_editor_session() -> bool:
	if not FileAccess.file_exists(EDITOR_SESSION_PATH):
		return false
	var file := FileAccess.open(EDITOR_SESSION_PATH, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return false
	var payload: Dictionary = json.data
	var loaded: Variant = payload.get("draft", {})
	if not loaded is Dictionary:
		return false
	var candidate := (loaded as Dictionary).duplicate(true)
	var id := str(candidate.get("id", ""))
	if id.is_empty() or not id.begins_with("custom_"):
		return false
	_draft = candidate
	_selected_piece = clampi(int(payload.get("selected_piece", 0)), 0, maxi(0, _piece_count() - 1))
	_selected_kind = ""
	_selected_index = -1
	_placement_mode = ""
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_editor_session()


func _exit_tree() -> void:
	if is_instance_valid(level_title_edit):
		_sync_draft_fields()
	_save_editor_session()


func _load_template(template_id: String, preserve_id: bool = false) -> void:
	var raw_result := LevelCatalog.get_raw_level(template_id)
	if not bool(raw_result.get("ok", false)):
		_set_status("载入失败：%s" % raw_result.get("error", ""))
		if _draft.is_empty():
			_create_default_draft()
		return
	var loaded: Dictionary = (raw_result.get("data", {}) as Dictionary).duplicate(true)
	if _developer_mode:
		loaded["custom"] = false
		loaded["source"] = "builtin"
	else:
		var was_builtin := not bool(loaded.get("custom", false))
		if not preserve_id or was_builtin:
			loaded["id"] = LevelCatalog.generate_custom_id()
		if was_builtin:
			loaded["name"] = "%s · 我的" % str(loaded.get("name", "环线"))
		loaded["source"] = "user"
		loaded["custom"] = true
	loaded["schema_version"] = LevelData.SCHEMA_VERSION
	_draft = loaded
	_selected_piece = 0
	_selected_kind = ""
	_selected_index = -1
	_placement_mode = ""
	_dirty = false
	if not _developer_mode:
		SaveManager.set_setting("editor_last_level_id", str(loaded.get("id", "")))
	_refresh_editor(true)
	_refresh_template_picker()
	_set_status("已载入%s：%s" % ["主线" if _developer_mode else "模板", str(loaded.get("name", ""))])
	_update_delete_level_button()


func _leave_editor() -> void:
	_sync_draft_fields()
	_save_editor_session()
	if not _developer_mode:
		SaveManager.set_setting("editor_last_level_id", str(_draft.get("id", "")))
	GameSession.developer_mode = false
	SceneRouter.goto_menu()


func _dismiss_unsaved_dialog() -> void:
	if _unsaved_panel != null:
		UIJuice.popup_out(_unsaved_panel, func() -> void: _unsaved_overlay.hide())


func _dismiss_delete_dialog() -> void:
	if _delete_panel != null:
		UIJuice.popup_out(_delete_panel, func() -> void: _delete_overlay.hide())


func _show_unsaved_dialog() -> void:
	if _unsaved_overlay != null and is_instance_valid(_unsaved_overlay):
		_unsaved_overlay.queue_free()
	_unsaved_overlay = Control.new()
	_unsaved_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_unsaved_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var ui_root := get_node_or_null("UILayer/Root") as Control
	if ui_root != null:
		ui_root.add_child(_unsaved_overlay)
	else:
		add_child(_unsaved_overlay)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.08, 0.12, 0.62)
	_unsaved_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_unsaved_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"PaperPanel"
	panel.custom_minimum_size = Vector2(500, 240)
	center.add_child(panel)
	_unsaved_panel = panel
	UIJuice.popup_in(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.theme_type_variation = &"HeadingLabel"
	title.text = "未保存的修改"
	box.add_child(title)
	var hint := Label.new()
	hint.theme_type_variation = &"MutedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "当前自制关卡有未保存的修改。直接返回会丢失这些修改。"
	box.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var cancel := Button.new()
	cancel.theme_type_variation = &"GhostButton"
	cancel.text = "继续编辑"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_dismiss_unsaved_dialog)
	buttons.add_child(cancel)
	var discard := Button.new()
	discard.theme_type_variation = &"GhostButton"
	discard.text = "不保存返回"
	discard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	discard.pressed.connect(func() -> void:
		_dirty = false
		_unsaved_overlay.hide()
		_leave_editor()
	)
	buttons.add_child(discard)
	var save := Button.new()
	save.theme_type_variation = &"PrimaryButton"
	save.text = "保存并返回"
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(func() -> void:
		_on_save_pressed()
		if not _dirty:
			_unsaved_overlay.hide()
			_leave_editor()
	)
	buttons.add_child(save)


func _create_default_draft() -> void:
	if _developer_mode:
		_create_developer_blank_draft()
		return
	_draft = {
		"schema_version": LevelData.SCHEMA_VERSION,
		"id": LevelCatalog.generate_custom_id(),
		"name": LevelCatalog.next_unique_user_name("我的环线"),
		"subtitle": "自制关卡",
		"description": "在关卡工坊中拼接的轨道。",
		"difficulty": 1,
		"par_time": 60.0,
		"theme": LevelData.DEFAULT_THEME.duplicate(true),
		"track": {
			"start_angle_deg": 0.0,
			"pieces": [
				{"type": "straight", "length": 280.0},
				{"type": "arc", "radius": 200.0, "angle": -35.0},
				{"type": "straight", "length": 300.0},
				{"type": "arc", "radius": 200.0, "angle": 35.0},
				{"type": "straight", "length": 320.0},
			],
			"start_s": 60.0,
			"finish_s": 900.0,
		},
		"obstacles": [],
		"analytics_tags": ["自制"],
	}
	_selected_piece = 0
	_selected_kind = ""
	_selected_index = -1
	_dirty = false
	_refresh_editor(true)
	_set_status("已创建新的环线草稿")


## 开发者模式新建主线：空白三角环线（三条直线首尾相接），保存后写入 res://data/levels/level_XX.json。
func _create_developer_blank_draft() -> void:
	var level_id := DeveloperService.next_level_id()
	var number := int(level_id.trim_prefix("level_"))
	_draft = {
		"schema_version": LevelData.SCHEMA_VERSION,
		"id": level_id,
		"name": "主线关卡 %02d" % number,
		"subtitle": "空白环线（三直线）",
		"description": "开发者新建的空白环线，可在工坊中继续拼接。",
		"difficulty": 1,
		"par_time": 60.0,
		"theme": LevelData.DEFAULT_THEME.duplicate(true),
		"track": {
			"start_angle_deg": 0.0,
			"pieces": [
				{"type": "straight", "length": 240.0, "origin": [0.0, 0.0], "heading_deg": 0.0},
				{"type": "straight", "length": 240.0, "origin": [240.0, 0.0], "heading_deg": 0.0},
				{"type": "straight", "length": 240.0, "origin": [480.0, 0.0], "heading_deg": 0.0},
			],
			"start_s": 60.0,
			"finish_s": 660.0,
		},
		"obstacles": [],
		"analytics_tags": ["主线", "空白环线"],
		"custom": false,
		"source": "builtin",
	}
	var track_probe := TrackGeometry.from_track_data(_draft["track"])
	if track_probe.is_valid():
		_draft["track"]["finish_s"] = track_probe.total_length * 0.96
	_selected_piece = 0
	_selected_kind = ""
	_selected_index = -1
	_placement_mode = ""
	_dirty = false
	_refresh_editor(true)
	_set_status("已创建空白环线 %s；保存后写入主线目录" % level_id)


func _refresh_editor(fit_view: bool = false) -> void:
	_level = LevelData.from_dictionary(_draft)
	_auto_expand_camera_bounds()
	track_view.configure(_level, true, _selected_piece)
	var preview_info := _get_obstacle_preview_info()
	overlay.set_obstacle_preview(_obstacle_prefab_id, float(preview_info.get("range", 0.0)), preview_info.get("path", PackedVector2Array()))
	var overlay_mouse := _mouse_world
	if _grid_enabled and _placement_mode == "obstacle":
		overlay_mouse = _grid_snap(_mouse_world)
	overlay.update_preview(_level, _selected_kind, _selected_index, _placement_mode, overlay_mouse)
	_sync_selected_obstacle_preview()
	_update_track_preview()
	_refresh_obstacle_previews()
	_sync_ui_from_draft()
	_apply_editor_theme()
	_refresh_inspector()
	_refresh_stats()
	if fit_view:
		call_deferred("_fit_view")
	_save_editor_session()


func _get_obstacle_preview_info() -> Dictionary:
	var info := {"range": 0.0, "path": PackedVector2Array()}
	if _placement_mode != "obstacle":
		return info
	var preview_scene := ObstacleDefinitionDB.get_scene(_obstacle_prefab_id)
	if preview_scene == null:
		return info
	var probe := preview_scene.instantiate() as Obstacle
	if probe == null:
		return info
	probe._reset_motion(Vector2.ZERO)
	probe.apply_flip(_placement_flip)
	if probe.trigger_enabled:
		var detector := probe.get_node_or_null("PlayerDetector") as Area2D
		if detector != null:
			for child in detector.get_children():
				if child is CollisionShape2D and (child as CollisionShape2D).shape is CircleShape2D:
					info["range"] = ((child as CollisionShape2D).shape as CircleShape2D).radius
	var root_scale := Vector2(absf(probe.scale.x), absf(probe.scale.y))
	# 运动偏移是世界坐标位移，不随场景根节点缩放；只缩放检测范围。
	info["path"] = probe.get_preview_path()
	info["range"] = float(info.get("range", 0.0)) * maxf(root_scale.x, root_scale.y)
	probe.free()
	return info


func _get_selected_obstacle_preview_info() -> Dictionary:
	if _selected_kind != "obstacle" or _selected_index < 0 or _selected_index >= _obstacle_count():
		return {}
	var data: Dictionary = _draft["obstacles"][_selected_index]
	var prefab_id := str(data.get("prefab", data.get("type", "bird")))
	var scene := ObstacleDefinitionDB.get_scene(prefab_id)
	if scene == null:
		return {}
	var probe := scene.instantiate() as Obstacle
	if probe == null:
		return {}
	probe._reset_motion(Vector2.ZERO)
	probe.apply_flip(bool(data.get("flip_x", false)))
	var offset_value: Variant = data.get("offset", Vector2.ZERO)
	var offset := Vector2.ZERO
	if offset_value is Dictionary:
		offset = Vector2(float(offset_value.get("x", 0.0)), float(offset_value.get("y", 0.0)))
	elif offset_value is Vector2:
		offset = offset_value
	var base := _level.track.sample_at(float(data.get("s", 0.0))) + LevelData.CART_ANCHOR_OFFSET + offset
	var trigger_range := 0.0
	if probe.trigger_enabled:
		var detector := probe.get_node_or_null("PlayerDetector") as Area2D
		if detector != null:
			for child in detector.get_children():
				if child is CollisionShape2D and (child as CollisionShape2D).shape is CircleShape2D:
					trigger_range = ((child as CollisionShape2D).shape as CircleShape2D).radius
	var root_scale := Vector2(absf(probe.scale.x), absf(probe.scale.y))
	var info := {"base": base, "path": probe.get_preview_path(), "range": trigger_range * maxf(root_scale.x, root_scale.y), "scale": maxf(root_scale.x, root_scale.y)}
	probe.free()
	return info


func _sync_selected_obstacle_preview() -> void:
	if overlay == null:
		return
	var info := _get_selected_obstacle_preview_info()
	overlay.set_selected_obstacle_path(
		info.get("base", Vector2.ZERO),
		info.get("path", PackedVector2Array()),
		float(info.get("range", 0.0)),
		float(info.get("scale", 1.0))
	)


func _refresh_preview_only() -> void:
	_level = LevelData.from_dictionary(_draft)
	track_view.configure(_level, true, _selected_piece)
	var preview_info := _get_obstacle_preview_info()
	overlay.set_obstacle_preview(_obstacle_prefab_id, float(preview_info.get("range", 0.0)), preview_info.get("path", PackedVector2Array()))
	var overlay_mouse := _mouse_world
	if _grid_enabled and _placement_mode == "obstacle":
		overlay_mouse = _grid_snap(_mouse_world)
	overlay.update_preview(_level, _selected_kind, _selected_index, _placement_mode, overlay_mouse)
	_sync_selected_obstacle_preview()
	_update_track_preview()
	_refresh_obstacle_previews()
	_refresh_stats()


func _sync_ui_from_draft() -> void:
	_syncing_ui = true
	level_title_edit.text = _clip_display_text(str(_draft.get("name", "未命名关卡")), 8.0)
	subtitle_edit.text = _normalize_subtitle(str(_draft.get("subtitle", "")))
	difficulty_spin.value = int(_draft.get("difficulty", 1))
	par_spin.value = float(_draft.get("time_limit_seconds", 0.0))
	_sync_theme_ui()
	_syncing_ui = false


func _camera_bounds_from_draft() -> Rect2:
	var value: Variant = _draft.get("camera_bounds", null)
	if value is Dictionary:
		var dict := value as Dictionary
		return Rect2(
			float(dict.get("x", 0.0)),
			float(dict.get("y", 0.0)),
			float(dict.get("w", dict.get("width", 1280.0))),
			float(dict.get("h", dict.get("height", 720.0)))
		)
	if value is Array and (value as Array).size() >= 4:
		var arr := value as Array
		return Rect2(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
	if _level != null and _level.camera_bounds.size.x > 64.0:
		return _level.camera_bounds
	return Rect2(0, 0, 1280, 720)


func _sync_theme_ui() -> void:
	var current: Dictionary = _draft.get("theme", {})
	var selected := 0
	for index in theme_option.item_count:
		var theme_id := str(theme_option.get_item_metadata(index))
		var preset := LevelData.get_theme_preset(theme_id)
		if str(current.get("sky_top", "")) == str(preset.get("sky_top", "")) \
		and str(current.get("mountain_near", "")) == str(preset.get("mountain_near", "")):
			selected = index
			break
	theme_option.select(selected)
	var background_id := str(_draft.get("background_id", "paradise"))
	var background_index := LevelData.get_background_ids().find(background_id)
	background_option.select(maxi(0, background_index))


func _apply_editor_theme() -> void:
	if backdrop == null:
		return
	backdrop.game_mode = false
	backdrop.apply_theme(_draft.get("theme", LevelData.DEFAULT_THEME), str(_draft.get("background_id", "paradise")))
	AudioDirector.set_background_music(str(_draft.get("background_id", "paradise")))
	backdrop.camera_x = camera.position.x


func _on_background_selected(index: int) -> void:
	if index < 0 or index >= background_option.item_count:
		return
	if _syncing_ui:
		return
	_record_undo()
	_draft["background_id"] = str(background_option.get_item_metadata(index))
	_refresh_preview_only()
	_update_overlay()
	_apply_editor_theme()


func _on_theme_selected(index: int) -> void:
	if index < 0 or index >= theme_option.item_count:
		return
	_record_undo()
	var theme_id := str(theme_option.get_item_metadata(index))
	_draft["theme"] = LevelData.get_theme_preset(theme_id)
	_apply_editor_theme()
	_set_status("关卡背景：%s" % str(LevelData.THEME_PRESETS[theme_id].get("label", theme_id)))


func _on_camera_fit_pressed() -> void:
	_fit_view()
	_set_status("视图已适配到完整相机范围")


func _auto_expand_camera_bounds() -> void:
	if _level == null or _level.track == null or not _level.track.is_valid():
		return
	# 相机范围只由轨道铺设决定，障碍不参与；四周固定留 120px。
	var needed := _level.track.get_bounds(0.0).grow(120.0)
	_level.camera_bounds = needed
	_draft["camera_bounds"] = {
		"x": needed.position.x,
		"y": needed.position.y,
		"w": needed.size.x,
		"h": needed.size.y,
	}


func _refresh_inspector() -> void:
	delete_selection_button.visible = _selected_piece >= 0 or not _selected_kind.is_empty()
	flip_object_button.visible = _selected_kind == "obstacle"
	var has_track := _selected_piece >= 0 and _selected_kind.is_empty()
	track_direction_button.visible = has_track
	if has_track:
		var direction := _selected_run_direction()
		track_direction_button.text = "轨道前进方向：" + ("右" if direction >= 0.0 else "左")


## 当前选中片段所在连续轨道段的方向；孤立轨道各自独立。
func _selected_run_direction() -> float:
	if _level == null or _level.track == null or _selected_piece < 0:
		return 1.0
	var run_index := _level.track.run_index_for_piece(_selected_piece)
	if run_index < 0:
		return 1.0
	return _level.track.get_run_direction(run_index)


func _toggle_track_direction() -> void:
	if _selected_piece < 0 or not _selected_kind.is_empty():
		return
	if _level == null or _level.track == null:
		return
	var run_index := _level.track.run_index_for_piece(_selected_piece)
	if run_index < 0:
		return
	var runs := _level.track.get_track_runs()
	if run_index >= runs.size():
		return
	var run: Dictionary = runs[run_index]
	var first_piece := int(run.get("first_piece", -1))
	var last_piece := int(run.get("last_piece", -1))
	var pieces: Array = _draft["track"]["pieces"]
	if first_piece < 0 or last_piece >= pieces.size():
		return
	var next_direction := -1.0 if _level.track.get_run_direction(run_index) >= 0.0 else 1.0
	_record_undo()
	# 旧关卡没有锚点时，把当前选中的片段作为“第一段放置轨道”。
	var has_anchor := false
	for piece_index in range(first_piece, last_piece + 1):
		if bool((pieces[piece_index] as Dictionary).get("direction_anchor", false)):
			has_anchor = true
			break
	if not has_anchor:
		(pieces[_selected_piece] as Dictionary)["direction_anchor"] = true
	# 只改这一段连续轨道；其它孤立轨道保持自己的方向。
	for piece_index in range(first_piece, last_piece + 1):
		var piece: Dictionary = pieces[piece_index]
		piece["direction"] = next_direction
	_draft["track"].erase("direction")
	_refresh_editor(false)
	_set_status("本段轨道前进方向：" + ("右" if next_direction >= 0.0 else "左"))


func _on_obstacle_prefab_selected(index: int) -> void:
	if index < 0 or index >= obstacle_prefab_option.item_count:
		return
	_obstacle_prefab_id = str(obstacle_prefab_option.get_item_metadata(index))


func _refresh_stats() -> void:
	if level_stats_label == null:
		return
	var track_length := _level.track.total_length if _level != null and _level.track != null else 0.0
	var errors := ""
	if _level != null and not _level.is_valid():
		errors = "\n校验：%s" % "；".join(_level.validation_errors)
	level_stats_label.text = "轨道 %.0f px　·　%d 片段　·　%d 障碍　·　%s" % [
		track_length,
		_piece_count(),
		_obstacle_count(),
		errors,
	]


func _set_row_visible(row: Control, row_visible: bool) -> void:
	row.visible = row_visible


func _select_option_metadata(option: OptionButton, value: String) -> void:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return


func _piece_from_kind(kind: String, length_value: float = DEFAULT_STRAIGHT_LENGTH, flip: bool = false, heading: float = 0.0, break_after: float = 0.0) -> Dictionary:
	var piece: Dictionary
	match kind:
		"straight":
			piece = {"type": "straight", "length": length_value}
		"curve15", "curve30", "curve45", "curve60":
			var curve_angle := -15.0 if kind == "curve15" else (-30.0 if kind == "curve30" else (-45.0 if kind == "curve45" else -60.0))
			if flip:
				curve_angle = -curve_angle
			var curve_radius := length_value / maxf(0.001, absf(deg_to_rad(curve_angle)))
			piece = {"type": "arc", "radius": curve_radius, "angle": curve_angle}
		"loop", "arc_left", "arc_right":
			var loop_angle := -360.0 if kind == "loop" else (-45.0 if kind == "arc_left" else 45.0)
			if flip:
				loop_angle = -loop_angle
			var loop_radius := length_value / maxf(0.001, absf(deg_to_rad(loop_angle)))
			piece = {"type": "loop" if kind == "loop" else "arc", "radius": loop_radius, "angle": loop_angle}
		_:
			return {}
	if heading != 0.0:
		piece["heading_deg"] = heading
	if break_after > 0.0:
		piece["break_after"] = break_after
	return piece


func _start_track_placement(kind: String) -> void:
	if not _track_kind.is_empty():
		_placement_lengths[_track_kind] = place_length_spin.value
		_placement_breaks[_track_kind] = break_mode_check.button_pressed
	_track_kind = kind
	_placement_mode = "track:" + kind
	_selected_kind = ""
	_selected_index = -1
	place_length_spin.set_value_no_signal(float(_placement_lengths.get(kind, DEFAULT_STRAIGHT_LENGTH)))
	break_mode_check.set_pressed_no_signal(bool(_placement_breaks.get(kind, false)))
	_update_overlay()
	_set_status("已选择%s：点击世界放置；靠近任意轨道端点会吸附，否则生成分段轨道" % _piece_type_label(_piece_from_kind(kind)))


func _on_place_length_changed(value: float) -> void:
	if not _track_kind.is_empty():
		_placement_lengths[_track_kind] = value
	if _placement_mode.begins_with("track:"):
		_update_overlay()


func _on_place_break_toggled(enabled: bool) -> void:
	break_mode_check.text = "定时断开：" + ("开" if enabled else "关")
	if not _track_kind.is_empty():
		_placement_breaks[_track_kind] = enabled
	if _placement_mode.begins_with("track:"):
		_update_overlay()


func _toggle_flip() -> void:
	_placement_flip = not _placement_flip
	_update_overlay()
	_set_status("左右翻转：%s" % ("开" if _placement_flip else "关"))


func _rotate_placement(degrees: float) -> void:
	_placement_rotation = wrapf(_placement_rotation + degrees, -180.0, 180.0)
	_update_overlay()
	_set_status("旋转角度：%.0f°" % _placement_rotation)


func _on_grid_toggled(enabled: bool) -> void:
	_grid_enabled = enabled
	grid_toggle.text = "网格显示：" + ("开" if enabled else "关")
	if overlay != null:
		overlay.set_grid_visible(enabled)
	_set_status("网格显示：" + ("开" if enabled else "关"))


func _grid_snap(world: Vector2) -> Vector2:
	if not _grid_enabled:
		return world
	return Vector2(roundf(world.x / GRID_SIZE) * GRID_SIZE, roundf(world.y / GRID_SIZE) * GRID_SIZE)


func _placement_piece(world_position: Vector2) -> Dictionary:
	var length_value := place_length_spin.value if place_length_spin != null else DEFAULT_STRAIGHT_LENGTH
	var break_after := place_break_spin.value if break_mode_check.button_pressed else 0.0
	var piece := _piece_from_kind(_track_kind, length_value, _placement_flip, 0.0, break_after)
	if piece.is_empty():
		return {}
	var snap := _nearest_snap(world_position)
	_placement_snap = snap
	var origin := _grid_snap(world_position) if snap.is_empty() else world_position
	var heading := deg_to_rad(_placement_rotation)
	if not snap.is_empty():
		origin = snap.get("point", world_position)
		# 吸附时强制与目标端点的切线对齐，不再叠加自由旋转角度。
		# 否则旋转过的片段会在接缝处形成硬折角。
		heading = float(snap.get("angle", 0.0))
	piece["origin"] = [origin.x, origin.y]
	piece["heading_deg"] = rad_to_deg(heading)
	if not snap.is_empty() and not bool(snap.get("end", true)):
		_orient_piece_to_end_at_start(piece, origin, float(snap.get("angle", 0.0)) - PI)
	# 只做单端吸附；不要自动改变片段长度/半径去凑第二个端点，
	# 否则用户看到的是“吸上去了但形状突然变了”的错误接口。
	if not snap.is_empty():
		_align_snap_tangent(piece, snap)
	return piece


## 吸附到 run 起点时，新片段必须“末端接在起点上”，而不是从起点向外接。
func _align_snap_tangent(piece: Dictionary, snap: Dictionary) -> void:
	var probe := TrackGeometry.from_track_data({
		"start_angle_deg": 0.0,
		"pieces": [piece],
		"start_s": 0.0,
		"finish_s": 1.0,
	})
	if probe.points.size() < 2 or probe.total_length <= 0.0:
		return
	if bool(snap.get("end", true)):
		var desired := float(snap.get("angle", 0.0))
		var actual := probe.piece_start_headings[0] if not probe.piece_start_headings.is_empty() else probe.tangent_at(0.0).angle()
		var delta := wrapf(desired - actual, -PI, PI)
		if absf(delta) > 0.0001:
			piece["heading_deg"] = float(piece.get("heading_deg", 0.0)) + rad_to_deg(delta)
	else:
		var desired := float(snap.get("angle", 0.0)) - PI
		var actual := probe.piece_end_headings[0] if not probe.piece_end_headings.is_empty() else probe.tangent_at(probe.total_length).angle()
		var delta := wrapf(desired - actual, -PI, PI)
		if absf(delta) > 0.0001:
			var origin_value: Variant = piece.get("origin", [0.0, 0.0])
			var origin: Vector2 = Vector2(float(origin_value[0]), float(origin_value[1])) if origin_value is Array else origin_value
			var end_point: Vector2 = probe.points[probe.points.size() - 1]
			var rotated_origin := end_point + (origin - end_point).rotated(delta)
			piece["origin"] = [rotated_origin.x, rotated_origin.y]
			piece["heading_deg"] = float(piece.get("heading_deg", 0.0)) + rad_to_deg(delta)


func _orient_piece_to_end_at_start(piece: Dictionary, start_point: Vector2, forward_heading: float) -> void:
	var original_angle := deg_to_rad(float(piece.get("angle", 0.0)))
	# 接在既有轨道“起点”时，沿行进方向反向观察会把上弯看成下弯。
	# 对片段做左右镜像，保证玩家看到的弯曲方向与放置前一致。
	var angle := -original_angle
	var start_heading := forward_heading - angle
	var probe_piece := piece.duplicate(true)
	probe_piece["origin"] = [0.0, 0.0]
	probe_piece["heading_deg"] = rad_to_deg(start_heading)
	probe_piece["angle"] = rad_to_deg(angle)
	var probe := TrackGeometry.from_track_data({
		"start_angle_deg": 0.0,
		"pieces": [probe_piece],
		"start_s": 0.0,
		"finish_s": 1.0,
	})
	if probe.points.size() < 2:
		return
	var end_local := probe.points[probe.points.size() - 1]
	var origin := start_point - end_local
	piece["origin"] = [origin.x, origin.y]
	piece["heading_deg"] = rad_to_deg(start_heading)
	piece["angle"] = rad_to_deg(angle)


## 只有连续轨道段（run）的两个端点可以吸附；内部片段接缝不可连接。
func _nearest_snap(world_position: Vector2) -> Dictionary:
	if _level == null or _level.track == null or not _level.track.is_valid():
		return {}
	var best: Dictionary = {}
	var best_distance := 120.0
	for candidate in _level.track.get_run_endpoints():
		var distance := world_position.distance_to(candidate.get("point", Vector2.ZERO))
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


func _place_track_piece(world_position: Vector2) -> void:
	var piece := _placement_piece(world_position)
	if piece.is_empty():
		return
	var object_snapshot := _snapshot_object_world_positions()
	var pieces: Array = _draft["track"]["pieces"]
	if not _placement_snap.is_empty():
		var snap_piece := int(_placement_snap.get("piece", 0))
		# 吸附到一段轨道时，新片段继承该段的前进方向。
		if snap_piece >= 0 and snap_piece < pieces.size():
			var snap_run := _level.track.run_index_for_piece(snap_piece)
			var target_direction := _level.track.get_run_direction(snap_run) if snap_run >= 0 else 1.0
			piece["direction"] = target_direction
			# 旧关卡没有锚点时补一个；新片段永远不抢“第一段放置轨道”的锚点。
			if snap_run >= 0 and _level.track.get_run_anchor_piece(snap_run) == snap_piece:
				var target_piece: Dictionary = pieces[snap_piece]
				if not bool(target_piece.get("direction_anchor", false)):
					target_piece["direction_anchor"] = true
		if bool(_placement_snap.get("end", true)):
			pieces.insert(snap_piece + 1, piece)
			_selected_piece = snap_piece + 1
		else:
			pieces.insert(maxi(0, snap_piece), piece)
			_selected_piece = maxi(0, snap_piece)
	else:
		piece["direction"] = 1.0
		piece["direction_anchor"] = true
		pieces.append(piece)
		_selected_piece = pieces.size() - 1
	_selected_kind = ""
	_selected_index = -1
	_refresh_editor(false)
	_restore_object_world_positions(object_snapshot)
	_refresh_preview_only()
	_set_status("已放置%s；可继续点击，或按 Esc 取消放置" % _piece_type_label(piece))


func _add_piece(kind: String) -> void:
	var piece := _piece_from_kind(kind)
	if piece.is_empty():
		return
	var pieces: Array = _draft["track"]["pieces"]
	pieces.append(piece)
	_selected_piece = pieces.size() - 1
	_selected_kind = ""
	_selected_index = -1
	_placement_mode = ""
	_refresh_editor(false)
	_set_status("已添加%s" % _piece_type_label(piece))


func _select_piece(index: int) -> void:
	_selected_piece = index
	_selected_kind = ""
	_selected_index = -1
	_refresh_preview_only()
	_refresh_inspector()
	_update_overlay()


func _snapshot_object_world_positions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _level == null or _level.track == null:
		return result
	var start_world := _level.track.sample_at(float(_draft.get("track", {}).get("start_s", 0.0)))
	var finish_world := _level.track.sample_at(float(_draft.get("track", {}).get("finish_s", 0.0)))
	result.append({"kind": "start", "world": start_world})
	result.append({"kind": "finish", "world": finish_world})
	for obstacle in _draft.get("obstacles", []):
		var offset: Variant = obstacle.get("offset", Vector2.ZERO)
		var vec := Vector2.ZERO
		if offset is Dictionary:
			vec = Vector2(float(offset.get("x", 0.0)), float(offset.get("y", 0.0)))
		elif offset is Vector2:
			vec = offset
		result.append({"kind": "obstacle", "world": _level.track.sample_at(float(obstacle.get("s", 0.0))) + LevelData.CART_ANCHOR_OFFSET + vec})
	return result


func _restore_object_world_positions(snapshot: Array[Dictionary]) -> void:
	if _level == null or _level.track == null:
		return
	var obstacle_index := 0
	for item in snapshot:
		var world: Vector2 = item.get("world", Vector2.ZERO)
		var s := _level.track.nearest_s(world)
		if str(item.get("kind", "")) == "start":
			_draft["track"]["start_s"] = s
			continue
		if str(item.get("kind", "")) == "finish":
			_draft["track"]["finish_s"] = s
			continue
		var offset := world - (_level.track.sample_at(s) + LevelData.CART_ANCHOR_OFFSET)
		if str(item.get("kind", "")) == "obstacle" and obstacle_index < _draft["obstacles"].size():
			_draft["obstacles"][obstacle_index]["s"] = s
			_draft["obstacles"][obstacle_index]["offset"] = {"x": offset.x, "y": offset.y}
			obstacle_index += 1


func _delete_piece() -> void:
	if _selected_piece < 0 or _piece_count() <= 1:
		_set_status("至少保留一个轨道片段")
		return
	var pieces: Array = _draft["track"]["pieces"]
	if _selected_piece >= pieces.size():
		_selected_piece = pieces.size() - 1
	if _selected_piece < 0 or _selected_piece >= pieces.size():
		_set_status("选中片段已失效")
		return
	# 删除锚点片段时，把锚点交给同段另一个片段，保持“第一段放置轨道”语义。
	if bool((pieces[_selected_piece] as Dictionary).get("direction_anchor", false)):
		var run_index := _level.track.run_index_for_piece(_selected_piece)
		if run_index >= 0:
			var run: Dictionary = _level.track.get_track_runs()[run_index]
			var first_piece := int(run.get("first_piece", -1))
			var last_piece := int(run.get("last_piece", -1))
			var next_anchor := first_piece if first_piece != _selected_piece else first_piece + 1
			if next_anchor >= 0 and next_anchor <= last_piece and next_anchor < pieces.size():
				(pieces[next_anchor] as Dictionary)["direction_anchor"] = true
	_record_undo()
	var object_snapshot := _snapshot_object_world_positions()
	pieces.remove_at(_selected_piece)
	_selected_piece = clampi(_selected_piece, 0, pieces.size() - 1)
	_refresh_editor(false)
	_restore_object_world_positions(object_snapshot)
	_refresh_preview_only()
	_set_status("已删除片段")


func _flip_selected_object() -> void:
	if _selected_kind == "obstacle" and _selected_index < _obstacle_count():
		_record_undo()
		_draft["obstacles"][_selected_index]["flip_x"] = not bool(_draft["obstacles"][_selected_index].get("flip_x", false))
	else:
		_set_status("请选择障碍或乘客后再翻转")
		return
	_refresh_editor(false)
	_set_status("对象已翻转")


func _delete_selection() -> void:
	if _selected_piece >= 0 and _selected_kind.is_empty():
		_delete_piece()
		return
	var removed_kind := _selected_kind
	if _selected_kind == "obstacle" and _selected_index < _obstacle_count():
		_record_undo()
		_draft["obstacles"].remove_at(_selected_index)
	elif _selected_kind == "start":
		_record_undo()
		_draft["track"]["start_s"] = 0.0
	elif _selected_kind == "finish":
		_record_undo()
		_draft["track"]["finish_s"] = 0.0
	else:
		return
	# 删除障碍/乘客后继续选中该类型最近一次放置的对象；场上没有该类型时才回到轨道。
	var next_kind := ""
	var next_index := -1
	if removed_kind == "obstacle" and _obstacle_count() > 0:
		next_kind = "obstacle"
		next_index = _obstacle_count() - 1
	if next_kind.is_empty():
		_selected_piece = 0 if _piece_count() > 0 else -1
		_selected_kind = ""
		_selected_index = -1
	else:
		_selected_piece = -1
		_selected_kind = next_kind
		_selected_index = next_index
	_refresh_editor(false)
	_set_status("已删除选中对象")


func _set_placement(mode: String) -> void:
	_placement_mode = "" if _placement_mode == mode else mode
	_update_overlay()
	if _placement_mode.is_empty():
		_set_status("已取消放置模式")
	else:
		_set_status("放置模式：%s，请在轨道附近点击" % _placement_mode)


func _cancel_placement() -> void:
	_placement_mode = ""
	_update_overlay()
	_set_status("已取消放置模式")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_points[event.index] = event.position
			if _touch_points.size() >= 2:
				# 第二指出现即视为双指缩放/平移，取消本次放置。
				_touch_place_pending = false
				_dragging = false
			elif not _placement_mode.is_empty():
				_touch_place_pending = true
				_touch_place_world = _screen_to_world(event.position)
				_mouse_world = _touch_place_world
				_update_overlay()
		else:
			_touch_points.erase(event.index)
			if _touch_place_pending:
				if _touch_points.is_empty():
					var world := _touch_place_world
					_touch_place_pending = false
					_place_at(world)
				else:
					_touch_place_pending = false
		_reset_touch_gesture()
		return
	if event is InputEventScreenDrag:
		_touch_points[event.index] = event.position
		if _touch_place_pending:
			if _touch_points.size() >= 2:
				_touch_place_pending = false
			else:
				# 单指拖动只移动预览，不立即放置，也不平移画布。
				_touch_place_world = _screen_to_world(event.position)
				_mouse_world = _touch_place_world
				_update_overlay()
				return
		_update_touch_gesture()
		return
	if event is InputEventMagnifyGesture:
		_zoom_camera_at(event.factor, event.position)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventPanGesture:
		camera.position -= event.delta / maxf(0.05, camera.zoom.x)
		_update_overlay()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		_mouse_world = get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_camera_at(1.12, event.position)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_camera_at(0.89, event.position)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_handle_left_press(_mouse_world)
			else:
				_dragging = false
			return
	elif event is InputEventMouseMotion:
		_mouse_world = get_global_mouse_position()
		if _panning and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			camera.position -= event.relative / maxf(0.05, camera.zoom.x)
			_update_overlay()
		elif _dragging and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_update_dragged_marker(_mouse_world)
		else:
			_update_overlay()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if _unsaved_overlay != null and is_instance_valid(_unsaved_overlay) and _unsaved_overlay.visible:
				_dismiss_unsaved_dialog()
			elif _delete_overlay != null and is_instance_valid(_delete_overlay) and _delete_overlay.visible:
				_dismiss_delete_dialog()
			elif not _placement_mode.is_empty():
				_cancel_placement()
			else:
				_on_back_pressed()
			get_viewport().set_input_as_handled()


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_position


func _handle_left_press(world_position: Vector2) -> void:
	if _level == null or _level.track == null or not _level.track.is_valid():
		return
	if not _placement_mode.is_empty():
		# 触屏放置延迟 0.16 秒；若期间出现第二指（缩放）就取消，避免双指误放。
		if OS.has_feature("mobile") or PlatformConfig.is_wechat or not _touch_points.is_empty():
			if _touch_points.size() >= 2 or _touch_place_pending:
				return
			_touch_place_world = world_position
			_mouse_world = world_position
			_touch_place_pending = true
			_update_overlay()
			return
		_place_at(world_position)
		return
	var hit := _find_marker_at(world_position)
	if hit.is_empty():
		var piece_index := _find_piece_at(world_position)
		if piece_index >= 0:
			_dragging = false
			_select_piece(piece_index)
			return
		_selected_kind = ""
		_selected_index = -1
		_dragging = false
		_refresh_inspector()
		_update_overlay()
		return
	_selected_kind = str(hit.get("kind", ""))
	_selected_index = int(hit.get("index", -1))
	_dragging = not (motion_preview_check.button_pressed and _selected_kind == "obstacle")
	_refresh_inspector()
	_update_overlay()


func _find_piece_at(world_position: Vector2) -> int:
	if _level == null or _level.track == null or not _level.track.is_valid():
		return -1
	var s := _level.track.nearest_rail_s(world_position)
	var threshold := 28.0 / maxf(0.2, camera.zoom.x)
	if world_position.distance_to(_level.track.sample_at(s)) > threshold:
		return -1
	return _level.track.piece_index_at_s(s)


func _place_at(world_position: Vector2) -> void:
	_record_undo()
	var placement_world := world_position if _placement_mode.begins_with("track:") else _grid_snap(world_position)
	world_position = placement_world
	if _placement_mode.begins_with("track:"):
		_place_track_piece(world_position)
		return
	var s := _level.track.nearest_s(world_position)
	var track_point := _level.track.sample_at(s)
	var offset := world_position - (track_point + LevelData.CART_ANCHOR_OFFSET)
	match _placement_mode:
		"obstacle":
			var obstacle_data := {
				"prefab": _obstacle_prefab_id,
				"s": s,
				"offset": {"x": offset.x, "y": offset.y},
				"flip_x": _placement_flip,
			}
			_draft["obstacles"].append(obstacle_data)
			_selected_kind = ""
			_selected_index = -1
			_selected_piece = -1
			_set_status("已放置障碍物；可继续点击，或按 Esc 结束")
			_refresh_editor(false)
			return
		"start":
			_draft["track"]["start_s"] = s
			_selected_kind = "start"
			_selected_index = -1
			_selected_piece = -1
			_set_status("起点已移动到 %.0f px" % s)
		"finish":
			_draft["track"]["finish_s"] = s
			_selected_kind = "finish"
			_selected_index = -1
			_selected_piece = -1
			_set_status("终点已移动到 %.0f px" % s)
	_placement_mode = ""
	_refresh_editor(false)


func _update_dragged_marker(world_position: Vector2) -> void:
	if _level == null or _level.track == null:
		return
	if motion_preview_check.button_pressed and _selected_kind == "obstacle":
		return
	# 网格开启时，拖动已选中的障碍 / 起点 / 终点都先吸附到网格顶点。
	# 起终点最终仍投影到轨道弧长上，所以只会沿轨道跳到最近的吸附位置。
	if _selected_kind == "obstacle" or _selected_kind == "start" or _selected_kind == "finish":
		world_position = _grid_snap(world_position)
	var s := _level.track.nearest_s(world_position)
	if _selected_kind == "start":
		_draft["track"]["start_s"] = s
	elif _selected_kind == "finish":
		_draft["track"]["finish_s"] = s
	elif _selected_kind == "obstacle" and _selected_index < _obstacle_count():
		var obstacle: Dictionary = _draft["obstacles"][_selected_index]
		var track_point := _level.track.sample_at(s)
		var offset := world_position - (track_point + LevelData.CART_ANCHOR_OFFSET)
		obstacle["s"] = s
		obstacle["offset"] = {"x": offset.x, "y": offset.y}
		_draft["obstacles"][_selected_index] = obstacle
	_refresh_preview_only()
	_update_overlay()


func _obstacle_scene_scale(prefab_id: String) -> float:
	if _obstacle_scale_cache.has(prefab_id):
		return float(_obstacle_scale_cache[prefab_id])
	var value := 1.0
	var scene := ObstacleDefinitionDB.get_scene(prefab_id)
	if scene != null:
		var probe := scene.instantiate() as Obstacle
		if probe != null:
			value = maxf(absf(probe.scale.x), absf(probe.scale.y))
			probe.free()
	_obstacle_scale_cache[prefab_id] = value
	return value


func _find_marker_at(world_position: Vector2) -> Dictionary:
	if _level == null or _level.track == null:
		return {}
	var threshold := 26.0 / maxf(0.2, camera.zoom.x)
	var candidates: Array[Dictionary] = [
		{"kind": "start", "index": -1, "point": _level.track.sample_at(float(_draft["track"].get("start_s", 0.0)))},
		{"kind": "finish", "index": -1, "point": _level.track.sample_at(float(_draft["track"].get("finish_s", 0.0)))},
	]
	for index in _obstacle_count():
		var obstacle: Dictionary = _draft["obstacles"][index]
		var offset: Dictionary = obstacle.get("offset", {})
		var point := _level.track.sample_at(float(obstacle.get("s", 0.0))) + LevelData.CART_ANCHOR_OFFSET + Vector2(float(offset.get("x", 0.0)), float(offset.get("y", 0.0)))
		var scene_scale := _obstacle_scene_scale(str(obstacle.get("prefab", "bird")))
		candidates.append({"kind": "obstacle", "index": index, "point": point, "scale": scene_scale})
	var best: Dictionary = {}
	var best_distance := threshold
	for candidate in candidates:
		var hit_scale := maxf(0.1, float(candidate.get("scale", 1.0)))
		var distance: float = world_position.distance_to(candidate.get("point", Vector2.ZERO)) / hit_scale
		if distance <= best_distance:
			best = candidate
			best_distance = distance
	return best


func _zoom_camera(factor: float) -> void:
	_zoom_camera_at(factor, get_viewport_rect().size * 0.5)


func _zoom_camera_at(factor: float, screen_position: Vector2) -> void:
	var before := get_viewport().get_canvas_transform().affine_inverse() * screen_position
	var new_zoom := clampf(camera.zoom.x * factor, 0.15, 2.5)
	camera.zoom = Vector2(new_zoom, new_zoom)
	var after := get_viewport().get_canvas_transform().affine_inverse() * screen_position
	camera.position += before - after
	_update_overlay()


func _reset_touch_gesture() -> void:
	_touch_last_distance = 0.0
	_touch_last_mid = Vector2.ZERO


func _update_touch_gesture() -> void:
	if _touch_points.size() == 1:
		var point: Vector2 = _touch_points.values()[0]
		# 正在拖拽已选对象时，单指只移动对象，不再平移画布。
		if _dragging:
			_touch_last_mid = point
			_touch_last_distance = 0.0
			return
		if _touch_last_mid != Vector2.ZERO:
			camera.position -= (point - _touch_last_mid) / maxf(0.05, camera.zoom.x)
			_update_overlay()
		_touch_last_mid = point
		_touch_last_distance = 0.0
	elif _touch_points.size() >= 2:
		_dragging = false
		_touch_place_pending = false
		var points: Array = _touch_points.values()
		var a: Vector2 = points[0]
		var b: Vector2 = points[1]
		var mid := (a + b) * 0.5
		var distance := a.distance_to(b)
		if _touch_last_distance > 1.0:
			_zoom_camera_at(distance / _touch_last_distance, mid)
		if _touch_last_mid != Vector2.ZERO:
			camera.position -= (mid - _touch_last_mid) / maxf(0.05, camera.zoom.x)
			_update_overlay()
		_touch_last_distance = distance
		_touch_last_mid = mid


func _fit_view() -> void:
	var bounds := _camera_bounds_from_draft()
	if bounds.size.x < 64.0 or bounds.size.y < 64.0:
		if _level == null or _level.track == null:
			return
		bounds = _level.track.get_bounds(220.0)
	var viewport_size := get_viewport_rect().size
	var zoom_x := viewport_size.x * 0.82 / maxf(1.0, bounds.size.x)
	var zoom_y := viewport_size.y * 0.82 / maxf(1.0, bounds.size.y)
	var new_zoom := clampf(minf(zoom_x, zoom_y), 0.15, 1.5)
	camera.position = bounds.position + bounds.size * 0.5
	camera.zoom = Vector2(new_zoom, new_zoom)
	_update_overlay()


func _update_overlay() -> void:
	if overlay == null:
		return
	if _level == null:
		_level = LevelData.from_dictionary(_draft)
	var preview_info := _get_obstacle_preview_info()
	overlay.set_obstacle_preview(_obstacle_prefab_id, float(preview_info.get("range", 0.0)), preview_info.get("path", PackedVector2Array()))
	var overlay_mouse := _mouse_world
	if _grid_enabled and _placement_mode == "obstacle":
		overlay_mouse = _grid_snap(_mouse_world)
	overlay.update_preview(_level, _selected_kind, _selected_index, _placement_mode, overlay_mouse)
	_sync_selected_obstacle_preview()
	_update_track_preview()
	_update_obstacle_ghost()
	if backdrop != null:
		backdrop.camera_x = camera.position.x


func _update_track_preview() -> void:
	if overlay == null:
		return
	if not _placement_mode.begins_with("track:") or _level == null or _level.track == null:
		overlay.set_track_preview(PackedVector2Array(), false, Vector2.ZERO)
		return
	var piece := _placement_piece(_mouse_world)
	if piece.is_empty():
		overlay.set_track_preview(PackedVector2Array(), false, Vector2.ZERO)
		return
	var snap := _nearest_snap(_mouse_world)
	var will_snap := not snap.is_empty()
	var snap_point: Vector2 = snap.get("point", _mouse_world) if will_snap else _mouse_world
	var preview_track := TrackGeometry.from_track_data({"start_angle_deg": 0.0, "pieces": [piece], "start_s": 0.0, "finish_s": 1.0})
	overlay.set_track_preview(preview_track.points, will_snap, snap_point)


func _display_units(text: String) -> float:
	var units := 0.0
	for index in text.length():
		var code := text.unicode_at(index)
		units += 1.0 if code > 127 else 0.5
	return units


func _clip_display_text(text: String, max_units: float) -> String:
	var result := ""
	var units := 0.0
	for index in text.length():
		var code := text.unicode_at(index)
		var cost := 1.0 if code > 127 else 0.5
		if units + cost > max_units:
			break
		result += text[index]
		units += cost
	return result


func _on_name_changed(new_name: String) -> void:
	if _syncing_ui:
		return
	var limited := _clip_display_text(new_name, 8.0)
	if limited != new_name:
		_syncing_ui = true
		level_title_edit.text = limited
		level_title_edit.caret_column = limited.length()
		_syncing_ui = false
	_record_undo()
	_draft["name"] = limited


func _normalize_subtitle(raw: String) -> String:
	# 严格 24 个字符、最多 3 行；输入过程中立即截断，不能等保存。
	var limited: String = raw.substr(0, 24)
	var lines: PackedStringArray = limited.split("\n", true)
	if lines.size() > 3:
		limited = "\n".join(lines.slice(0, 3))
	return limited


func _on_subtitle_changed() -> void:
	if _syncing_ui:
		return
	var raw := subtitle_edit.text
	var limited := _normalize_subtitle(raw)
	if limited != raw:
		_syncing_ui = true
		subtitle_edit.text = limited
		subtitle_edit.set_caret_line(subtitle_edit.get_line_count() - 1)
		subtitle_edit.set_caret_column(subtitle_edit.get_line(subtitle_edit.get_line_count() - 1).length())
		_syncing_ui = false
	_record_undo()
	_draft["subtitle"] = limited


func _on_level_field_changed(_value: float) -> void:
	if _syncing_ui:
		return
	_record_undo()
	_draft["difficulty"] = int(difficulty_spin.value)
	_draft["time_limit_seconds"] = maxf(0.0, par_spin.value)
	_draft["background_id"] = str(background_option.get_item_metadata(background_option.selected)) if background_option.selected >= 0 else "paradise"
	_level = LevelData.from_dictionary(_draft)
	_refresh_stats()


func _on_save_pressed() -> void:
	_sync_draft_fields()
	var result: Dictionary
	if _developer_mode:
		result = DeveloperService.save_level(_draft)
	else:
		result = LevelCatalog.save_user_level(_draft)
	if not bool(result.get("ok", false)):
		_set_status("保存失败：%s" % result.get("error", ""))
		return
	_draft["id"] = result.get("id", _draft.get("id", ""))
	if not _developer_mode:
		_draft["name"] = level_title_edit.text.strip_edges() if not level_title_edit.text.strip_edges().is_empty() else str(result.get("summary", {}).get("name", "我的环线"))
	_refresh_template_picker()
	_update_delete_level_button()
	_dirty = false
	if not _developer_mode:
		SaveManager.set_setting("editor_last_level_id", str(_draft.get("id", "")))
	_set_status(("已更新主线 %s" if _developer_mode else "已保存到 user://levels/%s.json") % _draft["id"])
	_refresh_editor(false)


func _on_test_pressed() -> void:
	_sync_draft_fields()
	_save_editor_session()
	var result: Dictionary
	if _developer_mode:
		result = DeveloperService.save_level(_draft)
	else:
		result = LevelCatalog.save_user_level(_draft)
	if not bool(result.get("ok", false)):
		_set_status("试玩前保存失败：%s" % result.get("error", ""))
		return
	var level_id := str(result.get("id", ""))
	_draft["id"] = level_id
	GameSession.test_from_editor = true
	GameSession.editor_return_level_id = level_id
	GameSession.start_level(level_id, GameSession.MODE_SOLO, true)


func _on_load_template_pressed() -> void:
	if template_picker.selected < 0:
		return
	var level_id := str(template_picker.get_item_metadata(template_picker.selected))
	if level_id.is_empty():
		_set_status("还没有可载入的关卡")
		return
	_load_template(level_id, true)


func _on_new_pressed() -> void:
	_create_default_draft()
	_refresh_template_picker()
	_update_delete_level_button()


func _on_delete_level_pressed() -> void:
	var level_id := str(_draft.get("id", ""))
	if not level_id.begins_with("custom_"):
		_set_status("内置关卡不能删除")
		return
	if _delete_overlay != null and is_instance_valid(_delete_overlay):
		_delete_overlay.queue_free()
	_delete_overlay = Control.new()
	_delete_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_delete_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	# 必须挂在带主题的 Control 下；CanvasLayer 不会继承 PaperPanel 主题，
	# 否则会退化成原生灰色窗口。
	var ui_root := get_node_or_null("UILayer/Root") as Control
	if ui_root != null:
		ui_root.add_child(_delete_overlay)
	else:
		add_child(_delete_overlay)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.08, 0.12, 0.62)
	_delete_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_delete_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"PaperPanel"
	panel.custom_minimum_size = Vector2(470, 230)
	center.add_child(panel)
	_delete_panel = panel
	UIJuice.popup_in(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.theme_type_variation = &"HeadingLabel"
	title.text = "删除自制关卡"
	box.add_child(title)
	var hint := Label.new()
	hint.theme_type_variation = &"MutedLabel"
	hint.text = "确定删除「%s」吗？此操作不可撤销。" % str(_draft.get("name", "未命名"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var cancel := Button.new()
	cancel.theme_type_variation = &"GhostButton"
	cancel.text = "取消"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_dismiss_delete_dialog)
	buttons.add_child(cancel)
	var confirm := Button.new()
	confirm.theme_type_variation = &"PrimaryButton"
	confirm.text = "删除"
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(_delete_level_confirmed.bind(level_id))
	buttons.add_child(confirm)


func _delete_level_confirmed(level_id: String) -> void:
	var result := LevelCatalog.delete_user_level(level_id)
	if not bool(result.get("ok", false)):
		_set_status("删除失败：%s" % result.get("error", ""))
	else:
		var remaining := LevelCatalog.get_user_summaries()
		if remaining.is_empty():
			_create_default_draft()
		else:
			_load_template(str(remaining[0].get("id", "")), true)
		_refresh_template_picker()
		_update_delete_level_button()
		_set_status("自制关卡已删除，已切换到下一张自制关卡")
	if _delete_panel != null:
		UIJuice.popup_out(_delete_panel, func() -> void: _delete_overlay.hide())


func _sync_draft_fields() -> void:
	_draft["name"] = _clip_display_text(level_title_edit.text.strip_edges(), 8.0)
	_draft["subtitle"] = _normalize_subtitle(subtitle_edit.text.strip_edges())
	_draft["difficulty"] = int(difficulty_spin.value)
	_draft["time_limit_seconds"] = maxf(0.0, par_spin.value)
	_draft["background_id"] = str(background_option.get_item_metadata(background_option.selected)) if background_option.selected >= 0 else "paradise"
	if str(_draft.get("name", "")).is_empty():
		_draft["name"] = LevelCatalog.next_unique_user_name("我的环线")


func _update_delete_level_button() -> void:
	delete_level_button.visible = not _developer_mode and str(_draft.get("id", "")).begins_with("custom_")


func _on_back_pressed() -> void:
	if _dirty:
		_show_unsaved_dialog()
		return
	GameSession.developer_mode = false
	SceneRouter.goto_menu()


func _set_status(message: String) -> void:
	status_label.text = message


func _piece_count() -> int:
	return (_draft.get("track", {}).get("pieces", []) as Array).size()


func _obstacle_count() -> int:
	return (_draft.get("obstacles", []) as Array).size()


func _piece_type_label(piece: Dictionary) -> String:
	match str(piece.get("type", "straight")):
		"straight":
			return "直线"
		"loop":
			return "圆环"
		_:
			var angle := absf(float(piece.get("angle", 45.0)))
			return "%.0f°曲线" % angle


# ---------- 自动化测试接口 ----------

func debug_get_draft() -> Dictionary:
	return _draft.duplicate(true)


func debug_add_piece(kind: String) -> void:
	_add_piece(kind)


func debug_place_track_at(kind: String, world_position: Vector2) -> void:
	_start_track_placement(kind)
	_place_at(world_position)


func debug_place_obstacle_at(world_position: Vector2) -> void:
	_placement_mode = "obstacle"
	_place_at(world_position)


func debug_set_start_at(world_position: Vector2) -> void:
	_placement_mode = "start"
	_place_at(world_position)


func debug_set_finish_at(world_position: Vector2) -> void:
	_placement_mode = "finish"
	_place_at(world_position)


func debug_save() -> Dictionary:
	_sync_draft_fields()
	return LevelCatalog.save_user_level(_draft)


func debug_get_track_length() -> float:
	return _level.track.total_length if _level != null and _level.track != null else 0.0

class_name LevelCard
extends Button
## 选关卡片。接收 LevelCatalog / SaveManager 已经整理好的展示数据，不读文件。

signal chosen(level_id: String)

@onready var accent_bar: ColorRect = $AccentBar
@onready var preview: LevelPreview = $Preview
@onready var number_label: Label = $Margin/VBox/NumberRow/NumberLabel
@onready var difficulty_label: Label = $Margin/VBox/NumberRow/DifficultyLabel
@onready var name_label: Label = $Margin/VBox/NameLabel
@onready var subtitle_label: Label = $Margin/VBox/SubtitleLabel
@onready var best_label: Label = $Margin/VBox/BestLabel
@onready var stars_label: Label = $Margin/VBox/Footer/StarsLabel
@onready var open_label: Label = $Margin/VBox/Footer/OpenLabel

var level_id: String = ""
var _locked: bool = false
var _accent: Color = Color(0.95, 0.37, 0.36)
var _hovered: bool = false
var _hover_tween: Tween


func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	resized.connect(_update_pivot)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_update_pivot()


func setup(
	summary: Dictionary,
	best: Dictionary,
	_stars: int,
	index: int,
	duo_mode: bool
) -> void:
	level_id = str(summary.get("id", ""))
	_accent = Color.from_string(str(summary.get("accent", "#ff6b5b")), Color(0.95, 0.37, 0.36))
	number_label.text = "%02d" % (index + 1)
	name_label.text = str(summary.get("name", "未命名关卡"))
	var custom := bool(summary.get("custom", false))
	# 自制关卡不再展示简介；主线仍保留教学/氛围文案。
	subtitle_label.visible = not custom
	var description := str(summary.get("subtitle", ""))
	if description.is_empty():
		description = str(summary.get("description", "新的轨道正在等你"))
	if custom:
		description = ""
	subtitle_label.text = description
	var difficulty := clampi(int(summary.get("difficulty", 1)), 1, 5)
	difficulty_label.text = "难度 " + "●".repeat(difficulty) + "○".repeat(5 - difficulty)
	best_label.text = (
		"最佳丢 %d 人 · %s" % [ScoreRules.get_lost_passengers(best), ScoreRules.format_time(float(best.get("time_seconds", 0.0)))]
		if not best.is_empty()
		else "等待首次挑战"
	)
	stars_label.visible = not custom
	stars_label.text = "★".repeat(_stars) + "☆".repeat(3 - _stars) if not custom else ""
	open_label.text = ("已通关 · 自制关卡 →" if SaveManager.is_level_cleared(level_id) else "自制关卡 →") if custom else "开始挑战 →"
	if duo_mode:
		open_label.text = "双人出发 →"
	accent_bar.color = _accent
	preview.set_accent(_accent)
	# 未通关卡片保留轻微倾斜，增加手工拼贴感；已通关卡片保持端正。
	if not SaveManager.is_level_cleared(level_id):
		rotation = deg_to_rad(-0.9 + float(index % 3) * 0.9)
	_apply_styles()
	tooltip_text = "进入「%s」" % name_label.text
	queue_redraw()


## 主线闯关：未解锁的卡片不可点击。
func set_locked(locked: bool) -> void:
	_locked = locked
	disabled = locked
	mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if locked else Control.CURSOR_POINTING_HAND
	if locked:
		open_label.text = "锁定 · 通关前一关后解锁"
		modulate = Color(1, 1, 1, 0.62)
		tooltip_text = "先通关上一关"
	else:
		modulate = Color.WHITE


## 供自动测试读取卡片展示值。
func get_best_text() -> String:
	return best_label.text


func get_stars_text() -> String:
	return stars_label.text


func _apply_styles() -> void:
	var normal := _make_style(Color(0.996, 0.972, 0.894), _accent.darkened(0.1), 20, 3, 9)
	var hover := _make_style(Color(1, 0.995, 0.965), _accent, 20, 4, 13)
	var pressed_style := _make_style(Color(0.97, 0.92, 0.8), _accent.darkened(0.2), 20, 3, 4)
	var focus := _make_style(Color(0, 0, 0, 0), UITheme.COLOR_YELLOW, 22, 4, 0)
	focus.bg_color = Color(0, 0, 0, 0)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed_style)
	add_theme_stylebox_override("focus", focus)
	add_theme_stylebox_override("disabled", normal)
	add_theme_color_override("font_color", Color.TRANSPARENT)


func _make_style(
	background: Color,
	border: Color,
	radius: int,
	border_width: int,
	shadow: int
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(0)
	box.shadow_color = Color(0.06, 0.16, 0.24, 0.18)
	box.shadow_size = 0 if PlatformConfig.is_wechat else shadow
	box.shadow_offset = Vector2(0, 4)
	box.anti_aliasing = true
	return box


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _on_pressed() -> void:
	if _locked:
		return
	AudioDirector.play_click()
	chosen.emit(level_id)


func _on_mouse_entered() -> void:
	_hovered = true
	_animate_scale(Vector2(1.018, 1.018))
	AudioDirector.play_move()


func _on_mouse_exited() -> void:
	_hovered = false
	if not has_focus():
		_animate_scale(Vector2.ONE)


func _on_focus_entered() -> void:
	_animate_scale(Vector2(1.018, 1.018))


func _on_focus_exited() -> void:
	if not _hovered:
		_animate_scale(Vector2.ONE)


func _animate_scale(target: Vector2) -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "scale", target, 0.18)

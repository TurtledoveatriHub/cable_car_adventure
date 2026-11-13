extends Node
## 全局 UI 主题与配色。所有界面共用同一套字体、圆角、描边与按钮样式。

## 2.2MB GB2312+项目字符子集；原始 10.6MB 字体只留在工具链中，不进入导出。
const FONT_PATH := "res://assets/fonts/CableCarSans-Subset.otf"

const COLOR_INK := Color(0.106, 0.196, 0.282)
const COLOR_INK_SOFT := Color(0.22, 0.31, 0.39)
const COLOR_SKY := Color(0.478, 0.839, 0.965)
const COLOR_SKY_DEEP := Color(0.22, 0.64, 0.84)
const COLOR_CREAM := Color(1.0, 0.965, 0.839)
const COLOR_PAPER := Color(0.992, 0.976, 0.918)
const COLOR_CORAL := Color(0.949, 0.373, 0.361)
const COLOR_CORAL_DARK := Color(0.76, 0.23, 0.22)
const COLOR_YELLOW := Color(1.0, 0.824, 0.247)
const COLOR_TEAL := Color(0.18, 0.769, 0.714)
const COLOR_BLUE := Color(0.19, 0.52, 0.76)
const COLOR_MUTED := Color(0.39, 0.49, 0.57)
const COLOR_WHITE := Color(1, 1, 1)
const COLOR_SHADOW := Color(0.08, 0.19, 0.28, 0.22)

var theme: Theme
var body_font: Font
var title_font: Font
var heavy_font: Font


func _ready() -> void:
	_build_fonts()
	_build_theme()
	get_tree().root.theme = theme
	ThemeDB.fallback_font = body_font
	ThemeDB.fallback_font_size = 20
	get_tree().node_added.connect(_on_ui_node_added)
	get_tree().scene_changed.connect(_on_scene_changed)
	# 颜色覆盖在节点加入时已写入；不再每帧 find_children + queue_redraw。
	set_process(false)
	call_deferred("_apply_ui_juice_to_tree")


func _on_ui_node_added(node: Node) -> void:
	if node is OptionButton:
		_style_option_button(node as OptionButton)
	if node is Button:
		UIJuice.attach_button(node as Button)


func _style_option_button(option: OptionButton) -> void:
	if option == null:
		return
	option.modulate = Color.WHITE
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		option.add_theme_color_override(state, COLOR_INK)
	var popup := option.get_popup()
	if popup != null and not popup.about_to_popup.is_connected(_hide_option_scrollbars.bind(option)):
		popup.about_to_popup.connect(_hide_option_scrollbars.bind(option))


func _hide_option_scrollbars(option: OptionButton) -> void:
	if option == null:
		return
	for bar in option.get_popup().find_children("*", "VScrollBar", true, false):
		bar.visible = false
		bar.modulate.a = 0.0
		bar.custom_minimum_size = Vector2.ZERO
	call_deferred("_hide_option_scrollbars_deferred", option)


func _hide_option_scrollbars_deferred(option: OptionButton) -> void:
	if not is_instance_valid(option):
		return
	for bar in option.get_popup().find_children("*", "VScrollBar", true, false):
		bar.visible = false
		bar.modulate.a = 0.0
		bar.custom_minimum_size = Vector2.ZERO


func _process(_delta: float) -> void:
	for node in get_tree().root.find_children("*", "OptionButton", true, false):
		var option := node as OptionButton
		if option == null or not option.is_visible_in_tree():
			continue
		option.add_theme_color_override("font_color", COLOR_INK)
		option.add_theme_color_override("font_hover_color", COLOR_INK)
		option.add_theme_color_override("font_pressed_color", COLOR_INK)
		option.add_theme_color_override("font_focus_color", COLOR_INK)
		option.add_theme_color_override("font_hover_pressed_color", COLOR_INK)
		option.add_theme_color_override("font_disabled_color", COLOR_INK)
		option.queue_redraw()
		var popup := option.get_popup()
		if popup != null and popup.visible:
			for bar in popup.find_children("*", "VScrollBar", true, false):
				bar.visible = false
				bar.modulate.a = 0.0


func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	if scene != null:
		scene.modulate.a = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	if get_tree().current_scene != null:
		if get_tree().current_scene is LevelEditor:
			get_tree().current_scene.modulate.a = 1.0
		else:
			UIJuice.page_in(get_tree().current_scene)
		get_tree().current_scene.modulate.a = 1.0


func _apply_ui_juice_to_tree() -> void:
	for node in get_tree().root.find_children("*", "", true, false):
		if node is OptionButton:
			_style_option_button(node as OptionButton)
		if node is Button:
			UIJuice.attach_button(node as Button)


func _build_fonts() -> void:
	var loaded_font := load(FONT_PATH) as Font
	if loaded_font == null:
		push_error("[UITheme] 无法加载中文字体：%s" % FONT_PATH)
		body_font = ThemeDB.fallback_font
		heavy_font = ThemeDB.fallback_font
		title_font = ThemeDB.fallback_font
		return

	# Noto Sans SC 可变字体的轴默认值偏低，显式指定正文 400 / 标题 700-900。
	body_font = _make_weight_font(loaded_font, 0.0)
	heavy_font = _make_weight_font(loaded_font, 0.35)
	title_font = _make_weight_font(loaded_font, 0.65)


func _make_weight_font(base: Font, embolden: float) -> Font:
	var variation := FontVariation.new()
	variation.base_font = base
	# Source Han Sans CN 是静态字体，用合成加粗区分正文/标题。
	variation.variation_embolden = embolden
	return variation


func _build_theme() -> void:
	theme = Theme.new()
	theme.default_font = body_font
	theme.default_font_size = 20

	_style_labels()
	_style_buttons()
	_style_panels()
	_style_inputs()
	_style_misc()


func _style_labels() -> void:
	theme.set_color("font_color", "Label", COLOR_INK)
	theme.set_color("font_outline_color", "Label", COLOR_CREAM)
	theme.set_constant("outline_size", "Label", 0)
	theme.set_constant("line_spacing", "Label", 4)

	_add_label_variation("TitleLabel", title_font, 72, COLOR_CREAM, COLOR_INK, 12)
	_add_label_variation("DisplayLabel", title_font, 54, COLOR_CREAM, COLOR_INK, 10)
	_add_label_variation("HeadingLabel", heavy_font, 30, COLOR_INK, COLOR_CREAM, 0)
	_add_label_variation("SubheadingLabel", heavy_font, 22, COLOR_INK, COLOR_CREAM, 0)
	_add_label_variation("BodyLabel", body_font, 19, COLOR_INK_SOFT, COLOR_CREAM, 0)
	_add_label_variation("MutedLabel", body_font, 17, COLOR_MUTED, COLOR_CREAM, 0)
	_add_label_variation("HudLabel", heavy_font, 22, COLOR_CREAM, COLOR_INK, 5)
	_add_label_variation("HudSmallLabel", body_font, 16, COLOR_CREAM, COLOR_INK, 4)
	_add_label_variation("NumberLabel", title_font, 36, COLOR_INK, COLOR_CREAM, 0)
	_add_label_variation("DangerLabel", heavy_font, 22, COLOR_CORAL_DARK, COLOR_CREAM, 0)


func _add_label_variation(
	variation_name: String,
	font: Font,
	size: int,
	color: Color,
	outline_color: Color,
	outline_size: int
) -> void:
	theme.set_type_variation(variation_name, "Label")
	theme.set_font("font", variation_name, font)
	theme.set_font_size("font_size", variation_name, size)
	theme.set_color("font_color", variation_name, color)
	theme.set_color("font_outline_color", variation_name, outline_color)
	theme.set_constant("outline_size", variation_name, outline_size)
	if variation_name in ["TitleLabel", "DisplayLabel"]:
		theme.set_color("font_shadow_color", variation_name, Color(0.06, 0.14, 0.2, 0.22))
		theme.set_constant("shadow_offset_x", variation_name, 4)
		theme.set_constant("shadow_offset_y", variation_name, 5)
		theme.set_constant("shadow_outline_size", variation_name, 10)


func _style_buttons() -> void:
	theme.set_font("font", "Button", heavy_font)
	theme.set_font_size("font_size", "Button", 22)
	theme.set_color("font_color", "Button", COLOR_INK)
	theme.set_color("font_hover_color", "Button", COLOR_INK)
	theme.set_color("font_pressed_color", "Button", COLOR_INK)
	theme.set_color("font_focus_color", "Button", COLOR_INK)
	theme.set_color("font_disabled_color", "Button", Color(COLOR_INK, 0.35))
	theme.set_constant("h_separation", "Button", 10)
	theme.set_constant("outline_size", "Button", 0)

	var normal := _make_box(COLOR_CREAM, COLOR_INK, 18, 3, 8)
	var hover := _make_box(COLOR_WHITE, COLOR_INK, 18, 3, 10)
	var pressed_style := _make_box(Color(0.93, 0.9, 0.8), COLOR_INK, 18, 3, 3)
	var disabled := _make_box(Color(0.86, 0.87, 0.84), Color(COLOR_INK, 0.3), 18, 2, 3)
	var focus := _make_box(Color(0, 0, 0, 0), COLOR_YELLOW, 20, 4, 0)
	_apply_button_styles("Button", normal, hover, pressed_style, disabled, focus)

	_add_primary_button()
	_add_secondary_button()
	_add_ghost_button()
	_add_danger_button()
	_add_icon_button()


func _apply_button_styles(
	type_name: String,
	normal: StyleBoxFlat,
	hover: StyleBoxFlat,
	pressed_style: StyleBoxFlat,
	disabled: StyleBoxFlat,
	focus: StyleBoxFlat
) -> void:
	theme.set_stylebox("normal", type_name, normal)
	theme.set_stylebox("hover", type_name, hover)
	theme.set_stylebox("pressed", type_name, pressed_style)
	theme.set_stylebox("disabled", type_name, disabled)
	theme.set_stylebox("focus", type_name, focus)


func _add_primary_button() -> void:
	var type_name := "PrimaryButton"
	theme.set_type_variation(type_name, "Button")
	theme.set_color("font_color", type_name, COLOR_CREAM)
	theme.set_color("font_hover_color", type_name, COLOR_WHITE)
	theme.set_color("font_pressed_color", type_name, COLOR_CREAM)
	theme.set_color("font_focus_color", type_name, COLOR_CREAM)
	theme.set_font_size("font_size", type_name, 24)
	var normal := _make_box(COLOR_CORAL, COLOR_INK, 20, 3, 10)
	var hover := _make_box(COLOR_CORAL.lightened(0.08), COLOR_INK, 20, 3, 12)
	var pressed_style := _make_box(COLOR_CORAL_DARK, COLOR_INK, 20, 3, 4)
	var disabled := _make_box(Color(COLOR_CORAL, 0.45), Color(COLOR_INK, 0.3), 20, 2, 4)
	var focus := _make_box(Color(0, 0, 0, 0), COLOR_YELLOW, 22, 4, 0)
	_apply_button_styles(type_name, normal, hover, pressed_style, disabled, focus)


func _add_secondary_button() -> void:
	var type_name := "SecondaryButton"
	theme.set_type_variation(type_name, "Button")
	theme.set_color("font_color", type_name, COLOR_INK)
	theme.set_color("font_hover_color", type_name, COLOR_INK)
	theme.set_color("font_pressed_color", type_name, COLOR_INK)
	theme.set_color("font_focus_color", type_name, COLOR_INK)
	theme.set_font_size("font_size", type_name, 20)
	var normal := _make_box(COLOR_CREAM, COLOR_INK, 16, 3, 5)
	var hover := _make_box(COLOR_WHITE, COLOR_INK, 16, 3, 7)
	var pressed_style := _make_box(COLOR_YELLOW, COLOR_INK, 16, 3, 2)
	var disabled := _make_box(Color(COLOR_CREAM, 0.35), Color(COLOR_INK, 0.3), 16, 2, 2)
	var focus := _make_box(Color(0, 0, 0, 0), COLOR_YELLOW, 18, 3, 0)
	_apply_button_styles(type_name, normal, hover, pressed_style, disabled, focus)


func _add_ghost_button() -> void:
	var type_name := "GhostButton"
	theme.set_type_variation(type_name, "Button")
	theme.set_color("font_color", type_name, COLOR_CREAM)
	theme.set_color("font_hover_color", type_name, COLOR_WHITE)
	theme.set_color("font_pressed_color", type_name, COLOR_INK)
	theme.set_color("font_focus_color", type_name, COLOR_CREAM)
	theme.set_font_size("font_size", type_name, 19)
	var normal := _make_box(Color(0.07, 0.17, 0.25, 0.82), Color(1, 1, 1, 0.3), 16, 2, 3)
	var hover := _make_box(Color(0.08, 0.21, 0.3, 0.95), Color(1, 1, 1, 0.55), 16, 2, 6)
	var pressed_style := _make_box(COLOR_YELLOW, COLOR_INK, 16, 2, 2)
	var disabled := _make_box(Color(0.07, 0.17, 0.25, 0.35), Color(1, 1, 1, 0.15), 16, 1, 0)
	var focus := _make_box(Color(0, 0, 0, 0), COLOR_YELLOW, 18, 3, 0)
	_apply_button_styles(type_name, normal, hover, pressed_style, disabled, focus)


func _add_danger_button() -> void:
	var type_name := "DangerButton"
	theme.set_type_variation(type_name, "Button")
	theme.set_color("font_color", type_name, COLOR_CREAM)
	theme.set_color("font_hover_color", type_name, COLOR_WHITE)
	theme.set_color("font_pressed_color", type_name, COLOR_CREAM)
	theme.set_font_size("font_size", type_name, 20)
	var normal := _make_box(COLOR_CORAL_DARK, COLOR_INK, 16, 3, 6)
	var hover := _make_box(COLOR_CORAL, COLOR_INK, 16, 3, 8)
	var pressed_style := _make_box(Color(0.6, 0.16, 0.16), COLOR_INK, 16, 3, 2)
	var disabled := _make_box(Color(0.6, 0.16, 0.16, 0.4), Color(COLOR_INK, 0.3), 16, 2, 2)
	var focus := _make_box(Color(0, 0, 0, 0), COLOR_YELLOW, 18, 4, 0)
	_apply_button_styles(type_name, normal, hover, pressed_style, disabled, focus)


func _add_icon_button() -> void:
	var type_name := "IconButton"
	theme.set_type_variation(type_name, "Button")
	theme.set_color("font_color", type_name, COLOR_INK)
	theme.set_color("font_hover_color", type_name, COLOR_INK)
	theme.set_color("font_pressed_color", type_name, COLOR_INK)
	theme.set_font_size("font_size", type_name, 24)
	var normal := _make_box(Color(COLOR_CREAM, 0.88), COLOR_INK, 18, 2, 5)
	var hover := _make_box(COLOR_WHITE, COLOR_INK, 18, 2, 7)
	var pressed_style := _make_box(COLOR_YELLOW, COLOR_INK, 18, 2, 2)
	var disabled := _make_box(Color(COLOR_CREAM, 0.4), Color(COLOR_INK, 0.3), 18, 1, 2)
	var focus := _make_box(Color(0, 0, 0, 0), COLOR_YELLOW, 20, 3, 0)
	_apply_button_styles(type_name, normal, hover, pressed_style, disabled, focus)


func _style_panels() -> void:
	theme.set_stylebox("panel", "PanelContainer", _make_box(Color(COLOR_CREAM, 0.96), COLOR_INK, 24, 3, 12))
	_add_panel_variation("CardPanel", COLOR_CREAM, 24, 12)
	_add_panel_variation("PaperPanel", COLOR_PAPER, 26, 14)
	_add_panel_variation("HudPanel", Color(0.08, 0.18, 0.26, 0.86), 18, 6, Color(1, 1, 1, 0.18), 2)
	_add_panel_variation("ToastPanel", Color(0.08, 0.18, 0.26, 0.94), 18, 10, COLOR_YELLOW, 2)
	_add_panel_variation("TransparentPanel", Color(0, 0, 0, 0), 0, 0, Color(0, 0, 0, 0), 0)


func _add_panel_variation(
	type_name: String,
	color: Color,
	radius: int,
	shadow: int,
	border_color: Color = COLOR_INK,
	border_width: int = 3
) -> void:
	theme.set_type_variation(type_name, "PanelContainer")
	theme.set_stylebox("panel", type_name, _make_box(color, border_color, radius, border_width, shadow))


func _style_inputs() -> void:
	for type_name: String in ["OptionButton", "MenuButton"]:
		theme.set_font("font", type_name, heavy_font)
		theme.set_font_size("font_size", type_name, 19)
		theme.set_color("font_color", type_name, COLOR_INK)
		theme.set_color("font_hover_color", type_name, COLOR_INK)
		theme.set_color("font_pressed_color", type_name, COLOR_INK)
		theme.set_color("font_focus_color", type_name, COLOR_INK)
		theme.set_stylebox("normal", type_name, _make_box(COLOR_CREAM, COLOR_INK, 14, 2, 4))
		theme.set_stylebox("hover", type_name, _make_box(COLOR_WHITE, COLOR_INK, 14, 2, 5))
		theme.set_stylebox("pressed", type_name, _make_box(COLOR_YELLOW, COLOR_INK, 14, 2, 2))
		theme.set_stylebox("focus", type_name, _make_box(Color(0, 0, 0, 0), COLOR_YELLOW, 16, 3, 0))
		theme.set_constant("arrow_margin", type_name, 10)

	theme.set_stylebox("panel", "PopupMenu", _make_box(COLOR_CREAM, COLOR_INK, 14, 3, 10))
	theme.set_font("font", "PopupMenu", body_font)
	theme.set_font_size("font_size", "PopupMenu", 19)
	theme.set_color("font_color", "PopupMenu", COLOR_INK)
	theme.set_color("font_hover_color", "PopupMenu", COLOR_INK)

	theme.set_stylebox("normal", "OptionButton", _make_box(COLOR_CREAM, COLOR_INK, 14, 2, 4))
	theme.set_stylebox("hover", "OptionButton", _make_box(COLOR_WHITE, COLOR_INK, 14, 2, 4))
	theme.set_stylebox("pressed", "OptionButton", _make_box(COLOR_YELLOW, COLOR_INK, 14, 2, 4))
	theme.set_stylebox("focus", "OptionButton", _make_box(COLOR_CREAM, COLOR_YELLOW, 14, 3, 4))
	theme.set_color("font_color", "OptionButton", COLOR_INK)
	theme.set_color("font_hover_color", "OptionButton", COLOR_INK)
	theme.set_color("font_pressed_color", "OptionButton", COLOR_INK)
	theme.set_color("font_focus_color", "OptionButton", COLOR_INK)
	theme.set_font("font", "OptionButton", body_font)
	theme.set_font_size("font_size", "OptionButton", 18)
	theme.set_stylebox("panel", "PopupMenu", _make_box(COLOR_PAPER, COLOR_INK, 14, 2, 5))
	theme.set_color("font_color", "PopupMenu", COLOR_INK)
	theme.set_color("font_hover_color", "PopupMenu", COLOR_CREAM)
	theme.set_font("font", "PopupMenu", body_font)
	theme.set_font_size("font_size", "PopupMenu", 17)
	for bar_type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", bar_type, _make_box(Color(COLOR_INK, 0.10), Color(COLOR_INK, 0.0), 6, 0, 0))
		theme.set_stylebox("grabber", bar_type, _make_box(Color(COLOR_INK, 0.32), Color(COLOR_INK, 0.12), 6, 1, 0))
		theme.set_stylebox("grabber_highlight", bar_type, _make_box(COLOR_YELLOW, COLOR_INK, 6, 1, 0))
		theme.set_stylebox("grabber_pressed", bar_type, _make_box(COLOR_CORAL, COLOR_INK, 6, 1, 0))
	theme.set_stylebox("panel", "PopupPanel", _make_box(COLOR_PAPER, COLOR_INK, 22, 3, 12))
	theme.set_stylebox("slider", "HSlider", _make_box(Color(COLOR_INK, 0.16), Color(COLOR_INK, 0.35), 6, 1, 0))
	theme.set_stylebox("grabber_area", "HSlider", _make_box(COLOR_CORAL, COLOR_INK, 6, 0, 0))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _make_box(COLOR_YELLOW, COLOR_INK, 6, 0, 0))
	theme.set_icon("grabber", "HSlider", _make_grabber_texture())
	theme.set_icon("grabber_highlight", "HSlider", _make_grabber_texture())
	theme.set_stylebox("normal", "LineEdit", _make_box(COLOR_WHITE, COLOR_INK, 14, 2, 2))
	theme.set_stylebox("focus", "LineEdit", _make_box(COLOR_WHITE, COLOR_YELLOW, 14, 3, 4))
	theme.set_color("font_color", "LineEdit", COLOR_INK)
	theme.set_color("caret_color", "LineEdit", COLOR_CORAL)
	theme.set_font("font", "LineEdit", body_font)
	theme.set_font_size("font_size", "LineEdit", 20)
	theme.set_stylebox("normal", "TextEdit", _make_box(COLOR_WHITE, COLOR_INK, 14, 2, 8))
	theme.set_stylebox("focus", "TextEdit", _make_box(COLOR_WHITE, COLOR_YELLOW, 14, 3, 10))
	theme.set_stylebox("read_only", "TextEdit", _make_box(Color(COLOR_CREAM, 0.8), COLOR_INK, 14, 2, 8))
	theme.set_color("font_color", "TextEdit", COLOR_INK)
	theme.set_color("caret_color", "TextEdit", COLOR_CORAL)
	theme.set_color("selection_color", "TextEdit", Color(COLOR_YELLOW, 0.45))
	theme.set_font("font", "TextEdit", body_font)
	theme.set_font_size("font_size", "TextEdit", 18)
	theme.set_constant("line_spacing", "TextEdit", 3)


func _make_grabber_texture() -> Texture2D:
	# 4x 超采样后缩小，得到圆润、无锯齿的滑块按钮；最终仍为 36x36。
	var size := 36
	var scale := 4
	var image := Image.create(size * scale, size * scale, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center := Vector2(size * scale - 1, size * scale - 1) * 0.5
	for y in size * scale:
		for x in size * scale:
			var distance := Vector2(x, y).distance_to(center)
			if distance <= 16.0 * scale:
				var color := COLOR_INK
				if distance <= 13.5 * scale:
					color = COLOR_CREAM
				if distance <= 7.5 * scale:
					color = COLOR_CORAL
				image.set_pixel(x, y, color)
	image.resize(size, size, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(image)

func _style_misc() -> void:
	theme.set_color("font_color", "CheckButton", COLOR_INK)
	theme.set_color("font_hover_color", "CheckButton", COLOR_INK)
	theme.set_color("font_pressed_color", "CheckButton", COLOR_INK)
	theme.set_font("font", "CheckButton", body_font)
	theme.set_font_size("font_size", "CheckButton", 19)

	theme.set_stylebox("panel", "TooltipPanel", _make_box(COLOR_INK, COLOR_INK, 10, 0, 5))
	theme.set_color("font_color", "TooltipLabel", COLOR_CREAM)
	theme.set_font("font", "TooltipLabel", body_font)
	theme.set_font_size("font_size", "TooltipLabel", 16)

	theme.set_stylebox("panel", "ProgressBar", _make_box(Color(1, 1, 1, 0.2), Color(COLOR_INK, 0.2), 10, 1, 0))
	theme.set_stylebox("fill", "ProgressBar", _make_box(COLOR_YELLOW, COLOR_INK, 10, 0, 0))
	theme.set_font("font", "ProgressBar", body_font)
	theme.set_font_size("font_size", "ProgressBar", 16)

	theme.set_stylebox("panel", "ItemList", _make_box(COLOR_CREAM, COLOR_INK, 16, 2, 6))
	theme.set_color("font_color", "ItemList", COLOR_INK)
	theme.set_color("font_selected_color", "ItemList", COLOR_CREAM)
	theme.set_stylebox("selected", "ItemList", _make_box(COLOR_CORAL, COLOR_CORAL, 10, 0, 0))
	theme.set_stylebox("selected_focus", "ItemList", _make_box(COLOR_CORAL, COLOR_YELLOW, 10, 2, 0))
	theme.set_font("font", "ItemList", body_font)
	theme.set_font_size("font_size", "ItemList", 18)


func _make_box(
	background: Color,
	border: Color,
	radius: int,
	border_width: int = 3,
	shadow_size: int = 8
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(18)
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	box.anti_aliasing = true
	if PlatformConfig.is_wechat:
		shadow_size = 0
	if shadow_size > 0:
		box.shadow_color = COLOR_SHADOW
		box.shadow_size = shadow_size
		box.shadow_offset = Vector2(0, maxf(2.0, shadow_size * 0.45))
	return box


func make_title(text: String, size: int = 72) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", title_font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", COLOR_CREAM)
	label.add_theme_color_override("font_outline_color", COLOR_INK)
	label.add_theme_constant_override("outline_size", maxi(6, int(size * 0.12)))
	return label

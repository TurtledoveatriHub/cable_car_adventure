class_name CartUnlockPopup
extends PopupPanel
## 独立缆车解锁弹窗场景。内容由 setup() 注入，布局/样式全部在 .tscn 中。

signal closed

@onready var icon: CartPreview = %Icon
@onready var name_label: Label = %NameLabel
@onready var description: Label = %Description
@onready var panel: PanelContainer = $Panel
@onready var close_button: Button = %CloseButton

var _closed_emitted: bool = false


func _ready() -> void:
	# PopupPanel 自身不要再画一层底板，否则会出现“大号空白弹窗 + 解锁弹窗”两层。
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.gui_input.connect(_on_panel_input)
	popup_hide.connect(_emit_closed)
	visibility_changed.connect(func() -> void:
		if not visible:
			_emit_closed()
	)
	close_button.pressed.connect(_request_close)
	UIJuice.popup_in(panel)


func setup(profile: CartProfile) -> void:
	if profile == null:
		return
	icon.setup(profile)
	name_label.text = profile.display_name
	description.text = profile.description


func _on_panel_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		_request_close()


func _request_close() -> void:
	if not visible:
		return
	UIJuice.popup_out(panel, hide)


func _emit_closed() -> void:
	if _closed_emitted:
		return
	_closed_emitted = true
	closed.emit()

extends Node
## 跨场景会话：选关页把选择写入这里，游戏页读取，结算页再读取本局结果。
## 该单例只保存内存数据，不负责存档或网络。

const MODE_SOLO := "solo"
const MODE_DUO := "duo"
const SPLIT_SIDE_BY_SIDE := "side_by_side"
const SPLIT_STACKED := "stacked"
const SPLIT_SHARED := "shared"

var mode: String = MODE_SOLO
var selected_level_id: String = ""
var last_result: Dictionary = {}
var test_from_editor: bool = false ## 是否由关卡编辑器发起试玩
var editor_return_level_id: String = "" ## 试玩后返回编辑器时保持的关卡 id
var duo_split: String = SPLIT_STACKED
var duo_show_ghost: bool = true
var authored_level_data: Dictionary = {}
var community_entry_id: String = ""
var return_to_plaza: bool = false
var developer_mode: bool = false
var suppress_editor_session: bool = false

## TouchControls 是否允许 PC 显示
@export var pc_debug_touch_controls: bool = false
## 选关界面“全解/重置”按钮显隐
@export var show_unlock_debug_buttons: bool = false
## 开发者界面Ctrl+Shift+D 是否可用
@export var developer_interface: bool = true


func set_mode(new_mode: String) -> void:
	mode = MODE_DUO if new_mode == MODE_DUO else MODE_SOLO


func is_duo() -> bool:
	return mode == MODE_DUO


func load_duo_settings() -> void:
	duo_split = str(SaveManager.get_setting("duo_split", duo_split))
	duo_show_ghost = bool(SaveManager.get_setting("duo_show_ghost", true))
	if duo_split != SPLIT_SIDE_BY_SIDE and duo_split != SPLIT_STACKED and duo_split != SPLIT_SHARED:
		duo_split = SPLIT_STACKED


func set_duo_split(split: String) -> void:
	if split == SPLIT_SIDE_BY_SIDE or split == SPLIT_SHARED:
		duo_split = split
	else:
		duo_split = SPLIT_STACKED
	SaveManager.set_setting("duo_split", duo_split)


## 准备一局游戏并切到游戏场景。
func start_level(level_id: String, play_mode: String = MODE_SOLO, from_editor: bool = false) -> void:
	return_to_plaza = false
	test_from_editor = from_editor or test_from_editor
	selected_level_id = level_id
	authored_level_data = {}
	community_entry_id = ""
	set_mode(play_mode)
	last_result = {}
	SceneRouter.goto_game()


func start_authored_level(data: Dictionary) -> void:
	authored_level_data = data.duplicate(true)
	selected_level_id = str(data.get("id", "authored_demo"))
	community_entry_id = ""
	set_mode(MODE_SOLO)
	last_result = {}
	SceneRouter.goto_game()


func start_community_level(entry_id: String, data: Dictionary) -> void:
	start_authored_level(data)
	community_entry_id = entry_id
	return_to_plaza = true


## 游戏结束，保存结果并进入结算场景。
func complete_run(result: Dictionary) -> void:
	last_result = result.duplicate(true)
	selected_level_id = str(result.get("level_id", selected_level_id))
	mode = str(result.get("mode", mode))
	SceneRouter.goto_result()


func return_to_level_select() -> void:
	test_from_editor = false
	if return_to_plaza:
		return_to_plaza = false
		SceneRouter.goto_plaza()
	else:
		SceneRouter.goto_level_select(mode)


func return_to_editor() -> void:
	var keep_id := editor_return_level_id
	test_from_editor = false
	selected_level_id = keep_id
	SceneRouter.goto_editor()


func clear() -> void:
	selected_level_id = ""
	last_result = {}
	test_from_editor = false
	editor_return_level_id = ""
	authored_level_data = {}
	community_entry_id = ""

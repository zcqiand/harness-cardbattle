extends Control
## 主场景（Task 11 三态机）：menu → battle → result → menu，jumper 同款
## change_state 形状（enum Screen + _show_x 私有迁移 + _clear_ui 拆旧屏）。
## menu 挂 menu_view（牌组/对手选择+成绩册），battle 挂 battle_view（收 finished
## 广播），result 挂 result_view（审计报告；audit.ok 前置在 result_view 侧执行，
## 入档也只在 ok 时发生）。
## storage 鸭子接口（load_text/save_text）可注入（headless 冒烟传内存假件），
## null 时 _ready 建 FileStorage（真 user:// 持久档）。

const MENU_VIEW := preload("res://scripts/menu_view.gd")
const BATTLE_VIEW := preload("res://scripts/battle_view.gd")
const RESULT_VIEW := preload("res://scripts/result_view.gd")
const FILE_STORAGE := preload("res://scripts/file_storage.gd")

enum Screen { MENU, BATTLE, RESULT }

## 测试注入口：与 file_storage.gd 同签名的鸭子接口；null → FileStorage。
var storage: RefCounted = null

var _screen: Screen = Screen.MENU
var _menu_view: Control = null
var _battle_view: Control = null
var _result_view: Control = null
var _config: Dictionary = {}  # 当前局配置（再来一局用）


func _ready() -> void:
	storage = storage if storage != null else FILE_STORAGE.new()
	_show_menu()


## ——状态迁移——

func _show_menu() -> void:
	_screen = Screen.MENU
	_clear_ui()
	_menu_view = MENU_VIEW.new()
	_menu_view.setup(storage)
	_menu_view.start_selected.connect(_start_battle)
	add_child(_menu_view)


func _start_battle(config: Dictionary) -> void:
	_config = config
	_clear_ui()
	_screen = Screen.BATTLE
	_battle_view = BATTLE_VIEW.new()
	_battle_view.setup(config)
	_battle_view.finished.connect(_on_battle_finished)
	add_child(_battle_view)


func _on_battle_finished(bundle: Dictionary) -> void:
	_show_result(bundle)


func _show_result(bundle: Dictionary) -> void:
	_screen = Screen.RESULT
	_clear_ui()
	_result_view = RESULT_VIEW.new()
	_result_view.setup(bundle, storage)
	_result_view.rematch_pressed.connect(_rematch)
	_result_view.back_to_menu_pressed.connect(_show_menu)
	add_child(_result_view)


## 再来一局：同配置重开（同牌组/同对手/同种子——审计重放面一致）。
func _rematch() -> void:
	_start_battle(_config)


## ——UI 件——

func _clear_ui() -> void:
	if _menu_view != null:
		_menu_view.queue_free()
		_menu_view = null
	if _battle_view != null:
		_battle_view.queue_free()
		_battle_view = null
	if _result_view != null:
		_result_view.queue_free()
		_result_view = null

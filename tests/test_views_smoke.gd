extends RefCounted
## 表现层冒烟套件（Task 11）：四个 UI 脚本可加载可实例化，main.tscn 可实例化
## 且可 free（不进树——headless 下不触 _ready，只证装配面完整）。
## RED 形状 = 脚本/场景 load() 得 null；实现后全绿。

const HARNESS_PATH := "res://tests/harness.gd"
const MAIN_SCENE_PATH := "res://scenes/main.tscn"

const SCRIPT_PATHS: Array[String] = [
	"res://scripts/main.gd",
	"res://scripts/menu_view.gd",
	"res://scripts/battle_view.gd",
	"res://scripts/result_view.gd",
]


func run(failures: Array[String]) -> void:
	var harness: GDScript = load(HARNESS_PATH)
	for path in SCRIPT_PATHS:
		var script: GDScript = load(path)
		harness.assert_true(script != null, "UI 脚本可加载：%s" % path, failures)
		harness.assert_true(script != null and script.can_instantiate(),
			"UI 脚本可实例化：%s" % path, failures)
	var scene: PackedScene = load(MAIN_SCENE_PATH)
	harness.assert_true(scene != null, "main.tscn 可加载", failures)
	if scene != null:
		var node: Node = scene.instantiate()
		harness.assert_true(node != null, "main.tscn 可实例化", failures)
		if node != null:
			node.free()

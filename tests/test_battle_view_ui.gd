extends RefCounted
## 战斗屏 UI 可点性回归（2026-11-20 live 指纹）：
## ①账本 ScrollContainer 曾整面盖住 attack/end_turn 按钮——透明矩形吃尽点击，
##   两钮自首航起不可点（e2e 走逻辑层直调 apply_action，不经真实鼠标，全绿
##   也拦不住）——本套件钉死「任何 ScrollContainer 矩形不得与 action 按钮
##   相交」的几何断言，布局再漂移即红。
## ②attack 按钮曾只看 my_turn 不看规则面（atk<=0 / 本回合已用仍可点，点了
##   只落一行屏底红字）——钉死 attack 预禁用与卡牌按钮（费用>能量禁用）
##   同规则：开局 atk=0 禁用、atk>0 可点、attack 结算后本回合禁用。

const BATTLE_VIEW_PATH := "res://scripts/battle_view.gd"
const CARDS := preload("res://scripts/core/cards.gd")


var completed := false


func _build_view() -> Control:
	var config: Dictionary = {
		"deck_player": ["sharpen_blade", "fire_bolt"],
		"deck_player_id": "test-deck",
		"deck_player_name": "测试牌组",
		"deck_enemy": ["fire_bolt", "fire_bolt"],
		"deck_enemy_id": "test-deck-enemy",
		"deck_enemy_name": "对手牌组",
		"opponent_path": "res://data/opponents/greedy.json",
		"opponent_id": "greedy",
		"opponent_name": "贪手",
		"seed": 20261120,
	}
	var view: Control = (load(BATTLE_VIEW_PATH) as GDScript).new()
	view.setup(config)
	return view


func run(failures: Array[String]) -> void:
	var harness: GDScript = load("res://tests/harness.gd")
	var view: Control = _build_view()
	var attack: Button = view._attack_button
	var end_turn: Button = view._end_turn_button
	harness.assert_true(attack != null and end_turn != null,
		"测试前提：action 按钮已装配", failures)

	# ① 几何：任何滚动区矩形不得与 action 按钮相交（吃点击 = 不可点）。
	for child in view.get_children():
		if child is ScrollContainer:
			var sc := child as ScrollContainer
			var scroll_rect := Rect2(sc.position, sc.size)
			harness.assert_true(
				not scroll_rect.intersects(Rect2(attack.position, attack.size)),
				"滚动区矩形不得盖住 attack 按钮（scroll @ %s size %s）"
					% [sc.position, sc.size], failures)
			harness.assert_true(
				not scroll_rect.intersects(Rect2(end_turn.position, end_turn.size)),
				"滚动区矩形不得盖住 end_turn 按钮（scroll @ %s size %s）"
					% [sc.position, sc.size], failures)

	# ② 预禁用规则面。
	var st: Dictionary = (view._game as Dictionary)["state"]
	var hero: Dictionary = (st["heroes"] as Dictionary)["player_hero"]
	harness.assert_true(int(hero["atk"]) == 0, "测试前提：开局玩家 atk=0", failures)
	harness.assert_true(attack.disabled, "开局 atk=0 时 attack 按钮应预禁用", failures)
	harness.assert_true(not end_turn.disabled, "开局 end_turn 按钮应可点", failures)

	hero["atk"] = 3
	view._refresh()
	harness.assert_true(not attack.disabled, "atk>0 且 attack 未用时 attack 按钮应可点", failures)
	harness.assert_true(not end_turn.disabled, "atk>0 时 end_turn 按钮应可点", failures)

	# 真实 attack 结算：attack_used 翻真 → 下一次刷新 attack 预禁用。
	view._player_action({"type": "attack"})
	harness.assert_true((view._reject_label as Label).text == "",
		"atk=3 的 attack 应被接受（拒因：%s）" % (view._reject_label as Label).text, failures)
	harness.assert_true(view._attack_button.disabled, "attack 结算后本回合 attack 按钮应预禁用", failures)
	harness.assert_true(not view._end_turn_button.disabled, "attack 结算后 end_turn 按钮应可点", failures)

	view.free()
	completed = true

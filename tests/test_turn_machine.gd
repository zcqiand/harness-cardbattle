extends RefCounted
## 回合状态机套件：流转表数据逐字全等 / MAIN 接受三类事件 / TURN_START 拒绝
## play_card（reason 逐字）/ GAME_OVER 拒绝全部三类。

const HARNESS_PATH := "res://tests/harness.gd"
const TM_PATH := "res://scripts/core/turn_machine.gd"

const LEGAL_EVENTS := {
	"TURN_START": [],
	"MAIN": ["play_card", "attack", "end_turn"],
	"TURN_END": [],
	"GAME_OVER": [],
}


var completed := false


func run(failures: Array[String]) -> void:
	var h: GDScript = load(HARNESS_PATH)
	var tm: GDScript = load(TM_PATH)
	if tm == null:
		h.assert_true(false, "turn_machine.gd 加载失败", failures)
		return

	# 规约=数据：流转表与规约逐字全等
	var table: Dictionary = tm.legal_events()
	h.assert_eq(table, LEGAL_EVENTS, "legal_events 表与规约逐字全等", failures)

	# MAIN 接受三类事件：ok=true 且 reason 为空
	for ev in ["play_card", "attack", "end_turn"]:
		var res: Dictionary = tm.can_accept("MAIN", ev)
		h.assert_true(res["ok"], "MAIN 接受 %s" % ev, failures)
		h.assert_eq(res["reason"], "", "MAIN 接受 %s 时 reason 为空" % ev, failures)

	# TURN_START 拒绝 play_card：ok=false 且 reason 逐字
	var rej: Dictionary = tm.can_accept("TURN_START", "play_card")
	h.assert_true(not rej["ok"], "TURN_START 拒绝 play_card", failures)
	h.assert_eq(rej["reason"], "TURN_START 不接受事件 play_card",
		"TURN_START 拒绝 reason 逐字", failures)

	# GAME_OVER 拒绝全部三类事件
	for ev in ["play_card", "attack", "end_turn"]:
		var go: Dictionary = tm.can_accept("GAME_OVER", ev)
		h.assert_true(not go["ok"], "GAME_OVER 拒绝 %s" % ev, failures)
		h.assert_eq(go["reason"], "GAME_OVER 不接受事件 %s" % ev,
			"GAME_OVER 拒绝 %s reason 逐字" % ev, failures)
	completed = true

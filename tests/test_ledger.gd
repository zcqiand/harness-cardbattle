extends RefCounted
## 账本套件：seq 自增 / 追加与返回值 / (target,field) 链连续性检查（连续 ok、
## 断链报后一条+expected/actual、异键异链互不干扰）。

const HARNESS_PATH := "res://tests/harness.gd"
const LEDGER_PATH := "res://scripts/core/ledger.gd"


func run(failures: Array[String]) -> void:
	var h: GDScript = load(HARNESS_PATH)
	var ledger: GDScript = load(LEDGER_PATH)
	if ledger == null:
		h.assert_true(false, "ledger.gd 加载失败", failures)
		return

	# new_ledger 形状
	var lg: Dictionary = ledger.new_ledger()
	h.assert_true(lg.has("entries") and lg.has("next_seq"), "new_ledger 含 entries/next_seq", failures)
	h.assert_true((lg["entries"] as Array).is_empty(), "新账本 entries 为空", failures)
	h.assert_eq(lg["next_seq"], 1, "新账本 next_seq=1", failures)

	# append：返回 seq，首条填 seq=1，再条 seq=2
	var e1 := {"turn": 1, "actor": "player", "event": "damage", "card": "c1",
		"field": "hp", "target": "enemy_hero", "before": 30, "after": 27, "formula": "30-3"}
	var s1: int = ledger.append(lg, e1)
	h.assert_eq(s1, 1, "首条 append 返回 1", failures)
	h.assert_eq((lg["entries"] as Array)[0]["seq"], 1, "首条目被填 seq=1", failures)
	h.assert_eq(lg["next_seq"], 2, "append 后 next_seq=2", failures)

	var e2 := {"turn": 1, "actor": "player", "event": "damage", "card": "c1",
		"field": "hp", "target": "enemy_hero", "before": 27, "after": 24, "formula": "27-3"}
	var s2: int = ledger.append(lg, e2)
	h.assert_eq(s2, 2, "第二条 append 返回 2", failures)
	h.assert_eq((lg["entries"] as Array).size(), 2, "追加后 entries=2 条", failures)

	# 同键链连续 → ok
	var ok_res: Dictionary = ledger.first_chain_break(lg["entries"])
	h.assert_true(ok_res["ok"], "同键连续链 first_chain_break ok", failures)

	# 构造断链：改同键第二条 before，使其 ≠ 前条 after
	var e3 := {"turn": 1, "actor": "player", "event": "damage", "card": "c2",
		"field": "hp", "target": "enemy_hero", "before": 99, "after": 90, "formula": "99-9"}
	ledger.append(lg, e3)
	var brk: Dictionary = ledger.first_chain_break(lg["entries"])
	h.assert_true(not brk["ok"], "断链报 ok=false", failures)
	h.assert_eq(brk["seq"], 3, "断链 seq 指向后一条（=3）", failures)
	h.assert_eq(brk["target"], "enemy_hero", "断链报 target", failures)
	h.assert_eq(brk["field"], "hp", "断链报 field", failures)
	h.assert_eq(brk["expected"], 24, "expected=前条 after", failures)
	h.assert_eq(brk["actual"], 99, "actual=本条 before", failures)

	# 异键（不同 field）不参与同一链：前条 after=27、异 field 首 before=27 之外任意值都不连
	var lg2: Dictionary = ledger.new_ledger()
	ledger.append(lg2, {"turn": 1, "actor": "player", "event": "heal", "card": "c3",
		"field": "hp", "target": "player_hero", "before": 20, "after": 25, "formula": "20+5"})
	ledger.append(lg2, {"turn": 1, "actor": "player", "event": "gain_shield", "card": "c4",
		"field": "shield", "target": "player_hero", "before": 0, "after": 3, "formula": "0+3"})
	var ok2: Dictionary = ledger.first_chain_break(lg2["entries"])
	h.assert_true(ok2["ok"], "异 field 异键各自成链不误报", failures)

	var lg3: Dictionary = ledger.new_ledger()
	ledger.append(lg3, {"turn": 1, "actor": "player", "event": "damage", "card": "c1",
		"field": "hp", "target": "enemy_hero", "before": 30, "after": 27, "formula": "30-3"})
	ledger.append(lg3, {"turn": 2, "actor": "enemy", "event": "damage", "card": "c5",
		"field": "hp", "target": "player_hero", "before": 30, "after": 28, "formula": "30-2"})
	var ok3: Dictionary = ledger.first_chain_break(lg3["entries"])
	h.assert_true(ok3["ok"], "异 target 异键各自成链不误报", failures)

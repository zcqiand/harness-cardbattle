extends RefCounted
## 效果解释器套件：damage 直打全键断言 / 穿盾拆两条 / heal 钳 30 / gain_shield /
## buff_attack / draw（无账本条目）与牌库空 pending_loser / 纯函数（入参不被改动）。

const HARNESS_PATH := "res://tests/harness.gd"
const EFFECTS_PATH := "res://scripts/core/effects.gd"
const LEDGER_PATH := "res://scripts/core/ledger.gd"


## 合成最小 state（heroes 双方 hp30/盾0/atk0/energy1、decks/hands 空、
## side_turns {1,1} ⇒ turn=1、active=player、phase=MAIN）。
func _min_state() -> Dictionary:
	return {
		"side_turns": {"player": 1, "enemy": 1},
		"active": "player",
		"phase": "MAIN",
		"heroes": {
			"player_hero": {"hp": 30, "shield": 0, "atk": 0, "energy": 1},
			"enemy_hero": {"hp": 30, "shield": 0, "atk": 0, "energy": 1},
		},
		"decks": {"player": [], "enemy": []},
		"hands": {"player": [], "enemy": []},
		"attack_used": {"player": false, "enemy": false},
		"pending_loser": "",
	}


func _card(cid: String, effects: Array) -> Dictionary:
	return {"id": cid, "name": cid, "cost": 1, "text": "测试卡", "effects": effects}


func run(failures: Array[String]) -> void:
	var h: GDScript = load(HARNESS_PATH)
	var effects: GDScript = load(EFFECTS_PATH)
	var ledger: GDScript = load(LEDGER_PATH)
	if effects == null:
		h.assert_true(false, "effects.gd 加载失败", failures)
		return
	if ledger == null:
		h.assert_true(false, "ledger.gd 加载失败", failures)
		return

	# ── damage 直打：敌 hp 30→27，条目全键断言 ──
	var st := _min_state()
	var lg: Dictionary = ledger.new_ledger()
	var dmg_card := _card("c_dmg", [{"type": "damage", "value": 3, "target": "enemy_hero"}])
	var r1: Dictionary = effects.resolve(st, dmg_card, "player", lg)
	var entries: Array = (r1["ledger"] as Dictionary)["entries"]
	h.assert_eq(entries.size(), 1, "damage 直打产 1 条目", failures)
	if entries.size() == 1:
		var e: Dictionary = entries[0]
		h.assert_eq(e["event"], "play_card", "条目 event=play_card", failures)
		h.assert_eq(e["card"], "c_dmg", "条目 card=卡 id", failures)
		h.assert_eq(e["field"], "hp", "条目 field=hp", failures)
		h.assert_eq(e["target"], "enemy_hero", "条目 target=enemy_hero", failures)
		h.assert_eq(e["before"], 30, "条目 before=30", failures)
		h.assert_eq(e["after"], 27, "条目 after=27", failures)
		h.assert_eq(e["formula"], "damage(3)", "条目 formula=damage(3)", failures)
		h.assert_eq(e["turn"], 1, "条目 turn=side_turns 之和-1", failures)
		h.assert_eq(e["actor"], "player", "条目 actor=player", failures)
		h.assert_eq(e["seq"], 1, "条目 seq=1", failures)
	h.assert_eq((r1["state"]["heroes"] as Dictionary)["enemy_hero"]["hp"], 27,
		"damage 后敌 hp 落 27", failures)
	h.assert_eq(r1["pending_loser"], "", "无判负时 pending_loser 为空串", failures)
	h.assert_eq(r1["state"]["pending_loser"], "", "state.pending_loser 同步为空串", failures)

	# ── damage 5 打盾 3：拆两条（盾 3→0、hp 30→28），formula 同为 damage(5) ──
	var st2 := _min_state()
	(st2["heroes"] as Dictionary)["enemy_hero"]["shield"] = 3
	var dmg5_card := _card("c_dmg5", [{"type": "damage", "value": 5, "target": "enemy_hero"}])
	var r2: Dictionary = effects.resolve(st2, dmg5_card, "player", ledger.new_ledger())
	var entries2: Array = (r2["ledger"] as Dictionary)["entries"]
	h.assert_eq(entries2.size(), 2, "穿盾拆两条目", failures)
	if entries2.size() == 2:
		var se: Dictionary = entries2[0]
		h.assert_eq(se["field"], "shield", "首条 field=shield", failures)
		h.assert_eq(se["before"], 3, "盾条 before=3", failures)
		h.assert_eq(se["after"], 0, "盾条 after=0", failures)
		h.assert_eq(se["formula"], "damage(5)", "盾条 formula=damage(5)", failures)
		var he: Dictionary = entries2[1]
		h.assert_eq(he["field"], "hp", "次条 field=hp", failures)
		h.assert_eq(he["before"], 30, "hp 条 before=30", failures)
		h.assert_eq(he["after"], 28, "hp 条 after=28（余 2 透盾）", failures)
		h.assert_eq(he["formula"], "damage(5)", "hp 条 formula 同为 damage(5)", failures)
	h.assert_eq((r2["state"]["heroes"] as Dictionary)["enemy_hero"]["shield"], 0,
		"穿盾后敌盾归 0", failures)
	h.assert_eq((r2["state"]["heroes"] as Dictionary)["enemy_hero"]["hp"], 28,
		"穿盾后敌 hp 落 28", failures)

	# ── heal 5 自钳：hp 28→30（钳到 30） ──
	var st3 := _min_state()
	(st3["heroes"] as Dictionary)["player_hero"]["hp"] = 28
	var heal_card := _card("c_heal", [{"type": "heal", "value": 5, "target": "player_hero"}])
	var r3: Dictionary = effects.resolve(st3, heal_card, "player", ledger.new_ledger())
	var entries3: Array = (r3["ledger"] as Dictionary)["entries"]
	h.assert_eq(entries3.size(), 1, "heal 产 1 hp 条目", failures)
	if entries3.size() == 1:
		h.assert_eq(entries3[0]["field"], "hp", "heal 条 field=hp", failures)
		h.assert_eq(entries3[0]["before"], 28, "heal 条 before=28", failures)
		h.assert_eq(entries3[0]["after"], 30, "heal 钳到 30", failures)
		h.assert_eq(entries3[0]["formula"], "heal(5)", "heal 条 formula=heal(5)", failures)
	h.assert_eq((r3["state"]["heroes"] as Dictionary)["player_hero"]["hp"], 30,
		"heal 后自方 hp=30", failures)

	# ── gain_shield：盾 0→2 ──
	var r4: Dictionary = effects.resolve(_min_state(),
		_card("c_shield", [{"type": "gain_shield", "value": 2, "target": "player_hero"}]),
		"player", ledger.new_ledger())
	var entries4: Array = (r4["ledger"] as Dictionary)["entries"]
	h.assert_eq(entries4.size(), 1, "gain_shield 产 1 条目", failures)
	if entries4.size() == 1:
		h.assert_eq(entries4[0]["field"], "shield", "gain_shield 条 field=shield", failures)
		h.assert_eq(entries4[0]["after"], 2, "gain_shield 条 after=2", failures)
		h.assert_eq(entries4[0]["formula"], "gain_shield(2)", "gain_shield 条 formula", failures)
	h.assert_eq((r4["state"]["heroes"] as Dictionary)["player_hero"]["shield"], 2,
		"gain_shield 后自方盾=2", failures)

	# ── buff_attack：atk 0→2（永久） ──
	var r5: Dictionary = effects.resolve(_min_state(),
		_card("c_buff", [{"type": "buff_attack", "value": 2, "target": "player_hero"}]),
		"player", ledger.new_ledger())
	var entries5: Array = (r5["ledger"] as Dictionary)["entries"]
	h.assert_eq(entries5.size(), 1, "buff_attack 产 1 条目", failures)
	if entries5.size() == 1:
		h.assert_eq(entries5[0]["field"], "atk", "buff_attack 条 field=atk", failures)
		h.assert_eq(entries5[0]["after"], 2, "buff_attack 条 after=2", failures)
		h.assert_eq(entries5[0]["formula"], "buff_attack(2)", "buff_attack 条 formula", failures)
	h.assert_eq((r5["state"]["heroes"] as Dictionary)["player_hero"]["atk"], 2,
		"buff_attack 后自方 atk=2", failures)

	# ── draw 2：pop 顶部（末尾）入手牌，无账本条目 ──
	var st6 := _min_state()
	(st6["decks"] as Dictionary)["player"] = ["a", "b", "c"]
	var draw_card := _card("c_draw", [{"type": "draw", "value": 2}])
	var r6: Dictionary = effects.resolve(st6, draw_card, "player", ledger.new_ledger())
	h.assert_eq(((r6["state"]["hands"] as Dictionary)["player"] as Array).size(), 2,
		"draw 2 后手牌 +2", failures)
	h.assert_eq(((r6["state"]["decks"] as Dictionary)["player"] as Array).size(), 1,
		"draw 2 后牌库 -2", failures)
	h.assert_eq(((r6["state"]["hands"] as Dictionary)["player"] as Array)[0], "c",
		"牌库顶部=末尾元素先抽（首张=原末尾 c）", failures)
	h.assert_eq(((r6["state"]["decks"] as Dictionary)["player"] as Array)[0], "a",
		"牌库剩底部 a", failures)
	h.assert_eq(((r6["ledger"] as Dictionary)["entries"] as Array).size(), 0,
		"draw 无账本条目", failures)

	# ── pending_loser：牌库空 draw 1 ⇒ pending_loser=player，后续 damage 仍结算 ──
	var st7 := _min_state()
	var combo := _card("c_combo", [
		{"type": "draw", "value": 1},
		{"type": "damage", "value": 2, "target": "enemy_hero"},
	])
	var r7: Dictionary = effects.resolve(st7, combo, "player", ledger.new_ledger())
	h.assert_eq(r7["pending_loser"], "player", "牌库空抽牌 pending_loser=player", failures)
	h.assert_eq(r7["state"]["pending_loser"], "player", "state.pending_loser 同步 player", failures)
	var entries7: Array = (r7["ledger"] as Dictionary)["entries"]
	h.assert_eq(entries7.size(), 1, "draw 判负后其余效果继续（damage 条目仍在）", failures)
	if entries7.size() == 1:
		h.assert_eq(entries7[0]["field"], "hp", "后续 damage 正常落账", failures)
	h.assert_eq((r7["state"]["heroes"] as Dictionary)["enemy_hero"]["hp"], 28,
		"后续 damage 敌 hp 30→28", failures)

	# ── 抽到一半牌库空：停余下抽牌，不误伤已抽 ──
	var st8 := _min_state()
	(st8["decks"] as Dictionary)["player"] = ["only"]
	var r8: Dictionary = effects.resolve(st8, _card("c_draw2", [{"type": "draw", "value": 2}]),
		"player", ledger.new_ledger())
	h.assert_eq(((r8["state"]["hands"] as Dictionary)["player"] as Array).size(), 1,
		"牌库 1 张抽 2：只入手 1 张", failures)
	h.assert_eq(((r8["state"]["decks"] as Dictionary)["player"] as Array).size(), 0,
		"牌库抽空", failures)
	h.assert_eq(r8["pending_loser"], "player", "半途抽空也判 pending_loser", failures)

	# ── 纯函数：resolve 前后原 state/ledger 不被改动（深拷贝对照） ──
	var st9 := _min_state()
	(st9["heroes"] as Dictionary)["enemy_hero"]["shield"] = 3
	(st9["decks"] as Dictionary)["player"] = ["a", "b"]
	var lg9: Dictionary = ledger.new_ledger()
	ledger.append(lg9, {"turn": 1, "actor": "player", "event": "damage", "card": "c0",
		"field": "hp", "target": "enemy_hero", "before": 30, "after": 27, "formula": "30-3"})
	var st9_copy: Dictionary = st9.duplicate(true)
	var lg9_copy: Dictionary = lg9.duplicate(true)
	var combo9 := _card("c_all", [
		{"type": "draw", "value": 1},
		{"type": "damage", "value": 5, "target": "enemy_hero"},
		{"type": "heal", "value": 5, "target": "player_hero"},
		{"type": "gain_shield", "value": 2, "target": "player_hero"},
		{"type": "buff_attack", "value": 1, "target": "player_hero"},
	])
	effects.resolve(st9, combo9, "player", lg9)
	h.assert_true(st9 == st9_copy, "纯函数：原 state 不被改动", failures)
	h.assert_true(lg9 == lg9_copy, "纯函数：原 ledger 不被改动", failures)

extends RefCounted
## 对手（JSON 策略）套件：load_policy 合法件+缺键拒+未知 play_order 拒+未知键拒+
## 负数 attack_min_atk 拒（走 user:// 临时 fixture，不污染 data/）；
## view_for 投影键集（含 attack_available 裁定键）与信息面裁剪（敌侧只有
## hp/shield/手牌张数，无内容键）；decide 三分支各一路（attack 门槛/未用门槛、
## highest_cost 取可出里最贵、lowest_cost 取最便宜、出不起落到 end_turn）。

const HARNESS_PATH := "res://tests/harness.gd"
const OPPONENT_PATH := "res://scripts/core/opponent.gd"
const CARDS_PATH := "res://scripts/core/cards.gd"

const VIEW_KEYS: Array[String] = ["attack_available", "self_hp", "self_shield",
	"self_atk", "self_energy", "self_hand", "self_deck_count",
	"enemy_hp", "enemy_shield", "enemy_hand_size"]


## 写一个策略 fixture 到 user:// 临时区，返回完整路径（load_policy 直接吃）。
func _policy_fixture(name: String, body: String) -> String:
	var path := "user://test_opponent_policies/%s.json" % name
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(body)
	f.close()
	return path


## 手搓最小 game（只含 view_for 读取的键，形状同 effects.gd 头注 state）。
func _game(player_hero: Dictionary, enemy_hero: Dictionary, decks: Dictionary,
		hands: Dictionary, attack_used: Dictionary) -> Dictionary:
	return {"state": {
		"heroes": {"player_hero": player_hero, "enemy_hero": enemy_hero},
		"decks": decks,
		"hands": hands,
		"attack_used": attack_used,
	}}


func run(failures: Array[String]) -> void:
	var h: GDScript = load(HARNESS_PATH)
	var opp: GDScript = load(OPPONENT_PATH)
	var cards: GDScript = load(CARDS_PATH)
	if opp == null:
		h.assert_true(false, "opponent.gd 加载失败", failures)
		return
	if cards == null:
		h.assert_true(false, "cards.gd 加载失败", failures)
		return
	var loaded: Dictionary = cards.load_card_table()
	h.assert_true(loaded["ok"], "卡表加载 ok", failures)
	var table: Dictionary = loaded["table"]

	# ── load_policy：两件真实策略合法 ──
	var r_agg: Dictionary = opp.load_policy("res://data/opponents/aggressive.json")
	h.assert_true(r_agg["ok"], "aggressive.json 合法加载", failures)
	if r_agg["ok"]:
		var agg: Dictionary = r_agg["policy"]
		h.assert_eq(agg["id"], "aggressive", "aggressive id", failures)
		h.assert_eq(agg["play_order"], "highest_cost", "aggressive play_order", failures)
		h.assert_eq(int(agg["attack_min_atk"]), 1, "aggressive attack_min_atk=1", failures)
	var r_greedy: Dictionary = opp.load_policy("res://data/opponents/greedy.json")
	h.assert_true(r_greedy["ok"], "greedy.json 合法加载", failures)
	if r_greedy["ok"]:
		var greedy: Dictionary = r_greedy["policy"]
		h.assert_eq(greedy["id"], "greedy", "greedy id", failures)
		h.assert_eq(greedy["play_order"], "lowest_cost", "greedy play_order", failures)
		h.assert_eq(int(greedy["attack_min_atk"]), 3, "greedy attack_min_atk=3", failures)

	# ── load_policy：拒载族四路 ──
	var r_missing: Dictionary = opp.load_policy("user://test_opponent_policies/不存在.json")
	h.assert_true(not r_missing["ok"], "缺失文件拒载", failures)
	var r_no_key: Dictionary = opp.load_policy(_policy_fixture("no_key",
		'{"id":"x","name":"x","attack_min_atk":1}'))
	h.assert_true(not r_no_key["ok"], "缺 play_order 拒载", failures)
	var r_bad_order: Dictionary = opp.load_policy(_policy_fixture("bad_order",
		'{"id":"x","name":"x","attack_min_atk":1,"play_order":"random_chaos"}'))
	h.assert_true(not r_bad_order["ok"], "未知 play_order 拒载", failures)
	var r_extra_key: Dictionary = opp.load_policy(_policy_fixture("extra_key",
		'{"id":"x","name":"x","attack_min_atk":1,"play_order":"highest_cost","cheat":true}'))
	h.assert_true(not r_extra_key["ok"], "schema 外未知键拒载", failures)
	var r_neg: Dictionary = opp.load_policy(_policy_fixture("neg_atk",
		'{"id":"x","name":"x","attack_min_atk":-1,"play_order":"highest_cost"}'))
	h.assert_true(not r_neg["ok"], "负 attack_min_atk 拒载", failures)

	# ── view_for：投影键集与信息面裁剪 ──
	var game := _game(
		{"hp": 12, "shield": 3, "atk": 2, "energy": 1},
		{"hp": 20, "shield": 0, "atk": 4, "energy": 5},
		{"player": ["a", "b", "c"], "enemy": ["x", "y"]},
		{"player": ["fire_bolt", "iron_skin"],
			"enemy": ["lightning_strike", "meteor_call", "war_banner"]},
		{"player": true, "enemy": false})
	var view: Dictionary = opp.view_for(game, "enemy")
	h.assert_eq(view.keys().size(), VIEW_KEYS.size(), "view 恰 10 键", failures)
	for key in VIEW_KEYS:
		h.assert_true(view.has(key), "view 含键 %s" % key, failures)
	h.assert_true(not view.has("enemy_hand"), "view 无敌方手牌内容键", failures)
	h.assert_true(not view.has("enemy_deck_count"), "view 无敌方牌库键", failures)
	h.assert_eq(view["self_hp"], 20, "view self_hp", failures)
	h.assert_eq(view["self_shield"], 0, "view self_shield", failures)
	h.assert_eq(view["self_atk"], 4, "view self_atk", failures)
	h.assert_eq(view["self_energy"], 5, "view self_energy", failures)
	h.assert_eq(view["self_deck_count"], 2, "view self_deck_count", failures)
	h.assert_eq(view["enemy_hp"], 12, "view enemy_hp", failures)
	h.assert_eq(view["enemy_shield"], 3, "view enemy_shield", failures)
	h.assert_eq(view["enemy_hand_size"], 2, "view enemy_hand_size=张数", failures)
	h.assert_eq(view["attack_available"], true, "view attack_available（未用⇒true）", failures)
	h.assert_eq(view["self_hand"], [
		{"id": "lightning_strike", "cost": 3, "name": "雷击"},
		{"id": "meteor_call", "cost": 5, "name": "陨石术"},
		{"id": "war_banner", "cost": 3, "name": "战旗"},
	], "view self_hand 内容齐（id/cost/name 原序）", failures)
	var view_p: Dictionary = opp.view_for(game, "player")
	h.assert_eq(view_p["attack_available"], false, "view attack_available（已用⇒false）", failures)

	# ── decide ①：attack 未用且过门槛 ⇒ attack ──
	var pol_high: Dictionary = {"id": "t", "name": "t", "attack_min_atk": 1,
		"play_order": "highest_cost"}
	var pol_low: Dictionary = {"id": "t", "name": "t", "attack_min_atk": 1,
		"play_order": "lowest_cost"}
	var pol_greedy: Dictionary = {"id": "t", "name": "t", "attack_min_atk": 3,
		"play_order": "lowest_cost"}
	var atk_view := {
		"attack_available": true, "self_atk": 2, "self_energy": 0,
		"self_hand": [{"id": "minor_mend", "cost": 1, "name": "轻微治疗"}],
	}
	h.assert_eq(opp.decide(atk_view, pol_high, table), {"type": "attack"},
		"①过门槛且未用⇒attack", failures)

	# ── decide ① 门槛：atk 2 < attack_min_atk 3 ⇒ 落 ② 出牌 ──
	var weak_view := {
		"attack_available": true, "self_atk": 2, "self_energy": 5,
		"self_hand": [{"id": "holy_light", "cost": 3, "name": "圣光"}],
	}
	h.assert_eq(opp.decide(weak_view, pol_greedy, table),
		{"type": "play_card", "card": "holy_light"},
		"①atk 低于门槛⇒落②出牌", failures)

	# ── decide ① 未用门槛：attack 已用 ⇒ 落 ② ──
	var used_view := {
		"attack_available": false, "self_atk": 9, "self_energy": 1,
		"self_hand": [{"id": "minor_mend", "cost": 1, "name": "轻微治疗"}],
	}
	h.assert_eq(opp.decide(used_view, pol_high, table),
		{"type": "play_card", "card": "minor_mend"},
		"①attack 已用⇒落②出牌", failures)

	# ── decide ②：highest_cost 取「可出的」里最贵（3 费出不起⇒出 1 费） ──
	var poor_view := {
		"attack_available": false, "self_atk": 0, "self_energy": 2,
		"self_hand": [
			{"id": "minor_mend", "cost": 1, "name": "轻微治疗"},
			{"id": "holy_light", "cost": 3, "name": "圣光"},
		],
	}
	h.assert_eq(opp.decide(poor_view, pol_high, table),
		{"type": "play_card", "card": "minor_mend"},
		"②highest_cost 能量 2 出不起 3 费⇒出 1 费", failures)

	# ── decide ②：能量够时 highest_cost 取最贵 ──
	var rich_view := {
		"attack_available": false, "self_atk": 0, "self_energy": 4,
		"self_hand": [
			{"id": "minor_mend", "cost": 1, "name": "轻微治疗"},
			{"id": "holy_light", "cost": 3, "name": "圣光"},
		],
	}
	h.assert_eq(opp.decide(rich_view, pol_high, table),
		{"type": "play_card", "card": "holy_light"},
		"②highest_cost 能量 4⇒出最贵 3 费", failures)

	# ── decide ②：lowest_cost 取可出里最便宜 ──
	h.assert_eq(opp.decide(rich_view, pol_low, table),
		{"type": "play_card", "card": "minor_mend"},
		"②lowest_cost⇒出最便宜 1 费", failures)

	# ── decide ② tie-break：同费并列取原手牌序在前（手牌序与 id 序相反防
	# 字典序掩盖——war_banner 在前，但 id 序 lightning_strike 在前） ──
	var tie_view := {
		"attack_available": false, "self_atk": 0, "self_energy": 5,
		"self_hand": [
			{"id": "war_banner", "cost": 3, "name": "战旗"},
			{"id": "lightning_strike", "cost": 3, "name": "雷击"},
		],
	}
	h.assert_eq(opp.decide(tie_view, pol_high, table),
		{"type": "play_card", "card": "war_banner"},
		"②同费并列 highest_cost⇒原手牌序在前的 war_banner", failures)
	h.assert_eq(opp.decide(tie_view, pol_low, table),
		{"type": "play_card", "card": "war_banner"},
		"②同费并列 lowest_cost⇒原手牌序在前的 war_banner", failures)

	# ── decide ① 阈值等值：self_atk == attack_min_atk ⇒ attack（≥ 显式锁） ──
	var edge_view := {
		"attack_available": true, "self_atk": 3, "self_energy": 0, "self_hand": [],
	}
	h.assert_eq(opp.decide(edge_view, pol_greedy, table), {"type": "attack"},
		"①atk==attack_min_atk 等值⇒attack", failures)

	# ── decide ② 防御：cost=-1 兜底条目永不可出（跳过不算可付） ──
	var mystery_view := {
		"attack_available": false, "self_atk": 0, "self_energy": 2,
		"self_hand": [
			{"id": "mystery", "cost": -1, "name": ""},
			{"id": "holy_light", "cost": 3, "name": "圣光"},
		],
	}
	h.assert_eq(opp.decide(mystery_view, pol_high, table), {"type": "end_turn"},
		"②cost=-1 条目跳过，不返回其 play_card", failures)

	# ── decide ③：全出不起且 attack 不可 ⇒ end_turn ──
	var stuck_view := {
		"attack_available": false, "self_atk": 0, "self_energy": 2,
		"self_hand": [{"id": "holy_light", "cost": 3, "name": "圣光"}],
	}
	h.assert_eq(opp.decide(stuck_view, pol_high, table), {"type": "end_turn"},
		"③无牌可出且 attack 不可⇒end_turn", failures)
	var empty_view := {
		"attack_available": true, "self_atk": 0, "self_energy": 0, "self_hand": [],
	}
	h.assert_eq(opp.decide(empty_view, pol_high, table), {"type": "end_turn"},
		"③空手牌且 atk 0⇒end_turn", failures)

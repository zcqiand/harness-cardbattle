extends RefCounted
## 端到端对账闭环套件：三牌组 × 两策略 = 6 局全组合（真实模块链 rng→cards→
## ledger→turn_machine→effects→battle→opponent→auditor，无合成件）。
## 每局：deck_player/deck_enemy 取两套不同牌组、seed 逐局固定不同；玩家侧
## aggressive.decide、敌侧 greedy.decide 按 state.active 交替 apply_action 至
## GAME_OVER（帽 500 动作）；断言每局 winner 非 null、turn_count ≤ 60、
## audit ok（runtime_winner 传运行时终局 winner 参与终判对账）。
## 局打不完/卡死/审计红 = 引擎缺陷——修引擎，不放松断言。

const HARNESS_PATH := "res://tests/harness.gd"
const BATTLE_PATH := "res://scripts/core/battle.gd"
const OPPONENT_PATH := "res://scripts/core/opponent.gd"
const CARDS_PATH := "res://scripts/core/cards.gd"
const AUDITOR_PATH := "res://scripts/core/auditor.gd"

const POLICY_PLAYER_PATH := "res://data/opponents/aggressive.json"
const POLICY_ENEMY_PATH := "res://data/opponents/greedy.json"

## 六局全组合：3×2——每局 deck_player 与 deck_enemy 取不同牌组（6 个有序对
## 覆盖 3 牌组全互异配对），seed 逐局固定且互不相同。
const GAME_PLANS: Array[Dictionary] = [
	{"player": "aggro", "enemy": "control", "seed": 101},
	{"player": "control", "enemy": "midrange", "seed": 202},
	{"player": "midrange", "enemy": "aggro", "seed": 303},
	{"player": "aggro", "enemy": "midrange", "seed": 404},
	{"player": "control", "enemy": "aggro", "seed": 505},
	{"player": "midrange", "enemy": "control", "seed": 606},
]

const ACTION_CAP := 500
const TURN_COUNT_CAP := 60


## 牌组 JSON 形状 {"id","name","cards":[...]}，取 cards 数组（同 test_battle 装载法）。
func _load_deck(path: String) -> Array:
	var txt := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(txt)
	return data["cards"]


func run(failures: Array[String]) -> void:
	var h: GDScript = load(HARNESS_PATH)
	var battle: GDScript = load(BATTLE_PATH)
	var opp: GDScript = load(OPPONENT_PATH)
	var cards: GDScript = load(CARDS_PATH)
	var auditor: GDScript = load(AUDITOR_PATH)
	if battle == null or opp == null or cards == null or auditor == null:
		h.assert_true(false, "e2e 核心模块加载失败", failures)
		return
	var loaded: Dictionary = cards.load_card_table()
	h.assert_true(loaded["ok"], "卡表加载 ok", failures)
	if not loaded["ok"]:
		return
	var table: Dictionary = loaded["table"]
	var r_agg: Dictionary = opp.load_policy(POLICY_PLAYER_PATH)
	h.assert_true(r_agg["ok"], "aggressive.json 合法加载", failures)
	if not r_agg["ok"]:
		return
	var r_greedy: Dictionary = opp.load_policy(POLICY_ENEMY_PATH)
	h.assert_true(r_greedy["ok"], "greedy.json 合法加载", failures)
	if not r_greedy["ok"]:
		return
	var player_policy: Dictionary = r_agg["policy"]
	var enemy_policy: Dictionary = r_greedy["policy"]
	var decks: Dictionary = {
		"aggro": _load_deck("res://data/decks/aggro.json"),
		"control": _load_deck("res://data/decks/control.json"),
		"midrange": _load_deck("res://data/decks/midrange.json"),
	}

	for i in GAME_PLANS.size():
		var plan: Dictionary = GAME_PLANS[i]
		var deck_p: Array = decks[plan["player"]]
		var deck_e: Array = decks[plan["enemy"]]
		var seed := int(plan["seed"])
		var tag := "局%d %s vs %s seed=%d" % [i + 1, plan["player"], plan["enemy"], seed]

		var game: Dictionary = battle.start(deck_p, deck_e, seed, table)
		var actions := 0
		while (game["state"] as Dictionary)["phase"] != "GAME_OVER" and actions < ACTION_CAP:
			var side: String = (game["state"] as Dictionary)["active"]
			var view: Dictionary = opp.view_for(game, side)
			var policy: Dictionary = player_policy if side == "player" else enemy_policy
			var action: Dictionary = opp.decide(view, policy, table)
			var res: Dictionary = battle.apply_action(game, action)
			actions += 1
			h.assert_true(res["accepted"], "%s 第 %d 动作 %s 被拒（%s）"
				% [tag, actions, action["type"], res["reason"]], failures)
			if not res["accepted"]:
				break
		var st: Dictionary = game["state"]
		var turns: int = battle.turn_count(game)
		var winner: Variant = st["winner"]
		var audit: Dictionary = auditor.audit(deck_p, deck_e, seed,
			game["action_log"], game["ledger"], table, winner)

		h.assert_true(actions < ACTION_CAP, "%s 在 %d 动作帽内终局（实际 %d）"
			% [tag, ACTION_CAP, actions], failures)
		h.assert_true(winner != null, "%s winner 非 null" % tag, failures)
		h.assert_true(winner == null or winner in ["player", "enemy", "draw"],
			"%s winner 取值合法" % tag, failures)
		h.assert_true(turns <= TURN_COUNT_CAP, "%s turn_count ≤ %d（实际 %d）"
			% [tag, TURN_COUNT_CAP, turns], failures)
		h.assert_true(audit["ok"], "%s audit ok%s" % [tag, _mismatch_note(audit)], failures)
		print("[e2e] %s → winner=%s turns=%d actions=%d audit_ok=%s" %
			[tag, winner, turns, actions, audit["ok"]])


## 审计红时把 first_mismatch 摘要拼进断言 label，便于定位；绿时返回空串。
static func _mismatch_note(audit: Dictionary) -> String:
	if audit["ok"]:
		return ""
	var m: Dictionary = audit["first_mismatch"]
	return "（kind=%s seq=%d）" % [m["kind"], m["seq"]]

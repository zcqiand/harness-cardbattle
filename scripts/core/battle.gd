extends RefCounted
## 战斗引擎：唯一改状态入口。start 造局（channel 洗牌/各抽 3/玩家 refill 落账），
## apply_action 原地推进 game 三件（state/ledger/action_log）——拒绝时三件全不动；
## 终判口径唯一收敛在 _judge（pending_loser 优先、hp 兜底、双方同亡 ⇒ draw）。
## apply_action 内卡表经 cards.load_card_table() 单源直读（签名不带 table，
## 全仓真数据源唯一=data/cards/core_set.json）。

const CARDS_PATH := "res://scripts/core/cards.gd"
const RNG_PATH := "res://scripts/core/rng.gd"
const TM_PATH := "res://scripts/core/turn_machine.gd"
const EFFECTS_PATH := "res://scripts/core/effects.gd"
const LEDGER_PATH := "res://scripts/core/ledger.gd"

const MAX_HP := 30
const START_HAND := 3
const MAX_ENERGY := 10
const TURN_CAP := 30


## 造局：各自 shuffle 牌组副本 → 起手各抽 3（末尾 pop，无账本条目）→
## 玩家初始能量 refill 落账（唯一 1 条）→ state.winner=null 待终判写入。
static func start(deck_player: Array, deck_enemy: Array, seed: int, card_table: Dictionary) -> Dictionary:
	var rng_lib: GDScript = load(RNG_PATH)
	var ledger_lib: GDScript = load(LEDGER_PATH)
	var deck_p: Array = deck_player.duplicate()
	var deck_e: Array = deck_enemy.duplicate()
	rng_lib.for_channel(seed, "shuffle_player").shuffle(deck_p)
	rng_lib.for_channel(seed, "shuffle_enemy").shuffle(deck_e)
	var state: Dictionary = {
		"side_turns": {"player": 1, "enemy": 1},
		"active": "player",
		"phase": "MAIN",
		"heroes": {
			"player_hero": {"hp": MAX_HP, "shield": 0, "atk": 0, "energy": 0},
			"enemy_hero": {"hp": MAX_HP, "shield": 0, "atk": 0, "energy": 0},
		},
		"decks": {"player": deck_p, "enemy": deck_e},
		"hands": {"player": [], "enemy": []},
		"attack_used": {"player": false, "enemy": false},
		"pending_loser": "",
		"winner": null,
	}
	var hands: Dictionary = state["hands"]
	var decks: Dictionary = state["decks"]
	for _i in START_HAND:
		(hands["player"] as Array).append((decks["player"] as Array).pop_back())
		(hands["enemy"] as Array).append((decks["enemy"] as Array).pop_back())
	var ledger: Dictionary = ledger_lib.new_ledger()
	ledger_lib.append(ledger, {"turn": 1, "actor": "player", "event": "turn_start",
		"card": "", "field": "energy", "target": "player_hero",
		"before": 0, "after": 1, "formula": "refill(1)"})
	(state["heroes"] as Dictionary)["player_hero"]["energy"] = 1
	return {"state": state, "ledger": ledger, "action_log": []}


## 决策入口：拒绝三件全不动（所有检查先于一切突变）；接受序按 brief 逐字。
static func apply_action(game: Dictionary, action: Dictionary) -> Dictionary:
	var state: Dictionary = game["state"]
	var event := action["type"] as String
	if state["phase"] == "GAME_OVER":
		return {"accepted": false, "reason": "对局已结束"}
	var gate: Dictionary = load(TM_PATH).can_accept(state["phase"], event)
	if not gate["ok"]:
		return {"accepted": false, "reason": gate["reason"]}
	if event == "play_card":
		return _play_card(game, action)
	if event == "attack":
		return _attack(game)
	if event == "end_turn":
		return _end_turn(game)
	return {"accepted": false, "reason": "未知事件 %s" % event}


## play_card：手牌 → 能量 → 付费条目 → 移出手牌 → effects.resolve（纯变换，
## 换回新 state/ledger）→ 消费返回键 pending_loser → 终判。
static func _play_card(game: Dictionary, action: Dictionary) -> Dictionary:
	var effects_lib: GDScript = load(EFFECTS_PATH)
	var ledger_lib: GDScript = load(LEDGER_PATH)
	var loaded: Dictionary = load(CARDS_PATH).load_card_table()
	if not loaded["ok"]:
		return {"accepted": false, "reason": loaded["error"]}
	var table: Dictionary = loaded["table"]
	var state: Dictionary = game["state"]
	var active: String = state["active"]
	var cid := action["card"] as String
	var hand: Array = (state["hands"] as Dictionary)[active]
	if not hand.has(cid):
		return {"accepted": false, "reason": "手牌中没有 card-%s" % cid}
	var card: Dictionary = table[cid]
	var cost := int(card["cost"])
	var hero: Dictionary = (state["heroes"] as Dictionary)[active + "_hero"]
	var energy := int(hero["energy"])
	if energy < cost:
		return {"accepted": false, "reason": "能量不足：需 %d 现有 %d" % [cost, energy]}
	ledger_lib.append(game["ledger"], {"turn": _turn_no(state), "actor": active,
		"event": "play_card", "card": cid, "field": "energy",
		"target": active + "_hero", "before": energy, "after": energy - cost,
		"formula": "cost(%d)" % cost})
	hero["energy"] = energy - cost
	hand.erase(cid)
	var res: Dictionary = effects_lib.resolve(state, card, active, game["ledger"])
	game["state"] = res["state"]
	game["ledger"] = res["ledger"]
	var pending: String = res["pending_loser"]
	if pending != "":
		(res["state"] as Dictionary)["pending_loser"] = pending
	(game["action_log"] as Array).append({"type": "play_card", "card": cid})
	_judge(res["state"])
	return {"accepted": true, "reason": ""}


## attack：used → atk>0 → action_log 记 attack → 穿盾结算（damage 同款拆条，
## event="attack"、card=""、formula="attack(%d)"）→ attack_used 翻真 → 终判。
static func _attack(game: Dictionary) -> Dictionary:
	var ledger_lib: GDScript = load(LEDGER_PATH)
	var state: Dictionary = game["state"]
	var active: String = state["active"]
	var used: Dictionary = state["attack_used"]
	if used[active]:
		return {"accepted": false, "reason": "attack 本回合已用"}
	var hero: Dictionary = (state["heroes"] as Dictionary)[active + "_hero"]
	var atk := int(hero["atk"])
	if atk <= 0:
		return {"accepted": false, "reason": "attack 需 atk > 0（当前 %d）" % atk}
	var foe := _other(active)
	var foe_hero: Dictionary = (state["heroes"] as Dictionary)[foe + "_hero"]
	(game["action_log"] as Array).append({"type": "attack"})
	var turn := _turn_no(state)
	var shield := int(foe_hero["shield"])
	if shield > 0:
		var to_shield := mini(shield, atk)
		ledger_lib.append(game["ledger"], {"turn": turn, "actor": active,
			"event": "attack", "card": "", "field": "shield",
			"target": foe + "_hero", "before": shield, "after": shield - to_shield,
			"formula": "attack(%d)" % atk})
		foe_hero["shield"] = shield - to_shield
		var remain := atk - to_shield
		if remain > 0:
			_damage_hp(game["ledger"], turn, active, foe, foe_hero, remain, atk)
	else:
		_damage_hp(game["ledger"], turn, active, foe, foe_hero, atk, atk)
	used[active] = true
	_judge(state)
	return {"accepted": true, "reason": ""}


## attack 的 hp 条（盾后余量或无盾全额），formula 一律 attack(全额)。
static func _damage_hp(ledger: Dictionary, turn: int, actor: String, foe: String,
		foe_hero: Dictionary, value: int, atk: int) -> void:
	var hp := int(foe_hero["hp"])
	load(LEDGER_PATH).append(ledger, {"turn": turn, "actor": actor, "event": "attack",
		"card": "", "field": "hp", "target": foe + "_hero",
		"before": hp, "after": hp - value, "formula": "attack(%d)" % atk})
	foe_hero["hp"] = hp - value


## end_turn：action_log 记录 → 终判一次（防回合末忘判，终局则不切侧）→
## 30 帽（切侧前当前侧满帽且局未终 ⇒ draw，不再切侧）→ 切侧自动步：
## side_turns+1 → refill（before=0 不累积，after=min(side_turns,10)）→
## 抽 1（空库 ⇒ pending_loser=进手方）→ MAIN → attack_used 复位 → 终判。
static func _end_turn(game: Dictionary) -> Dictionary:
	var ledger_lib: GDScript = load(LEDGER_PATH)
	var state: Dictionary = game["state"]
	var cur: String = state["active"]
	(game["action_log"] as Array).append({"type": "end_turn"})
	if _judge(state):
		return {"accepted": true, "reason": ""}
	var side_turns: Dictionary = state["side_turns"]
	if int(side_turns[cur]) >= TURN_CAP:
		state["winner"] = "draw"
		state["phase"] = "GAME_OVER"
		return {"accepted": true, "reason": ""}
	var nxt := _other(cur)
	side_turns[nxt] = int(side_turns[nxt]) + 1
	state["active"] = nxt
	state["phase"] = "TURN_START"
	var refill := mini(int(side_turns[nxt]), MAX_ENERGY)
	var hero: Dictionary = (state["heroes"] as Dictionary)[nxt + "_hero"]
	ledger_lib.append(game["ledger"], {"turn": _turn_no(state), "actor": nxt,
		"event": "turn_start", "card": "", "field": "energy",
		"target": nxt + "_hero", "before": 0, "after": refill,
		"formula": "refill(%d)" % refill})
	hero["energy"] = refill
	var deck: Array = (state["decks"] as Dictionary)[nxt]
	if (deck as Array).is_empty():
		state["pending_loser"] = nxt
	else:
		var top: String = (deck as Array).pop_back()
		((state["hands"] as Dictionary)[nxt] as Array).append(top)
	state["phase"] = "MAIN"
	(state["attack_used"] as Dictionary)[nxt] = false
	_judge(state)
	return {"accepted": true, "reason": ""}


## 终判（唯一口径）：pending_loser 优先、hp 兜底；双方同亡 ⇒ draw，单方 ⇒ 对侧胜。
## pending_loser 主形状 String（""/"player"/"enemy"，effects.gd 契约）；
## 兼容 Array（双方 pending 的构造形状，仅测试/审计构造可达）。
## 写入 winner ⇒ phase=GAME_OVER，返回是否终局。
static func _judge(state: Dictionary) -> bool:
	var heroes: Dictionary = state["heroes"]
	var player_lost := int((heroes["player_hero"] as Dictionary)["hp"]) <= 0
	var enemy_lost := int((heroes["enemy_hero"] as Dictionary)["hp"]) <= 0
	var pending: Variant = state.get("pending_loser", "")
	if pending is String:
		if pending == "player":
			player_lost = true
		elif pending == "enemy":
			enemy_lost = true
	elif pending is Array:
		if (pending as Array).has("player"):
			player_lost = true
		if (pending as Array).has("enemy"):
			enemy_lost = true
	var winner: Variant = null
	if player_lost and enemy_lost:
		winner = "draw"
	elif player_lost:
		winner = "enemy"
	elif enemy_lost:
		winner = "player"
	if winner == null:
		return false
	state["winner"] = winner
	state["phase"] = "GAME_OVER"
	return true


## 回合号 = 双方 side_turns 之和 - 1（与账本条目 turn 同源）。
static func turn_count(game: Dictionary) -> int:
	return _turn_no(game["state"])


static func _turn_no(state: Dictionary) -> int:
	var side_turns: Dictionary = state["side_turns"]
	return int(side_turns["player"]) + int(side_turns["enemy"]) - 1


static func _other(side: String) -> String:
	return "enemy" if side == "player" else "player"

extends RefCounted
## 效果解释器（纯变换）：resolve(state, card, actor, ledger) 按卡 effects 顺序逐条结算，
## 返回 {"state", "ledger", "pending_loser"}（pending_loser 同时写进 state，无判负为 ""）。
## 本文件是 state 形状的全仓唯一定义处——battle/auditor/opponent 全消费此形状：
## state = {
##   "side_turns": {"player": 1, "enemy": 1},   # 各自第几个回合（驱动能量）
##   "active": "player" | "enemy",
##   "phase": "TURN_START" | "MAIN" | "TURN_END" | "GAME_OVER",
##   "heroes": {
##     "player_hero": {"hp": 30, "shield": 0, "atk": 0, "energy": 0},
##     "enemy_hero": {...}
##   },
##   "decks": {"player": ["id", ...], "enemy": [...]},   # 顶部=末尾元素（pop_back 出牌序）
##   "hands": {"player": ["id", ...], "enemy": [...]},
##   "attack_used": {"player": false, "enemy": false},
##   "pending_loser": "" | "player" | "enemy",   # 结算途中判负暂记，终判归 battle
## }
## 各效果结算规则：
##   damage(value,target) —— target.shield>0 先盾后血：盾条目+hp 条目（余量透盾），
##     两条 formula 同为 "damage(value)"；盾=0 单 hp 条目。
##   heal(value,target) —— hp 条目，after=min(before+value, 30)。
##   gain_shield(value,target) —— 盾条目。buff_attack(value,target) —— atk 条目（永久）。
##   draw(value) —— actor 牌库 pop（顶部=末尾）入手牌；无账本条目（牌面移动非字段变动）；
##     需抽而牌库空 ⇒ pending_loser=actor 并停余下抽牌，其余效果继续结算。
## 纯函数：不改入参——state 与 ledger 内部 duplicate(true) 后变换，条目 turn =
## side_turns["player"] + side_turns["enemy"] - 1，event 一律 "play_card"。

const LEDGER_PATH := "res://scripts/core/ledger.gd"
const MAX_HP := 30


static func resolve(state: Dictionary, card: Dictionary, actor: String, ledger: Dictionary) -> Dictionary:
	var s: Dictionary = state.duplicate(true)
	var lg: Dictionary = ledger.duplicate(true)
	var ledger_lib: GDScript = load(LEDGER_PATH)
	var side_turns: Dictionary = s["side_turns"]
	var turn: int = side_turns["player"] + side_turns["enemy"] - 1
	var cid := card["id"] as String
	var pending_loser := ""
	for eff_v in (card["effects"] as Array):
		var eff: Dictionary = eff_v
		var etype := eff["type"] as String
		var value := int(eff["value"])
		match etype:
			"damage":
				var target := eff["target"] as String
				var hero: Dictionary = (s["heroes"] as Dictionary)[target]
				var shield: int = hero["shield"]
				if shield > 0:
					var to_shield := mini(shield, value)
					_hero_entry(ledger_lib, lg, turn, actor, cid, "shield", target,
						shield, shield - to_shield, "damage(%d)" % value)
					hero["shield"] = shield - to_shield
					var remain := value - to_shield
					if remain > 0:
						var hp: int = hero["hp"]
						_hero_entry(ledger_lib, lg, turn, actor, cid, "hp", target,
							hp, hp - remain, "damage(%d)" % value)
						hero["hp"] = hp - remain
				else:
					var hp0: int = hero["hp"]
					_hero_entry(ledger_lib, lg, turn, actor, cid, "hp", target,
						hp0, hp0 - value, "damage(%d)" % value)
					hero["hp"] = hp0 - value
			"heal":
				var target2 := eff["target"] as String
				var hero2: Dictionary = (s["heroes"] as Dictionary)[target2]
				var hp2: int = hero2["hp"]
				var after := mini(hp2 + value, MAX_HP)
				_hero_entry(ledger_lib, lg, turn, actor, cid, "hp", target2,
					hp2, after, "heal(%d)" % value)
				hero2["hp"] = after
			"gain_shield":
				var target3 := eff["target"] as String
				var hero3: Dictionary = (s["heroes"] as Dictionary)[target3]
				var sh3: int = hero3["shield"]
				_hero_entry(ledger_lib, lg, turn, actor, cid, "shield", target3,
					sh3, sh3 + value, "gain_shield(%d)" % value)
				hero3["shield"] = sh3 + value
			"buff_attack":
				var target4 := eff["target"] as String
				var hero4: Dictionary = (s["heroes"] as Dictionary)[target4]
				var atk: int = hero4["atk"]
				_hero_entry(ledger_lib, lg, turn, actor, cid, "atk", target4,
					atk, atk + value, "buff_attack(%d)" % value)
				hero4["atk"] = atk + value
			"draw":
				var deck: Array = (s["decks"] as Dictionary)[actor]
				var hand: Array = (s["hands"] as Dictionary)[actor]
				for _i in value:
					if (deck as Array).is_empty():
						pending_loser = actor
						break
					var top: String = (deck as Array).pop_back()
					(hand as Array).append(top)
	if pending_loser != "":
		s["pending_loser"] = pending_loser
	return {"state": s, "ledger": lg, "pending_loser": pending_loser}


## 产一条英雄字段变动账本条目（键全：seq 由 ledger.append 填，其余调用方给全）。
static func _hero_entry(ledger_lib: GDScript, lg: Dictionary, turn: int, actor: String,
		cid: String, field: String, target: String, before: int, after: int,
		formula: String) -> void:
	ledger_lib.append(lg, {"turn": turn, "actor": actor, "event": "play_card",
		"card": cid, "field": field, "target": target,
		"before": before, "after": after, "formula": formula})

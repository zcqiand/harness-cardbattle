extends RefCounted
## 审计器：结算审计即对战的裁判。对局结束时独立重放整局——shadow game 由
## battle.start(同 deck/seed/card_table) 重建，逐条消费 action_log 经
## apply_action 演进（与运行时同一对纯函数作重放内核，但独立演进实例；
## 反自证=不复用运行时 state/ledger 对象，独立性来自分开的演进而非重写规则），
## 再与运行时账本逐条对账。apply_action 自读卡表（cards 单源），audit 的
## card_table 入参只供 start 洗牌/开局链路，两路同源一致。
##
## 对账 diff 顺序（报第一条命中即返）：
##   ①chain-break      —— ledger.first_chain_break 按 turn 分段逐段非 ok
##                        （expected/actual=断点两侧值）。分段原因：battle._end_turn
##                        的 refill 条目 before=0「不累积」是设计形状——能量链
##                        每回合重置，整账本裸跑 first_chain_break 会把每个
##                        有余能过回合的诚实局全打成断链（实测 seed=7 seq 21）；
##                        跨回合连续性（hp 等）由 ② 逐条全等覆盖，不漏抓。
##   ②entry-divergence —— 逐 seq 对比 shadow vs 运行时条目：seq 错位或字段不等
##                        （expected=shadow 条目，actual=运行时条目）
##   ③tail-extra       —— shadow 比 runtime 多出条目（log 多记了没入账的动作；
##                        expected=首个多出条目，actual=null）
##   ④final-state      —— 终局全等：双方 heroes 四字段+winner。运行时终局值从
##                        账本推导（各 (target,field) 键取最后一条 after，未上账
##                        字段取开局缺省）；winner 推导走 battle._judge 本尊
##                        （同一终判纯函数，非重实现）。
## 返回 {"ok": bool, "first_mismatch": null | {"seq": int, "kind": String,
##        "expected": Variant, "actual": Variant}}；④无条目可指，seq=运行时
##        末条 seq（空账本给 0）。
##
## 边界（在册）：④ 的 winner 推导只覆盖 hp 终局形状——牌库枯竭（pending_loser）
## 与 30 回合帽的 draw 在账本里没有 hp≤0 指纹，推导不出 winner；此类对局
## 请以 hp 终局对局审计或在调用面另行对 winner（调用方持有运行时 state 时
## 可自行比对 state.winner 与 shadow 侧）。

const BATTLE_PATH := "res://scripts/core/battle.gd"
const LEDGER_PATH := "res://scripts/core/ledger.gd"

## 英雄四字段对账序（终局全等的比对面）。
const AUDITED_FIELDS: Array[String] = ["hp", "shield", "atk", "energy"]


## 审计入参：双方牌组、种子、运行时 action_log、运行时账本、卡表。
## 纯读取——不改动任何入参（shadow 演进发生在 battle.start 自建的副本上）。
static func audit(deck_player: Array, deck_enemy: Array, seed: int,
		action_log: Array, ledger: Dictionary, card_table: Dictionary) -> Dictionary:
	var battle: GDScript = load(BATTLE_PATH)
	var ledger_lib: GDScript = load(LEDGER_PATH)
	# ① 链连续性（按 turn 分段逐段查——理由见文件头 ① 注）
	var chain: Dictionary = _first_chain_break(ledger_lib, ledger)
	if not chain["ok"]:
		return _reject(int(chain["seq"]), "chain-break", chain["expected"], chain["actual"])
	# 独立重放：shadow game 从 start 重建，逐条消费 action_log。
	# 重放中被拒的动作不特判——账本对不上会在 ②③④ 露形。
	var shadow: Dictionary = battle.start(deck_player, deck_enemy, seed, card_table)
	for action_v in action_log:
		battle.apply_action(shadow, action_v as Dictionary)
	var shadow_entries: Array = (shadow["ledger"] as Dictionary)["entries"]
	var runtime_entries: Array = ledger["entries"]
	# ② 逐 seq 对比（共同前缀段）
	var common: int = mini(shadow_entries.size(), runtime_entries.size())
	for i in common:
		var shadow_entry: Dictionary = shadow_entries[i]
		var runtime_entry: Dictionary = runtime_entries[i]
		if int(shadow_entry["seq"]) != int(runtime_entry["seq"]) \
				or shadow_entry != runtime_entry:
			return _reject(int(runtime_entry["seq"]), "entry-divergence",
				shadow_entry, runtime_entry)
	# ③ shadow 多出条目（runtime 短了：条目被删到尾部 / log 多记动作）
	if shadow_entries.size() > runtime_entries.size():
		var extra: Dictionary = shadow_entries[runtime_entries.size()]
		return _reject(int(extra["seq"]), "tail-extra", extra, null)
	# ④ 终局全等
	return _final_state(battle, shadow["state"], ledger)


static func _reject(seq: int, kind: String, expected: Variant, actual: Variant) -> Dictionary:
	return {"ok": false,
		"first_mismatch": {"seq": seq, "kind": kind, "expected": expected, "actual": actual}}


## ① 链检查：按条目 turn 分段，每段各自跑 ledger.first_chain_break 本尊，
## 任一段断链即返回该断点。段内链=回合一手（refill→costs、穿盾两条、heal
## 段）自洽；段间断链不可能是真篡改的漏检——被改条目若在自己段内断链①抓，
## 否则字段值必变②抓（逐条全等与段划分无关）。
static func _first_chain_break(ledger_lib: GDScript, ledger: Dictionary) -> Dictionary:
	var by_turn: Dictionary = {}
	for e_v in ledger["entries"]:
		var e: Dictionary = e_v
		var turn := int(e["turn"])
		if not by_turn.has(turn):
			by_turn[turn] = []
		(by_turn[turn] as Array).append(e)
	var turns: Array = by_turn.keys()
	turns.sort()
	for turn in turns:
		var seg: Dictionary = ledger_lib.first_chain_break(by_turn[turn])
		if not seg["ok"]:
			return seg
	return {"ok": true}


## ④ 终局全等：heroes 四字段+winner。运行时终局值从账本推导（数据的最后一手），
## winner 用 battle._judge 本尊对推导 heroes 再判（同一终判口径，非重实现）。
## expected=shadow 值，actual=运行时推导值（与 ②③ 同向）。
static func _final_state(battle: GDScript, shadow_state: Dictionary,
		ledger: Dictionary) -> Dictionary:
	var runtime_heroes: Dictionary = _heroes_from_ledger(battle, ledger)
	var judge_probe: Dictionary = {"heroes": runtime_heroes, "pending_loser": ""}
	battle._judge(judge_probe)
	# _judge 在无人判负时不写 winner 键直接返回 false——get 缺省 null 对齐。
	var runtime_winner: Variant = judge_probe.get("winner", null)
	var shadow_heroes: Dictionary = shadow_state["heroes"]
	for side in ["player_hero", "enemy_hero"]:
		var shadow_hero: Dictionary = shadow_heroes[side]
		var runtime_hero: Dictionary = runtime_heroes[side]
		for field in AUDITED_FIELDS:
			if shadow_hero[field] != runtime_hero[field]:
				return _reject(_last_seq(ledger), "final-state",
					shadow_hero[field], runtime_hero[field])
	if shadow_state["winner"] != runtime_winner:
		return _reject(_last_seq(ledger), "final-state",
			shadow_state["winner"], runtime_winner)
	return {"ok": true, "first_mismatch": null}


## 运行时终局 heroes：逐条扫账本，(target,field) 命中英雄字段就取 after
## （append-only ⇒ 最后一条即终值）；未上账字段取开局缺省——hp/shield/atk
## 按 battle.start 开局形状，energy 按「玩家开局 refill(1)、敌 0」契约。
static func _heroes_from_ledger(battle: GDScript, ledger: Dictionary) -> Dictionary:
	var heroes: Dictionary = {
		"player_hero": {"hp": int(battle.MAX_HP), "shield": 0, "atk": 0, "energy": 1},
		"enemy_hero": {"hp": int(battle.MAX_HP), "shield": 0, "atk": 0, "energy": 0},
	}
	for e_v in ledger["entries"]:
		var e: Dictionary = e_v
		var target: String = e["target"]
		if heroes.has(target) and (heroes[target] as Dictionary).has(e["field"]):
			(heroes[target] as Dictionary)[e["field"]] = e["after"]
	return heroes


static func _last_seq(ledger: Dictionary) -> int:
	var entries: Array = ledger["entries"]
	if entries.is_empty():
		return 0
	return int((entries[entries.size() - 1] as Dictionary)["seq"])

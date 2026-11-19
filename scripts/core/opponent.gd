extends RefCounted
## 对手（JSON 策略）：load_policy 从 JSON 读策略（schema 闭集——必填
## id/name/attack_min_atk/play_order，出现 schema 外键=拒载）；view_for 把
## state 投影成信息面裁剪后的只读 view（对手看不见敌方手牌内容，只有张数；
## attack_available=本回合 attack 未用——controller 裁定补充键，decide ①
## 分支据此判断）；decide 按优先级三分支：①attack 未用且过 atk 门槛⇒attack，
## ②按 play_order 排手牌取第一张能量付得起的⇒play_card，③否则 end_turn。
## state 形状唯一定义在 effects.gd 头注；卡表经 cards.load_card_table() 单源直读。

const CARDS_PATH := "res://scripts/core/cards.gd"

const POLICY_KEYS: Array[String] = ["id", "name", "attack_min_atk", "play_order"]
const PLAY_ORDERS: Array[String] = ["highest_cost", "lowest_cost"]


## JSON.parse_string 把数字解析成 float，字面量传入的是 int——两者都收，
## 非整数值（如 1.5）与其它类型一律打回 -1 走拒载分支（cards._as_int 同款）。
static func _as_int(v: Variant) -> int:
	if v is int:
		return v
	if v is float:
		var f := v as float
		if f == floorf(f):
			return int(f)
	return -1


## 加载策略文件：{"ok","policy","error"}。schema 闭集——四个必填键齐全、
## id/name 为字符串、attack_min_atk 为非负整数、play_order 在两枚举内；
## 缺键/多键/类型不符/值非法一律 ok=false。
static func load_policy(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "policy": {}, "error": "策略文件缺失：%s" % path}
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return {"ok": false, "policy": {}, "error": "策略 JSON 解析失败：%s" % path}
	var p: Dictionary = parsed
	for key in POLICY_KEYS:
		if not p.has(key):
			return {"ok": false, "policy": {}, "error": "%s: 缺必填键 %s" % [path, key]}
	for key in (p.keys() as Array):
		if not POLICY_KEYS.has(key):
			return {"ok": false, "policy": {}, "error": "%s: schema 外未知键 %s" % [path, key]}
	if not (p["id"] is String) or not (p["name"] is String):
		return {"ok": false, "policy": {}, "error": "%s: id/name 须为字符串" % path}
	if _as_int(p["attack_min_atk"]) < 0:
		return {"ok": false, "policy": {}, "error": "%s: attack_min_atk 须为非负整数" % path}
	if not (p["play_order"] as String in PLAY_ORDERS):
		return {"ok": false, "policy": {}, "error": "%s: play_order 须为 highest_cost|lowest_cost" % path}
	return {"ok": true, "policy": p, "error": ""}


## 只读投影：self_* 全量（self_hand 逐张 id/cost/name，原序），敌侧只有
## hp/shield/手牌张数——对手看不见敌方手牌内容与牌库。attack_available=
## 本回合 attack 未用（controller 裁定补充键）。卡表直读单源；查无此卡的
## 兜底条目 cost=-1/name=""（正常对局不触达）。
static func view_for(game: Dictionary, side: String) -> Dictionary:
	var state: Dictionary = game["state"]
	var me: Dictionary = (state["heroes"] as Dictionary)[side + "_hero"]
	var foe_side := "enemy" if side == "player" else "player"
	var foe: Dictionary = (state["heroes"] as Dictionary)[foe_side + "_hero"]
	var table: Dictionary = load(CARDS_PATH).load_card_table()["table"]
	var self_hand: Array = []
	for cid in (state["hands"] as Dictionary)[side]:
		var card: Dictionary = table.get(cid, {})
		self_hand.append({"id": cid, "cost": int(card.get("cost", -1)),
			"name": str(card.get("name", ""))})
	return {
		"attack_available": not (state["attack_used"] as Dictionary)[side],
		"self_hp": int(me["hp"]),
		"self_shield": int(me["shield"]),
		"self_atk": int(me["atk"]),
		"self_energy": int(me["energy"]),
		"self_hand": self_hand,
		"self_deck_count": ((state["decks"] as Dictionary)[side] as Array).size(),
		"enemy_hp": int(foe["hp"]),
		"enemy_shield": int(foe["shield"]),
		"enemy_hand_size": ((state["hands"] as Dictionary)[foe_side] as Array).size(),
	}


## 决策（优先级从上到下）：①attack_available 且 self_atk ≥ attack_min_atk
## 且 self_atk>0 ⇒ attack；②按 play_order 排手牌（highest_cost=贵在前，
## lowest_cost=便宜在前），第一张 self_energy 付得起且 cost≥0 的 ⇒
## play_card；③否则 end_turn。花费读 view.self_hand 的 cost；card_table
## 入参保留签名位（未来校验/生成面用），当前不消费。
## 确定性：sort_custom 非稳定排序，cost 并列时比原手牌序 index（先在手里的
## 先出）补全序——同种子⇒同行动不因构建/手牌规模漂移；cost<0（view_for
## 查无此卡的兜底条目）一律跳过，永不可出。
static func decide(view: Dictionary, policy: Dictionary, _card_table: Dictionary) -> Dictionary:
	var atk := int(view["self_atk"])
	if view["attack_available"] and atk > 0 and atk >= int(policy["attack_min_atk"]):
		return {"type": "attack"}
	var hand: Array = view["self_hand"] as Array
	var order: Array = []
	for i in hand.size():
		var card: Dictionary = hand[i]
		order.append({"i": i, "cost": int(card["cost"]), "id": card["id"]})
	var highest := (policy["play_order"] as String) == "highest_cost"
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["cost"] == b["cost"]:
			return int(a["i"]) < int(b["i"])
		return int(a["cost"]) > int(b["cost"]) if highest else int(a["cost"]) < int(b["cost"]))
	var energy := int(view["self_energy"])
	for entry_v in order:
		var entry: Dictionary = entry_v
		if int(entry["cost"]) < 0:
			continue
		if energy >= int(entry["cost"]):
			return {"type": "play_card", "card": entry["id"]}
	return {"type": "end_turn"}

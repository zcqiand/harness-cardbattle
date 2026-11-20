extends RefCounted
## 卡表：单卡校验（validate_card，""=合法否则报 card-<id>: <原因>）与
## 数据卡池加载（load_card_table，任一卡违规⇒整表拒载 ok=false）。

const CARD_TABLE_PATH := "res://data/cards/core_set.json"

const REQUIRED_KEYS: Array[String] = ["id", "name", "cost", "text", "effects"]
const TARGETED_TYPES: Array[String] = ["damage", "heal", "gain_shield", "buff_attack"]
const UNTARGETED_TYPES: Array[String] = ["draw"]
const VALID_TARGETS: Array[String] = ["player_hero", "enemy_hero"]


static func validate_card(card: Dictionary) -> String:
	var cid := str(card.get("id", "?"))
	for key in REQUIRED_KEYS:
		if not card.has(key):
			return "card-%s: 缺必填键 %s" % [cid, key]
	for key in ["id", "name", "text"]:
		if not (card[key] is String):
			return "card-%s: %s 须为字符串" % [cid, key]
	var cost := _as_int(card["cost"])
	if cost < 1 or cost > 5:
		return "card-%s: cost 须为 1-5 的整数" % [cid]
	var effects: Variant = card["effects"]
	if not (effects is Array):
		return "card-%s: effects 须为数组" % [cid]
	for i in (effects as Array).size():
		var err := _validate_effect(cid, i, (effects as Array)[i])
		if err != "":
			return err
	return ""


static func _validate_effect(cid: String, i: int, effect: Variant) -> String:
	if not (effect is Dictionary):
		return "card-%s: effects[%d] 须为对象" % [cid, i]
	var eff: Dictionary = effect
	var type: Variant = eff.get("type")
	if not (type is String):
		return "card-%s: effects[%d] 缺 type" % [cid, i]
	var value := _as_int(eff.get("value"))
	if value <= 0:
		return "card-%s: effects[%d] value 须为正整数" % [cid, i]
	var type_s := type as String
	if type_s in TARGETED_TYPES:
		var target: Variant = eff.get("target")
		if not (target is String) or not (VALID_TARGETS.has(target)):
			return "card-%s: effects[%d] %s target 须为 player_hero|enemy_hero" % [cid, i, type_s]
		return ""
	if type_s in UNTARGETED_TYPES:
		if eff.has("target"):
			return "card-%s: effects[%d] %s 禁 target" % [cid, i, type_s]
		return ""
	return "card-%s: effects[%d] 未知 type %s" % [cid, i, type_s]


## JSON.parse_string 把数字解析成 float，字面量传入的是 int——两者都收，
## 非整数值（如 1.5）与其它类型一律打回 -1 走拒载分支。
# @impl M02.F03.I01
# @impl M04.F01.I01
static func _as_int(v: Variant) -> int:
	if v is int:
		return v
	if v is float:
		var f := v as float
		if f == floorf(f):
			return int(f)
	return -1


static func load_card_table() -> Dictionary:
	if not FileAccess.file_exists(CARD_TABLE_PATH):
		return {"ok": false, "table": {}, "error": "卡表文件缺失：%s" % CARD_TABLE_PATH}
	var txt := FileAccess.get_file_as_string(CARD_TABLE_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return {"ok": false, "table": {}, "error": "卡表 JSON 解析失败：%s" % CARD_TABLE_PATH}
	var cards: Variant = (parsed as Dictionary).get("cards")
	if not (cards is Array):
		return {"ok": false, "table": {}, "error": "卡表缺 cards 数组：%s" % CARD_TABLE_PATH}
	var table := {}
	for card_v in (cards as Array):
		if not (card_v is Dictionary):
			return {"ok": false, "table": {}, "error": "卡表含非对象条目：%s" % CARD_TABLE_PATH}
		var card: Dictionary = card_v
		var err := validate_card(card)
		if err != "":
			return {"ok": false, "table": {}, "error": err}
		var cid := card["id"] as String
		if table.has(cid):
			return {"ok": false, "table": {}, "error": "card-%s: id 重复" % cid}
		table[cid] = card
	return {"ok": true, "table": table, "error": ""}

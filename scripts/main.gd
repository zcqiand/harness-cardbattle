extends Node2D
## 主场景脚本（骨架）：加载卡组 JSON 契约并做形状校验。
## ch11 落回合状态机与效果结算断言；本骨架只证「契约文件可加载、可校验」。

const DECK_PATH := "res://data/cards/starter_deck.json"


func _ready() -> void:
	var deck := load_deck(DECK_PATH)
	if deck.is_empty():
		push_error("卡组加载失败，见上方错误。")
		return
	print("卡组加载成功：%s（%d 张卡）" % [deck["name"], (deck["cards"] as Array).size()])


## 读取并解析卡组契约文件；任何一步失败返回空字典（fail-fast，错误经 push_error 上报）。
func load_deck(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("卡组文件打不开：%s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("卡组契约不是 JSON 对象：%s" % path)
		return {}
	var deck: Dictionary = parsed
	if not is_valid_deck(deck):
		push_error("卡组契约形状不合法：%s" % path)
		return {}
	return deck


## 卡牌规约（骨架版）：必须有 name 与 cards；每张卡有 id/name/cost/attack/health，
## 数值字段为非负数。
func is_valid_deck(deck: Dictionary) -> bool:
	if not deck.has_all(["name", "cards"]):
		return false
	var cards: Variant = deck["cards"]
	if typeof(cards) != TYPE_ARRAY or (cards as Array).is_empty():
		return false
	for card in cards as Array:
		if typeof(card) != TYPE_DICTIONARY:
			return false
		if not (card as Dictionary).has_all(["id", "name", "cost", "attack", "health"]):
			return false
		for key in ["cost", "attack", "health"]:
			var value: Variant = (card as Dictionary)[key]
			if not (value is float or value is int) or (value as float) < 0.0:
				return false
	return true

extends RefCounted
## 卡表套件：合法卡过检 / 三路拒载（缺键/未知 type/负值）/ 数据卡池与牌组加载全绿。

const HARNESS_PATH := "res://tests/harness.gd"
const CARDS_PATH := "res://scripts/core/cards.gd"


func run(failures: Array[String]) -> void:
	var h: GDScript = load(HARNESS_PATH)
	var cards: GDScript = load(CARDS_PATH)
	if cards == null:
		h.assert_true(false, "cards.gd 加载失败", failures)
		return

	var good := {"id": "c1", "name": "打击", "cost": 1, "text": "造成 3 点伤害",
		"effects": [{"type": "damage", "value": 3, "target": "enemy_hero"}]}
	h.assert_eq(cards.validate_card(good), "", "合法卡过检", failures)

	var missing := {"id": "c2", "name": "残卡", "cost": 1, "text": "缺 effects"}
	h.assert_true(cards.validate_card(missing) != "", "缺必填键拒载", failures)

	var unknown := {"id": "c3", "name": "怪卡", "cost": 1, "text": "?",
		"effects": [{"type": "summon", "value": 1, "target": "enemy_hero"}]}
	var msg: String = cards.validate_card(unknown)
	h.assert_true(msg.contains("card-c3"), "未知 type 拒载报卡号", failures)

	var neg := {"id": "c4", "name": "负卡", "cost": 1, "text": "?",
		"effects": [{"type": "heal", "value": 0, "target": "player_hero"}]}
	h.assert_true(cards.validate_card(neg) != "", "value 非正整数拒载", failures)

	var loaded: Dictionary = cards.load_card_table()
	h.assert_true(loaded["ok"], "数据卡池加载 ok（error=%s）" % loaded.get("error", ""), failures)
	h.assert_true(loaded["table"].size() >= 15, "卡池 ≥15 张", failures)
	var dir := DirAccess.open("res://data/decks")
	var deck_files: Array[String] = []
	if dir != null:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".json"):
				deck_files.append("res://data/decks/" + f)
			f = dir.get_next()
	h.assert_true(deck_files.size() >= 3, "内置牌组 ≥3 组", failures)
	for deck_path in deck_files:
		var txt := FileAccess.get_file_as_string(deck_path)
		var data: Variant = JSON.parse_string(txt)
		var ids: Array = data["cards"]
		h.assert_eq(ids.size(), 20, "%s 恰 20 张" % deck_path, failures)
		for cid in ids:
			h.assert_true(loaded["table"].has(cid), "%s 引用未知卡 %s" % [deck_path, cid], failures)

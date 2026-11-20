extends Control
## 菜单屏（Task 11 三态机 menu 态）：牌组选择（读 data/decks/）、对手选择
## （读 data/opponents/，经 opponent.load_policy 校验闸）、种子显示（每进菜单
## 随机一枚，开战即用此种子——审计重放与运行时同源）、开始按钮；
## 底部成绩册最近 10 条（scorebook.recent，追加序尾部原序）。
## 拒载牌组/策略在列表尾部红字报原因，不崩（UI 面宽容）。
## 对手牌组不另设选择器：取扫描序中「下一个与玩家不同」的牌组（确定性），
## 开战前在屏上明示。

signal start_selected(config: Dictionary)

const SCOREBOOK := preload("res://scripts/scorebook.gd")
const OPPONENT := preload("res://scripts/core/opponent.gd")

const DECKS_DIR := "res://data/decks"
const OPPONENTS_DIR := "res://data/opponents"
const RECENT_COUNT := 10

const COL_X := 60.0
const TITLE_Y := 40.0
const DECK_TOP := 130.0
const DECK_STEP := 56.0
const OPP_STEP := 56.0
const CARD_W := 420.0
const CARD_H := 44.0

var _decks: Array[Dictionary] = []
var _deck_rejects: Array[String] = []
var _opponents: Array[Dictionary] = []
var _opponent_rejects: Array[String] = []
var _deck_index := -1
var _opponent_index := -1
var _seed := 0
var _deck_buttons: Array[Button] = []
var _opponent_buttons: Array[Button] = []
var _seed_label: Label = null
var _enemy_deck_label: Label = null
var _start_button: Button = null


## 建整屏。storage 鸭子接口（scorebook 读成绩册）。
# @entry M01.F01.I01
# @entry M01.F01.I02
# @entry M01.F01.I03
# @entry M01.F02.I01
# @entry M01.F02.I02
# @entry M01.F02.I03
# @entry M01.F03.I01
# @impl M04.F01.I02
# @impl M04.F01.I03
func setup(storage) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_seed = randi()

	_label(Vector2(COL_X, TITLE_Y), "harness-cardbattle · 结算审计即对战", 30, Color.WHITE)
	_label(Vector2(COL_X, TITLE_Y + 48.0), "每一个数字都过账，结算页就是审计报告", 16, Color(0.75, 0.78, 0.85))

	_scan_decks()
	_scan_opponents()

	var y := DECK_TOP
	_label(Vector2(COL_X, y), "选你的牌组", 20, Color.WHITE)
	y += 34.0
	for i in _decks.size():
		var deck: Dictionary = _decks[i]
		var btn := _select_button(Vector2(COL_X, y),
			"%s（%d 张）" % [deck["name"], (deck["cards"] as Array).size()])
		btn.pressed.connect(_on_deck_pressed.bind(i))
		_deck_buttons.append(btn)
		y += DECK_STEP
	for j in _deck_rejects.size():
		_label(Vector2(COL_X, y), _deck_rejects[j], 14, Color(0.95, 0.35, 0.35))
		y += 24.0

	y += 16.0
	_label(Vector2(COL_X, y), "选对手策略", 20, Color.WHITE)
	y += 34.0
	for i in _opponents.size():
		var opp: Dictionary = _opponents[i]
		var policy: Dictionary = opp["policy"]
		var btn := _select_button(Vector2(COL_X, y), "%s（attack≥%d · %s）"
			% [policy["name"], int(policy["attack_min_atk"]), policy["play_order"]])
		btn.pressed.connect(_on_opponent_pressed.bind(i))
		_opponent_buttons.append(btn)
		y += OPP_STEP
	for j in _opponent_rejects.size():
		_label(Vector2(COL_X, y), _opponent_rejects[j], 14, Color(0.95, 0.35, 0.35))
		y += 24.0

	# 右列：种子 + 对手牌组 + 开始 + 成绩册。
	var rx := 620.0
	_seed_label = _label(Vector2(rx, DECK_TOP), "种子：%d" % _seed, 20, Color(0.85, 0.85, 0.9))
	_enemy_deck_label = _label(Vector2(rx, DECK_TOP + 36.0), _enemy_deck_text(), 16,
		Color(0.75, 0.78, 0.85))
	_start_button = Button.new()
	_start_button.position = Vector2(rx, DECK_TOP + 76.0)
	_start_button.size = Vector2(240.0, 52.0)
	_start_button.text = "开战"
	_start_button.pressed.connect(_on_start_pressed)
	add_child(_start_button)

	_label(Vector2(rx, DECK_TOP + 150.0), "成绩册 · 最近 %d 条" % RECENT_COUNT, 20, Color.WHITE)
	var lines := _recent_lines(storage)
	var row_y := DECK_TOP + 186.0
	if lines.is_empty():
		_label(Vector2(rx, row_y), "（还没有入档战绩——打完第一局）", 14,
			Color(0.6, 0.63, 0.7))
		row_y += 24.0
	for k in lines.size():
		if row_y > 620.0:
			_label(Vector2(rx, row_y), "…（更早战绩略）", 14, Color(0.6, 0.63, 0.7))
			break
		_label(Vector2(rx, row_y), lines[k], 14, Color(0.8, 0.82, 0.88))
		row_y += 24.0

	_update_selection_marks()
	_update_start_enabled()


## 选中态（冒烟断言口）：当前选中的牌组/对手 id，未选为 ""。
func selection() -> Dictionary:
	var deck_id := ""
	var opponent_id := ""
	if _deck_index >= 0 and _deck_index < _decks.size():
		deck_id = _decks[_deck_index]["id"]
	if _opponent_index >= 0 and _opponent_index < _opponents.size():
		opponent_id = _opponents[_opponent_index]["policy"]["id"]
	return {"deck_id": deck_id, "opponent_id": opponent_id}


## ——内部——

## 扫牌组目录：{"id","name","cards":[非空 id 数组]} 合法出列，否则红字拒载。
func _scan_decks() -> void:
	for path in _scan_json_paths(DECKS_DIR):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			_deck_rejects.append("%s × 拒载（不是 JSON 对象）" % path.get_file())
			continue
		var data: Dictionary = parsed
		var cards: Variant = data.get("cards")
		if not (data.get("id") is String) or not (data.get("name") is String) \
				or not (cards is Array) or (cards as Array).is_empty():
			_deck_rejects.append("%s × 拒载（须 id/name/cards 非空数组）" % path.get_file())
			continue
		_decks.append({"id": data["id"], "name": data["name"], "cards": cards})


## 扫对手目录：过 opponent.load_policy 校验闸，合法出列，拒载红字报原因。
func _scan_opponents() -> void:
	for path in _scan_json_paths(OPPONENTS_DIR):
		var res: Dictionary = OPPONENT.load_policy(path)
		if res["ok"]:
			_opponents.append({"path": path, "policy": res["policy"]})
		else:
			_opponent_rejects.append("%s × 拒载（%s）" % [path.get_file(), res["error"]])


func _scan_json_paths(dir_path: String) -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			paths.append("%s/%s" % [dir_path, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


## 对手牌组：扫描序中第一个 id ≠ 玩家所选的牌组；未选玩家牌组时给第一个。
func _enemy_deck() -> Dictionary:
	var chosen_id := ""
	if _deck_index >= 0 and _deck_index < _decks.size():
		chosen_id = _decks[_deck_index]["id"]
	for deck in _decks:
		if deck["id"] != chosen_id:
			return deck
	return {} if _decks.is_empty() else _decks[0]


func _enemy_deck_text() -> String:
	var deck: Dictionary = _enemy_deck()
	if deck.is_empty():
		return "对手牌组：（无可用牌组）"
	return "对手牌组：%s" % deck["name"]


func _on_deck_pressed(index: int) -> void:
	_deck_index = index
	_update_selection_marks()
	_enemy_deck_label.text = _enemy_deck_text()
	_update_start_enabled()


func _on_opponent_pressed(index: int) -> void:
	_opponent_index = index
	_update_selection_marks()
	_update_start_enabled()


func _update_selection_marks() -> void:
	for i in _deck_buttons.size():
		var selected := i == _deck_index
		_deck_buttons[i].text = "▶ %s" % _decks[i]["name"] if selected else _decks[i]["name"]
		_deck_buttons[i].add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.4) if selected else Color.WHITE)
	for i in _opponent_buttons.size():
		var selected: bool = i == _opponent_index
		var policy: Dictionary = _opponents[i]["policy"]
		_opponent_buttons[i].text = "▶ %s" % policy["name"] if selected else str(policy["name"])
		_opponent_buttons[i].add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.4) if selected else Color.WHITE)


func _update_start_enabled() -> void:
	_start_button.disabled = _deck_index < 0 or _opponent_index < 0


func _on_start_pressed() -> void:
	if _deck_index < 0 or _opponent_index < 0:
		return
	var deck: Dictionary = _decks[_deck_index]
	var enemy: Dictionary = _enemy_deck()
	var opp: Dictionary = _opponents[_opponent_index]
	start_selected.emit({
		"deck_player": (deck["cards"] as Array).duplicate(),
		"deck_player_id": deck["id"],
		"deck_player_name": deck["name"],
		"deck_enemy": (enemy["cards"] as Array).duplicate(),
		"deck_enemy_id": enemy["id"],
		"deck_enemy_name": enemy["name"],
		"opponent_path": opp["path"],
		"opponent_id": opp["policy"]["id"],
		"opponent_name": opp["policy"]["name"],
		"seed": _seed,
	})


## 成绩册最近条目 → 行文本（尾切统一走 scorebook.recent——追加序=最近序的
## 语义只在 scorebook 一处；#N 编号沿用全册全局位次）。
func _recent_lines(storage) -> Array[String]:
	var full_book: Array = SCOREBOOK.load_book(storage)
	var book: Array = SCOREBOOK.recent(full_book, RECENT_COUNT)
	var offset: int = full_book.size() - book.size()
	var lines: Array[String] = []
	for i in book.size():
		var entry: Dictionary = book[i]
		lines.append("#%d seed=%d %s vs %s · T%d · %s · %s" % [offset + i + 1,
			int(entry.get("seed", 0)), entry.get("deck", "?"), entry.get("opponent", "?"),
			int(entry.get("turns", 0)), entry.get("result", "?"),
			entry.get("finished_at", "?")])
	return lines


func _select_button(pos: Vector2, text: String) -> Button:
	var btn := Button.new()
	btn.position = pos
	btn.size = Vector2(CARD_W, CARD_H)
	btn.text = text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(btn)
	return btn


func _label(pos: Vector2, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label

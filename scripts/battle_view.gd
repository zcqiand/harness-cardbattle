extends Control
## 战斗屏（Task 11 三态机 battle 态）：左区双方英雄面板（hp/shield/atk/energy
## 数值条）、手牌按钮列（费+名+效果文本）、attack/end_turn 按钮；右区账本流
## 滚动列表——论点的常驻 UI 面一条不落：每条账本条目一行
## `#seq T{n} {卡名/attack/refill} → {target} {field} {before}→{after} [{formula}]`，
## 最新置顶（钉死方向）。
## HARD RULE：视图只经 battle.apply_action 改局面，绝不直写 state。
## 每按一次玩家 action：apply_action → 若未终局且不在玩家侧，循环
## opponent.decide + apply_action 直到轮到玩家或 GAME_OVER（全同步，无动画
## 时序依赖）→ 刷新视图；终局 emit finished(bundle) 交主态机进 result 态。

signal finished(bundle: Dictionary)

const BATTLE := preload("res://scripts/core/battle.gd")
const OPPONENT := preload("res://scripts/core/opponent.gd")
const CARDS := preload("res://scripts/core/cards.gd")

## 敌方循环保险丝：e2e 已证单局 ≤35 动作，帽只防构造坏数据下的死循环。
const ENEMY_LOOP_CAP := 500

const STAT_FIELDS: Array[String] = ["hp", "shield", "atk", "energy"]
const STAT_NAMES := {"hp": "HP", "shield": "护盾", "atk": "攻击", "energy": "能量"}
const STAT_CAPS := {"hp": 30, "shield": 30, "atk": 30, "energy": 10}
const TARGET_NAMES := {"player_hero": "我方英雄", "enemy_hero": "敌方英雄"}
const SIDE_NAMES := {"player": "你", "enemy": "对手"}

const BAR_MAX_W := 180.0
const PANEL_W := 660.0
const PANEL_H := 140.0
const PLAYER_COLOR := Color(0.65, 0.8, 1.0)
const ENEMY_COLOR := Color(1.0, 0.78, 0.55)

var _config: Dictionary = {}
var _game: Dictionary = {}
var _table: Dictionary = {}
var _policy: Dictionary = {}
var _rendered_count := 0
var _panels := {}  # side → {"labels": {field: Label}, "fills": {field: ColorRect}}
var _name_labels := {}  # side → Label
var _turn_label: Label = null
var _reject_label: Label = null
var _hand_box: VBoxContainer = null
var _attack_button: Button = null
var _end_turn_button: Button = null
var _ledger_box: VBoxContainer = null
var _load_error := ""


## 造局并建屏。config 形状见 menu_view._on_start_pressed。
## 卡表/策略加载失败 fail-fast：屏上红字，不出牌不出局。
func setup(config: Dictionary) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_config = config.duplicate(true)

	var loaded: Dictionary = CARDS.load_card_table()
	if not loaded["ok"]:
		_load_error = loaded["error"]
	var r_policy: Dictionary = OPPONENT.load_policy(config["opponent_path"])
	if not r_policy["ok"]:
		_load_error = r_policy["error"]
	if _load_error == "":
		_table = loaded["table"]
		_policy = r_policy["policy"]
		_game = BATTLE.start(config["deck_player"], config["deck_enemy"],
			int(config["seed"]), _table)

	_build_ui()
	if _load_error != "":
		_reject_label.text = "加载失败：%s" % _load_error
		return
	_rendered_count = 0
	_refresh()


## 终局 bundle（result 态审计入参 + 成绩册条目原料）。账本/行动日志按引用交出
## （Dictionary 是引用类型，视图 queue_free 后数据仍存活）。
func _bundle() -> Dictionary:
	var st: Dictionary = _game["state"]
	return {
		"deck_player": _config["deck_player"],
		"deck_player_id": _config["deck_player_id"],
		"deck_player_name": _config["deck_player_name"],
		"deck_enemy": _config["deck_enemy"],
		"deck_enemy_id": _config["deck_enemy_id"],
		"deck_enemy_name": _config["deck_enemy_name"],
		"opponent_id": _config["opponent_id"],
		"opponent_name": _config["opponent_name"],
		"seed": int(_config["seed"]),
		"card_table": _table,
		"action_log": _game["action_log"],
		"ledger": _game["ledger"],
		"runtime_winner": st["winner"],
		"turns": BATTLE.turn_count(_game),
	}


## ——UI 装配——

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.09, 0.13)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_build_hero_panel(40.0, 24.0, "enemy")
	_build_hero_panel(40.0, 216.0, "player")

	_turn_label = _label(Vector2(40.0, 364.0), "", 18, Color.WHITE)
	_build_hand_area()
	_attack_button = _action_button(Vector2(768.0, 396.0), "attack（攻击）",
		_on_attack_pressed)
	_end_turn_button = _action_button(Vector2(768.0, 448.0), "end_turn（回合结束）",
		_on_end_turn_pressed)
	_reject_label = _label(Vector2(40.0, 584.0), "", 15, Color(0.95, 0.4, 0.4))

	var ledger_title := _label(Vector2(768.0, 24.0), "账本流 · 最新在上", 18, Color(0.85, 0.88, 0.95))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(768.0, 56.0)
	scroll.size = Vector2(356.0, 576.0)
	add_child(scroll)
	_ledger_box = VBoxContainer.new()
	_ledger_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ledger_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_ledger_box)


func _build_hero_panel(x: float, y: float, side: String) -> void:
	var panel := ColorRect.new()
	panel.position = Vector2(x, y)
	panel.size = Vector2(PANEL_W, PANEL_H)
	panel.color = Color(0.13, 0.15, 0.2)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var title := "你 · %s" % _config.get("deck_player_name", "") if side == "player" \
		else "对手 · %s（%s）" % [_config.get("opponent_name", ""), _config.get("deck_enemy_name", "")]
	var name_label := _label(Vector2(x + 16.0, y + 10.0), title, 17, Color.WHITE)
	_name_labels[side] = name_label

	var labels := {}
	var fills := {}
	for i in STAT_FIELDS.size():
		var field := STAT_FIELDS[i]
		var ry := y + 42.0 + 24.0 * i
		var stat_label := _label(Vector2(x + 16.0, ry), "%s 0" % STAT_NAMES[field], 14,
			Color(0.85, 0.87, 0.92))
		var bar_bg := ColorRect.new()
		bar_bg.position = Vector2(x + 110.0, ry + 5.0)
		bar_bg.size = Vector2(BAR_MAX_W, 12.0)
		bar_bg.color = Color(0.22, 0.24, 0.3)
		bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar_bg)
		var fill := ColorRect.new()
		fill.position = bar_bg.position
		fill.size = Vector2(0.0, 12.0)
		fill.color = PLAYER_COLOR if side == "player" else ENEMY_COLOR
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)
		labels[field] = stat_label
		fills[field] = fill
	_panels[side] = {"labels": labels, "fills": fills}


func _build_hand_area() -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40.0, 392.0)
	scroll.size = Vector2(700.0, 182.0)
	add_child(scroll)
	_hand_box = VBoxContainer.new()
	_hand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hand_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_hand_box)


func _action_button(pos: Vector2, text: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.position = pos
	btn.size = Vector2(356.0, 44.0)
	btn.text = text
	btn.pressed.connect(handler)
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


## ——玩家行动入口（唯一三件改局面的按钮路径）——

func _on_card_pressed(cid: String) -> void:
	_player_action({"type": "play_card", "card": cid})


func _on_attack_pressed() -> void:
	_player_action({"type": "attack"})


func _on_end_turn_pressed() -> void:
	_player_action({"type": "end_turn"})


## 玩家 action → 对方循环 → 刷新 → 终局收口。
func _player_action(action: Dictionary) -> void:
	if _load_error != "":
		return
	var res: Dictionary = BATTLE.apply_action(_game, action)
	if not res["accepted"]:
		_reject_label.text = "被拒：%s" % res["reason"]
		return
	_reject_label.text = ""
	_run_enemy_until_player()
	_refresh()
	if (_game["state"] as Dictionary)["phase"] == "GAME_OVER":
		finished.emit(_bundle())


## 对方循环：未终局且不在玩家侧就 decide + apply，全同步。
func _run_enemy_until_player() -> void:
	var steps := 0
	while true:
		var st: Dictionary = _game["state"]
		if st["phase"] == "GAME_OVER" or st["active"] == "player":
			return
		var view: Dictionary = OPPONENT.view_for(_game, "enemy")
		var action: Dictionary = OPPONENT.decide(view, _policy, _table)
		BATTLE.apply_action(_game, action)
		steps += 1
		if steps >= ENEMY_LOOP_CAP:
			push_error("对方循环超帽 %d 步，强制跳出（对局数据可疑）" % ENEMY_LOOP_CAP)
			return


## ——刷新——

func _refresh() -> void:
	var st: Dictionary = _game["state"]
	for side in ["player", "enemy"]:
		_update_hero(side, st)
	_turn_label.text = "回合 %d · %s 行动" % [BATTLE.turn_count(_game),
		SIDE_NAMES[st["active"]]]
	_rebuild_hand(st)
	_append_new_ledger_entries()
	_update_buttons(st)


func _update_hero(side: String, st: Dictionary) -> void:
	var hero: Dictionary = (st["heroes"] as Dictionary)[side + "_hero"]
	var panel: Dictionary = _panels[side]
	for field in STAT_FIELDS:
		var value := int(hero[field])
		(panel["labels"] as Dictionary)[field].text = "%s %d" % [STAT_NAMES[field], value]
		var cap := float(STAT_CAPS[field])
		var ratio: float = clampf(float(value) / cap, 0.0, 1.0)
		((panel["fills"] as Dictionary)[field] as ColorRect).size.x = BAR_MAX_W * ratio


func _rebuild_hand(st: Dictionary) -> void:
	for child in _hand_box.get_children():
		child.queue_free()
	if st["phase"] == "GAME_OVER" or st["active"] != "player":
		return
	var energy := int((st["heroes"] as Dictionary)["player_hero"]["energy"])
	var hand: Array = (st["hands"] as Dictionary)["player"]
	for cid_v in hand:
		var cid := cid_v as String
		var card: Dictionary = _table.get(cid, {})
		var cost := int(card.get("cost", -1))
		var btn := Button.new()
		btn.text = "%d费 %s · %s" % [cost, card.get("name", cid), card.get("text", "")]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 13)
		btn.disabled = cost > energy
		btn.pressed.connect(_on_card_pressed.bind(cid))
		_hand_box.add_child(btn)


func _update_buttons(st: Dictionary) -> void:
	var my_turn: bool = st["phase"] == "MAIN" and st["active"] == "player"
	_attack_button.disabled = not my_turn
	_end_turn_button.disabled = not my_turn


## 账本流：只渲染增量，最新置顶（方向钉死）。条目色随 actor（你=蓝、对手=橙）。
func _append_new_ledger_entries() -> void:
	var entries: Array = (_game["ledger"] as Dictionary)["entries"]
	if entries.size() <= _rendered_count:
		return
	for i in range(_rendered_count, entries.size()):
		var entry: Dictionary = entries[i]
		var line := Label.new()
		line.text = _ledger_line(entry)
		line.add_theme_font_size_override("font_size", 12)
		var color: Color = PLAYER_COLOR if entry["actor"] == "player" else ENEMY_COLOR
		line.add_theme_color_override("font_color", color)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_ledger_box.add_child(line)
		_ledger_box.move_child(line, 0)
	_rendered_count = entries.size()


## 账本条目 → 一行人话：`#seq T{n} {卡名/attack/refill} → {target} {field}
## {before}→{after} [{formula}]`。
func _ledger_line(entry: Dictionary) -> String:
	var what: String = entry["card"]
	if what != "":
		what = str(_table.get(what, {}).get("name", what))
	elif entry["event"] == "attack":
		what = "attack"
	elif entry["event"] == "turn_start":
		what = "refill"
	else:
		what = str(entry["event"])
	var target: String = TARGET_NAMES.get(entry["target"], str(entry["target"]))
	return "#%d T%d %s → %s %s %s→%s [%s]" % [int(entry["seq"]), int(entry["turn"]),
		what, target, entry["field"], entry["before"], entry["after"], entry["formula"]]

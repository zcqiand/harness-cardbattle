extends Control
## 结算屏（Task 11 三态机 result 态）——结算页就是审计报告：
## 独立重放整局（auditor.audit，runtime_winner 入参参与终判对账），
## ok ⇒ 绿字「对账通过 ✓」+ 战果 + 当场入档（scorebook.record，audit.ok
## 前置由本调用侧执行——红局永不入档）；不 ok ⇒ 红字报第一条 mismatch
## （seq/kind/expected/actual）+「成绩拒收不入档」。
## 再来一局（同配置重开）/回菜单 两按钮，信号交主态机。

signal rematch_pressed
signal back_to_menu_pressed

const AUDITOR := preload("res://scripts/core/auditor.gd")
const SCOREBOOK := preload("res://scripts/scorebook.gd")

const OK_COLOR := Color(0.4, 0.9, 0.5)
const BAD_COLOR := Color(0.95, 0.35, 0.35)

var _bundle: Dictionary = {}


## 跑审计并建屏。bundle 形状见 battle_view._bundle。
## storage 鸭子接口（audit ok 时经 scorebook.record 入档）。
func setup(bundle: Dictionary, storage) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_bundle = bundle

	var audit: Dictionary = AUDITOR.audit(bundle["deck_player"], bundle["deck_enemy"],
		int(bundle["seed"]), bundle["action_log"], bundle["ledger"],
		bundle["card_table"], bundle["runtime_winner"])

	_label(Vector2(80.0, 48.0), "结算审计报告", 32, Color.WHITE)
	var result_text := _result_text(str(bundle["runtime_winner"]))
	_label(Vector2(80.0, 104.0), result_text, 22, Color.WHITE)
	_label(Vector2(80.0, 140.0), "你（%s）vs 对手 %s（%s） · 种子 %d · %d 回合 · %d 条账本"
		% [bundle["deck_player_name"], bundle["opponent_name"], bundle["deck_enemy_name"],
		int(bundle["seed"]), int(bundle["turns"]),
		(bundle["ledger"] as Dictionary)["entries"].size()], 15,
		Color(0.8, 0.82, 0.88))

	var verdict_y := 200.0
	if audit["ok"]:
		_label(Vector2(80.0, verdict_y), "对账通过 ✓", 26, OK_COLOR)
		verdict_y += 44.0
		var record_line := "账本链连续 · 逐条目全等 · 终局全等"
		_label(Vector2(80.0, verdict_y), record_line, 14, Color(0.7, 0.85, 0.75))
		verdict_y += 30.0
		var entry := {
			"seed": int(bundle["seed"]),
			"deck": str(bundle["deck_player_id"]),
			"opponent": str(bundle["opponent_id"]),
			"turns": int(bundle["turns"]),
			"result": _result_key(str(bundle["runtime_winner"])),
			"finished_at": Time.get_datetime_string_from_system(true),
		}
		var saved: bool = SCOREBOOK.record(storage, entry)
		_label(Vector2(80.0, verdict_y), "已入档（user://scorebook.json）" if saved
			else "入档失败（写档被拒，本局成绩丢失）", 15,
			Color(0.7, 0.85, 0.75) if saved else Color(1.0, 0.7, 0.4))
	else:
		var mismatch: Dictionary = audit["first_mismatch"]
		_label(Vector2(80.0, verdict_y), "对账失败 — 成绩拒收不入档", 26, BAD_COLOR)
		verdict_y += 46.0
		_label(Vector2(80.0, verdict_y), "首条不一致：seq %d · kind %s"
			% [int(mismatch["seq"]), str(mismatch["kind"])], 17, BAD_COLOR)
		verdict_y += 30.0
		_label(Vector2(80.0, verdict_y), "expected：%s" % JSON.stringify(mismatch["expected"]),
			13, Color(1.0, 0.85, 0.6))
		verdict_y += 24.0
		_label(Vector2(80.0, verdict_y), "actual：%s" % JSON.stringify(mismatch["actual"]),
			13, Color(1.0, 0.6, 0.5))

	_rem_button("再来一局（同配置）", Vector2(80.0, 480.0), rematch_pressed)
	_rem_button("回菜单", Vector2(80.0, 540.0), back_to_menu_pressed)


## ——内部——

## winner → 展示文案（玩家视角）。
func _result_text(winner: String) -> String:
	if winner == "player":
		return "胜利"
	if winner == "enemy":
		return "败北"
	return "平局"


## winner → 成绩册 result 键（"win"/"lose"/"draw"）。
func _result_key(winner: String) -> String:
	if winner == "player":
		return "win"
	if winner == "enemy":
		return "lose"
	return "draw"


func _rem_button(text: String, pos: Vector2, sig: Signal) -> void:
	var btn := Button.new()
	btn.position = pos
	btn.size = Vector2(280.0, 48.0)
	btn.text = text
	btn.pressed.connect(func() -> void: sig.emit())
	add_child(btn)


func _label(pos: Vector2, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label

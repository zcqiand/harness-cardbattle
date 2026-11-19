extends RefCounted
## 战斗引擎套件：start 形状与同种子确定性 / 出牌全链（付费+效果 seq 连续）/
## 拒绝族六路（各断言三件全不动）/ attack 链含穿盾 / 终判口径三边界 /
## 30 回合帽 / 牌库抽空判负 / turn_count。

const HARNESS_PATH := "res://tests/harness.gd"
const BATTLE_PATH := "res://scripts/core/battle.gd"
const CARDS_PATH := "res://scripts/core/cards.gd"
const SEED := 42


func _load_deck(path: String) -> Array:
	var txt := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(txt)
	return data["cards"]


func run(failures: Array[String]) -> void:
	var h: GDScript = load(HARNESS_PATH)
	var battle: GDScript = load(BATTLE_PATH)
	var cards: GDScript = load(CARDS_PATH)
	if battle == null:
		h.assert_true(false, "battle.gd 加载失败", failures)
		return
	if cards == null:
		h.assert_true(false, "cards.gd 加载失败", failures)
		return
	var loaded: Dictionary = cards.load_card_table()
	h.assert_true(loaded["ok"], "卡表加载 ok", failures)
	var table: Dictionary = loaded["table"]
	var deck_p: Array = _load_deck("res://data/decks/aggro.json")
	var deck_e: Array = _load_deck("res://data/decks/control.json")

	# ── start 形状：牌库 17/手牌 3/账本恰 1 条 refill/phase/winner/能量 ──
	var g: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	var st: Dictionary = g["state"]
	h.assert_eq((st["decks"] as Dictionary)["player"].size(), 17, "start 后玩家牌库 17", failures)
	h.assert_eq((st["decks"] as Dictionary)["enemy"].size(), 17, "start 后敌牌库 17", failures)
	h.assert_eq((st["hands"] as Dictionary)["player"].size(), 3, "玩家手牌 3", failures)
	h.assert_eq((st["hands"] as Dictionary)["enemy"].size(), 3, "敌手牌 3", failures)
	var entries: Array = (g["ledger"] as Dictionary)["entries"]
	h.assert_eq(entries.size(), 1, "开局账本恰 1 条", failures)
	if entries.size() == 1:
		var e0: Dictionary = entries[0]
		h.assert_eq(e0["event"], "turn_start", "开局条目 event=turn_start", failures)
		h.assert_eq(e0["card"], "", "开局条目 card=空", failures)
		h.assert_eq(e0["field"], "energy", "开局条目 field=energy", failures)
		h.assert_eq(e0["target"], "player_hero", "开局条目 target=player_hero", failures)
		h.assert_eq(e0["before"], 0, "开局条目 before=0", failures)
		h.assert_eq(e0["after"], 1, "开局条目 after=1", failures)
		h.assert_eq(e0["formula"], "refill(1)", "开局条目 formula=refill(1)", failures)
		h.assert_eq(e0["seq"], 1, "开局条目 seq=1", failures)
	h.assert_eq(st["phase"], "MAIN", "开局 phase=MAIN", failures)
	h.assert_eq(st["winner"], null, "开局 winner=null", failures)
	h.assert_eq(st["active"], "player", "开局 active=player", failures)
	h.assert_eq(st["side_turns"], {"player": 1, "enemy": 1}, "开局 side_turns {1,1}", failures)
	h.assert_eq((st["heroes"] as Dictionary)["player_hero"]["energy"], 1,
		"玩家初始能量 1", failures)
	h.assert_eq(st["attack_used"], {"player": false, "enemy": false},
		"attack_used 双 false", failures)
	h.assert_eq((g["action_log"] as Array).size(), 0, "开局 action_log 空", failures)
	h.assert_eq(battle.turn_count(g), 1, "start 后 turn_count=1", failures)

	# ── 同种子确定性：decks/hands 序列全等 ──
	var g2: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	h.assert_true((g2["state"] as Dictionary)["decks"] == st["decks"],
		"同种子洗牌序列一致", failures)
	h.assert_true((g2["state"] as Dictionary)["hands"] == st["hands"],
		"同种子起手一致", failures)

	# ── 出牌全链：满能量出 fire_bolt，付费条目+伤害条目 seq 连续 ──
	var gp: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	var stp: Dictionary = gp["state"]
	(stp["hands"] as Dictionary)["player"] = ["fire_bolt"]
	(stp["heroes"] as Dictionary)["player_hero"]["energy"] = 10
	var hp_before: int = (stp["heroes"] as Dictionary)["enemy_hero"]["hp"]
	var rp: Dictionary = battle.apply_action(gp, {"type": "play_card", "card": "fire_bolt"})
	h.assert_true(rp["accepted"], "出伤卡 accepted", failures)
	h.assert_eq(rp["reason"], "", "接受时 reason 空", failures)
	var entries_p: Array = (gp["ledger"] as Dictionary)["entries"]
	h.assert_eq(entries_p.size(), 3, "出牌后账本 3 条（开局+付费+伤害）", failures)
	if entries_p.size() == 3:
		var cost_e: Dictionary = entries_p[1]
		h.assert_eq(cost_e["seq"], 2, "付费条目 seq=2", failures)
		h.assert_eq(cost_e["event"], "play_card", "付费条目 event=play_card", failures)
		h.assert_eq(cost_e["card"], "fire_bolt", "付费条目 card=卡 id", failures)
		h.assert_eq(cost_e["field"], "energy", "付费条目 field=energy", failures)
		h.assert_eq(cost_e["target"], "player_hero", "付费条目 target=己方英雄", failures)
		h.assert_eq(cost_e["before"], 10, "付费条目 before=10", failures)
		h.assert_eq(cost_e["after"], 9, "付费条目 after=9", failures)
		h.assert_eq(cost_e["formula"], "cost(1)", "付费条目 formula=cost(1)", failures)
		var dmg_e: Dictionary = entries_p[2]
		h.assert_eq(dmg_e["seq"], 3, "伤害条目 seq=3（与付费连续）", failures)
		h.assert_eq(dmg_e["field"], "hp", "伤害条目 field=hp", failures)
		h.assert_eq(dmg_e["target"], "enemy_hero", "伤害条目 target=enemy_hero", failures)
		h.assert_eq(dmg_e["before"], hp_before, "伤害条目 before=原 hp", failures)
		h.assert_eq(dmg_e["after"], hp_before - 3, "伤害条目 after=hp-3", failures)
		h.assert_eq(dmg_e["formula"], "damage(3)", "伤害条目 formula=damage(3)", failures)
	var stp2: Dictionary = gp["state"]
	h.assert_eq((stp2["heroes"] as Dictionary)["enemy_hero"]["hp"], hp_before - 3,
		"终判后敌方 hp 减少", failures)
	h.assert_eq((stp2["heroes"] as Dictionary)["player_hero"]["energy"], 9,
		"付费后能量 9", failures)
	h.assert_true(not ((stp2["hands"] as Dictionary)["player"] as Array).has("fire_bolt"),
		"出牌后移出手牌", failures)
	h.assert_eq((gp["action_log"] as Array).size(), 1, "action_log 增一条", failures)
	h.assert_eq((gp["action_log"] as Array)[0], {"type": "play_card", "card": "fire_bolt"},
		"action_log play_card 条目形状", failures)

	# ── 拒绝族六路：各断言 accepted=false、reason 非空、三件全不动 ──
	# ① GAME_OVER 后行动（三类全拒，reason 逐字）
	var gr: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	(gr["state"] as Dictionary)["phase"] = "GAME_OVER"
	var before_r: Dictionary = gr.duplicate(true)
	for act in [{"type": "play_card", "card": "fire_bolt"}, {"type": "attack"}, {"type": "end_turn"}]:
		var rr: Dictionary = battle.apply_action(gr, act)
		h.assert_true(not rr["accepted"], "GAME_OVER 拒 %s" % act["type"], failures)
		h.assert_eq(rr["reason"], "对局已结束", "GAME_OVER 拒 %s reason 逐字" % act["type"], failures)
	h.assert_true(gr == before_r, "GAME_OVER 拒绝三件全不动", failures)

	# ② 手牌无此卡
	var gb: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	var before_b: Dictionary = gb.duplicate(true)
	var rb: Dictionary = battle.apply_action(gb, {"type": "play_card", "card": "no_such"})
	h.assert_true(not rb["accepted"], "手牌无此卡拒绝", failures)
	h.assert_true(rb["reason"] != "", "手牌无此卡 reason 非空", failures)
	h.assert_eq(rb["reason"], "手牌中没有 card-no_such", "手牌无此卡 reason 逐字", failures)
	h.assert_true(gb == before_b, "手牌无此卡拒绝三件全不动", failures)

	# ③ 能量不足
	var gc: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	(gc["state"] as Dictionary)["hands"]["player"] = ["meteor_call"]
	(gc["state"] as Dictionary)["heroes"]["player_hero"]["energy"] = 1
	var before_c: Dictionary = gc.duplicate(true)
	var rc: Dictionary = battle.apply_action(gc, {"type": "play_card", "card": "meteor_call"})
	h.assert_true(not rc["accepted"], "能量不足拒绝", failures)
	h.assert_eq(rc["reason"], "能量不足：需 5 现有 1", "能量不足 reason 逐字", failures)
	h.assert_true(gc == before_c, "能量不足拒绝三件全不动", failures)

	# ④ 重复 attack（先接受一次，再拒第二次；顺带断言无盾 attack 条目）
	var gd: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	(gd["state"] as Dictionary)["heroes"]["player_hero"]["atk"] = 3
	h.assert_true(battle.apply_action(gd, {"type": "attack"})["accepted"],
		"首次 attack 接受", failures)
	var ent_d: Array = (gd["ledger"] as Dictionary)["entries"]
	h.assert_eq(ent_d[ent_d.size() - 1]["formula"], "attack(3)", "无盾 attack 条 formula=attack(3)", failures)
	h.assert_eq(ent_d[ent_d.size() - 1]["after"], 27, "无盾 attack 敌 hp 30→27", failures)
	var before_d: Dictionary = gd.duplicate(true)
	var rd: Dictionary = battle.apply_action(gd, {"type": "attack"})
	h.assert_true(not rd["accepted"], "重复 attack 拒绝", failures)
	h.assert_eq(rd["reason"], "attack 本回合已用", "重复 attack reason 逐字", failures)
	h.assert_true(gd == before_d, "重复 attack 拒绝三件全不动", failures)

	# ⑤ atk=0 时 attack
	var ge: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	var before_e: Dictionary = ge.duplicate(true)
	var re1: Dictionary = battle.apply_action(ge, {"type": "attack"})
	h.assert_true(not re1["accepted"], "atk=0 attack 拒绝", failures)
	h.assert_eq(re1["reason"], "attack 需 atk > 0（当前 0）", "atk=0 reason 逐字", failures)
	h.assert_true(ge == before_e, "atk=0 拒绝三件全不动", failures)

	# ⑥ MAIN 外 end_turn（透传 turn_machine reason）
	var gf: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	(gf["state"] as Dictionary)["phase"] = "TURN_START"
	var before_f: Dictionary = gf.duplicate(true)
	var rf: Dictionary = battle.apply_action(gf, {"type": "end_turn"})
	h.assert_true(not rf["accepted"], "TURN_START 拒 end_turn", failures)
	h.assert_eq(rf["reason"], "TURN_START 不接受事件 end_turn",
		"MAIN 外 end_turn 透传流转表 reason", failures)
	h.assert_true(gf == before_f, "TURN_START 拒绝三件全不动", failures)

	# ── attack 链：atk=3 穿盾 2，拆两条 formula 同 attack(3) ──
	var ga: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	var sta: Dictionary = ga["state"]
	(sta["heroes"] as Dictionary)["player_hero"]["atk"] = 3
	(sta["heroes"] as Dictionary)["enemy_hero"]["shield"] = 2
	var n_a: int = ((ga["ledger"] as Dictionary)["entries"] as Array).size()
	var ra: Dictionary = battle.apply_action(ga, {"type": "attack"})
	h.assert_true(ra["accepted"], "attack 穿盾接受", failures)
	var ent_a: Array = (ga["ledger"] as Dictionary)["entries"]
	h.assert_eq(ent_a.size(), n_a + 2, "attack 穿盾拆两条", failures)
	if ent_a.size() == n_a + 2:
		var se_a: Dictionary = ent_a[n_a]
		h.assert_eq(se_a["event"], "attack", "attack 条目 event=attack", failures)
		h.assert_eq(se_a["card"], "", "attack 条目 card=空", failures)
		h.assert_eq(se_a["field"], "shield", "盾条 field=shield", failures)
		h.assert_eq(se_a["target"], "enemy_hero", "盾条 target=enemy_hero", failures)
		h.assert_eq(se_a["before"], 2, "盾条 before=2", failures)
		h.assert_eq(se_a["after"], 0, "盾条 after=0", failures)
		h.assert_eq(se_a["formula"], "attack(3)", "盾条 formula=attack(3)", failures)
		var he_a: Dictionary = ent_a[n_a + 1]
		h.assert_eq(he_a["field"], "hp", "hp 条 field=hp", failures)
		h.assert_eq(he_a["before"], 30, "hp 条 before=30", failures)
		h.assert_eq(he_a["after"], 29, "hp 条 after=29（余 1 透盾）", failures)
		h.assert_eq(he_a["formula"], "attack(3)", "hp 条 formula=attack(3)", failures)
	h.assert_true((ga["state"] as Dictionary)["attack_used"]["player"],
		"attack_used 翻真", failures)
	h.assert_eq((ga["state"] as Dictionary)["heroes"]["enemy_hero"]["hp"], 29,
		"attack 后敌 hp 29", failures)
	h.assert_eq((ga["action_log"] as Array)[ga["action_log"].size() - 1], {"type": "attack"},
		"action_log 记 attack", failures)
	h.assert_true(not battle.apply_action(ga, {"type": "attack"})["accepted"],
		"attack 后再 attack 被拒", failures)

	# ── 边界局①：敌牌库+手牌清空，end_turn 触发敌抽空 ⇒ winner=先手侧 ──
	var gdry: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	(gdry["state"] as Dictionary)["decks"]["enemy"] = []
	(gdry["state"] as Dictionary)["hands"]["enemy"] = []
	var rdry: Dictionary = battle.apply_action(gdry, {"type": "end_turn"})
	h.assert_true(rdry["accepted"], "敌空库 end_turn 接受", failures)
	h.assert_eq((gdry["state"] as Dictionary)["pending_loser"], "enemy",
		"抽空 pending_loser=enemy", failures)
	h.assert_eq((gdry["state"] as Dictionary)["winner"], "player",
		"敌抽空判负 winner=先手侧", failures)
	h.assert_eq((gdry["state"] as Dictionary)["phase"], "GAME_OVER", "终局 phase=GAME_OVER", failures)

	# ── 边界局②：双方同归零 ⇒ draw（hp 路与 pending 双方形状路） ──
	var gd0: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	(gd0["state"] as Dictionary)["heroes"]["player_hero"]["hp"] = 0
	(gd0["state"] as Dictionary)["heroes"]["enemy_hero"]["hp"] = 0
	battle.apply_action(gd0, {"type": "end_turn"})
	h.assert_eq((gd0["state"] as Dictionary)["winner"], "draw", "双方 hp 归零 draw", failures)
	h.assert_eq((gd0["state"] as Dictionary)["phase"], "GAME_OVER", "draw 也终局", failures)
	h.assert_eq((gd0["state"] as Dictionary)["active"], "player", "终局不再切侧", failures)

	var gdb: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	(gdb["state"] as Dictionary)["pending_loser"] = ["player", "enemy"]
	battle.apply_action(gdb, {"type": "end_turn"})
	h.assert_eq((gdb["state"] as Dictionary)["winner"], "draw",
		"pending 双方形状 draw", failures)

	# 单方归零 ⇒ 对侧胜（end_turn 首步终判兜住）
	var g1: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	(g1["state"] as Dictionary)["heroes"]["enemy_hero"]["hp"] = 0
	battle.apply_action(g1, {"type": "end_turn"})
	h.assert_eq((g1["state"] as Dictionary)["winner"], "player", "单方归零对侧胜", failures)
	h.assert_eq((g1["state"] as Dictionary)["active"], "player", "单方判负不切侧", failures)

	# ── 边界局③：30 回合帽 ──
	var gc30: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	(gc30["state"] as Dictionary)["side_turns"] = {"player": 30, "enemy": 30}
	battle.apply_action(gc30, {"type": "end_turn"})
	h.assert_eq((gc30["state"] as Dictionary)["winner"], "draw", "30 帽 draw", failures)
	h.assert_eq((gc30["state"] as Dictionary)["phase"], "GAME_OVER", "30 帽终局", failures)
	h.assert_eq((gc30["state"] as Dictionary)["side_turns"], {"player": 30, "enemy": 30},
		"30 帽不切侧", failures)

	var g29: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	(g29["state"] as Dictionary)["side_turns"] = {"player": 29, "enemy": 1}
	battle.apply_action(g29, {"type": "end_turn"})
	h.assert_eq((g29["state"] as Dictionary)["winner"], null, "29 帽不触发", failures)
	h.assert_eq((g29["state"] as Dictionary)["active"], "enemy", "29 帽正常切侧", failures)
	h.assert_eq(battle.turn_count(g29), 30, "29+2 切侧后 turn_count=30", failures)

	# ── end_turn 完整自动步：切侧/side_turns/refill 记真前值/抽 1/复位/落账 ──
	var gt: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	var stt: Dictionary = gt["state"]
	(stt["heroes"] as Dictionary)["enemy_hero"]["energy"] = 15
	var enemy_deck_n: int = (stt["decks"] as Dictionary)["enemy"].size()
	var rt: Dictionary = battle.apply_action(gt, {"type": "end_turn"})
	h.assert_true(rt["accepted"], "end_turn 接受", failures)
	h.assert_eq(stt["active"], "enemy", "切侧到 enemy", failures)
	h.assert_eq(stt["phase"], "MAIN", "自动步后 MAIN", failures)
	h.assert_eq(stt["side_turns"], {"player": 1, "enemy": 2}, "enemy side_turns=2", failures)
	h.assert_eq((stt["heroes"] as Dictionary)["enemy_hero"]["energy"], 2,
		"能量 refill=2（真前值 15 落账后归 2）", failures)
	h.assert_eq((stt["decks"] as Dictionary)["enemy"].size(), enemy_deck_n - 1,
		"自动步抽 1", failures)
	h.assert_eq((stt["hands"] as Dictionary)["enemy"].size(), 4, "敌手牌 3→4", failures)
	h.assert_eq(stt["attack_used"], {"player": false, "enemy": false},
		"attack_used 对侧复位", failures)
	h.assert_eq((gt["action_log"] as Array)[gt["action_log"].size() - 1], {"type": "end_turn"},
		"action_log 记 end_turn", failures)
	var ent_t: Array = (gt["ledger"] as Dictionary)["entries"]
	h.assert_eq(ent_t.size(), 2, "end_turn 落 1 条 refill 账", failures)
	if ent_t.size() == 2:
		var rf_t: Dictionary = ent_t[1]
		h.assert_eq(rf_t["seq"], 2, "refill 条 seq=2", failures)
		h.assert_eq(rf_t["event"], "turn_start", "refill 条 event=turn_start", failures)
		h.assert_eq(rf_t["actor"], "enemy", "refill 条 actor=enemy", failures)
		h.assert_eq(rf_t["card"], "", "refill 条 card=空", failures)
		h.assert_eq(rf_t["target"], "enemy_hero", "refill 条 target=enemy_hero", failures)
		h.assert_eq(rf_t["before"], 15, "refill 条 before=真前值（本侧能量现值 15）", failures)
		h.assert_eq(rf_t["after"], 2, "refill 条 after=min(2,10)=2", failures)
		h.assert_eq(rf_t["formula"], "refill(2)", "refill 条 formula=refill(2)", failures)
	h.assert_eq(battle.turn_count(gt), 2, "end_turn 后 turn_count=2", failures)

	# 第二次 end_turn 切回 player，turn_count=3
	battle.apply_action(gt, {"type": "end_turn"})
	h.assert_eq(battle.turn_count(gt), 3, "再 end_turn turn_count=3", failures)
	h.assert_eq(stt["active"], "player", "切回 player", failures)

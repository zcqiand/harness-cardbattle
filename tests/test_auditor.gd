extends RefCounted
## 审计器套件：真卡池+真策略打满一整局（双方各走 opponent.decide，防呆帽
## ACTION_CAP）→ 绿局 audit 全等（ok=true / first_mismatch==null）+ 入参三件
## 不被 audit 触碰（快照全等）；极短局（end_turn×2 未终局）audit ok；
## 篡改四路各抓：改末条 after ⇒ entry-divergence（钉死）；删中段条 ⇒ ok=false
## + 删末条 ⇒ tail-extra（③ 正名形状，钉死）；append 假条目（before 硬伤）⇒
## chain-break；删 action_log 末条重交 ⇒ ok=false（kind 不钉死，按 brief 只断
## ok=false）；append 无操作假条目（before=after=链头现值，①链/②前缀/④终局
## 全过得过的隐形形）⇒ tail-extra（③ 双向，runtime 侧多出，钉死）。
## seed=7 为 _work/probe_seed.gd 实测选点：aggro(player,aggressive) vs
## control(enemy,greedy) 31 动作 48 条目、敌方 hp 归零终局。
## 链检查口径=全局 first_chain_break 一次（refill 已改记真实前值——battle
## 同批修复，链跨回合全局成立，无需分段容忍）；winner 对账走 runtime_winner
## 第 7 参（传对值 ok/传错值 final-state，账本无 winner 指纹，由调用方供给）。

const HARNESS_PATH := "res://tests/harness.gd"
const AUDITOR_PATH := "res://scripts/core/auditor.gd"
const BATTLE_PATH := "res://scripts/core/battle.gd"
const OPPONENT_PATH := "res://scripts/core/opponent.gd"
const CARDS_PATH := "res://scripts/core/cards.gd"
const LEDGER_PATH := "res://scripts/core/ledger.gd"
const SEED := 7
const ACTION_CAP := 500


func _load_deck(path: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (parsed as Dictionary)["cards"]


## 真局驱动：当前 active 侧的 view → decide → apply_action，直到 GAME_OVER
## 或防呆帽。返回 game 三件（state/ledger/action_log）。
func _play_full_game(battle: GDScript, opp: GDScript, agg: Dictionary,
		greedy: Dictionary, deck_p: Array, deck_e: Array,
		table: Dictionary) -> Dictionary:
	var game: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	var actions := 0
	while (game["state"] as Dictionary)["phase"] != "GAME_OVER" and actions < ACTION_CAP:
		var active: String = (game["state"] as Dictionary)["active"]
		var policy: Dictionary = agg if active == "player" else greedy
		var view: Dictionary = opp.view_for(game, active)
		battle.apply_action(game, opp.decide(view, policy, table))
		actions += 1
	return game


var completed := false


func run(failures: Array[String]) -> void:
	var h: GDScript = load(HARNESS_PATH)
	var auditor: GDScript = load(AUDITOR_PATH)
	var battle: GDScript = load(BATTLE_PATH)
	var opp: GDScript = load(OPPONENT_PATH)
	var ledger_lib: GDScript = load(LEDGER_PATH)
	if auditor == null:
		h.assert_true(false, "auditor.gd 加载失败", failures)
		return
	if battle == null:
		h.assert_true(false, "battle.gd 加载失败", failures)
		return
	if opp == null:
		h.assert_true(false, "opponent.gd 加载失败", failures)
		return
	if ledger_lib == null:
		h.assert_true(false, "ledger.gd 加载失败", failures)
		return
	var table: Dictionary = load(CARDS_PATH).load_card_table()["table"]
	var deck_p: Array = _load_deck("res://data/decks/aggro.json")
	var deck_e: Array = _load_deck("res://data/decks/control.json")
	var r_agg: Dictionary = opp.load_policy("res://data/opponents/aggressive.json")
	var r_greedy: Dictionary = opp.load_policy("res://data/opponents/greedy.json")
	h.assert_true(r_agg["ok"] and r_greedy["ok"], "两策略加载 ok", failures)
	if not (r_agg["ok"] and r_greedy["ok"]):
		return
	var agg: Dictionary = r_agg["policy"]
	var greedy: Dictionary = r_greedy["policy"]

	# ── 绿局：真卡池真策略打满局 → audit 全等 ──
	var game: Dictionary = _play_full_game(battle, opp, agg, greedy, deck_p, deck_e, table)
	var st: Dictionary = game["state"]
	h.assert_eq(st["phase"], "GAME_OVER", "整局打到 GAME_OVER", failures)
	h.assert_eq(st["winner"], "player", "seed=7 玩家胜（probe 实测）", failures)
	var log: Array = game["action_log"]
	h.assert_true(log.size() > 0 and log.size() < ACTION_CAP,
		"动作数在 1..%d 之间（实得 %d）" % [ACTION_CAP, log.size()], failures)
	var entries: Array = (game["ledger"] as Dictionary)["entries"]
	h.assert_true(entries.size() > log.size(),
		"账本条目多于动作数（play_card 一动多条；%d 条 vs %d 动）" % [entries.size(), log.size()],
		failures)
	var snapshot: Dictionary = game.duplicate(true)
	var res: Dictionary = auditor.audit(deck_p, deck_e, SEED, log,
		game["ledger"], table)
	h.assert_true(res["ok"], "绿局 audit ok", failures)
	h.assert_true(res["first_mismatch"] == null, "绿局 first_mismatch==null", failures)
	h.assert_true(game == snapshot, "audit 不动入参（三件快照全等）", failures)

	# ── 极短局：end_turn×2 未终局 → audit ok ──
	var short_game: Dictionary = battle.start(deck_p, deck_e, SEED, table)
	h.assert_true(battle.apply_action(short_game, {"type": "end_turn"})["accepted"],
		"短局 end_turn ① accepted", failures)
	h.assert_true(battle.apply_action(short_game, {"type": "end_turn"})["accepted"],
		"短局 end_turn ② accepted", failures)
	h.assert_eq((short_game["state"] as Dictionary)["phase"], "MAIN",
		"两动后局未终（回到玩家 MAIN）", failures)
	var res_short: Dictionary = auditor.audit(deck_p, deck_e, SEED,
		short_game["action_log"], short_game["ledger"], table)
	h.assert_true(res_short["ok"], "极短局 audit ok", failures)
	h.assert_true(res_short["first_mismatch"] == null, "极短局 first_mismatch==null", failures)

	# ── 篡改一路：改末条 after ⇒ entry-divergence（kind 钉死） ──
	var t1: Dictionary = (game["ledger"] as Dictionary).duplicate(true)
	var last: Dictionary = ((t1["entries"] as Array)[entries.size() - 1]) as Dictionary
	var true_after: Variant = last["after"]
	last["after"] = int(true_after) + 1
	var res1: Dictionary = auditor.audit(deck_p, deck_e, SEED, log, t1, table)
	h.assert_true(not res1["ok"], "改 after ⇒ ok=false", failures)
	var m1: Dictionary = res1["first_mismatch"]
	h.assert_eq(m1["kind"], "entry-divergence", "改 after ⇒ kind=entry-divergence", failures)
	h.assert_eq(int(m1["seq"]), int(last["seq"]), "改 after ⇒ seq=被改条", failures)
	h.assert_eq(m1["actual"], last, "改 after ⇒ actual=被改运行时条", failures)

	# ── 篡改二路：删中段一条 ⇒ ok=false（kind 不钉死）；删末条 ⇒ tail-extra
	#（shadow 比 runtime 长一段前缀外条目，③ 的正名形状，钉死） ──
	var t2: Dictionary = (game["ledger"] as Dictionary).duplicate(true)
	(t2["entries"] as Array).remove_at(entries.size() / 2)
	var res2: Dictionary = auditor.audit(deck_p, deck_e, SEED, log, t2, table)
	h.assert_true(not res2["ok"], "删中段条 ⇒ ok=false", failures)
	h.assert_true(res2["first_mismatch"] != null, "删中段条 ⇒ 有 first_mismatch", failures)
	var t2b: Dictionary = (game["ledger"] as Dictionary).duplicate(true)
	(t2b["entries"] as Array).remove_at(entries.size() - 1)
	var res2b: Dictionary = auditor.audit(deck_p, deck_e, SEED, log, t2b, table)
	h.assert_true(not res2b["ok"], "删末条 ⇒ ok=false", failures)
	var m2b: Dictionary = res2b["first_mismatch"]
	h.assert_eq(m2b["kind"], "tail-extra", "删末条 ⇒ kind=tail-extra", failures)
	h.assert_eq(int(m2b["seq"]), entries.size(), "删末条 ⇒ seq=shadow 首个多出条", failures)

	# ── 篡改三路：append 假条目 ⇒ ok=false（kind 不钉死）。假条目造 before
	# 硬伤（比真实末条 before 少 5）——段内同键相邻必断链，① 抓 ──
	var t3: Dictionary = (game["ledger"] as Dictionary).duplicate(true)
	var fake: Dictionary = (entries[entries.size() - 1] as Dictionary).duplicate()
	fake["before"] = int(fake["before"]) - 5
	ledger_lib.append(t3, fake)
	h.assert_eq((t3["entries"] as Array).size(), entries.size() + 1,
		"假条目已入账（%d→%d 条）" % [entries.size(), entries.size() + 1], failures)
	var res3: Dictionary = auditor.audit(deck_p, deck_e, SEED, log, t3, table)
	h.assert_true(not res3["ok"], "append 假条目 ⇒ ok=false", failures)
	h.assert_true(res3["first_mismatch"] != null, "append 假条目 ⇒ 有 first_mismatch", failures)
	h.assert_eq(res3["first_mismatch"]["kind"], "chain-break",
		"append 假条目（before 硬伤）⇒ 全局断链 kind=chain-break", failures)

	# ── 篡改四路：删 action_log 末条重交 ⇒ ok=false（kind 不钉死：
	# 终局 heroes/winner 从 ledger 推导 vs shadow 少一步演进，final-state 形） ──
	var log4: Array = (log as Array).duplicate(true)
	(log4 as Array).remove_at(log4.size() - 1)
	var res4: Dictionary = auditor.audit(deck_p, deck_e, SEED, log4,
		game["ledger"], table)
	h.assert_true(not res4["ok"], "删 log 末条 ⇒ ok=false", failures)
	h.assert_true(res4["first_mismatch"] != null, "删 log 末条 ⇒ 有 first_mismatch", failures)

	# ── 篡改五路：append 无操作假条目（before=after=链头现值——①链连续、
	# ②共同前缀全等、④终局推导不变，「隐形」形）⇒ runtime 比 shadow 多条
	# ⇒ tail-extra（③ 双向：expected=null（无 shadow 对手条目），
	# actual=首个多出条目=假条目） ──
	var t5: Dictionary = (game["ledger"] as Dictionary).duplicate(true)
	var noop: Dictionary = (entries[entries.size() - 1] as Dictionary).duplicate()
	noop["before"] = noop["after"]
	ledger_lib.append(t5, noop)
	h.assert_eq((t5["entries"] as Array).size(), entries.size() + 1,
		"无操作假条目已入账（%d→%d 条）" % [entries.size(), entries.size() + 1], failures)
	var res5: Dictionary = auditor.audit(deck_p, deck_e, SEED, log, t5, table)
	h.assert_true(not res5["ok"], "append 无操作假条目 ⇒ ok=false", failures)
	var m5: Dictionary = res5["first_mismatch"]
	h.assert_eq(m5["kind"], "tail-extra", "无操作假条目 ⇒ kind=tail-extra（runtime 侧多出）", failures)
	h.assert_eq(int(m5["seq"]), int(noop["seq"]), "无操作假条目 ⇒ seq=假条目", failures)
	h.assert_eq(m5["actual"], noop, "无操作假条目 ⇒ actual=假条目", failures)
	h.assert_true(m5["expected"] == null, "无操作假条目 ⇒ expected=null（无 shadow 对手条目）", failures)

	# ── runtime_winner 第 7 参：传对值 ⇒ ok；传错值 ⇒ ok=false kind=final-state
	#（expected=shadow winner，actual=runtime_winner） ──
	var res_w_ok: Dictionary = auditor.audit(deck_p, deck_e, SEED, log,
		game["ledger"], table, "player")
	h.assert_true(res_w_ok["ok"], "runtime_winner 传对值 ⇒ ok", failures)
	var res_w_bad: Dictionary = auditor.audit(deck_p, deck_e, SEED, log,
		game["ledger"], table, "enemy")
	h.assert_true(not res_w_bad["ok"], "runtime_winner 传错值 ⇒ ok=false", failures)
	var mw: Dictionary = res_w_bad["first_mismatch"]
	h.assert_eq(mw["kind"], "final-state", "runtime_winner 错值 ⇒ kind=final-state", failures)
	h.assert_eq(mw["expected"], "player", "runtime_winner 错值 ⇒ expected=shadow winner", failures)
	h.assert_eq(mw["actual"], "enemy", "runtime_winner 错值 ⇒ actual=runtime_winner", failures)
	completed = true

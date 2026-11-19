# Settlement Audit Cardbattle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完整可玩 1v1 卡牌对战，突出点=结算审计即对战：每笔数值变动落编号账本，局末审计器从零重算对账，全等才入档。

**Architecture:** 结算核心（scripts/core/，纯函数 Dictionary 进出，无节点依赖）与表现层（scripts/ 视图 + scenes/）分离；审计器只消费核心层输入（牌组+种子+行动日志+卡表）独立重算。headless 自建 runner 测试（jumper 同款）。

**Tech Stack:** Godot 4.7 stable + GDScript，零三方依赖，mulberry32 手写。

**Spec:** docs/superpowers/specs/2026-11-19-settlement-audit-cardbattle-design.md（同仓 specs/，实现者须同读）

## Global Constraints

- Godot 4.7 stable；GDScript 4.x 兼容语法（禁 `is not`）；GDScript 缩进用 **TAB**。
- 零三方依赖；RNG=mulberry32 手写；npm/docker 镜像等本仓不涉及。
- 测试命令（exit code 唯一真相）：`"D:/qiand-life/3-resources/8-ego/software/godot/Godot_v4.7-stable_win64_console.exe" --headless --path . --script res://tests/test_runner.gd`
- runner 合同：自动发现 `res://tests/test_*.gd`（排除自身），逐个 `run(failures)`；套件 0 checks=红；零套件=红；全绿 `ALL PASS (N suites, M checks)` quit(0)。harness 静态断言 `assert_true/assert_eq`，`count` 静态计数（runner 每套件清零）。
- 账本 field 枚举一次定死：`hp` / `shield` / `atk` / `energy`——四字段全部变动必入账本，无豁免面。
- action_log 只含三类决策：`{"type":"play_card","card":id}` / `{"type":"attack"}` / `{"type":"end_turn"}`；抽牌是后果不是决策（引擎按种子派生，不进日志）。
- 数值规则：hp 上限/初始 30；shield 先盾后血、跨回合保留、无上限；atk 初始 0、buff 永久到局终；能量=min(本方 side_turns,10)、不累积；卡费 1-5；先手玩家、开局各抽 3、先手第 1 回合不抽；牌库 20 张/组；一次决策全部效果结算完才判 GAME_OVER（致命伤不打断剩余效果，溢出照记）；需抽而牌库空⇒该方判负；任一侧 side_turns 达 30 且局未终⇒平局。
- 效果类型枚举：`damage` / `heal`（超上限钳到 30） / `gain_shield` / `buff_attack`（永久） / `draw`；target 枚举：`player_hero` / `enemy_hero`（draw 无 target）。
- commit 尾注逐字 `Co-Authored-By: Claude Code <noreply@anthropic.com>`；逐文件 add，禁 `git add -A`。
- 过程件进 `_work/`（整目录 gitignore，仓根已有）；正式区不留调试脚本。
- 核心模块全部静态函数风格（`extends RefCounted`，Dictionary 进出，`load("res://scripts/core/x.gd")` 取用），不注册 class_name、不挂节点——审计器与测试同走这套纯函数面。

## Review Focus

1. **账本篡改四路**（改一条 after / 删一条 / 加一条 / 改终局 HP）——期望：审计器逐路必抓，报第一条 mismatch 的 seq/kind。钉子：test_auditor 四路篡改用例（T8）。
2. **非法事件**（错状态出牌 / 重复 attack / atk=0 时 attack / 能量不足出牌 / 对局结束后行动）——期望：拒绝+原因字符串，不改状态不落账。钉子：test_turn_machine 流转拒绝（T4）+ test_battle 合法性拒绝（T6）。
3. **非法卡牌 JSON**（缺必填键 / 未知效果 type / value 非正整数）——期望：该卡拒载，报 `card-<id>: ...` 形状原因，卡表加载失败不崩。钉子：test_cards 三路拒载（T2）。
4. **边界局**（牌库抽空判负 / 双方同归零平局 / 30 side-turns 平局）——期望：winner 有界且审计重放同口径。钉子：test_battle 边界用例（T6）+ test_end_to_end 重放（T10）。
5. **坏档读入**（成绩册损坏 JSON / 顶层非数组 / 条目非 Dictionary）——期望：一律空册或跳过坏条目，不抛错。钉子：test_scorebook 读侧 guard（T9）。

---

### Task 1: 测试 runner + harness + 种子化 RNG

**Files:**
- Create: `tests/test_runner.gd`、`tests/harness.gd`（从 `../harness-jumper/tests/` 同名文件**逐字照抄**，只删 .uid 侧车——Godot 首次导入自动生成）
- Create: `scripts/core/rng.gd`
- Test: `tests/test_rng.gd`

**Interfaces:**
- Produces: runner/harness 全仓测试基座；`Rng.for_channel(seed: int, channel: String) -> RefCounted`、`next_int(bound: int) -> int`（[0,bound)）、`shuffle(arr: Array) -> void`（Fisher-Yates 原地）。
- channel 派生规则（全仓唯一）：`for_channel(seed, channel)` = `script.new(seed ^ channel.hash())`。channel 名常量（后续任务引用，逐字）：`"shuffle_player"` / `"shuffle_enemy"`。

- [ ] **Step 1: 照抄 runner 与 harness**

从 `../harness-jumper/tests/test_runner.gd` 与 `tests/harness.gd` 逐字复制到本仓 `tests/`（实现机制已在源文件注释里，含 0-checks 哨兵与零套件哨兵；勿改动逻辑）。

- [ ] **Step 2: 写失败测试 tests/test_rng.gd**

```gdscript
extends RefCounted
## RNG 套件：同种子同序列 / 不同种子不同序列 / channel 隔离（同种子异 channel 互异）/ shuffle 全同重排。

const HARNESS_PATH := "res://tests/harness.gd"
const RNG_PATH := "res://scripts/core/rng.gd"


func run(failures: Array[String]) -> void:
	var h: GDScript = load(HARNESS_PATH)
	var rng_s: GDScript = load(RNG_PATH)
	if rng_s == null:
		h.assert_true(false, "rng.gd 加载失败", failures)
		return

	var a = rng_s.for_channel(42, "shuffle_player")
	var b = rng_s.for_channel(42, "shuffle_player")
	var seq_a: Array[int] = []
	var seq_b: Array[int] = []
	for i in 8:
		seq_a.append(a.next_int(100))
		seq_b.append(b.next_int(100))
	h.assert_eq(seq_a, seq_b, "同种子同 channel 序列全等", failures)

	var c = rng_s.for_channel(42, "shuffle_enemy")
	h.assert_true(a_seq_needs(seq_a, c, 100), "同种子异 channel 序列互异", failures)

	var base := [1, 2, 3, 4, 5, 6, 7, 8]
	var r = rng_s.for_channel(7, "shuffle_player")
	var once := base.duplicate()
	r.shuffle(once)
	var r2 = rng_s.for_channel(7, "shuffle_player")
	var twice := base.duplicate()
	r2.shuffle(twice)
	h.assert_eq(once, twice, "同种子 shuffle 结果可复现", failures)
	h.assert_eq(once.size(), 8, "shuffle 不增删元素", failures)
	var sorted_once := once.duplicate()
	sorted_once.sort()
	h.assert_eq(sorted_once, base, "shuffle 是重排不是改值", failures)


static func a_seq_needs(seq: Array, other, bound: int) -> bool:
	for i in seq.size():
		if seq[i] != other.next_int(bound):
			return true
	return false
```

- [ ] **Step 3: 跑测试验证失败**

Run: 测试命令（见 Global Constraints）
Expected: FAIL（rng.gd 加载失败）

- [ ] **Step 4: 实现 scripts/core/rng.gd**

`extends RefCounted`；mulberry32 步进（JS 参考实现照抄成 GDScript，`Math.imul` 用 `(a * b) & 0xFFFFFFFF` 替代、每步 `& 0xFFFFFFFF` 收敛）；`next_int(bound)` = `int(next_float() * bound)` 再钳 `bound-1`。

- [ ] **Step 5: 跑测试验证通过**；**Step 6: Commit**

```bash
git add tests/test_runner.gd tests/harness.gd scripts/core/rng.gd tests/test_rng.gd
git commit -m "feat(core): headless runner+ harness 与种子化 mulberry32 RNG（channel 分流）"
```

---

### Task 2: 卡表加载与效果断言拒载 + 数据卡池

**Files:**
- Create: `scripts/core/cards.gd`、`data/cards/core_set.json`、`data/decks/aggro.json`、`data/decks/control.json`、`data/decks/midrange.json`
- Delete: `data/cards/starter_deck.json`（骨架占位，被正式卡池/牌组替代）
- Test: `tests/test_cards.gd`

**Interfaces:**
- Produces: `validate_card(card: Dictionary) -> String`（""=合法，否则 `"card-<id>: <原因>"`）；`load_card_table() -> Dictionary`（读 `data/cards/core_set.json`，`{"ok": bool, "table": {id: card}, "error": String}`）。
- 卡 schema：必填键 `id`(str)/`name`(str)/`cost`(int 1-5)/`text`(str)/`effects`(Array)；效果描述符 schema：`damage|heal|gain_shield|buff_attack` 必填 `value`(正整数)+`target`(`player_hero|enemy_hero`)；`draw` 必填 `value`、禁 target；未知 type 拒载。任一违规 ⇒ 该卡不入表，error 报 `card-<id>: effects[<i>] <原因>`。
- 数据约束：卡池 15-20 张，四机制（直伤/治疗+盾/buff/抽牌）各有 ≥2 张；每牌组恰好 20 张卡 id（可重复）、引用的 id 全在卡池。

- [ ] **Step 1: 写失败测试 tests/test_cards.gd**（合成卡直测 validate_card，不碰数据文件；数据文件另测加载 ok）

```gdscript
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
```

- [ ] **Step 2: 跑测试验证失败**（cards.gd 加载失败）；**Step 3: 实现 cards.gd**（校验函数逐条对照 schema；load_card_table 用 FileAccess+JSON.parse_string，坏 JSON⇒ok=false）。
- [ ] **Step 4: 写数据文件**（core_set.json `{"cards":[...]}`；三牌组 20 张/组、风格分化：aggro 直伤+buff、control 盾+治疗、midrange 均衡+抽牌；删除 starter_deck.json）。
- [ ] **Step 5: 跑测试验证通过**；**Step 6: Commit**

```bash
git add tests/test_cards.gd scripts/core/cards.gd data/cards/core_set.json data/decks/aggro.json data/decks/control.json data/decks/midrange.json
git rm data/cards/starter_deck.json
git commit -m "feat(core): 卡表加载+效果断言拒载与 16 张数据卡池三牌组"
```

---

### Task 3: 账本

**Files:**
- Create: `scripts/core/ledger.gd`
- Test: `tests/test_ledger.gd`

**Interfaces:**
- Produces: `new_ledger() -> Dictionary`（`{"entries": [], "next_seq": 1}`）；`append(ledger: Dictionary, entry: Dictionary) -> int`（填 `seq`=next_seq 自增、追加、返回 seq；entry 其余键由调用方给全：`turn/actor/event/card/field/target/before/after/formula`）；`first_chain_break(entries: Array) -> Dictionary`（按 (target,field) 分键检查 `entries[i].after == entries[i+1].before`，返回 `{"ok": true}` 或 `{"ok": false, "seq": int, "target": str, "field": str, "expected": Variant, "actual": Variant}`）。
- 条目 schema（本文件是全仓唯一定义处，文件头注释写明键集）。

- [ ] **Step 1: 写失败测试**——断言：append 返回 1 再 2（seq 自增）；首条目被填 seq；两条同键链连续 first_chain_break ok；构造断链（同键第二条 before≠前条 after）报 `ok=false` 且 seq 指向后一条、expected/actual 为两侧值；异键（不同 target 或 field）不参与同一链。
- [ ] **Step 2: 跑失败**（ledger.gd 加载失败）；**Step 3: 实现 ledger.gd**；**Step 4: 跑通过**；**Step 5: Commit**

```bash
git add tests/test_ledger.gd scripts/core/ledger.gd
git commit -m "feat(core): append-only 账本（seq 自增+(target,field) 链连续性检查）"
```

---

### Task 4: 回合状态机

**Files:**
- Create: `scripts/core/turn_machine.gd`
- Test: `tests/test_turn_machine.gd`

**Interfaces:**
- Produces: `legal_events() -> Dictionary`——流转表数据本体：`{"TURN_START": [], "MAIN": ["play_card", "attack", "end_turn"], "TURN_END": [], "GAME_OVER": []}`；`can_accept(phase: String, event: String) -> Dictionary`（`{"ok": bool, "reason": String}`；ok 时 reason=""）。
- 拒绝原因逐字：`"%s 不接受事件 %s" % [phase, event]`。

- [ ] **Step 1: 写失败测试**——断言 legal_events 表内容与上逐字全等（规约=数据，直接断言表）；MAIN 接受三类事件各 ok；`can_accept("TURN_START", "play_card")` ok=false 且 reason="TURN_START 不接受事件 play_card"；GAME_OVER 拒绝全部三类。
- [ ] **Step 2: 跑失败**；**Step 3: 实现**（表+查表函数，十行级）；**Step 4: 跑通过**；**Step 5: Commit**

```bash
git add tests/test_turn_machine.gd scripts/core/turn_machine.gd
git commit -m "feat(core): 回合状态机规约（状态+事件+合法流转数据表）"
```

---

### Task 5: 效果解释器（纯变换）

**Files:**
- Create: `scripts/core/effects.gd`
- Test: `tests/test_effects.gd`

**Interfaces:**
- Consumes: ledger（T3 签名）、卡 schema（T2）。
- Produces: `resolve(state: Dictionary, card: Dictionary, actor: String, ledger: Dictionary) -> Dictionary`——返回 `{"state": Dictionary, "ledger": Dictionary, "pending_loser": String}`（pending_loser 同时写进 state）；**纯函数**：不改入参（内部 `state.duplicate(true)` 后变换），效果按 descriptors 顺序逐条结算，产出账本条目键全（`turn=side_turns["player"]+side_turns["enemy"]-1`、actor、event="play_card"、card=id、formula=`"<type>(<value>)"`）。
- 状态形状（全仓唯一定义处，文件头注释；battle/auditor/opponent 全消费此形状）：

```gdscript
# state = {
#   "side_turns": {"player": 1, "enemy": 1},   # 各自第几个回合（驱动能量）
#   "active": "player" | "enemy",
#   "phase": "TURN_START" | "MAIN" | "TURN_END" | "GAME_OVER",
#   "heroes": {
#     "player_hero": {"hp": 30, "shield": 0, "atk": 0, "energy": 0},
#     "enemy_hero": {...}
#   },
#   "decks": {"player": ["id", ...], "enemy": [...]},   # 顶部=末尾元素（pop_back 出牌序）
#   "hands": {"player": ["id", ...], "enemy": [...]},
#   "attack_used": {"player": false, "enemy": false},
#   "pending_loser": "" | "player" | "enemy",   # 结算途中判负暂记，终判归 battle
# }
```

- 各效果结算规则（逐字实现）：`damage(value,target)`——target.shield>0 时先盾：盾条目 `field="shield", before/after=盾损前后`，剩余到 hp 再一条 `field="hp"`，两条 formula 同为 `"damage(value)"`；盾=0 时单 hp 条目。`heal(value,target)`——hp 条目，after=min(before+value, 30)，formula=`"heal(value)"`。`gain_shield(value,target)`——盾条目 formula=`"gain_shield(value)"`。`buff_attack(value,target)`——atk 条目 formula=`"buff_attack(value)"`（永久，无过期条目）。`draw(value)`——从 actor 牌库 pop value 次（顶部=末尾）入手牌；**无账本条目**（抽牌是牌面移动不是英雄字段变动）；需抽而牌库空⇒`pending_loser=actor` 并停止该效果余下抽牌，其余效果继续结算。

- [ ] **Step 1: 写失败测试**——合成最小 state（heroes 双方 hp30/盾0/atk0/energy1、decks/hands 空、side_turns {1,1}、turn 用 state["side_turns"] 读、active=player、phase=MAIN）与合成卡逐类型各一路：damage 打敌（敌 hp 30→27，条目 event/card/field/target/before/after/formula/turn/actor 全断言）；damage 5 打盾 3 敌（两条目：盾 3→0、hp 30→28）；heal 5 自钳（hp 28→30 断言钳到 30）；gain_shield；buff_attack（atk 0→2）；draw 2（hands 增 2、decks 减 2、账本无新条目）；纯函数断言（resolve 前后原 state 字典不被改动——deep copy 对照）；pending_loser（decks 空、draw 1 ⇒ pending_loser="player" 且后续 damage 效果仍结算）。
- [ ] **Step 2: 跑失败**；**Step 3: 实现 effects.gd**；**Step 4: 跑通过**；**Step 5: Commit**

```bash
git add tests/test_effects.gd scripts/core/effects.gd
git commit -m "feat(core): 效果解释器纯变换（五类型结算+穿盾拆条+pending_loser）"
```

---

### Task 6: 战斗引擎

**Files:**
- Create: `scripts/core/battle.gd`
- Test: `tests/test_battle.gd`

**Interfaces:**
- Consumes: rng/cards/turn_machine/effects/ledger 全部签名。
- Produces: `start(deck_player: Array, deck_enemy: Array, seed: int, card_table: Dictionary) -> Dictionary`（返回 `{"state":…, "ledger":…, "action_log": []}`；洗牌=Rng.for_channel(seed,"shuffle_player"/"shuffle_enemy") 各自 shuffle 牌组副本→入 state.decks；开局各抽 3（无条目）；side_turns {player:1, enemy:1}；active=player；phase="MAIN"；玩家初始能量=1 并落账 `{"event":"turn_start","card":"","field":"energy","target":"player_hero","before":0,"after":1,"formula":"refill(1)"}`；attack_used 复位）。
- `apply_action(game: Dictionary, action: Dictionary) -> Dictionary`——返回 `{"accepted": bool, "reason": String}`；接受时原地推进 game（state/ledger/action_log 三件同步），拒绝时三件全不动。action 键 `{"type": "play_card", "card": id}` / `{"type":"attack"}` / `{"type":"end_turn"}`。
- `turn_count(game: Dictionary) -> int` = `side_turns["player"] + side_turns["enemy"] - 1`。

- 合法性与流程（逐字）：
  - 通用：`phase=="GAME_OVER"` ⇒ 拒 `"对局已结束"`；流转表检查（turn_machine.can_accept）不过⇒透传 reason。
  - play_card：手牌无此 id⇒拒 `"手牌中没有 card-%s"`；energy<cost⇒拒 `"能量不足：需 %d 现有 %d"`。接受序：付费条目（formula `"cost(%d)"`，target=己方英雄，event="play_card"，card=id）→ 从手牌移除 → effects.resolve → 终判（见下）。
  - attack：attack_used[active]⇒拒 `"attack 本回合已用"`；己方 atk<=0⇒拒 `"attack 需 atk > 0（当前 %d）"`。接受序：action_log 记 `{"type":"attack"}` → 以己方 atk 对敌方英雄走 damage 同款穿盾结算（条目 event="attack"、card=""、formula `"attack(%d)"`、actor=active）→ attack_used[active]=true → 终判。
  - end_turn：action_log 记录 → 终判一次（防回合末忘判）→ 切 active 到对侧、phase="TURN_START" 自动步：side_turns[对侧]+=1 → 能量 refill 条目（before=0（不累积）… after=min(side_turns,10)，formula `"refill(%d)"`，event="turn_start"，card=""，actor=对侧）→ 抽 1（空库⇒pending_loser=对侧）→ phase="MAIN" → attack_used[对侧]=false → 终判。
  - **终判（每次决策自动步全完后恰好一次）**：pending_loser 非空⇒winner=对侧（双方都 pending⇒draw）；否则双方 hp≤0⇒draw，单方≤0⇒对侧胜；否则无 winner。判终后 phase="GAME_OVER"。win/lose 视角换算由调用侧（UI/测试）按 active/winner 自行解释，battle 只存 `"winner": null|"player"|"enemy"|"draw"`（加在 state）。
  - 30 回合帽：end_turn 切侧前若 `side_turns[active] >= 30` 且局未终⇒winner="draw"、phase="GAME_OVER"（不再切侧）。

- [ ] **Step 1: 写失败测试**——用 T2 数据卡池+三牌组真件：
  - start 形状：decks 各 17（20-3）、hands 各 3、账本恰 1 条（refill）、phase=MAIN、winner=null。
  - 出牌全链：手工造满能量局面（直接改 state.heroes 后调 apply_action——测试允许，审计器 T8 才管重放），出一张真伤卡：accepted、能量条目+伤害条目 seq 连续、action_log 增一条、终判后敌方 hp 减少。
  - 拒绝族：GAME_OVER 后行动 / 手牌无此卡 / 能量不足 / 重复 attack / atk=0 时 attack / MAIN 外 end_turn——各断言 accepted=false、reason 非空、state与ledger与action_log 均不变（前深拷贝对照）。
  - attack 链：直接把己方 atk 改 3 再 attack：条目 formula="attack(3)"、attack_used 翻真、重复 attack 被拒。
  - 边界局：①牌库抽空——把对侧 decks 削到 0 张、hands 清 0、end_turn 两次到对侧 TURN_START 抽空 ⇒ winner=先手侧；②双方同归零——双方 hp 改 1、出直伤双方?（单效果打不了双方，改用 hp 全 1+attack 互击构造，或直接 pending_loser 双方形状调终判路径——允许直接构造 state 验终判函数行为）；③30 帽——side_turns 双方改 30、end_turn ⇒ draw。
  - turn_count：start 后=1，end_turn 后=2。
- [ ] **Step 2: 跑失败**；**Step 3: 实现 battle.gd**；**Step 4: 跑通过**；**Step 5: Commit**

```bash
git add tests/test_battle.gd scripts/core/battle.gd
git commit -m "feat(core): 战斗引擎（合法性拒绝族/attack 链/终判口径/30 帽/牌库判负）"
```

---

### Task 7: 对手（JSON 策略）

**Files:**
- Create: `scripts/core/opponent.gd`、`data/opponents/aggressive.json`、`data/opponents/greedy.json`
- Test: `tests/test_opponent.gd`

**Interfaces:**
- Consumes: battle 的 state 形状。
- Produces: `load_policy(path: String) -> Dictionary`（`{"ok","policy","error"}`；schema：必填 `id`(str)/`name`(str)/`attack_min_atk`(非负整数)/`play_order`("highest_cost"|"lowest_cost")，其余键拒载）；`view_for(game: Dictionary, side: String) -> Dictionary`——只读投影：`{"self_hp","self_shield","self_atk","self_energy","self_hand":[{"id","cost","name"}...],"self_deck_count","enemy_hp","enemy_shield","enemy_hand_size"}`（对手看不见敌方手牌内容——只给张数）；`decide(view: Dictionary, policy: Dictionary, card_table: Dictionary) -> Dictionary`——返回一个 action（同 battle 三形状）。
- decide 规则（逐字，优先级从上到下）：①本回合 attack 未用 且 self_atk ≥ policy.attack_min_atk 且 self_atk>0 ⇒ `{"type":"attack"}`；②按 play_order 排手牌，第一张 energy≥cost 的 ⇒ `{"type":"play_card","card":id}`；③否则 `{"type":"end_turn"}`。

- [ ] **Step 1: 写失败测试**——load_policy 合法件+缺键拒+未知 play_order 拒；view_for 投影断言（self_hand 内容齐、enemy 侧只有 hp/shield/张数、无敌方手牌内容键）；decide 三分支各一路（造 view：atk 2+attack_min_atk 1⇒attack；atk 0+手里有 1 费与 3 费+能量 2+highest_cost⇒出 1 费那张（3 费出不起）…（注：highest_cost 取**可出的**里最贵））；无牌可出且 attack 不可⇒end_turn。
- [ ] **Step 2: 跑失败**；**Step 3: 实现+两个策略文件**（aggressive: attack_min_atk=1/highest_cost；greedy: attack_min_atk=3/lowest_cost）；**Step 4: 跑通过**；**Step 5: Commit**

```bash
git add tests/test_opponent.gd scripts/core/opponent.gd data/opponents/aggressive.json data/opponents/greedy.json
git commit -m "feat(core): 对手接口 decide(view)+JSON 策略两件（信息面投影裁剪）"
```

---

### Task 8: 审计器

**Files:**
- Create: `scripts/core/auditor.gd`
- Test: `tests/test_auditor.gd`

**Interfaces:**
- Consumes: battle.start + apply_action（重放内核——与运行时同一对纯函数，但**独立演进实例**：shadow game 从 start 重建，逐条消费 action_log，跑完得到 shadow_ledger 与 shadow_state）。
- Produces: `audit(deck_player: Array, deck_enemy: Array, seed: int, action_log: Array, ledger: Dictionary, card_table: Dictionary) -> Dictionary`——`{"ok": bool, "first_mismatch": null | {"seq": int, "kind": String, "expected": Variant, "actual": Variant}}`。
- diff 顺序（报第一条命中）：①`chain-break`（ledger.first_chain_break 非_ok——expected/actual=断点两侧值）；②逐 seq 对比 shadow vs 运行时条目：seq 错位或字段不等⇒`entry-divergence`（expected=shadow 条目，actual=运行时条目）；③shadow 多出条目⇒`tail-extra`；④终局不等（双方 heroes 四字段+winner）⇒`final-state`。

- [ ] **Step 1: 写失败测试**——用真卡池牌组打一整局（双方都走 opponent.decide 策略，循环 apply_action 直到 GAME_OVER，防呆帽 500 次动作）：
  - 绿局：audit ok=true、first_mismatch==null。
  - 篡改四路（各 copy 绿局材料后改一处再 audit）：改一条目 after ⇒ entry-divergence；删一条 ⇒ entry-divergence 或 tail-extra（断言 ok=false 即可，kind 不钉死）；append 假条目 ⇒ tail-extra 或 entry-divergence（同前）；改终局 heroes.hp（审计入参的 ledger 改不了终局——改法：构造 action_log 与账本不一致的局：直接删 action_log 最后一条后重交 ⇒ final-state 或 entry-divergence，断言 ok=false）。
  - 空 action_log 空 ledger 的 start 形状局：audit ok（开局即无动作终局也算自洽——不成立：start 后未终局。改用：两 action 内 end_turn end_turn 的极短局 audit ok）。
- [ ] **Step 2: 跑失败**；**Step 3: 实现 auditor.gd**；**Step 4: 跑通过**；**Step 5: Commit**

```bash
git add tests/test_auditor.gd scripts/core/auditor.gd
git commit -m "feat(core): 审计器（独立重放对账+四路篡改必抓+终局全等）"
```

---

### Task 9: 成绩册

**Files:**
- Create: `scripts/file_storage.gd`、`scripts/scorebook.gd`
- Test: `tests/test_scorebook.gd`

**Interfaces:**
- Produces: `file_storage.gd`——`load_text(path: String) -> String` / `save_text(path: String, text: String) -> bool` / `exists(path: String) -> bool`（user://，jumper 同款签名，测试用内存假件鸭子替换）；`scorebook.gd`——`load_book(storage) -> Array`（坏档/顶层非数组/条目非 Dictionary 一律跳过或空册）；`record(storage, entry: Dictionary) -> bool`（追加+写回，写失败 false）；`recent(book: Array, n: int) -> Array`（最近 n 条）。
- 条目 schema：`{"seed": int, "deck": str, "opponent": str, "turns": int, "result": "win"|"lose"|"draw", "finished_at": ISO str}`。

- [ ] **Step 1: 写失败测试**（jumper test_scorebook 同构：MemStorage 内联假件三方法）——写入路径 user://scorebook.json；读缺失/坏 JSON/顶层非数组/条目混入非 Dictionary 各一路（混入坏条目=好条目保留）；record 返回 true 且 load 回读全等；写失败 false；recent(n) 排序取尾。
- [ ] **Step 2: 跑失败**；**Step 3: 实现两件**；**Step 4: 跑通过**；**Step 5: Commit**

```bash
git add tests/test_scorebook.gd scripts/file_storage.gd scripts/scorebook.gd
git commit -m "feat(core): 成绩册（audit.ok 前置由调用侧执行；读侧条目级 guard）"
```

---

### Task 10: 端到端对账闭环

**Files:**
- Test: `tests/test_end_to_end.gd`

**Interfaces:**
- Consumes: 全部 core 模块真实组合（无合成件）。

- [ ] **Step 1: 写失败测试**——三套牌 × 两策略全组合（3×2=6 局）：每局 deck_player=某牌组、deck_enemy=另一牌组、seed=固定值逐局不同；玩家侧用 aggressive.decide、敌侧 greedy.decide 交替 apply_action 至 GAME_OVER（帽 500 动作）；断言每局 winner 非 null、turn_count ≤ 60、audit ok。
- [ ] **Step 2: 跑失败**；**Step 3: 补齐使 6 局全绿**（若某组合打不完/卡死/审计红——这是引擎缺陷，修引擎不是放松断言）；**Step 4: 跑全量 runner 验证通过**；**Step 5: Commit**

```bash
git add tests/test_end_to_end.gd
git commit -m "test(e2e): 三牌组×两策略六局全审计绿闭环"
```

---

### Task 11: 表现层（三视图 + 三态机）

**Files:**
- Modify: `scripts/main.gd`、`scenes/main.tscn`（骨架件重做）
- Create: `scripts/menu_view.gd`、`scripts/battle_view.gd`、`scripts/result_view.gd`、`icon.svg`
- Test: `tests/test_views_smoke.gd`

**Interfaces:**
- Consumes: battle/opponent/auditor/scorebook/cards 全部签名。
- 三态机（main.gd）：`menu → battle → result → menu`（jumper 同款 `change_state` 形状）。
- menu_view：牌组选择（读 data/decks/）、对手选择（读 data/opponents/）、种子显示、开始按钮；成绩册最近 10 条列表（scorebook.recent）。
- battle_view：双方英雄面板（hp/shield/energy/atk 数值条）、手牌按钮列（费+名+效果文本）、attack/end_turn 按钮、右侧账本流滚动列表（每条目一行 `#seq T{n} {卡名/attack/refill} → {target} {field} {before}→{after} [{formula}]`，新条目置顶或置底一致滚动）；每按一次玩家 action：apply_action → 若对侧未终局则循环 opponent.decide+apply_action 直到轮到玩家或终局（回合推进全在按下后同步完成，无动画时序依赖）→ 刷新视图。
- result_view：audit(deck…, action_log, ledger, card_table) 跑审计——ok⇒绿字「对账通过 ✓」+战果+「入档」；不 ok⇒红字报第一条 mismatch（seq/kind/expected/actual）+「成绩拒收不入档」；再来一局/回菜单按钮。
- 节点树自由（spec 已留实现者），但**核心层调用形状不得绕过**：视图只经 battle.apply_action 改局面，UI 不直改 state。

- [ ] **Step 1: 写 smoke 测试 tests/test_views_smoke.gd**——四个脚本 `load()` 全非 null；main.tscn 可实例化（`load(...).instantiate()` 非 null 且 free()）。
- [ ] **Step 2: 跑失败**；**Step 3: 实现 main.gd/main.tscn/三视图/icon.svg**；**Step 4: 跑全量通过**；**Step 5: Commit**

```bash
git add scripts/main.gd scripts/menu_view.gd scripts/battle_view.gd scripts/result_view.gd scenes/main.tscn icon.svg tests/test_views_smoke.gd
git commit -m "feat(ui): 三态机 menu/battle/result 与账本流战斗视图、审计报告结算视图"
```

---

### Task 12: 部署五件套 + 收尾

**Files:**
- Create: `Dockerfile`、`export_presets.cfg`、`nginx.conf`、`.github/workflows/ci.yml`、`deploy/harness-cardbattle.sh`、`deploy/nginx-vps.conf.example`
- Modify: `version-lock.json`（godot 回填 `4.7-stable`）、`README.md`、`.gitignore`（确认 `_work/` 与 `build-web/` 在列）

**Interfaces:**
- 从 `../harness-jumper/` 同名件照抄改仓名/端口/域名：Dockerfile（mkdir 前置指纹保留）、nginx.conf（COOP/COEP 双层头）、ci.yml（test job headless runner 7s 形状+deploy job）、export_presets.cfg（preset 恰名 "Web"）。
- deploy 脚本参数：端口 **5311**、域名 `hcardbattle.xiangru.uk`、容器名 `harness-cardbattle-web`、镜像 `zcqiand/harness-cardbattle-web`（sed 顺序纪律照 jumper）。
- README：玩法一段+突出点一段（结算审计）+本地测试命令+部署说明一行。

- [ ] **Step 1: 照抄六件并改参**（逐文件核 diff：仓名字串无 jumper 残留、5310→5311、hjumper→hcardbattle）；**Step 2: version-lock/README/.gitignore 收尾**；**Step 3: 跑全量 runner 最后一次全绿**；**Step 4: Commit**

```bash
git add Dockerfile export_presets.cfg nginx.conf .github/workflows/ci.yml deploy/harness-cardbattle.sh deploy/nginx-vps.conf.example version-lock.json README.md .gitignore
git commit -m "chore(deploy): web-only 五件套照 jumper 形状落 5311/hcardbattle+version-lock 回填"
```

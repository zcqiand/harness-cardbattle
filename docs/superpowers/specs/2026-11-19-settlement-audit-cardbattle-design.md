# harness-cardbattle 设计文档：结算审计即对战

> 书三 ch11 配套（xr-know-022），Godot 保栈仓之二。ch15 v2 批将在同仓加策略 AI 对手。
> 日期：2026-11-19

## 意图与为什么

卡牌对战游戏最常见的死法是「算错血」：效果互相叠加、结算顺序含糊，玩家输了一局却不知道数字是怎么来的。本仓的突出点是**结算审计即对战**：

- 每一笔伤害/治疗/增益/护甲变动都落地为一条**编号账本条目**（事件、来源卡、作用对象、字段、前值→后值、效果公式与输入）。
- 一局打完，本地**审计器**拿「牌组状态 + 行动日志 + 卡牌效果表」从零重算一遍账本，与运行时账本**逐条全等对账**；不平账=当局成绩不入档，并报出第一条不平的账目序号与差异。
- 结算画面本身就是审计报告：玩家看到的不只是「你赢了」，而是「这局的每个数字都有账可查」。

与前四仓的谱系：2048=种子重放、snake=快照捕获、maze=走线认证、jumper=物理契约，cardbattle=**数字必须对账**。书稿 ch11 四个 section（回合状态机规约/卡牌效果断言/数值结算审计/整合成可运行对战）逐节有落点；ch15 的回放与胜率评估工具将来直接消费账本条目。

## 目标

1. 完整可玩的 1v1 卡牌对战：选牌组 → 回合制对战（抽牌/出牌/结束回合）→ 结算审计报告 → 成绩册。
2. 每笔数值变动有编号账本条目；局末审计器重算全等是成绩入档的唯一前置。
3. 回合状态机规约化：状态+事件+合法流转表；非法操作在错误状态下被拒绝并给出原因，不崩溃不静默。
4. 卡牌纯数据 JSON + 效果描述符，规则引擎解释执行；新增卡牌不改代码，加载时效果断言拒载非法卡。
5. 对手走干净接口（`decide(view) -> action`），v1 用脚本化 JSON 策略对手；ch15 换策略 AI 不换桌。
6. headless 测试 runner 全绿（jumper 先例：自建 runner，exit code 唯一真相）。

## 非目标

- 联网对战、账号系统、卡牌收集/抽卡/开包经济。
- 重度动画演出（战斗表现走轻量卡片/数字弹跳，重心在账本流 UI）。
- 玩家自定义卡组 JSON 导入导出（B 方案的突出点，v1 不做；卡组从内置 JSON 选）。
- ch15 的策略 AI、回放工具、胜率评估（v1 只留接口与账本数据形状）。

## 反目标（出现即失败）

- 任何一条 HP/攻击/护甲变动绕过账本直接改战斗状态——审计器将必然抓到，但运行时不允许这种路径存在。
- 任何未记录种子的随机数进入结算（洗牌/效果掷骰必须走局面种子派生 RNG，行动日志可重放）。
- 账本条目只有「后值」没有「前值→后值」链——链断裂即审计失效。
- 审计器与结算引擎共享可变状态（审计器必须从原始输入纯函数重建，否则是自证清白）。

## 约束

- Godot 4.7 stable + GDScript（4.x 兼容语法，勿 `is not`）；version-lock.json 回填 `4.7-stable`（jumper 同款，装机已实测）。
- 零三方依赖；RNG 用自写种子化 mulberry32（2048 先例）。
- 测试 = headless runner（`Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tests/test_runner.gd`），套件契约 `extends RefCounted` + `run(failures: Array[String])`，runner 自动发现 `test_*.gd`。
- 成绩册落 Godot `user://`（浏览器侧存储）；读侧条目级类型 guard（jumper T8 先例）。
- 确定性：同种子+同行动日志 ⇒ 同账本 ⇒ 同审计结论。这是审计成立的前提，也是测试可断言的前提。
- 部署照 jumper 五件套（Dockerfile Godot headless 导出/export_presets.cfg preset 恰名 "Web"/ci.yml/deploy 脚本/nginx-vps.conf.example），**四指纹直接照抄**：导出前 mkdir 目标目录、CI Dockerfile 内拉引擎+只解 web_* templates、COOP/COEP 双层头、版本 ARG 钉 4.7-stable。端口 5311，域名 `hcardbattle.xiangru.uk`。
- 正式区/临时区纪律：过程件进 `_work/`（整目录 gitignore）。
- commit 尾注逐字 `Co-Authored-By: Claude Code <noreply@anthropic.com>`；禁止 git add -A。

## 方案比较（已裁定）

- **A. 结算审计即对战（选定）**：突出点=数字必须对账。吃满 ch11 章钩子「每一笔结算都有账可查」，与 ch15 回放/评估工具同源同数据。结算画面即审计报告是独立记忆点。
- B. 牌组契约即对战：新卡只是数据+导入拒载。离 ch11 审计交付物偏一半；AI 强度不可解释的痛点没人管。效果断言/纯数据卡牌作为 A 的支撑机制保留，不作为突出点。
- C. 回合状态机即对战：太薄，A/B 都内含严格状态机，无独立记忆点。

## 架构

### 分层（结算核心与表现分离——审计器只碰核心层）

```
data/cards/*.json          卡牌数据（纯 JSON：数值+效果描述符）
data/decks/*.json          内置牌组（卡 id 列表）
data/opponents/*.json      v1 对手策略（优先级规则表）
scripts/core/
  rng.gd                   mulberry32 种子化 RNG（局面种子按 channel 分流）
  cards.gd                 卡表加载+效果断言拒载（非法卡=加载失败并报卡号与违规字段）
  turn_machine.gd          回合状态机（状态/事件/合法流转表；非法流转返回拒绝+原因）
  effects.gd               效果解释器（描述符 → 对战斗状态的纯变换，产出账本条目）
  ledger.gd                账本（append-only 条目列表；条目 schema 唯一定义处）
  battle.gd                战斗引擎（组合状态机+效果+账本+双方牌库；唯一改状态入口）
  auditor.gd               审计器（纯函数：牌组+行动日志+卡表 → 重算账本 → 逐条 diff → 结论）
  opponent.gd              对手接口 decide(view) -> action；JSON 优先级策略实现
  scorebook.gd             成绩册（user:// 读写；入档唯一前置=审计 clean）
scripts/
  main.gd                  三态机 menu → battle → result（jumper 同款形状）
  battle_view.gd           战斗 UI：手牌/场面/HP 条 + 账本流侧栏（实时滚动）
  result_view.gd           结算=审计报告：对账全绿 ✓ / 第一条不平账红字+不入档
  menu_view.gd             选牌组+对手+开局；成绩册入口
tests/                     runner + harness + 套件（每 core 模块一套 + 端到端对账一套）
```

### 实体模型与数值规则（builder check 裁定回填）

- **无单位**。场上只有双方英雄；英雄四字段：`hp`（上限 30，初始 30）/ `shield`（伤害先盾后血，跨回合保留，无上限）/ `atk`（英雄攻击力，初始 0，buff_attack 加成**永久**到局终）/ `energy`（能量，见下）。
- **能量经济**：每回合行动方能量刷新为 `min(本方回合数, 10)`，不跨回合累积；出牌付费、回合开始 refill 都入账本（field=energy）。energy 上限 10、卡费 1-5 区间。
- **target 枚举**：`player_hero` / `enemy_hero`（能量条目的 target=付费方英雄）。
- **draw 是后果不是决策**：action_log 只含三类决策 `play_card(card_id)` / `attack` / `end_turn`；开局抽 3、每回合 TURN_START 抽 1、抽牌效果附带抽 N——全部由引擎按规则派生（牌序=种子 channel 洗牌序），不进 action_log。审计器按同一规则重放派生抽牌。
- **先手**：玩家先手；先手第 1 回合不抽牌（后手抽），开局各抽 3。
- **attack 事件**：MAIN 态每回合限一次，己方英雄以当前 atk 攻击敌方英雄；atk=0 时 attack 非法（拒绝+原因）。伤害走对方盾→血。
- **效果即时结算**：出牌那一刻逐条效果按序结算入账，无独立结算阶段。
- **终局判定时机**：一次决策（play_card/attack）的全部效果结算完、全部入账**之后**才判 GAME_OVER——致命伤中途不打断剩余效果，溢出伤害照记照入账（审计与终局共用同一口径）。双方 hp 同时 ≤0 判平局。
- **牌库抽空**：需要抽牌而牌库空 ⇒ 该方判负（审计重放同规则同口径）。
- **回合上限 30**：第 30 回合结束仍未分胜负 ⇒ 平局（scorebook.turns 有界，无僵局局）。

### 回合状态机规约

- 状态：`TURN_START`（引擎自动：refill 能量+抽牌，各入账）→ `MAIN`（决策态：play_card 任意次/attack 每回合一次/end_turn）→ `TURN_END`（buff 无过期结算，纯标记）→ 切换行动方回 `TURN_START`；任一状态可转 `GAME_OVER`（判定时机见上节）。
- 合法流转表按「状态+事件」数据表落 `turn_machine.gd`（章 section 1 落点）；非法事件返回 `{accepted: false, reason: "end_turn 不在 TURN_START 状态"}` 形状——拒绝也是可断言的规约行为（测试覆盖至少 3 路非法样例：错状态出牌/重复 attack/atk=0 时 attack）。

### 卡牌效果表（纯数据+断言拒载）

卡牌 JSON 形状（示意，实现时以 cards.gd schema 为准）：

```json
{
  "id": "ember_strike",
  "name": "余烬打击",
  "cost": 1,
  "text": "造成 3 点伤害",
  "effects": [
    {"type": "damage", "value": 3, "target": "enemy_hero"}
  ]
}
```

- 效果描述符类型 v1 集：`damage` / `heal` / `gain_shield` / `buff_attack`（永久到局终）/ `draw`。每个描述符在 cards.gd 有 schema 断言：缺字段/未知 type/value 非正整数 ⇒ 该卡拒载，报 `card-<id>: effects[<i>] 未知类型 "x"` 形状。
- 效果解释器是纯变换：`(battle_state, card, descriptors) -> {new_state, ledger_entries}`——不直接改状态，由 battle.gd 统一落账。这是「任何变动必过账本」的结构保证。

### 结算账本（唯一权威）

条目 schema（ledger.gd 唯一定义处）：

```
{ "seq": 7, "turn": 3, "actor": "player", "event": "play_card",
  "card": "ember_strike", "field": "hp", "target": "enemy_hero",
  "before": 18, "after": 15, "formula": "damage(3)" }
```

- append-only；`seq` 全局自增。同一 target+field 的连续条目满足**链连续性**：`entries[i].after == entries[i+1].before`（按 (target, field) 分键各自成链）。
- 一次出牌产多条目（多效果/多目标/付费/伤害穿盾拆两条）按序 append，各键链连续性同样成立。
- **field 枚举一次定死**：`hp` / `shield` / `atk` / `energy`——四字段全入账本，结构上无豁免面（能量付费不记=审计必然抓到，且运行时不允许该路径存在）。
- 战斗内 UI 账本流直接渲染条目（`#seq T3 余烬打击 → 敌方英雄 HP 18→15 [damage(3)]`）。

### 审计器（对账=成绩门）

```
audit(deck_player, deck_enemy, seed, action_log, card_table)
  -> {ok: bool, first_mismatch: null | {seq, kind, expected, actual}}
```

- 重算路径与 battle.gd 完全独立：auditor 自建一套从零演进的战斗状态，逐步消费 action_log，重放效果解释器生成 shadow ledger，然后与运行时 ledger 逐条 diff。mismatch kinds：`entry-divergence`（同 seq 条目字段不等）/`chain-break`（链连续性断）/`tail-extra`（重算多出条目）/`final-state`（终局 HP/胜负不等）。
- **成绩入档唯一前置 = audit.ok**。不平账时 result_view 报第一条 mismatch（seq、kind、期望/实际），当局成绩拒收。
- 自测的一部分：测试套件含「篡改账本必被抓」用例（改一条 after、删一条、多一条、改终局 HP 四路篡改各一路用例）——审计器的可信度用攻击者视角证明，不靠自觉。

### 随机数规约（审计成立的前提）

- 每局一个 `seed`（开局生成，menu 可见可复制），洗牌与一切掷骰走 `Rng(seed)` 派生（`Rng(seed + channel)` 按 channel（洗牌/效果掷骰）分流域，避免取数次序耦合）。
- seed 与 action_log 一起构成完整重放输入；审计器签名里 seed 显式出现。

### 对手接口（v1 脚本，ch15 换脑不换桌）

```
decide(view: Dictionary) -> Dictionary   # view=对手可感知状态的只读投影; 返回一个 action（play_card(id)/end_turn）
```

- v1 实现：JSON 优先级规则表（`data/opponents/*.json`：如「费用能出则从高到低出牌，否则结束回合」）；策略文件加载时走同一效果断言门。
- 对手 action 与玩家 action 走同一 battle 入口、同一账本——对手的每一笔结算同样有账可查（章钩子「AI 再也糊弄不了数值」的落点）。

### 成绩册

- `user://scorebook.json`；条目 `{seed, deck, opponent, turns, result(win/lose/draw), finished_at}`——只在 audit.ok 时写入。
- 读侧条目级 `is Dictionary` guard（jumper T8 先例）；menu_view 列最近战绩。

### 表现层

- Godot 2D 轻量节点（ColorRect/Label/Button），无美术资源依赖（jumper 同款自律）；卡片=成本+名称+效果文本的按钮块。
- 战斗视图右侧账本流实时滚动（突出点在 UI 上的常驻存在感）；结算视图=审计报告全绿 ✓ 或第一条不平账红字。
- 触屏可点（鼠标即点）；无动画时序依赖，全部状态由数据驱动。

## 测试面

headless runner 套件划分（每套一个 test_*.gd）：

1. rng——同种子同序列/不同种子不同序列/channel 隔离
2. cards——schema 断言拒载（缺字段/未知 type/负值 各一路）+合法卡全载
3. turn_machine——合法流转表断言+非法事件拒绝原因（至少 3 路非法样例）
4. effects——每描述符类型一路：变换正确+账本条目字段齐
5. ledger——append/seq 自增/链连续性检查函数
6. battle——完整打一局（脚本化双方行动）终局判定/平局判定/出牌扣费
7. auditor——绿局对账 ok + 四路篡改全抓（改值/删条/加条/改终局）
8. opponent——策略表解释：能出则出最高费/不能出则结束回合
9. scorebook——audit.ok 才入档/读侧 guard/最近战绩排序
10. end_to_end——种子局全程重放：battle 打完 → auditor 对账 ok → 篡改 action_log 一处 → 审计红（端到端闭环证明）

## 留给实现者的决定（已划范围）

- 具体卡池与牌组数值（3-4 个内置牌组、15-20 张卡，保证「buff/护甲/直伤/抽牌」四机制各有用武之地、有可玩的攻防节奏）；平衡性不做精密调参，打起来完整即可。
- 视图节点树与 tscn 组织方式（jumper 形状可参考，不强制同构）。
- view 投影的字段裁剪（对手不该看到玩家手牌——投影里手牌只给张数；这是 v1 就做对的点，ch15 策略 AI 受益）。

## ch15 预留（v1 不实现）

- auditor 的重放路径即未来回放工具的内核；账本条目 schema 即胜率评估的数据面。
- opponent 接口即策略 AI 座位；view 投影已裁剪信息面。

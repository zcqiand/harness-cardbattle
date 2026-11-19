# harness-cardbattle

书《Harness 工程：Codex 智能游戏开发入门》（xr-know-022）配套仓——Godot 卡牌对战游戏（结算审计即对战）。

| 字段 | 值 |
|---|---|
| 绑定章节 | ch11 卡牌对战 / ch15 策略 AI 对手（v2） |
| 技术栈 | GDScript（Godot 4.7，钉 `version-lock.json`）+ JSON 卡牌契约 |
| 状态 | 已实现（2026-11-19；11 套件 610 checks 全绿；web-only 五件套照 jumper 形状落 5311） |

## 玩法

选一副牌组（aggro / control / midrange）与一种 AI 对手策略（激进型 / 贪婪型）开局。双方英雄各 30 生命，每回合手牌补满、费用随回合增长；打出 `data/cards/core_set.json` 契约卡（伤害 / 治疗 / 护盾 / 增攻 / 抽牌五类效果）累积优势，英雄攻击时按当前攻击力互殴，先归零者负。全局随机流种子化，同种子同操作必同局。

## 特色：结算审计即对战

每一手牌的每一步结算（抽牌 / 结算效果 / 掉血 / 死亡 / 回合推进）都记入对局账本；终局时审计器从零独立重放整局对账——账本对不上（无论哪个环节被篡改）则该局成绩无效、审计 `ok=false`。**结果只有在对账通过时才算数**，成绩册（user:// 浏览器侧存储）只收审计通过的胜局。

## 本地测试

```bash
"D:/qiand-life/3-resources/8-ego/software/godot/Godot_v4.7-stable_win64_console.exe" --headless --path . --script res://tests/test_runner.gd
```

## 部署

web-only 变体（tag push → Godot headless 导出静态产物 → nginx:alpine 容器），五件套照 harness-jumper 形状，端口 5311 / `https://hcardbattle.xiangru.uk`，细节见 `deploy/harness-cardbattle.sh` 与 `.github/workflows/ci.yml`。

工程纪律见 [CLAUDE.md](CLAUDE.md)。

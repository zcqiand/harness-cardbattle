# 目录结构与章节绑定

> 树是文件系统的复写，以仓库实际为准；模块职责与章节绑定在此维护。

```text
harness-cardbattle/
├── CLAUDE.md                       ← 工程约定入口
├── version-lock.json               ← 版本钉死 SSOT（Godot 版本）
├── project.godot                   ← Godot 工程描述（config_version=5）
├── scenes/
│   └── main.tscn                   ← 主场景：卡牌对战渲染根
├── scripts/
│   └── main.gd                     ← 主场景脚本：加载卡组 JSON 并校验
├── data/
│   └── cards/
│       └── starter_deck.json       ← 卡牌契约样例（起手卡组）
├── docs/conventions/               ← structure / tagging
└── _work/                          ← 过程件（gitignore）
```

## 章节绑定表

| 章节 | 落点 | 交付物 |
|---|---|---|
| ch11 卡牌对战 | `data/cards/`+`scripts/` | 回合状态机规约+效果断言+数值结算审计表 |
| ch15 策略 AI v2 | `scripts/`（随章节落） | 行动枚举规约+模拟对战胜率评估 |

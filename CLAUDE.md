# harness-cardbattle — 仓库工作约定（供 Claude Code）

本仓为书《Harness 工程：Codex 智能游戏开发入门》（xr-know-022）配套仓，
是书稿代码块的 **source of truth**。绑定章节：ch11（卡牌对战）、ch15（策略 AI 对手 v2）。

## 项目定位

Godot 卡牌对战游戏：ch11 落回合状态机规约+卡牌效果断言+数值结算审计表；ch15 v2 落可对战的策略 AI（行动枚举规约+模拟对战胜率评估）。

## 铁律

- **版本钉死**：Godot 版本以 `version-lock.json` 为准（ch4 安装实测后回填实测回执）；不引入 lock 外的插件
- **TDD**：回合机/效果结算/伤害公式等纯逻辑先写断言脚本 → 确认失败 → 实现 → 确认绿 → commit（headless 跑，无 Key 无网）
- **卡牌契约化**：卡牌定义必须从 `data/cards/` JSON 加载，禁止硬编码到 GDScript；数值结算必须可审计（每步产出结算记录）
- **零伪代码**：禁止 `pass`/`TODO` 占位，每段代码必须可运行
- **只增不改**：随章节扩仓不动现有模块签名/行为

## 验收

```bash
godot --headless --path . --quit   # 工程可被 Godot 正常导入解析（ch4 Godot 装机后启用）
```

GDScript 侧断言脚本随 ch11 章节落。本机无 Godot 时，工程结构以 ch4 实测为准补验。

## 正式区 / 临时区（2026-10-24 人定，全产品线通用）

- 过程件（对战实验、胜率模拟记录、调试日志）进 `_work/`，不与正式件混放
- 正式区同名正式件有且仅有一个；`_work/` 整目录 .gitignore；`.godot/` 为可再生件，gitignore

## 细则（docs/conventions/，按需引用）

- 目录结构与章节绑定 → `docs/conventions/structure.md`
- Tag 规约：Release 格式 `v<MAJOR>.<MINOR>.<PATCH>-<YYYYMMDD>`，禁止删/覆盖，禁止 `git push --tags` → `docs/conventions/tagging.md`

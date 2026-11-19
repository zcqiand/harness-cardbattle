extends RefCounted
## 账本：全仓数值变动的唯一权威（append-only）。本文件是账本条目 schema 的
## 全仓唯一定义处——条目键集固定为：
##   seq: int        —— append 时由 next_seq 填入，调用方不给
##   turn: int       —— 对战回合号（=双方 side_turns 之和 - 1）
##   actor: String   —— 动作方（"player"/"enemy"）
##   event: String   —— 事件类型，枚举三值："play_card"/"attack"/"turn_start"
##   card: String    —— 触发卡 id（attack/turn_start 无卡事件给 ""）
##   field: String   —— 被改英雄字段，枚举四值："hp"/"shield"/"atk"/"energy"
##   target: String  —— 被改对象（英雄字段变动只落双方英雄："player_hero"/
##                     "enemy_hero"；draw 是牌面移动非字段变动，不产条目）
##   before: Variant —— 变更前值
##   after: Variant  —— 变更后值
##   formula: String —— 变更公式（人类可读，如 "damage(3)"/"heal(4)"/"refill(2)"）
## 真实条目示例（引擎 emit 形状）：
##   {"seq":7,"turn":3,"actor":"player","event":"play_card","card":"fire_bolt",
##    "field":"hp","target":"enemy_hero","before":30,"after":27,"formula":"damage(3)"}
## 除 seq 外各键由调用方给全。链连续性按 (target, field) 分键检查：
## 同键相邻条目须满足 entries[i].after == entries[i+1].before。


static func new_ledger() -> Dictionary:
	return {"entries": [], "next_seq": 1}


static func append(ledger: Dictionary, entry: Dictionary) -> int:
	var seq: int = ledger["next_seq"]
	entry["seq"] = seq
	ledger["next_seq"] = seq + 1
	(ledger["entries"] as Array).append(entry)
	return seq


static func first_chain_break(entries: Array) -> Dictionary:
	var last_by_key := {}
	for e in entries:
		var entry: Dictionary = e
		var key := "%s|%s" % [entry["target"], entry["field"]]
		if last_by_key.has(key):
			var prev: Dictionary = last_by_key[key]
			if prev["after"] != entry["before"]:
				return {"ok": false, "seq": entry["seq"], "target": entry["target"],
					"field": entry["field"], "expected": prev["after"], "actual": entry["before"]}
		last_by_key[key] = entry
	return {"ok": true}

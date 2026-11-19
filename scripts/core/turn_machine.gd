extends RefCounted
## 回合状态机（数据表+查表）：legal_events 是流转表数据本体，
## can_accept 按表判定，未列出的相位/事件一律拒绝，拒绝原因逐字固定。

## 合法流转表：相位 -> 该相位接受的事件列表
const LEGAL_EVENTS := {
	"TURN_START": [],
	"MAIN": ["play_card", "attack", "end_turn"],
	"TURN_END": [],
	"GAME_OVER": [],
}


static func legal_events() -> Dictionary:
	return LEGAL_EVENTS.duplicate(true)


static func can_accept(phase: String, event: String) -> Dictionary:
	var events: Array = LEGAL_EVENTS.get(phase, [])
	if events.has(event):
		return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "%s 不接受事件 %s" % [phase, event]}

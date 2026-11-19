extends RefCounted
## 种子化 RNG（mulberry32）：同种子同序列，channel 派生隔离不同子系统流。
## for_channel(seed, channel) = new(seed ^ channel.hash())——全仓唯一派生规则；
## next_int(bound) ∈ [0, bound)；shuffle 为 Fisher-Yates 原地重排。

const SELF_PATH := "res://scripts/core/rng.gd"

var _state: int


func _init(seed_value: int) -> void:
	_state = seed_value & 0xFFFFFFFF


## channel 派生：seed 异或 channel 名哈希后作 32 位种子。
static func for_channel(seed: int, channel: String) -> RefCounted:
	var self_s: GDScript = load(SELF_PATH)
	return self_s.new(seed ^ channel.hash())


## mulberry32 步进，返回 [0, 1) 均匀浮点（JS 参考实现的 GDScript 版：
## Math.imul 用 (a * b) & 0xFFFFFFFF 替代，每步 & 0xFFFFFFFF 收敛）。
func next_float() -> float:
	_state = (_state + 0x6D2B79F5) & 0xFFFFFFFF
	var t := _state
	t = _imul(t ^ (t >> 15), t | 1)
	t = (t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return float(t ^ (t >> 14)) / 4294967296.0


## [0, bound) 均匀整数；浮点乘后取整再钳 bound-1 兜浮点边界。
func next_int(bound: int) -> int:
	return mini(int(next_float() * bound), bound - 1)


## Fisher-Yates 原地洗牌（从尾向前，j ∈ [0, i]）。
func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := next_int(i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func _imul(a: int, b: int) -> int:
	return (a * b) & 0xFFFFFFFF

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

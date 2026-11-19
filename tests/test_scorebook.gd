extends RefCounted
## 成绩册套件：读侧守卫（缺档/坏 JSON/顶层非数组 → 空册；条目混入非 Dictionary
## → 坏条目丢弃好条目保留）+ record 追加写回（写失败 false）+ recent 排序取尾。
## 排序语义钉死：册内条目即追加序（append order）；recent(book, n) 取**尾部**
## 最近 n 条、按追加序原样返回（不倒序不重排）——JSON 档本身不保证时间序，
## 追加序是唯一可靠序。storage 用内联内存假件 MemStorage（同签名三方法
## load_text/save_text/exists），测试不碰真 user://；写失败由 fail_writes 开关模拟。
## audit.ok 前置由调用侧执行（Task 11 结果页），本套件只管存储 + 读 guard。

const HARNESS_PATH := "res://tests/harness.gd"
const SCOREBOOK_PATH := "res://scripts/scorebook.gd"
const STORAGE_PATH := "res://scripts/file_storage.gd"


## 条目 schema 钉样板：{"seed": int, "deck": str, "opponent": str, "turns": int,
## "result": "win"|"lose"|"draw", "finished_at": ISO str}。
func _entry(seed: int, deck: String, opponent: String, turns: int, result: String, finished_at: String) -> Dictionary:
	return {
		"seed": seed,
		"deck": deck,
		"opponent": opponent,
		"turns": turns,
		"result": result,
		"finished_at": finished_at,
	}


## 内联内存假件：与 file_storage.gd 同签名的鸭子接口，store 字典即"磁盘"。
class MemStorage:
	extends RefCounted
	var store: Dictionary = {}
	var fail_writes: bool = false

	func load_text(path: String) -> String:
		return store.get(path, "")

	func save_text(path: String, text: String) -> bool:
		if fail_writes:
			return false
		store[path] = text
		return true

	func exists(path: String) -> bool:
		return store.has(path)


var completed := false


func run(failures: Array[String]) -> void:
	var h: GDScript = load(HARNESS_PATH)
	var scorebook: GDScript = load(SCOREBOOK_PATH)
	if scorebook == null:
		h.assert_true(false, "scorebook.gd 加载失败", failures)
		return
	var storage_impl: GDScript = load(STORAGE_PATH)
	if storage_impl == null:
		h.assert_true(false, "file_storage.gd 加载失败", failures)
		return

	_test_save_path(h, scorebook, failures)
	_test_load_missing(h, scorebook, failures)
	_test_load_bad_json(h, scorebook, failures)
	_test_load_not_array(h, scorebook, failures)
	_test_load_bad_entry_dropped(h, scorebook, failures)
	_test_load_valid(h, scorebook, failures)
	_test_record_appends(h, scorebook, failures)
	_test_record_second_appends(h, scorebook, failures)
	_test_record_write_failure(h, scorebook, failures)
	_test_record_persists_via_file_storage(h, scorebook, storage_impl, failures)
	_test_recent_tail(h, scorebook, failures)
	_test_recent_edge(h, scorebook, failures)
	_test_recent_pure(h, scorebook, failures)
	_test_file_storage(h, storage_impl, failures)
	completed = true


func _test_save_path(h: GDScript, scorebook: GDScript, failures: Array[String]) -> void:
	h.assert_eq(scorebook.SAVE_PATH, "user://scorebook.json", "SAVE_PATH 钉值 user://scorebook.json", failures)


func _test_load_missing(h: GDScript, scorebook: GDScript, failures: Array[String]) -> void:
	# 档不存在（load_text=""）→ 空册
	var mem: MemStorage = MemStorage.new()
	var book: Array = scorebook.load_book(mem)
	h.assert_eq(book.size(), 0, "缺档 → 空册", failures)


func _test_load_bad_json(h: GDScript, scorebook: GDScript, failures: Array[String]) -> void:
	var mem: MemStorage = MemStorage.new()
	mem.store[scorebook.SAVE_PATH] = "not json{"
	var book: Array = scorebook.load_book(mem)
	h.assert_eq(book.size(), 0, "坏 JSON → 空册", failures)


func _test_load_not_array(h: GDScript, scorebook: GDScript, failures: Array[String]) -> void:
	# 合法 JSON 但顶层非数组（Dictionary / 数字 / 字符串）各一路 → 空册
	var cases := {"dict 顶层": '{"a": 1}', "数字顶层": "42", "字符串顶层": '"oops"'}
	for case_name: String in cases:
		var mem: MemStorage = MemStorage.new()
		mem.store[scorebook.SAVE_PATH] = cases[case_name]
		var book: Array = scorebook.load_book(mem)
		h.assert_eq(book.size(), 0, "顶层非数组（%s）→ 空册" % case_name, failures)


func _test_load_bad_entry_dropped(h: GDScript, scorebook: GDScript, failures: Array[String]) -> void:
	# 条目级 guard：数组内混入非 Dictionary 条目 → 坏条目丢弃，好条目保留
	var mem: MemStorage = MemStorage.new()
	var good_a: Dictionary = _entry(7, "aggro", "control", 12, "win", "2026-01-01T08:00:00")
	var good_b: Dictionary = _entry(9, "control", "aggro", 20, "lose", "2026-01-02T09:30:00")
	var raw: Array = [good_a, "oops", good_b, 42]
	# JSON 往返后数字升 float：比对基线同升（钉此形状，与 load_valid 同口径）
	good_a["seed"] = 7.0
	good_a["turns"] = 12.0
	good_b["seed"] = 9.0
	good_b["turns"] = 20.0
	mem.store[scorebook.SAVE_PATH] = JSON.stringify(raw)
	var book: Array = scorebook.load_book(mem)
	h.assert_eq(book.size(), 2, "好坏混合档：只剩两条好条目", failures)
	h.assert_eq(book[0], good_a, "好条目 1 原样保留", failures)
	h.assert_eq(book[1], good_b, "好条目 2 原样保留", failures)


func _test_load_valid(h: GDScript, scorebook: GDScript, failures: Array[String]) -> void:
	var mem: MemStorage = MemStorage.new()
	# 数字写 7.0 / 12.0（float）：JSON.parse_string 把一切数字升为 float，
	# 好档读回的形状即 float 形——钉此事实。
	var expected: Array = [
		_entry(7, "aggro", "control", 12, "win", "2026-01-01T08:00:00"),
		_entry(9, "control", "aggro", 20, "lose", "2026-01-02T09:30:00"),
	]
	expected[0]["seed"] = 7.0
	expected[0]["turns"] = 12.0
	expected[1]["seed"] = 9.0
	expected[1]["turns"] = 20.0
	mem.store[scorebook.SAVE_PATH] = JSON.stringify(expected)
	var book: Array = scorebook.load_book(mem)
	h.assert_eq(book, expected, "好档原样读回（数字 float 形）", failures)


func _test_record_appends(h: GDScript, scorebook: GDScript, failures: Array[String]) -> void:
	# record 返回 true 且 load 回读全等（JSON 数字面升 float：读回即 float 形）
	var mem: MemStorage = MemStorage.new()
	var entry: Dictionary = _entry(7, "aggro", "control", 12, "win", "2026-01-01T08:00:00")
	var ok: bool = scorebook.record(mem, entry)
	h.assert_true(ok, "record 成功 true", failures)
	h.assert_true(mem.exists(scorebook.SAVE_PATH), "假件磁盘有档", failures)
	var book: Array = scorebook.load_book(mem)
	h.assert_eq(book.size(), 1, "record 后册内 1 条", failures)
	var expected: Dictionary = entry.duplicate(true)
	expected["seed"] = 7.0
	expected["turns"] = 12.0
	h.assert_eq(book[0], expected, "load 回读全等（数字 float 形）", failures)
	h.assert_eq(book[0]["deck"], "aggro", "回读 deck 字段", failures)
	h.assert_eq(book[0]["result"], "win", "回读 result 字段", failures)
	h.assert_eq(book[0]["finished_at"], "2026-01-01T08:00:00", "回读 finished_at 字段", failures)


func _test_record_second_appends(h: GDScript, scorebook: GDScript, failures: Array[String]) -> void:
	# record 是追加：既有条目保留、新条目落尾（追加序即册序）
	var mem: MemStorage = MemStorage.new()
	var first: Dictionary = _entry(7, "aggro", "control", 12, "win", "2026-01-01T08:00:00")
	var second: Dictionary = _entry(9, "control", "aggro", 20, "lose", "2026-01-02T09:30:00")
	h.assert_true(scorebook.record(mem, first), "第一条 record true", failures)
	h.assert_true(scorebook.record(mem, second), "第二条 record true", failures)
	var book: Array = scorebook.load_book(mem)
	h.assert_eq(book.size(), 2, "两次 record 后册内 2 条", failures)
	h.assert_eq(book[0]["seed"], 7.0, "首条仍为首条（追加保序）", failures)
	h.assert_eq(book[1]["seed"], 9.0, "新条目落尾", failures)


func _test_record_write_failure(h: GDScript, scorebook: GDScript, failures: Array[String]) -> void:
	# 写侧守卫：storage.save_text 失败 → record false（静默降级不抛错），且不落档
	var mem: MemStorage = MemStorage.new()
	mem.fail_writes = true
	var entry: Dictionary = _entry(7, "aggro", "control", 12, "win", "2026-01-01T08:00:00")
	var ok: bool = scorebook.record(mem, entry)
	h.assert_true(not ok, "写失败 → record false", failures)
	h.assert_true(not mem.exists(scorebook.SAVE_PATH), "写失败不落档", failures)


func _test_record_persists_via_file_storage(h: GDScript, scorebook: GDScript, storage_impl: GDScript, failures: Array[String]) -> void:
	# 接线形状：record 接受运行时 file_storage 实例（真 user:// 写不测，
	# 用 res:// 侧路径探针验证鸭子接线 + load_book 对 file_storage 读面成立）
	var impl: RefCounted = storage_impl.new()
	var probe_path := "res://_work/scorebook_probe.json"
	h.assert_true(impl.save_text(probe_path, JSON.stringify([])), "file_storage 探针档写入", failures)
	var mem_like: MemStorage = MemStorage.new()
	mem_like.store[scorebook.SAVE_PATH] = impl.load_text(probe_path)
	var entry: Dictionary = _entry(7, "aggro", "control", 12, "win", "2026-01-01T08:00:00")
	h.assert_true(scorebook.record(mem_like, entry), "鸭子接线 record true", failures)
	var book: Array = scorebook.load_book(mem_like)
	h.assert_eq(book.size(), 1, "file_storage 读面 + scorebook 守卫链成立", failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(probe_path))


func _test_recent_tail(h: GDScript, scorebook: GDScript, failures: Array[String]) -> void:
	# recent(book, n) 排序取尾：最近 n 条 = 追加序尾部 n 条，原序返回
	var book: Array = [
		_entry(1, "a", "b", 10, "win", "2026-01-01T08:00:00"),
		_entry(2, "b", "c", 11, "lose", "2026-01-02T08:00:00"),
		_entry(3, "c", "a", 12, "draw", "2026-01-03T08:00:00"),
	]
	var recent: Array = scorebook.recent(book, 2)
	h.assert_eq(recent.size(), 2, "recent(2) 取 2 条", failures)
	h.assert_eq(recent[0]["seed"], 2.0, "尾部首条=倒数第二条（原序不倒）", failures)
	h.assert_eq(recent[1]["seed"], 3.0, "尾部末条=最后一条", failures)
	var recent_all: Array = scorebook.recent(book, 5)
	h.assert_eq(recent_all.size(), 3, "n > 册长 → 全册", failures)
	h.assert_eq(recent_all[0]["seed"], 1.0, "n > 册长时原序保留", failures)


func _test_recent_edge(h: GDScript, scorebook: GDScript, failures: Array[String]) -> void:
	var book: Array = [_entry(1, "a", "b", 10, "win", "2026-01-01T08:00:00")]
	h.assert_eq(scorebook.recent(book, 1).size(), 1, "recent(1) 取 1 条", failures)
	h.assert_eq(scorebook.recent(book, 0).size(), 0, "recent(0) → 空册", failures)
	h.assert_eq(scorebook.recent([], 3).size(), 0, "空册 recent → 空册", failures)


func _test_recent_pure(h: GDScript, scorebook: GDScript, failures: Array[String]) -> void:
	# recent 纯：不改传入 book
	var book: Array = [
		_entry(1, "a", "b", 10, "win", "2026-01-01T08:00:00"),
		_entry(2, "b", "c", 11, "lose", "2026-01-02T08:00:00"),
	]
	var before: Array = book.duplicate(true)
	scorebook.recent(book, 1)
	h.assert_eq(book, before, "recent 不改传入 book", failures)


func _test_file_storage(h: GDScript, storage_impl: GDScript, failures: Array[String]) -> void:
	# 运行时实现的只读面 + 写失败守卫（真 user:// 写路径不测，内存假件覆盖签名面）
	var impl: RefCounted = storage_impl.new()
	h.assert_true(impl.exists("res://project.godot"), "exists 命中 res://project.godot", failures)
	h.assert_true(not impl.exists("res://no_such_file_probe.txt"), "exists 不存在 → false", failures)
	h.assert_true(
		not (impl.load_text("res://project.godot") as String).is_empty(),
		"load_text 读到非空文本", failures,
	)
	h.assert_eq(impl.load_text("res://no_such_file_probe.txt"), "", "load_text 不存在 → 空串", failures)
	h.assert_true(
		not impl.save_text("res://no_such_dir_probe/x.txt", "x"),
		"save_text 目录不存在 → false（写失败守卫）", failures,
	)

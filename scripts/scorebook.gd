extends RefCounted
## 成绩册（纯逻辑）：读侧守卫 + 追加写回 + recent 排序取尾。存档形状 =
## JSON 数组，条目 schema：
## {"seed": int, "deck": str, "opponent": str, "turns": int,
##  "result": "win"|"lose"|"draw", "finished_at": ISO str}
##
## **结算审计即对战**：audit.ok 前置由调用侧执行（Task 11 结果页只对
## audit.ok 的终局调 record），本模块只管存储 + 读 guard，不 import
## auditor/battle。
##
## 读侧守卫纪律（家族同款）：缺档/坏档（JSON 解析失败/顶层非数组）
## 一律回空册 []，不抛错——坏档只丢历史成绩，不挡本局开玩。
## 条目级坏形（数组内混入非 Dictionary，如手改档字符串/数字）当缺失丢弃，
## 好条目保留——不丢弃会让 recent 消费侧对非 Dictionary 调 .get 崩。
##
## 排序语义钉死：册内条目即追加序（append order）——JSON 档不保证
## finished_at 时间序，追加序是唯一可靠序；record 追加落尾，
## recent(book, n) 取尾部最近 n 条、按追加序原样返回（不倒序不重排）。
## 写侧 record 失败随 storage 返回 false（静默降级，成绩写失败不致命）。
## storage 是鸭子接口（load_text/save_text/exists 同签名即可），运行时注入
## file_storage.gd 实例，测试注入内存假件。

const SAVE_PATH := "user://scorebook.json"


## 读册：storage.load_text 拿文本，逐层守卫，缺档/坏档 → []，坏条目丢弃。
static func load_book(storage) -> Array:
	var text: String = storage.load_text(SAVE_PATH)
	if text.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Array):
		return []
	# 条目级守卫：数组内非 Dictionary 条目（手改档字符串/数字）当缺失丢弃。
	var book: Array = []
	for entry: Variant in parsed:
		if entry is Dictionary:
			book.append(entry)
	return book


## 记成绩：load 现册 → 追加落尾 → 写回；写失败（含打不开文件）→ false。
## audit.ok 前置由调用侧保证，本函数不校验。
static func record(storage, entry: Dictionary) -> bool:
	var book: Array = load_book(storage)
	book.append(entry)
	return storage.save_text(SAVE_PATH, JSON.stringify(book))


## 最近 n 条：追加序尾部 n 条，原序返回（不倒序不重排）；纯函数不改传入 book。
static func recent(book: Array, n: int) -> Array:
	if n <= 0:
		return []
	var start: int = maxi(0, book.size() - n)
	return book.slice(start)

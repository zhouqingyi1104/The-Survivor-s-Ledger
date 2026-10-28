extends SceneTree
## 文案检查：玩家看得到的字句里不许出现给开发看的词（规范见 docs/38-copy-style.md 第 2 节）。
## 扫 scripts/ 下的字符串字面量和 data/*.json 的文字；写给 AI 的记录、试玩报告、存档迁移、开发工具不算玩家界面。
## 运行：godot --headless --path . --script res://tests/copy_lint.gd

## 不是玩家界面的文件：前世档案（写给 AI）、试玩报告（写给开发者）、导演校验、存档迁移、截图演示
const SKIP_FILES := [
	"res://scripts/core/life_memory_file.gd",
	"res://scripts/core/playtest_report.gd",
	"res://scripts/core/director.gd",
	"res://scripts/core/migrate.gd",
]
const SKIP_DIRS := ["res://scripts/dev"]
## 这些调用里的字只进日志或给 AI，不上屏
const SKIP_CALLS := ["Director.note_choice(", "push_error(", "push_warning(", "print(", "printerr("]

## 禁用词：每清掉一类就加进来，已经加进来的就不许再出现
const BANNED := [
	"玩家", "NPC", "AI", "主线", "剧情", "任务", "系统", "功能", "机制",
	"Memory.md", "断网", "本机制", "Zzz",
	# 术语统一（第 2 批）：这一世写今世 / 这一世，前世写前世，精神值写心神
	"本世", "旧世", "心情",
]

## 扫到的字符串太少说明扫描本身坏了（文件没读到、正则失效），不能当成"干净"
const MIN_STRINGS := 3000

var checks := 0
var failures := 0
var _literal := RegEx.create_from_string("\"((?:[^\"\\\\\\n]|\\\\.)*)\"")
var _cjk := RegEx.create_from_string("[\\x{4e00}-\\x{9fff}]")
var _ai := RegEx.create_from_string("(?<![A-Za-z])AI(?![A-Za-z])")


func _initialize() -> void:
	test_matcher()
	var strings := []
	_scan_dir("res://scripts", strings)
	_scan_data(strings)
	check(strings.size() >= MIN_STRINGS, "只扫到 %d 条字符串，扫描可能坏了" % strings.size())
	var hits := 0
	for entry in strings:
		var word := banned_word(str(entry.text))
		if word != "":
			hits += 1
			check(false, "%s 里出现「%s」：%s" % [entry.where, word, str(entry.text).left(80)])
	print("[copy_lint] 扫了 %d 条玩家可见字符串，禁用词 %d 处" % [strings.size(), hits])
	print("[copy_lint] %d 项检查，失败 %d 处" % [checks, failures])
	quit(0 if failures == 0 else 1)


## 判定本身要对：禁用词要抓得到，正常的字不能误伤（AI 只认独立的两个字母）
func test_matcher() -> void:
	check(banned_word("这是给玩家看的") == "玩家", "抓不到「玩家」")
	check(banned_word("也不需要等待 AI；") == "AI", "抓不到独立的 AI")
	check(banned_word("MAIN 线路") == "", "把 MAIN 里的 AI 误判了")
	check(banned_word("天黑前把门窗墙补齐。") == "", "正常的字被误判")


func banned_word(text: String) -> String:
	for word in BANNED:
		if word == "AI":
			if _ai.search(text) != null:
				return word
		elif text.contains(word):
			return word
	return ""


func _scan_dir(dir: String, out: Array) -> void:
	if dir in SKIP_DIRS:
		return
	for sub in DirAccess.get_directories_at(dir):
		_scan_dir(dir.path_join(sub), out)
	for file in DirAccess.get_files_at(dir):
		var path := dir.path_join(file)
		if file.ends_with(".gd") and not path in SKIP_FILES:
			_scan_script(path, out)


func _scan_script(path: String, out: Array) -> void:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for i in lines.size():
		var code := _strip_comment(lines[i])
		var skip := false
		for call in SKIP_CALLS:
			if code.contains(call):
				skip = true
		if skip:
			continue
		for m in _literal.search_all(code):
			var text := m.get_string(1)
			if _cjk.search(text) != null:
				out.append({"where": "%s:%d" % [path.trim_prefix("res://"), i + 1], "text": text})


## 去掉字符串外面的 # 注释
func _strip_comment(line: String) -> String:
	var inside := false
	var escaped := false
	for i in line.length():
		var ch := line[i]
		if escaped:
			escaped = false
		elif ch == "\\":
			escaped = true
		elif ch == "\"":
			inside = not inside
		elif ch == "#" and not inside:
			return line.left(i)
	return line


func _scan_data(out: Array) -> void:
	for file in DirAccess.get_files_at("res://data"):
		if file.ends_with(".json"):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data".path_join(file)))
			_walk(parsed, "data/" + file, out)


## 以下划线开头的键是给开发看的注释（如 _note、_comment），不上屏
func _walk(value, where: String, out: Array) -> void:
	if value is Dictionary:
		for key in value:
			if not str(key).begins_with("_"):
				_walk(value[key], where + "." + str(key), out)
	elif value is Array:
		for i in value.size():
			_walk(value[i], "%s[%d]" % [where, i], out)
	elif value is String and _cjk.search(value) != null:
		out.append({"where": where, "text": value})


func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok:
		return
	failures += 1
	push_error("断言失败：" + msg)

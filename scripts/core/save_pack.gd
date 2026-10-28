extends RefCounted
## 存档备份与搬运：把一局打成 `.jyz` 文件，换个地方还能原样打开。
##
## 为什么不是直接复制 save.json：玩家会拿它当长期备份、当"换身份前的存档点"、也会发给人。
## 裸 JSON 没有格式标记、没有版本、坏了一半也看不出来，导入时更分不清"这是存档"还是"别的 json"。
## 所以外面套一层信封：格式名 + 信封版本 + 导出时间 + 游戏版本 + 里面那局的存档版本。
##
## 信封刻意用缩进 JSON（不是压缩包）：出问题能直接用记事本打开看，
## 这也符合"存档要能被玩家自己读懂"的一贯做法。

const Migrate = preload("res://scripts/core/migrate.gd")
const Data = preload("res://scripts/core/data.gd")

const FORMAT := "jieshi-save"
## 信封自己的版本，和 run.version（存档结构版本）不是一回事
const FORMAT_VERSION := 1
const EXT := "jyz"


## 把一份存档包成信封。snapshots 也一起带上，否则"翻回昨日"到了新机器就没了。
static func pack(save: Dictionary, game_version: String, exported_at: String) -> Dictionary:
	return {
		"format": FORMAT,
		"format_version": FORMAT_VERSION,
		"exported_at": exported_at,
		"game_version": game_version,
		"run_version": int(save.get("run", {}).get("version", 0)),
		"data": save,
	}


static func to_text(envelope: Dictionary) -> String:
	return JSON.stringify(envelope, "\t")


## 解析并验证。返回 {"ok": bool, "note": String, "data": Dictionary, "info": Dictionary}。
## 失败时 note 是给玩家看的一句话，不抛异常。
static func parse(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return _fail("文件是空的。")
	var json := JSON.new()
	if json.parse(text) != OK:
		return _fail("这不是一份存档文件（JSON 读不出来，第 %d 行）。" % json.get_error_line())
	var envelope := _as_dict(json.data)
	if envelope.is_empty():
		return _fail("这不是一份存档文件。")
	if str(envelope.get("format", "")) != FORMAT:
		return _fail("这不是《劫余录》的存档（缺少格式标记）。")
	var fv := int(envelope.get("format_version", 0))
	if fv > FORMAT_VERSION:
		return _fail("这份存档来自更新的版本（信封 v%d，本作只认到 v%d）。" % [fv, FORMAT_VERSION])
	var data := _as_dict(envelope.get("data"))
	if data.is_empty() or not (data.get("run") is Dictionary) or (data.get("run", {}) as Dictionary).is_empty():
		return _fail("文件是存档，但里面没有一局。")
	if not _playable_run(data.run):
		return _fail("存档缺少必要的身份、阶段或局内数据，不能安全导入。")
	if int(data.run.get("version", 0)) > Migrate.VERSION:
		return _fail("这份存档来自更新的游戏版本，本版本不能安全导入。")
	if not data.get("snapshots", {}) is Dictionary:
		return _fail("存档里的回溯快照损坏，不能安全导入。")
	for snapshot in data.get("snapshots", {}).values():
		if not snapshot is Dictionary or not _playable_run(snapshot):
			return _fail("存档里的回溯快照损坏，不能安全导入。")
		if int(snapshot.get("version", 0)) > Migrate.VERSION:
			return _fail("存档的回溯快照来自更新的游戏版本，不能安全导入。")
	# 老版本的存档要在导入时补齐字段，走和读档同一条迁移
	var upgraded := Migrate.save(Data.normalize(data))
	return {
		"ok": true,
		"note": "",
		"data": upgraded,
		"info": {
			"exported_at": str(envelope.get("exported_at", "")),
			"game_version": str(envelope.get("game_version", "")),
			"run_version": int(envelope.get("run_version", 0)),
			"upgraded": int(upgraded.get("run", {}).get("version", 0)) != int(envelope.get("run_version", 0)),
		},
	}


## 给文件起个能看懂的默认名：劫余录-第3日-落第书生-20261027-1250.jyz
## 只用文件名安全的字符（身份名里可能有空格以外的符号）。
static func suggest_name(run: Dictionary, role_name: String, stamp: String) -> String:
	var day := int(run.get("pday", 0))
	var part := "备劫" if day <= 0 else "第%d日" % day
	return "%s-%s-%s-%s.%s" % [_safe("劫余录"), part, _safe(role_name), _safe(stamp), EXT]


static func _safe(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text[i]
		out += "_" if c in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"] else c
	return out


static func _as_dict(value) -> Dictionary:
	return value if value is Dictionary else {}


## 只核验旧版本也应有的基本事实和容器，其他新增字段交给 Migrate 补全。
static func _playable_run(value: Dictionary) -> bool:
	if str(value.get("phase", "")) not in ["pre", "post", "dead", "ending"]: return false
	if str(value.get("role", "")) not in Data.table("roles"): return false
	for key in ["home", "attrs", "flags", "explore"]:
		if not value.get(key) is Dictionary: return false
	for key in ["hp", "hp_max", "food", "water", "mood", "energy", "warmth"]:
		if not value.attrs.has(key) or not typeof(value.attrs[key]) in [TYPE_INT, TYPE_FLOAT]: return false
	for key in ["seed", "day", "pday", "hour"]:
		if not value.has(key) or not typeof(value[key]) in [TYPE_INT, TYPE_FLOAT]: return false
		if float(value[key]) != floor(float(value[key])): return false
	if value.has("t") and (not typeof(value.t) in [TYPE_INT, TYPE_FLOAT] or float(value.t) != floor(float(value.t))): return false
	for key in ["plots", "facilities", "log"]:
		if not value.get(key) is Array: return false
	for key in ["night", "fight", "busy"]:
		if value.has(key) and not value[key] is Dictionary: return false
	for plot in value.plots:
		if not plot is Dictionary: return false
	if value.has("furniture") and not value.furniture is Array: return false
	return true


static func _fail(note: String) -> Dictionary:
	return {"ok": false, "note": note, "data": {}, "info": {}}

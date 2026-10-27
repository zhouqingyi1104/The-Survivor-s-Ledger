extends RefCounted
## 配置表读取。对应原版 ConfigManager + Config_*.bytes（MemoryPack），这里换成 res://data/*.json。

const TABLES := ["items", "shops", "facilities", "roles", "talents", "recipes", "crops",
	"devices", "map_points", "waves", "weather", "omens", "wishes", "events", "clues",
	"furniture", "difficulty", "challenge", "companions", "chores"]

static var _tables: Dictionary = {}


static func ensure() -> void:
	if not _tables.is_empty():
		return
	for table_name in TABLES:
		var path := "res://data/%s.json" % table_name
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed == null:
			push_error("配置表解析失败: " + path)
			parsed = {}
		_tables[table_name] = normalize(parsed)


static func table(table_name: String):
	ensure()
	return _tables[table_name]


static func item(id: String) -> Dictionary:
	return table("items").get(id, {})


static func item_name(id: String) -> String:
	return item(id).get("name", id)


## 例："米 ×2、炊饼 ×3"
static func describe_items(items: Dictionary) -> String:
	var parts := []
	for id in items:
		parts.append("%s ×%d" % [item_name(id), items[id]])
	return "、".join(parts)


## JSON 里的数字都是 float；整数值转回 int，界面上才不会出现 "3.0"。存档读回来也走这里。
static func normalize(v):
	match typeof(v):
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = normalize(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(normalize(x))
			return a
		TYPE_FLOAT:
			if v == floorf(v) and absf(v) < 1e15:
				return int(v)
	return v

extends RefCounted
## 旧存档升级。读档时整份过一遍（连同生死簿快照），缺的字段补上默认值。
##   v1：v0.2 的回合制劫中，按"时段"（seg）推进；菜畦记 watered。
##   v2：连续时间，run.t 是劫后第一天 6:00 起的分钟数；菜畦记 watered_t。
##   v3：守夜布防（posture / posture_due）。
##   v4：三面（门/窗/院墙）+ 三轮夜战 + 守夜方针。
##   v5：被砸烂的家具记进 run.broken（要拿材料重做）。
##   v6：能源链——柴油发电机 + 暖气，夜里烧柴油转机器（run.powered）。

const Post = preload("res://scripts/core/post.gd")

const VERSION := 6
## v2 新加的字段
const ADDED := {
	"t": 0, "busy": {}, "sleeping": false, "heated": false, "night_lines": [],
	"wave_due": false, "wave_day": 0, "wave_report": {}, "raid_report": {}, "dawn_due": false,
}
## v3 新加的字段
const ADDED_3 := {"posture": "", "posture_due": false, "heat_weak": false}
## v4 新加的字段
const ADDED_4 := {
	"wall": {"cur": 120, "max": 120}, "guard_spot": "", "plan_due": false,
	"night": {}, "night_policy": "", "fight": {}, "door_open": false,
}
## v5 新加的字段
const ADDED_5 := {"broken": []}
## v6 新加的字段
const ADDED_6 := {"powered": false}
## v1 的时段（晨 / 午 / 暮 / 夜）→ 当天第几分钟（从 6:00 起）：8:00、12:00、16:00、18:00
const SEG_MINUTE := [120, 360, 600, 720]


static func save(data: Dictionary) -> Dictionary:
	var out := data.duplicate()
	out.run = upgrade(data.get("run", {}))
	var snaps := {}
	var old: Dictionary = data.get("snapshots", {})
	for k in old:
		snaps[k] = upgrade(old[k])
	out.snapshots = snaps
	return out


static func upgrade(run: Dictionary) -> Dictionary:
	if run.is_empty() or int(run.get("version", 1)) >= VERSION:
		return run
	var v := int(run.get("version", 1))
	var had_t := run.has("t")
	for key in ADDED:
		if not run.has(key):
			var val = ADDED[key]
			run[key] = val.duplicate() if (val is Dictionary or val is Array) else val
	if v < 2 and not had_t and int(run.get("pday", 0)) > 0:
		var seg := clampi(int(run.get("seg", 0)), 0, SEG_MINUTE.size() - 1)
		run.t = (int(run.pday) - 1) * Post.DAY + SEG_MINUTE[seg]
	for plot in run.get("plots", []):
		if not plot.has("watered_t"):
			plot["watered_t"] = int(run.t)
		plot.erase("watered")
	if v < 2:
		# 回合制的外出记录和现在的翻找流程对不上：算作已经回到家
		if not run.get("explore", {}).is_empty():
			run.explore = {}
			run.loc = "home"
		run.erase("seg")
		run.erase("night_done")
	if v < 3:
		for key in ADDED_3:
			if not run.has(key):
				var val = ADDED_3[key]
				run[key] = val.duplicate() if (val is Dictionary or val is Array) else val
	if v < 4:
		for key in ADDED_4:
			if not run.has(key):
				var val = ADDED_4[key]
				run[key] = val.duplicate() if (val is Dictionary or val is Array) else val
		# v3 的「守夜方略」并进 v4 的「守夜方针」
		if not run.has("night_policy"):
			run.night_policy = ""
		run.erase("posture")
		run.erase("posture_due")
	if v < 5:
		for key in ADDED_5:
			if not run.has(key):
				var val = ADDED_5[key]
				run[key] = val.duplicate() if (val is Dictionary or val is Array) else val
	if v < 6:
		for key in ADDED_6:
			if not run.has(key):
				var val = ADDED_6[key]
				run[key] = val.duplicate() if (val is Dictionary or val is Array) else val
	run.version = VERSION
	return run

extends RefCounted
## 旧存档升级。读档时整份过一遍（连同生死簿快照），缺的字段补上默认值。
##   v1：v0.2 的回合制劫中，按"时段"（seg）推进；菜畦记 watered。
##   v2：连续时间，run.t 是劫后第一天 6:00 起的分钟数；菜畦记 watered_t。
##   v3：守夜布防（posture / posture_due）。
##   v4：三面（门/窗/院墙）+ 三轮夜战 + 守夜方针。
##   v5：被砸烂的家具记进 run.broken（要拿材料重做）。
##   v6：能源链——柴油发电机 + 暖气，夜里烧柴油转机器（run.powered）。
##   v7：难度预设（run.difficulty），四档参数乘数。
##   v8：挑战自选——了愿（tally.goals）与记账本（bought / repair_door / home_trips）。
##   v9：记账本补 orders（第 7 条誓约「不雇工」用）。

const Post = preload("res://scripts/core/post.gd")

const VERSION := 9
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
## v7 新加的字段
const ADDED_7 := {"difficulty": "normal"}
## v8 新加的字段（挑战记账本；老存档一律当成没挑了愿）
const ADDED_8 := {"tally": {"goals": [], "vows": [], "boons": [], "bought": {}, "repair_door": 0, "home_trips": 0}}
## v9 补进已有 tally 的字段（注意：不能整体替换 tally，v8 的档里已经有 goals/vows 等）
const TALLY_9 := {"orders": 0}
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
	if v < 7:
		for key in ADDED_7:
			if not run.has(key):
				var val = ADDED_7[key]
				run[key] = val.duplicate() if (val is Dictionary or val is Array) else val
	if v < 8:
		for key in ADDED_8:
			if not run.has(key):
				var val = ADDED_8[key]
				run[key] = val.duplicate(true) if (val is Dictionary or val is Array) else val
	if v < 9:
		# 只补字段，不整体替换——v8 的档里 tally 已经有内容（挑过的愿、买过的东西）
		if not (run.get("tally") is Dictionary):
			run.tally = ADDED_8["tally"].duplicate(true)
		for key in TALLY_9:
			if not run.tally.has(key):
				run.tally[key] = TALLY_9[key]
	run.version = VERSION
	return run

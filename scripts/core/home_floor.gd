extends RefCounted
## 不同空间共享同一时间与设施规则；旧卷默认回原宅院。
const ATTIC_COST := {"wood": 8, "nails": 4}
const ATTIC_MINUTES := 120

static func attic_stage(run: Dictionary) -> String:
	var value = run.get("attic", {})
	if not value is Dictionary:
		return "unprepared"
	var stage := str(value.get("stage", "unprepared"))
	return stage if stage in ["unprepared", "ready", "complete"] else "unprepared"

static func unlocked(run: Dictionary, id: String) -> bool:
	match id:
		"courtyard": return true
		"cellar": return "cellar" in run.get("facilities", [])
		"attic": return attic_stage(run) == "complete"
	return false

static func current(run: Dictionary) -> String:
	var id := str(run.get("home_floor", "courtyard"))
	return id if unlocked(run, id) else "courtyard"

static func return_to_courtyard(run: Dictionary) -> void:
	run["home_floor"] = "courtyard"

static func finish_attic(run: Dictionary) -> bool:
	if attic_stage(run) != "ready":
		return false
	run["attic"] = {"stage": "complete"}
	return true

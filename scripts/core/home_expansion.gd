extends RefCounted
## 东侧小院：旧档缺字段时仍是未施工；只有完整施工才开放新空间。
const COST := {"wood": 8, "nails": 4}
const CLEAR_MINUTES := 60
const BUILD_MINUTES := 120


static func stage(run: Dictionary) -> String:
	var value = run.get("expansion", {})
	if not value is Dictionary:
		return "survey"
	var current := str(value.get("stage", "survey"))
	return current if current in ["survey", "cleared", "ready", "complete"] else "survey"


static func complete(run: Dictionary) -> bool:
	return stage(run) == "complete"


## 只接受当前阶段对应的完工事件；重复或过期工作不会推进阶段。
static func finish(run: Dictionary, expected: String) -> bool:
	if stage(run) != expected or not expected in ["survey", "ready"]:
		return false
	run["expansion"] = {"stage": "cleared" if expected == "survey" else "complete"}
	return true

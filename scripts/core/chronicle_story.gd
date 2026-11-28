extends RefCounted

const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const State = preload("res://scripts/core/state.gd")

## 只记本世的选择。来信、回文和旧页均从同一份日历读取。
static func enabled(run: Dictionary) -> bool:
	return run.get("hundred_days") is Dictionary


static func chapter(run: Dictionary, letter: Dictionary = {}) -> Dictionary:
	if not enabled(run):
		return {}
	var chapters: Array = Data.table("hundred_days").chapters
	var day := int(letter.get("day", run.get("pday", 1)))
	var index := clampi((day - 1) / 20, 0, chapters.size() - 1)
	return chapters[index]


static func current_event(run: Dictionary) -> Dictionary:
	if not enabled(run) or run.get("phase") != "post":
		return {}
	var choices: Dictionary = run.hundred_days.get("choices", {})
	for event in Data.table("hundred_days").events:
		if int(event.day) > int(run.pday):
			break
		if not choices.has(str(event.id)):
			return event
	return {}


static func echo(run: Dictionary, event: Dictionary) -> String:
	var link: Dictionary = event.get("echo", {})
	if link.is_empty():
		return ""
	var choices: Dictionary = run.hundred_days.get("choices", {})
	if str(choices.get(link.event, "")) == str(link.choice):
		return str(link.text)
	return ""


static func option_for(event: Dictionary, choice_id: String) -> Dictionary:
	for choice in event.get("options", []):
		if choice.id == choice_id:
			return choice
	return {}


static func reply_block(run: Dictionary, option: Dictionary) -> String:
	if not run.get("dawn_due", false):
		if not run.get("explore", {}).is_empty() or str(run.get("home_floor", "")).begins_with("guest_"):
			return "回家再回信。"
		if not run.get("busy", {}).is_empty() or run.get("sleeping", false):
			return "等手头的事结束再回信。"
		if run.get("pending_event", "") != "" or run.get("plan_due", false) or run.get("wave_due", false) or not run.get("wave_report", {}).is_empty() or not run.get("fight", {}).is_empty():
			return "先处理眼前的事。"
	if not Inv.has_all(run.home, option.get("cost", {})):
		return "家中存货不足。"
	return ""


static func decide(run: Dictionary, event_id: String, choice_id: String) -> String:
	var event := current_event(run)
	if event.is_empty() or str(event.id) != event_id:
		return "这封信已处理，或尚未送到。"
	var option := option_for(event, choice_id)
	if option.is_empty():
		return "信上没有这项办法。"
	var block := reply_block(run, option)
	if block != "":
		return block
	Inv.take_all(run.home, option.get("cost", {}))
	Inv.add_all(run.home, option.get("gain", {}))
	run.hundred_days.choices[event_id] = choice_id
	State.note(run, "街坊 · %s｜%s。%s" % [event.title, option.label, option.result])
	return ""


static func journal(run: Dictionary) -> Array:
	var pages := []
	if not enabled(run):
		return pages
	var choices: Dictionary = run.hundred_days.get("choices", {})
	for event in Data.table("hundred_days").events:
		var choice := option_for(event, str(choices.get(event.id, "")))
		if not choice.is_empty():
			pages.append({"day": event.day, "title": event.title, "person": event.person,
				"label": choice.label, "result": choice.result, "echo": echo(run, event)})
	return pages


## 入份的人可以在白天再来当值。材料开工时交，收成只在完工时入库。
const SHIFTS := {
	"well": {"event": "well_bucket", "choice": "winch", "label": "同桂娘轮值打水",
		"minutes": 40, "cost": {}, "gain": {"water": 3}},
	"dock": {"event": "return_cargo", "choice": "berth", "label": "随货船换粮",
		"minutes": 90, "cost": {"firewood": 2}, "gain": {"rice": 1, "salt": 1}},
	"kiln": {"event": "charcoal_mouth", "choice": "bank", "label": "同孟九合窑烧炭",
		"minutes": 100, "cost": {"firewood": 2}, "gain": {"charcoal": 2}},
}


static func unlocked(run: Dictionary, id: String) -> bool:
	if not enabled(run) or not SHIFTS.has(id):
		return false
	var job: Dictionary = SHIFTS[id]
	return run.hundred_days.get("choices", {}).get(job.event, "") == job.choice


static func shift_block(run: Dictionary, id: String) -> String:
	if not unlocked(run, id):
		return "这一世还没约下这门差事。"
	if int(run.hundred_days.get("shifts", {}).get(id, 0)) == int(run.pday):
		return "今天已经排过这一班。"
	var job: Dictionary = SHIFTS[id]
	var minute := int(run.t) % 1440
	if minute + int(job.minutes) > 720:
		return "天黑就收工，明早再来。"
	if not Inv.has_all(run.home, job.cost):
		return "家中存货不足。"
	return ""


static func begin_shift(run: Dictionary, id: String) -> void:
	var job: Dictionary = SHIFTS[id]
	if not run.hundred_days.has("shifts"):
		run.hundred_days.shifts = {}
	run.hundred_days.shifts[id] = int(run.pday)
	Inv.take_all(run.home, job.cost)
	State.add_attr(run, "energy", -5)
	run.busy = {"kind": "street_shift", "label": job.label, "start": run.t,
		"end": int(run.t) + int(job.minutes), "data": {"id": id}}
	State.note(run, "出门当值：%s。" % job.label)


static func finish_shift(run: Dictionary, id: String) -> void:
	if not unlocked(run, id):
		return
	var job: Dictionary = SHIFTS[id]
	Inv.add_all(run.home, job.gain)
	State.note(run, "%s，分得%s，已送回家。" % [job.label, Data.describe_items(job.gain)])

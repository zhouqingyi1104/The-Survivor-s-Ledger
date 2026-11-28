extends RefCounted
## 后巷船匠一家在找过夜的地方。信、回音和结局只记在这一世。
const Inv = preload("res://scripts/core/inv.gd")
const OPEN := 11 * 1440 + 120
const LAST_SIGNAL := 17 * 1440 + 720
const CLOSE := 18 * 1440 + 720
const ACTIONS := {
	"lane_signal": {"label": "在巷口留灯", "minutes": 30, "energy": 3, "cost": {"lamp_oil": 1},
		"hint": "灯油一壶，30 分钟、精力 3。把灯搁在船匠看得见的窗边，明早八点再来看回音。"},
	"lane_shelter": {"label": "腾出西厢，请他们进院", "minutes": 90, "energy": 8, "cost": {"rice": 3, "water": 2},
		"hint": "米三斗、清水两瓢，90 分钟、精力 8。管一家人的食宿；船匠会给窗添一对撑木，当前和上限各加 15。"},
	"lane_ferry": {"label": "替他们修船，送一家人过河", "minutes": 60, "energy": 6, "cost": {"wood": 2, "nails": 1},
		"hint": "木料两根、铁钉一包，60 分钟、精力 6。船匠送街坊过河时把空船灯放往下游，第二十夜来宅前的尸群少一成。"},
	"lane_decline": {"label": "回信说明家里顾不过来", "minutes": 0, "energy": 0, "cost": {},
		"hint": "把船匠的布条系回巷口，两边各寻去处。这一世就不再相约。"},
}


static func status(story: Dictionary, now: int) -> String:
	var letter: Dictionary = story.get("lane_lantern", {})
	var stage := str(letter.get("stage", ""))
	if stage in ["shelter", "ferry", "declined", "missed"]:
		return stage
	if stage == "lit":
		if now >= CLOSE: return "missed"
		return "reply" if now >= int(letter.reply_t) else "waiting"
	return "offer" if now >= OPEN and now + 30 <= LAST_SIGNAL else ""


static func prompt(story: Dictionary, now: int) -> String:
	match status(story, now):
		"offer": return "巷口留灯 · 对岸船匠把一条白布系在窗上。第十八日傍晚前点灯，他会知道这条巷子里还有人。"
		"waiting":
			var reply_day := int(story.lane_lantern.reply_t) / 1440 + 1
			return "巷口留灯 · 灯还亮着。第 %d 日 08:00 再到窗边收信。" % reply_day
		"reply": return "巷口留灯 · 白布上多了一行字：「娘走不动了。你家可有空铺？若有木料，渡船也能补。」第十九日 18:00 前办完。"
		"shelter": return "西厢里晾着船家的衣裳。窗背新撑的那两根木头，是船匠亲手量的。"
		"ferry": return "渡船已过河。船匠约好第二十夜在下游放灯，将一成尸群引离宅院。"
		"declined": return "白布已经还回去。船家收下回信，另寻住处。"
		"missed": return "去巷口时，岸边的白布已经解走。你没能赶上这次接应。"
	return ""


static func choices(story: Dictionary, now: int) -> Array:
	match status(story, now):
		"offer": return ["lane_signal"]
		"reply": return ["lane_shelter", "lane_ferry", "lane_decline"]
	return []


static func block(run: Dictionary, story: Dictionary, action: String) -> String:
	var now := int(run.t)
	if action not in choices(story, now): return "这盏灯的情形已变，看看巷口的回信。"
	var option: Dictionary = ACTIONS[action]
	if action != "lane_signal" and now + int(option.minutes) >= CLOSE: return "赶不上第十九日 18:00 之前办完。"
	if float(run.attrs.energy) < int(option.energy): return "精力不足，需要 %d。" % int(option.energy)
	if not Inv.has_all(run.home, option.cost): return "家中存货不足。"
	return ""


static func complete(run: Dictionary, story: Dictionary, action: String) -> String:
	var now := int(run.t)
	var stage := status(story, now)
	if action == "lane_signal" and not story.has("lane_lantern") and now >= OPEN and now <= LAST_SIGNAL:
		story["lane_lantern"] = {"stage": "lit", "reply_t": (now / 1440 + 1) * 1440 + 120}
		return prompt(story, now)
	if stage != "reply": return ""
	match action:
		"lane_shelter":
			story.lane_lantern.stage = "shelter"
			run.window.max += 15
			run.window.cur = mini(int(run.window.max), int(run.window.cur) + 15)
			return "船匠扶着母亲进了西厢，当晚替你撑牢了窗扇。窗耐久与上限各加 15。"
		"lane_ferry":
			story.lane_lantern.stage = "ferry"
			return prompt(story, now)
		"lane_decline":
			story.lane_lantern.stage = "declined"
			return prompt(story, now)
	return ""


static func epilogue(story: Dictionary, kind: String) -> String:
	match str(story.get("lane_lantern", {}).get("stage", "")):
		"shelter": return "临走前，船匠接过院钥，答应照看西厢。" if kind == "escape" else "天亮后，西厢先起了炊烟。船匠给母亲盛了一碗，也替你留了一碗。"
		"ferry": return "河对岸的船工把白布高高系起。那一家人已经到了。"
		"declined": return "当初那条回信的白布收走后，你再没见过船匠。"
		"lit", "missed": return "你最后记得的，是船匠窗前那条白布。他们后来去了哪里，无人传信。"
	return ""

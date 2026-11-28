extends RefCounted
## 只按这份存档已经取得的线索写页。翻手记不推进故事，也不初始化旧卷的剧情字段。
const Rice = preload("res://scripts/core/rice_story.gd")
const Apothecary = preload("res://scripts/core/apothecary_story.gd")
const Trails = preload("res://scripts/core/supply_trails.gd")
const Lane = preload("res://scripts/core/lane_lantern.gd")
const Data = preload("res://scripts/core/data.gd")


static func pages(run: Dictionary) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	var rice := _rice(run, Rice.stage(run))
	if not rice.is_empty():
		all.append(rice)
	var flags = run.get("flags", {})
	if flags is Dictionary:
		var ticket := _ticket(run, flags)
		if not ticket.is_empty():
			all.append(ticket)
	var trails = run.get("supply_trails", {})
	if trails is Dictionary:
		for source: String in Trails.TRAILS:
			var record = trails.get(source)
			if record is Dictionary:
				var page := _waybill(run, source, record)
				if not page.is_empty():
					all.append(page)
	var story = run.get("mainline", {})
	if story is Dictionary:
		var letter = story.get("lane_lantern")
		if letter is Dictionary:
			var state := str(letter.get("stage", ""))
			if (state == "lit" and int(letter.get("reply_t", 0)) > 0) or state in ["shelter", "ferry", "declined", "missed"]:
				all.append(_letter(story, run))
	return all


static func _page(title: String, place: String, note: String, next := "") -> Dictionary:
	return {"title": title, "place": place, "note": note, "next": next}


static func _fallen(run: Dictionary, place: String) -> bool:
	var visit = run.get("explore", {})
	if visit is Dictionary and visit.get("point") == place:
		return false
	var day := int(Data.table("map_points")[place].get("fall_day", 0))
	return day > 0 and int(run.get("pday", 0)) >= day


static func _rice(run: Dictionary, step: String) -> Dictionary:
	if step == "":
		return {}
	var paper := "折角的赊书单上印着燕尾，背面写着「西巷，六碗」。"
	if step == "paper":
		if run.get("phase") == "pre":
			return _page("燕尾担", "米行门槛", paper, "带纸条去书肆。掌柜营业时，留一个时辰问他。")
		return _page("燕尾担", "米行门槛", paper + " 还没来得及见书肆掌柜，城里就出了事。")
	var lesson := "书肆掌柜教了我挑担换肩。" if step == "carry" else "书肆掌柜教了我认巷里的燕尾记号。"
	if Rice.heard_echo(run):
		return _page("燕尾担", "废弃米行 · 账簿背页", lesson + "\n" + Rice.echo_text(run))
	if run.get("phase") != "pre" and _fallen(run, "rice_ruin"):
		return _page("燕尾担", "米行旧账", lesson + " 米行已经沦陷，没能翻到掌柜提过的那本账。")
	return _page("燕尾担", "书肆 · 米行旧账", lesson, "掌柜提醒过，米行旧账簿背面还有字。有机会去米行翻翻账。")


static func _ticket(run: Dictionary, flags: Dictionary) -> Dictionary:
	const NAME := "七号药签"
	const PLACE := "回春堂 · 渡口"
	const PIGEON := "灾后第 2 日起，在家中于 08:00–18:00 翻「劫余录」的「人」，用纸鹤找过路客。"
	match flags.get(Apothecary.KEY):
		"fold":
			return _page(NAME, "回春堂", "旧药包里折着半张纸签，只辨得一个「七」字。",
				"去回春堂，请药师对一对柜里的寄药簿。" if run.get("phase") == "pre" else PIGEON)
		"signed":
			return _page(NAME, PLACE, "药师把两半纸签合在一起盖了印。七号箱存过一瓶金创药。", PIGEON)
		"kept":
			return _page(NAME, PLACE, "我请过路客把那瓶金创药捎回家。存单上添了一行：「按签交还，共一瓶。」")
		"sent":
			var day := int(flags.get(Apothecary.REPLY_DAY, 0))
			var next := "白天在家中用纸鹤找过路客接回信。"
			if day > 0:
				next = "第 %d 日起，08:00–18:00 在家中用纸鹤找过路客接回信。" % day
			return _page(NAME, PLACE, "我托过路客把金创药留给渡口抬担架的人。签背多了一枚指印。", next)
		"replied":
			return _page(NAME, PLACE, "留给渡口的药送到了。回信说：「夜里三趟，两副担架都回来了。」过路客还捎来一壶灯油。")
		"unsigned":
			return _page(NAME, PLACE, "过路客抄来了渡口旧账。七号箱少了药铺的印，已经跟着伤船走了。末行写着「两副担架，都回来了」。")
	return {}


static func _waybill(run: Dictionary, source: String, record: Dictionary) -> Dictionary:
	var trail: Dictionary = Trails.TRAILS[source]
	var place := str(Data.table("map_points")[source].name)
	var title := str(trail.name)
	match record.get("status"):
		"found":
			if _fallen(run, source):
				return _page(title, place, str(trail.clue) + " 后来那里沦陷，再也进不去了。")
			return _page(title, place, trail.clue, "去%s的原处，再决定怎样处置。" % place)
		"kept":
			return _page(title, place, "%s。我当场收下%s，这张运单就此作罢。" % [trail.keep, Data.describe_items(trail.small)])
		"marked", "open":
			var dest := Trails.destination(source)
			var note := "我留下了记号，抄下取件处：%s。" % dest
			if record.status == "open":
				note = "我已在%s打开旧藏。" % dest
			if _fallen(run, trail.dest):
				return _page(title, place, note + " 后来那里沦陷，再也进不去了。")
			var hint := "下次到%s，循着记号去找。" % dest
			if record.status == "open":
				var remaining = record.get("remaining", {})
				if remaining is Dictionary and not remaining.is_empty():
					hint = "旧藏里还剩%s，腾出背囊再去取。" % Data.describe_items(remaining)
				else:
					hint = "再到旧藏处查看。"
			return _page(title, place, note, hint)
		"empty":
			return _page(title, place, "已循着记号找到%s，最后一件物资也装进了背囊。" % Trails.destination(source))
	return {}


static func _letter(story: Dictionary, run: Dictionary) -> Dictionary:
	var now := int(run.get("t", 0))
	var detail := Lane.prompt(story, now)
	var status := Lane.status(story, now)
	if status == "reply" and not story.lane_lantern.get("notified", false):
		detail = "约定的时辰到了，去巷口窗边看看回音。"
	if status in ["waiting", "reply"]:
		return _page("巷口的白布", "巷口 · 船匠家", "我留了一盏灯，让对岸的船匠看见巷子里还有人。", detail.trim_prefix("巷口留灯 · "))
	return _page("巷口的白布", "巷口 · 船匠家", detail)

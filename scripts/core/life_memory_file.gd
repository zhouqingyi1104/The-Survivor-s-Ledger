extends RefCounted
## Human-readable runtime archive. Planning reads this file, not a renamed JSON copy.
const Past = preload("res://scripts/core/past_lives.gd")
const Data = preload("res://scripts/core/data.gd")
const MAX_CHARS := 8000
const ROLES := {"scholar": "落第书生", "escort": "镖局趟子手", "herbalist": "药铺学徒", "watchman": "打更人"}

static func line(value, limit := 240) -> String:
	return str(value).replace("\r", " ").replace("\n", " ").left(limit)

static func render(meta: Dictionary) -> String:
	var b := Past.book(meta)
	var text := "<!-- survivors-memory:v1 count:%d -->\n# 轮回记忆\n\n游戏每轮最终结算后更新。以下是已完结旧世，不能当作本世已经发生的事。\nAI 编剧可据此铺垫后续；NPC 只知道本世已经觉醒的片段。\n\n" % int(b.count)
	if b.lives.is_empty(): return text + "尚无已封存轮回；这一轮完结后会写入结局与关键选择。\n"
	for k in range(b.lives.size() - 1, -1, -1):
		var life: Dictionary = b.lives[k]
		var summary: Dictionary = life.get("summary", {})
		var section := "## 第 %d 世\n\n" % int(life.life)
		if not summary.is_empty():
			section += "- 身份：%s；模式：%s；最后到达：第 %d 日；结局：%s。\n" % [ROLES.get(str(summary.get("role", "")), "未知"), line(summary.get("mode", "未知"), 20), int(summary.get("day", 0)), line(summary.get("outcome", "未知"), 24)]
			if summary.get("cause", "") != "": section += "- 结束原因：%s\n" % line(summary.cause, 160)
			section += "- 守住尸潮：%d 次；击倒：%d。\n" % [int(summary.get("waves", 0)), int(summary.get("kills", 0))]
		section += "\n### 已确认人物往事\n\n"
		if life.facts.is_empty(): section += "没有可辨认的人物往事；不要据此编造相遇或恩怨。\n"
		for fact in life.facts:
			if Past.valid_fact(fact): section += "- %s · 第 %d 日：%s\n" % [Past.ACTORS[fact.actor], int(fact.get("day", 0)), line(fact.fact, 160)]
		if not summary.get("choices", []).is_empty():
			section += "\n### 关键选择回顾（原事件叙述，不能扩写成未经确认的疗效或死亡）\n\n"
			for choice in summary.choices:
				section += "- 第 %d 日 · %s：%s\n" % [int(choice.get("day", 0)), line(choice.get("title", ""), 40), line(choice.get("result", ""), 120)]
		if not summary.get("relations", {}).is_empty():
			section += "\n### 结算时世情关系\n\n"
			for actor in Past.ACTORS:
				if summary.relations.has(actor): section += "- %s：%+d\n" % [Past.ACTORS[actor], int(summary.relations[actor])]
		var trade := Past.trade_snapshot(summary.get("trade", {}))
		if not trade.is_empty():
			section += "\n### 旧世交易结算\n\n以下为旧世合卷时账本；旧债和待收回礼不带入新世，不是本世债务或可领取奖励。\n\n"
			for actor in Past.ACTORS:
				var person: Dictionary = trade.actors[actor]
				section += "- %s：信任 %+d；欠你的人情 %d；未化解失约 %d；累计失约 %d。\n" % [Past.ACTORS[actor], int(person.trust), int(person.favors), int(person.breaches), int(person.breach_total)]
			if trade.debt.is_empty():
				section += "- 未清旧债：无。\n"
			else:
				var debt: Dictionary = trade.debt
				section += "- 未清旧债：欠%s%s；约定第 %d 日 18:00 前偿还；%s。已赊取：%s。\n" % [Past.ACTORS[debt.actor], Data.describe_items(debt.req), int(debt.due_day), "当时已逾期" if debt.overdue else "当时尚未逾期", Data.describe_items(debt.give)]
			if trade.aid.is_empty(): section += "- 待收旧世回礼：无。\n"
			for gift in trade.aid:
				section += "- 待收旧世回礼：%s约定第 %d 日 08:00 送来%s；你已交出%s。\n" % [Past.ACTORS[gift.actor], int(gift.due_day), Data.describe_items(gift.give), Data.describe_items(gift.req)]
		section += "\n"
		if text.to_utf16_buffer().size() + section.to_utf16_buffer().size() > (MAX_CHARS - 100) * 2:
			text += "较早轮回的更多细节已按篇幅省略；上文优先保留最近完结的一轮。\n"
			break
		text += section
	return text

static func read_context(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_CHARS * 4: return {}
	var text := file.get_as_text()
	if text.strip_edges().is_empty() or text.to_utf16_buffer().size() > MAX_CHARS * 2: return {}
	return {"markdown": text, "sha256": text.sha256_text()}

static func count_in(text: String) -> int:
	var pattern := RegEx.new()
	pattern.compile("^<!-- survivors-memory:v1 count:([0-9]+) -->")
	var found := pattern.search(text)
	return int(found.get_string(1)) if found != null else -1

static func sync(meta: Dictionary, path: String) -> Error:
	if path == "": return ERR_UNCONFIGURED
	var b := Past.book(meta)
	if FileAccess.file_exists(path):
		var existing := read_context(path)
		if existing.is_empty():
			# An oversized/manual file is not permission to silently erase its contents.
			return ERR_FILE_CORRUPT
		# Preserve same-generation manual edits and never let an old run erase a newer book.
		if not existing.is_empty() and count_in(existing.markdown) >= int(b.count): return OK
	var absolute := ProjectSettings.globalize_path(path)
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(render(meta))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return error
	return DirAccess.rename_absolute(temporary, absolute)

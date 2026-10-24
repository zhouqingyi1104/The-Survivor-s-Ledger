extends RefCounted
## Human-readable runtime archive. Planning reads this file, not a renamed JSON copy.
const Past = preload("res://scripts/core/past_lives.gd")
const Data = preload("res://scripts/core/data.gd")
const MAX_CHARS := 8000
const ROLES := {"scholar": "落第书生", "escort": "镖局趟子手", "herbalist": "药铺学徒", "watchman": "打更人"}

static func line(value, limit := 240) -> String:
	return str(value).replace("\r", " ").replace("\n", " ").left(limit)

static func _crisis_line(entry: Dictionary) -> String:
	var titles := {"well_freeze": "井口冻裂", "fuel_shortage": "运柴中断", "herb_shortage": "药草挤兑"}
	var truth := {"unknown": "尚未核实，真假未知", "real": "已确认属实", "false": "已确认虚惊"}
	var responses := {"": "未选处置", "prepare": "自行筹备", "aid": "请线人帮忙", "ignore": "本次观望", "emergency": "事后补救"}
	var outcomes := {"": "本世合卷时尚未结案", "averted": "危机成真但影响被防住", "false_alarm": "虚惊结案", "endured": "影响自然结束", "repaired": "补救后提前恢复"}
	return "- %s · 来源%s · 第 %d 日公开：%s；%s，%s；%s。原定影响判定第 %d 日 18:00，自然结束第 %d 日 08:00。\n" % [titles[entry.kind], Past.ACTORS[entry.actor], int(entry.warning_day), truth[entry.confirmed], responses[entry.response], "处置已完成" if entry.protected else "没有完成提前处置", outcomes[entry.outcome], int(entry.warning_day) + 2, int(entry.warning_day) + 4]

static func _crisis_section(value, compact := false) -> String:
	var crisis := Past.crisis_snapshot(value)
	if crisis.is_empty(): return ""
	var out := "\n### 旧世风声与危机结算\n\n只记录曾公开的预兆与实际行动；未核实传闻仍是真假未知。旧世危机不是本世处罚，也不会自动搬到新世。\n\n"
	for entry in crisis.completed: out += _crisis_line(entry)
	if not crisis.active.is_empty(): out += _crisis_line(crisis.active)
	if not crisis.history.is_empty():
		out += "\n最近核实与应对记录：\n"
		for entry in crisis.history.slice(maxi(0, crisis.history.size() - (3 if compact else 6))):
			out += "- 第 %d 日 · %s：%s\n" % [int(entry.day), Past.ACTORS[entry.actor], line(entry.result, 60 if compact else 100)]
	return out

static func render(meta: Dictionary, compact := false) -> String:
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
		var facts: Array = life.facts.slice(maxi(0, life.facts.size() - 6)) if compact else life.facts
		for fact in facts:
			if Past.valid_fact(fact): section += "- %s · 第 %d 日：%s\n" % [Past.ACTORS[fact.actor], int(fact.get("day", 0)), line(fact.fact, 100 if compact else 160)]
		if not summary.get("choices", []).is_empty():
			section += "\n### 关键选择回顾（原事件叙述，不能扩写成未经确认的疗效或死亡）\n\n"
			var choices: Array = summary.choices.slice(maxi(0, summary.choices.size() - 4)) if compact else summary.choices
			for choice in choices:
				section += "- 第 %d 日 · %s：%s\n" % [int(choice.get("day", 0)), line(choice.get("title", ""), 40), line(choice.get("result", ""), 80 if compact else 120)]
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
		section += _crisis_section(summary.get("crisis", {}), compact)
		section += _npc_section(summary.get("npcs", {}), compact)
		section += _mainline_section(summary.get("mainline", {}))
		section += _identity_section(summary.get("identity", {}), compact)
		section += "\n"
		if text.to_utf16_buffer().size() + section.to_utf16_buffer().size() > (MAX_CHARS - 100) * 2:
			# Keep the newest complete life across all systems. Trim repeated prose,
			# never discard its entire story merely because a new system was added.
			if k == b.lives.size() - 1 and not compact: return render(meta, true)
			text += "较早轮回的更多细节已按篇幅省略；上文优先保留最近完结的一轮。\n"
			break
		text += section
	return text


static func _npc_section(value, compact := false) -> String:
	var npcs := Past.npc_snapshot(value)
	if npcs.is_empty(): return ""
	var modes := {"gather": "筹措周转", "stockpile": "备货自保", "guard": "收紧往来", "share": "主动回报"}
	var responses := {"": "未介入", "support": "玩家送物支援", "favor": "玩家凭情改托", "decline": "玩家由他安排"}
	var out := "\n### 旧世邻人自主行动\n\n以下是旧世的周转物资和行动记录；旧计划、库存和待送物资不带入新世。只有已经觉醒的本人片段才能影响今世决定。\n\n"
	for actor in Past.ACTORS:
		var person: Dictionary = npcs.actors[actor]
		out += "- %s：周转%s；新报价%s、%s。" % [Past.ACTORS[actor], Data.describe_items(person.stock), "加米 %d" % int(person.policy.price_add) if int(person.policy.price_add) > 0 else "无自主加价", "允许申请赊欠（仍受信用条件限制）" if person.policy.credit_allowed else "暂停新赊欠"]
		if not person.plan.is_empty():
			var p: Dictionary = person.plan
			var action := "原%s让位于凭情改托" % modes[p.mode] if p.response == "favor" else str(modes[p.mode])
			out += "第 %d 日%s，%s，%s。" % [int(p.day), action, responses[p.response], "已执行" if p.status == "done" else "合卷时尚未执行，不等于已兑现"]
		out += "\n"
	for fact in npcs.history.slice(maxi(0, npcs.history.size() - (3 if compact else 6))):
		out += "- 第 %d 日 · %s：%s\n" % [int(fact.day), Past.ACTORS[fact.actor], line(fact.result, 80 if compact else 100)]
	return out

static func _mainline_section(value) -> String:
	var story := Past.mainline_snapshot(value)
	if story.is_empty(): return ""
	var stages := {"waiting": "尚未公开主线", "contact": "道士尚待接待", "fallback": "自查路线待办", "mortuary": "义庄取证待办", "mortuary_choice": "义庄证据待处置", "temple": "青云观取证待办", "routes": "最终路线待选", "escape_ready": "已备撤离，尚未离城", "ritual_ready": "已备封阵，尚未熄灯", "sealed": "七灯已熄，仍须守残潮", "hold": "锁定守宅", "closed": "本世已结案", "failed": "未完成路线，转守宅", "endless": "继续守宅无尽"}
	var routes := {"": "尚未锁定", "hold": "坚守", "escape": "撤离", "ritual": "破阵"}
	var work_names := {"host": "接待道士", "self_route": "自行打听义庄路线", "disrupt": "截断运尸支路", "copy": "抄录运尸簿", "prepare_escape": "筹备撤离行装", "prepare_ritual": "筹备封阵法具", "prepare_light_escape": "筹备轻装撤离", "prepare_convoy": "筹备旧路早行", "prepare_paper_ritual": "筹备纸阵封阵", "escape": "沿后山道撤离", "search_mortuary": "义庄现场取证", "search_temple": "青云观现场取证", "search_ritual": "青云观现场封阵", "return_mortuary": "携义庄证物返程", "return_temple": "携青云观证物返程"}
	var out := "\n### 旧世主线与结局\n\n以下为旧世本世取证、施工和结案；旧残卷、旧路线与旧施工不等于新世已完成，未觉醒NPC不能据此得知旧事。\n\n"
	out += "- 进度：%s；路线：%s。\n" % [stages[story.stage], routes[story.route]]
	if story.route == "escape" and story.has("escape_method"): out += "- 本世撤离方式：%s；筹备和实际离城仍须分别完成。\n" % {"normal": "常规山道", "light": "更夫轻装更道", "convoy": "趟子手旧路早行"}[story.escape_method]
	if story.route == "ritual" and story.has("ritual_method"): out += "- 本世封阵方式：%s；筹备不等于已完成现场封阵。\n" % {"normal": "常规法具", "paper": "书生纸阵"}[story.ritual_method]
	out += "- 今世已实际交回证据：义庄%s；青云观%s。\n" % ["已取回" if story.evidence.mortuary else "未取回", "已取回" if story.evidence.temple else "未取回"]
	for key in ["disrupt_t", "ritual_t"]:
		var time := int(story.interventions[key])
		out += "- %s：%s。\n" % ["断运" if key == "disrupt_t" else "封阵", "第 %d 日完成" % (time / 1440 + 1) if time >= 0 else "尚未完成，不具有相应减潮效果"]
	if not story.work.is_empty(): out += "- 合卷时未完成工作：%s；原定第 %d 日完成，不能记作已经生效。\n" % [work_names[story.work.action], int(story.work.end_t) / 1440 + 1]
	if not story.ending.is_empty(): out += "- 实际结局：%s；%s\n" % [line(story.ending.title, 40), line(story.ending.text, 160)]
	else: out += "- 本线尚无已完成结局；材料投入不等于已经撤离或破阵。\n"
	for fact in story.history.slice(maxi(0, story.history.size() - 4)):
		out += "- 第 %d 日：%s\n" % [int(fact.day), line(fact.result, 80)]
	return out

static func _identity_section(value, compact := false) -> String:
	var identity := Past.identity_snapshot(value)
	if identity.is_empty(): return ""
	var names := {"scholar_collate": "书生校勘符诀", "scholar_diagram": "书生推演纸阵", "escort_intercept": "趟子手强截运尸", "escort_convoy": "趟子手勘旧路早行", "herbalist_lure": "学徒药饵引尸", "herbalist_ink": "学徒研制药墨", "watchman_lane": "更夫轻装探路", "watchman_intel": "更夫辨认残潮"}
	var skills := {"scribe_talisman": "校勘制符工法", "paper_ritual": "纸阵封阵筹备", "early_convoy": "第17日起旧路早行", "efficient_plague": "节料配避瘟散", "medicinal_talisman": "药墨制符", "light_escape": "轻装撤离筹备", "wave_intel": "第11/17/20夜尸数与特性情报"}
	var out := "\n### 旧世身份专属解法\n\n以下只记录旧世本人的选择和完成工法。旧世经验只解锁新世备选，不等于今世已学习、已取证或已施工；NPC仍须本人实际觉醒才知道旧事。\n\n"
	if identity.chosen == "": out += "- 合卷时身份工作尚未完工，专属能力尚未生效。\n" if not identity.work.is_empty() else "- 合卷时尚未选择身份解法。\n"
	elif int(identity.completed_t) < 0: out += "- 已选择%s，但合卷时没有完工，专属能力尚未生效。\n" % names[identity.chosen]
	else:
		out += "- 第 %d 日完成%s。\n" % [int(identity.completed_t) / 1440 + 1, names[identity.chosen]]
		if identity.learned.is_empty(): out += "- 这次设卡已按本世规则截断运尸，没有额外传承配方。\n"
		else: out += "- 本世实际掌握：%s；不会自动搬成新世成果。\n" % skills[identity.learned[0]]
	if not identity.work.is_empty(): out += "- 合卷时未完成工作：%s；原定第 %d 日完工，投入不代表已经学会或已经生效。\n" % [names[identity.work.action], int(identity.work.end_t) / 1440 + 1]
	for fact in identity.history.slice(maxi(0, identity.history.size() - (2 if compact else 4))):
		out += "- 第 %d 日：%s\n" % [int(fact.day), line(fact.result, 60 if compact else 80)]
	return out


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

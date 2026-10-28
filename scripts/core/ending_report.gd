extends RefCounted
## 结局复盘：赢也要知道自己是怎么赢的。
##
## 与生死簿残页对称——那边回答"我是怎么死的"，这边回答"我靠什么扛住的"。
## 只引用这一世真发生过的事：没受过伤就不写伤害，没修过门就不写修门，
## 用掉零张残页就闭嘴。宁可少一行，不编一句。

const State = preload("res://scripts/core/state.gd")
const Defense = preload("res://scripts/core/defense.gd")
const DeathReport = preload("res://scripts/core/death_report.gd")
const Mainline = preload("res://scripts/core/mainline.gd")

## 最多几条：结局页本来就有标题、结局文、残卷、道心、三个选项卡
const MAX_LINES := 4


## 返回 [{label, text}]。label 是短标签（"气血""三面""代价"），text 是一句话。
static func lines(run: Dictionary) -> Array:
	if run.is_empty():
		return []
	var out := []

	# 一、这一世总共掉了多少血，最狠的是哪一路
	var rep: Dictionary = DeathReport.report(run)
	var total := int(rep.get("total", 0))
	if total > 0:
		var top := ""
		var top_amount := 0
		for share in rep.shares:
			if int(share.amount) > top_amount:
				top_amount = int(share.amount)
				top = str(share.name)
		var text := "一共掉了 %d 点气血" % total
		if top != "":
			text += "，最狠的是%s（%d）" % [top, top_amount]
		out.append({"label": "气血", "text": text + "。"})

	# 二、三面最后剩多少：这是"你靠什么站在这里"的最直接答案
	# 撤离的人第20夜前就走了，宅院没撑到最后，只能说离城时的样子
	var parts := []
	for sid in Defense.SURFACES:
		var part: Dictionary = Defense.part_of(run, sid)
		parts.append("%s %d/%d" % [Defense.surface_name(sid), int(part.get("cur", 0)), int(part.get("max", 0))])
	var when := "离城时" if str(Mainline.ending(run).get("kind", "")) == "escape" else "撑到最后"
	out.append({"label": "三面", "text": when + "：" + "、".join(parts) + "。"})

	# 三、手上有过哪些办法（只在真的用过时说）
	# 不写 tally.home_trips：那是备劫时回家卸货的次数，不是劫后出门搜寻
	# 不写斩尸：结局页标题下面已经写了斩尸与守住几次
	var tally: Dictionary = State.tally(run)
	var deeds := []
	var repairs := int(tally.get("repair_door", 0))
	if repairs > 0:
		deeds.append("修补门窗墙 %d 次" % repairs)
	if not deeds.is_empty():
		out.append({"label": "手段", "text": "、".join(deeds) + "。"})

	# 四、代价：残页与同伴
	var costs := []
	var spent := 3 - int(run.get("rebirths_left", 3))
	if spent > 0:
		costs.append("用掉残页 %d 张" % spent)
	var mates: Array = run.get("companions", [])
	if not mates.is_empty():
		costs.append("同院 %d 人陪着" % mates.size())
	if not costs.is_empty():
		out.append({"label": "代价", "text": "、".join(costs) + "。"})

	if out.is_empty():
		out.append({"label": "这一世", "text": "平平安安地走到了这里。"})
	return out.slice(0, MAX_LINES)

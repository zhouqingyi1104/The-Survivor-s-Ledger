extends RefCounted
## 药签是本世的存单。看信、开窗或读档都不会替玩家兑走药。

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const KEY := "apothecary_ticket"
const REPLY_DAY := "apothecary_reply_day"


static func stage(run: Dictionary) -> String:
	return str(run.get("flags", {}).get(KEY, ""))


static func issue(run: Dictionary, action: String) -> String:
	var step := stage(run)
	if action in ["unfold", "identify"]:
		if run.get("phase") != "pre" or run.get("loc") != "pharmacy":
			return "要在备劫时去回春堂看。"
		if int(run.hour) < State.OPEN_HOUR or int(run.hour) > State.CURFEW_HOUR or Pre.status(run, "pharmacy") == "关门":
			return "药铺已打烊。"
		if action == "unfold":
			return "" if step == "" else "这张药签已经收下了。"
		if step != "fold":
			return "手上没有待辨的药签。"
		if run.role != "herbalist" and Pre.hours_left(run) < 1:
			return "药师要忙到打烊，得另找一个时辰。"
		return ""
	var access := Trade._access_block(run)
	if access != "":
		return access
	if str(run.get("home_floor", "courtyard")).begins_with("guest_"):
		return "回自家再与过路客通信。"
	match action:
		"keep", "send":
			return "" if step == "signed" else "七号药没有可兑的签了。"
		"ask":
			return "" if step == "fold" else "手上没有未辨的药签。"
		"reply":
			if step != "sent":
				return "没有待收的回信。"
			var day := int(run.flags.get(REPLY_DAY, 0))
			if day <= 0 or int(run.pday) < day:
				return "过路客还在渡口，第 %d 日 08:00 起再来接信。" % day
			return ""
	return "药签上没有这件事。"


static func act(run: Dictionary, action: String) -> String:
	var block := issue(run, action)
	if block != "":
		return block
	var result := ""
	match action:
		"unfold":
			run.flags[KEY] = "fold"
			result = "从回春堂柜脚的旧药包里翻出半张纸签，墨字只剩一个「七」。药师兴许认得。"
		"identify":
			if run.role != "herbalist":
				run.hour = int(run.hour) + 1
			run.flags[KEY] = "signed"
			result = "认出蜡封的金创药方，取药签上补了回春堂的印。药箱寄存在渡口。尸劫第 2 日起，白天从劫余录「人」里用纸鹤问过路客。"
		"keep":
			run.flags[KEY] = "kept"
			Inv.add(run.home, "salve", 1)
			result = "过路客照七号药签从渡口领回一瓶金创药，放在你家门槛上。存单已销。"
		"send":
			run.flags[KEY] = "sent"
			run.flags[REPLY_DAY] = int(run.pday) + 1
			var trust := int(Trade.contact(run, "traveler").trust)
			if trust < 5:
				Trade.influence(run, "traveler", 1, "七号药留给渡口抬担架的人")
			result = "七号金创药送给了渡口抬担架的人。" + ("过路客信任 +1。" if trust < 5 else "过路客已十分信任你。") + "他约你明日白天再接一次纸鹤。"
		"reply":
			run.flags[KEY] = "replied"
			Inv.add(run.home, "lamp_oil", 1)
			result = "回信上印着拇指和四个模糊的指印：「夜里三趟，两副担架都回来了。」过路客捎来一壶渡灯油，已经收进家中。"
		"ask":
			run.flags[KEY] = "unsigned"
			result = "过路客认得半张药签，可惜药铺的印没盖。无主的七号药早随伤船走了。他把渡口的旧账抄给你，末行写着「两副担架，都回来了」。"
	State.note(run, "七号药签 · " + result)
	return ""

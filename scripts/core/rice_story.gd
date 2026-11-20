extends RefCounted
## 米行短担：线索、学艺和劫后回响都留在本世。

const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const State = preload("res://scripts/core/state.gd")

const STAGE_KEY := "rice_story_stage"
const ECHO_KEY := "rice_story_echo"
const PAPER_TEXT := "你把短担翻过来，底下刻着一对燕尾。担绳里夹着张裁歪的纸条，正面印的是书肆的赊书单，背面也画着燕尾，旁边写着「西巷，六碗」。"


static func stage(run: Dictionary) -> String:
	var flags = run.get("flags", {})
	if flags is Dictionary:
		var value = flags.get(STAGE_KEY, "")
		if value is String and value in ["paper", "carry", "marks"]:
			return value
	return ""


## 短担靠在门槛外。最后一个时辰卸完粮，临走仍能翻看。
static func can_inspect(run: Dictionary) -> bool:
	if run.get("phase") != "pre" or run.get("loc") != "rice_shop" or not Pre.prep_work_done(run, "rice_shop"):
		return false
	return not run.flags.has(STAGE_KEY) and not run.flags.has(ECHO_KEY) \
		and int(run.hour) >= State.OPEN_HOUR and int(run.hour) <= State.CURFEW_HOUR


static func inspect(run: Dictionary) -> String:
	if not can_inspect(run):
		return "眼下翻不到这根短担。"
	run.flags[STAGE_KEY] = "paper"
	State.note(run, "短担底下刻着燕尾，担绳里有张书肆的纸条。去书肆问问，兴许有人认得。")
	return ""


static func lesson_issue(run: Dictionary) -> String:
	if run.get("phase") != "pre" or run.get("loc") != "bookshop":
		return "要趁备劫时到书肆问问。"
	var progress := stage(run)
	if progress in ["carry", "marks"]:
		return "这堂课已经学过了。"
	if progress != "paper" or run.flags.has(ECHO_KEY):
		return "手上缺了短担的纸条。"
	if int(run.hour) < State.OPEN_HOUR or Pre.hours_left(run) < 1:
		return "得留一个时辰跟掌柜学。"
	return ""


static func learn(run: Dictionary, choice: String) -> String:
	var issue := lesson_issue(run)
	if issue != "":
		return issue
	if choice not in ["carry", "marks"]:
		return "掌柜只教挑担和认记号。"
	run.flags[STAGE_KEY] = choice
	run.hour = int(run.hour) + 1
	var result: String
	if choice == "carry":
		run.attrs.hp_max = State.attr_max(run, "hp") + 5
		State.add_attr(run, "hp", 5)
		result = "学会了挑担换肩。本世气血上限和当前气血各加 5。"
	else:
		State.add_xp(run, "search", 10)
		result = "学会了认燕尾路标。本世搜寻经验增加 10 点。"
	State.note(run, result + "书肆掌柜说，米行那本旧账簿，背页也写过字。")
	return ""


static func heard_echo(run: Dictionary) -> bool:
	var flags = run.get("flags", {})
	return flags is Dictionary and flags.get(ECHO_KEY) is bool and flags[ECHO_KEY]


static func can_reveal(run: Dictionary) -> bool:
	if stage(run) not in ["carry", "marks"] or run.flags.has(ECHO_KEY) or run.get("phase") != "post":
		return false
	var ex: Dictionary = run.get("explore", {})
	if ex.get("point") != "rice_ruin" or Post._expedition_available(run) != "":
		return false
	# 只读本趟已经查到的账簿；查看能否翻页也不能替玩家初始化机关。
	var expedition = ex.get("expedition")
	if not expedition is Dictionary:
		return false
	var clues = expedition.get("clues")
	return clues is Array and clues.size() == 2 and clues[0] is bool and clues[0]


static func echo_text(run: Dictionary) -> String:
	match stage(run):
		"carry":
			return "账簿背页上，一个小人歪着肩膀挑担。画到下一个巷口，小人换了肩，站直了些。底下一行小字：「娘挑大担，我挑小担。西巷六碗，都送到了。」那个写得头大脚小的「碗」字，和你捡到的纸条上一模一样。"
		"marks":
			return "账簿背页画着一排燕尾，一直分到六扇小门。你顺着尾尖读，才看出这是当年送粥的路。第六扇门边有行新墨：「小时候，我在这儿等。今儿轮到我送。」落款盖着书肆的印。"
	return ""


static func reveal(run: Dictionary) -> String:
	if not can_reveal(run):
		return "眼下翻看不了这本账簿的背页。"
	run.flags[ECHO_KEY] = true
	State.note(run, echo_text(run))
	return ""

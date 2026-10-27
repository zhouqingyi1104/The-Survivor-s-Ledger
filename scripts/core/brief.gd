extends RefCounted
## 今日要务：玩家每天醒来只该回答一个问题——"今天做什么才不会死"。
##
## 这里**不新造任何规则或数值**，只从既有状态里挑出"现在就该知道"的几件事：
## 三面破没破、今夜尸潮挡不挡得住、柴炭够不够、粮和水还剩不剩、离劫满还有几天。
## 宁缺勿编：条件不成立就不出这条；全都不成立就直说"眼下没有急事"。
##
## 放在 core 里是为了能无界面断言——提示文案错了比没有提示更糟，
## 它会让玩家按错误的信息去准备。

const State = preload("res://scripts/core/state.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Defense = preload("res://scripts/core/defense.gd")

## 危急（今天不管就会死）/ 要紧（会在几日内咬人）/ 提醒（知道就好）
const ALARM := 2
const WARN := 1
const NOTE := 0
## 一次最多说几条：HUD 和面板都不是日志，多了等于没说
const MAX_LINES := 4


## 本局的目标，一句话。
static func goal(run: Dictionary) -> String:
	if run.is_empty():
		return "还没有开局。"
	if bool(run.get("endless", false)):
		return "守到死：没有终点，能撑多久算多久。"
	if str(run.get("phase", "")) == "pre":
		return "备劫第 %d / %d 日：尸劫之后要活过 %d 日。" % [
			int(run.get("day", 1)), State.PRE_DAYS, State.STORY_DAYS]
	var left: int = State.STORY_DAYS - int(run.get("pday", 0))
	if left > 0:
		return "距劫满还有 %d 日（共 %d 日）。" % [left, State.STORY_DAYS]
	return "已经活过 %d 日。" % State.STORY_DAYS


## 进度：0..1，用在进度条或"HUD 上的那句距离"。
static func progress(run: Dictionary) -> float:
	if run.is_empty() or bool(run.get("endless", false)):
		return 0.0
	return clampf(float(run.get("pday", 0)) / float(State.STORY_DAYS), 0.0, 1.0)


## 今天该注意的事。按 level 降序，最多 MAX_LINES 条。
static func lines(run: Dictionary) -> Array:
	if run.is_empty() or str(run.get("phase", "")) != "post":
		return []
	var out := []
	var wave := Defense.wave_for_run(run, int(run.get("pday", 0)))
	var has_wave := not wave.is_empty()

	# 一、已经砸穿到 0 的面：尸群可以直接进院子
	var broken := []
	for sid in Defense.SURFACES:
		if Defense.is_broken(run, sid):
			broken.append(Defense.surface_name(sid))
	if not broken.is_empty():
		out.append({"level": ALARM, "text": "%s已经砸穿到 0，尸群能直接进院子。" % "、".join(broken)})

	# 二、今夜有尸潮，但最弱的一面撑不住（这一条只在"今夜真的来"时说）
	if has_wave:
		var weakest := ""
		var weakest_pct := 101.0
		for sid in Defense.SURFACES:
			var part: Dictionary = Defense.part_of(run, sid)
			var maxv := maxf(1.0, float(part.get("max", 1)))
			var cur := float(part.get("cur", 0))
			if cur <= 0.0:
				continue
			var pct := cur / maxv
			if pct < weakest_pct:
				weakest_pct = pct
				weakest = Defense.surface_name(sid)
		if weakest != "" and weakest_pct < 0.3:
			out.append({"level": ALARM, "text": "今夜有尸潮，%s只剩 %d%%。" % [weakest, int(round(weakest_pct * 100.0))]})
		else:
			out.append({"level": WARN, "text": "今夜有尸潮：天黑前把门窗墙补齐、守具摆好。"})

	# 三、冷夜却没有能烧的
	var cold := int(State.weather(run).get("cold", 0))
	var wood := Inv.count(run.get("home", {}), "firewood")
	var coal := Inv.count(run.get("home", {}), "charcoal")
	if cold > 0 and wood + coal == 0:
		out.append({"level": WARN, "text": "今夜会冷，屋里没有柴也没有炭。"})
	elif cold > 0 and wood + coal <= 1 and not bool(run.get("heated", false)):
		out.append({"level": NOTE, "text": "只剩 %d 份柴炭，一捆柴只够烧半夜。" % (wood + coal)})

	# 四、断粮断水
	var food := Inv.total(run.get("home", {}), Inv.GRAINS) + Inv.total(run.get("home", {}), Inv.food_ids(run.get("home", {})))
	if food <= 0:
		out.append({"level": ALARM, "text": "仓里没有能下锅的东西了。"})
	if Inv.count(run.get("home", {}), "water") <= 0 and not State.has_facility(run, "water_vat"):
		out.append({"level": WARN, "text": "没有存水，也没有水缸；渴起来只能去井边。"})

	if out.is_empty():
		out.append({"level": NOTE, "text": "眼下没有急事，可以把日子往前过。"})
	out.sort_custom(func(a, b): return int(a.level) > int(b.level))
	return out.slice(0, MAX_LINES)


## HUD 上那一行短句：离劫满还有几天。
static func countdown(run: Dictionary) -> String:
	if run.is_empty():
		return ""
	if bool(run.get("endless", false)):
		return "守到死"
	if str(run.get("phase", "")) == "pre":
		return "%d 日后尸劫" % maxi(1, State.PRE_DAYS + 1 - int(run.get("day", 1)))
	var left: int = State.STORY_DAYS - int(run.get("pday", 0))
	if left > 0:
		return "距劫满 %d 日" % left
	return "劫满"

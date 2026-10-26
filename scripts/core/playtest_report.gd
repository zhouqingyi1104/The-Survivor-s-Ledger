extends RefCounted
## 试玩报告：把一局里"能拿来复现和定位问题"的事实整理成一份可读文本。
##
## 玩家说"有点难""卡住了"没法直接下手；但只要有种子、难度、死因账本、最后几十条日志，
## 就能在本地把那一局复现出来。所以报告只写事实，主观感受留给玩家自己填三个问题。
##
## 不编：没有账本就写没有账本，没有进行中的局就说没有，不拿属性去猜死因。

const State = preload("res://scripts/core/state.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const DeathReport = preload("res://scripts/core/death_report.gd")
const Pre = preload("res://scripts/core/pre.gd")

## 附上多少条日志：太少看不出过程，太多没人看
const LOG_TAIL := 40
## 客观数据之外，只能问玩家自己的三个问题
const QUESTIONS := [
	"最烦的三件事（哪一步让你想关掉游戏）：",
	"最看不懂的三处（不知道为什么要做、不知道做了会发生什么）：",
	"二十天是长了还是短了？从第几天开始觉得重复：",
]
## 分隔线（Markdown 里一眼能看出段落）
const RULE := "----"


## 生成报告的全文。ctx 见 Game.export_playtest() 的组装处：
##   version / engine / os / resolution / save_bytes / bindings / director
static func build(run: Dictionary, meta: Dictionary, ctx: Dictionary = {}) -> String:
	var out := []
	out.append("# 劫余录 试玩报告")
	out.append("")
	out.append("生成：%s　版本：%s　引擎：%s" % [
		str(ctx.get("now", State.today_text())), str(ctx.get("version", "?")), str(ctx.get("engine", "?"))])
	out.append("系统：%s　分辨率：%s　存档：%s" % [
		str(ctx.get("os", "?")), str(ctx.get("resolution", "?")), str(ctx.get("save_bytes", "无"))])
	out.append("")
	out.append(RULE)
	out.append("")

	if run.is_empty():
		out.append("## 这一局")
		out.append("")
		out.append("（当前没有在进行的局：报告只含跨轮回底稿与本机设置。）")
	else:
		out.append_array(_run_section(run))
		out.append_array(_damage_section(run))
		out.append_array(_log_section(run))
	out.append_array(_meta_section(meta))
	out.append_array(_settings_section(ctx))
	out.append_array(_questions_section())
	return "\n".join(out) + "\n"


# ---------- 这一局 ----------

static func _run_section(run: Dictionary) -> Array:
	var out := []
	var role_name := "?"
	var role: Dictionary = State.role(run)
	if not role.is_empty():
		role_name = str(role.get("name", run.get("role", "?")))
	var phase := str(run.get("phase", ""))
	var alive := phase == "post" or phase == "pre"
	var mode := []
	if bool(run.get("endless", false)):
		mode.append("守到死")
	if Past.daily(run):
		mode.append("每日一局")
	var tally: Dictionary = run.get("tally", {}) if run.get("tally") is Dictionary else {}
	var vows: Array = tally.get("vows", [])
	var goals: Array = tally.get("goals", [])

	out.append("## 这一局")
	out.append("")
	out.append("身份：%s　难度：%s　模式：%s" % [
		role_name, State.diff_name(run), "、".join(mode) if not mode.is_empty() else "寻常"])
	out.append("世次：第 %d 世　种子：%d（拿这个能在同一版本复现）" % [
		int(Past.state(run).generation) + 1, int(run.get("seed", 0))])
	out.append("开局：%s" % _opening_text(run))
	if not vows.is_empty() or not goals.is_empty():
		out.append("挑战：誓约 %d 条、了愿 %d 条" % [vows.size(), goals.size()])
	out.append("")
	if alive:
		out.append("**还在进行**：第 %d 日 · %s · 气血 %d/%d" % [
			int(run.get("pday", 0)), _clock_text(run), int(State.attr(run, "hp")), int(State.attr_max(run, "hp"))])
		out.append("手头：%s" % (str(run.get("busy", {}).get("label", "")) if State.attr(run, "energy") >= 0 and not run.get("busy", {}).is_empty() else "空闲"))
	else:
		var end: Dictionary = Mainline.ending(run)
		if not end.is_empty():
			out.append("**结局**：%s" % str(end.get("title", "结局")))
			out.append("")
			out.append("> %s" % str(end.get("text", "")))
		else:
			out.append("**身死**：第 %d 日" % int(run.get("pday", 0)))
			out.append("")
			out.append("> %s" % str(run.get("death_cause", "（没有记下死因）")))
	out.append("")
	out.append("战果：守住 %d 夜尸潮　斩 %d 只　功德 %d　余银 %s" % [
		int(run.get("waves_survived", 0)), int(run.get("kills", 0)), int(run.get("merit", 0)), Pre.money(int(run.get("silver", 0)))])
	out.append("")
	out.append(RULE)
	out.append("")
	return out


static func _opening_text(run: Dictionary) -> String:
	var o: Dictionary = run.get("opening", {}) if run.get("opening") is Dictionary else {}
	var choice := str(o.get("choice", "plain"))
	if choice == "" or choice == "plain":
		return "普通行囊"
	return "%s（%s）" % [str(o.get("label", choice)), str(o.get("summary", "")).strip_edges()]


static func _clock_text(run: Dictionary) -> String:
	if str(run.get("phase", "")) == "pre":
		return "备劫第 %d 日" % int(run.get("day", 1))
	return State.time_label(run)


# ---------- 失血构成 ----------

static func _damage_section(run: Dictionary) -> Array:
	var out := []
	var reps: Dictionary = DeathReport.report(run)
	out.append("## 死因构成")
	out.append("")
	if int(reps.get("total", 0)) <= 0:
		out.append("（这一局没有掉血记录：老存档，或还没受过伤。）")
		out.append("")
		out.append(RULE)
		out.append("")
		return out
	var parts := []
	for s in reps.shares:
		parts.append("%s %d" % [str(s.name), int(s.amount)])
	out.append("本世共失血 %d：%s" % [int(reps.total), " · ".join(parts)])
	if str(reps.last) != "":
		out.append("最后一击：%s" % str(reps.last))
	if not (reps.hints as Array).is_empty():
		out.append("当时的余地：%s" % "／".join(reps.hints))
	out.append("")
	out.append(RULE)
	out.append("")
	return out


# ---------- 日志 ----------

static func _log_section(run: Dictionary) -> Array:
	var out := []
	var log: Array = run.get("log", [])
	out.append("## 最后 %d 条记录" % mini(LOG_TAIL, log.size()))
	out.append("")
	if log.is_empty():
		out.append("（没有记录。）")
	else:
		for i in range(maxi(0, log.size() - LOG_TAIL), log.size()):
			out.append("- %s" % str(log[i]))
	out.append("")
	out.append(RULE)
	out.append("")
	return out


# ---------- 跨轮回底稿 ----------

static func _meta_section(meta: Dictionary) -> Array:
	var out := []
	out.append("## 跨轮回底稿")
	out.append("")
	out.append("道心 %d　轮回 %d 次　身死 %d 次　劫满 %d 次　最久活到第 %d 日　残卷 %d 篇" % [
		int(meta.get("daoxin", 0)), int(meta.get("runs", 0)), int(meta.get("deaths", 0)),
		int(meta.get("endings", 0)), int(meta.get("best_day", 0)), (meta.get("clues", []) as Array).size()])
	var book: Dictionary = meta.get("past_lives", {}) if meta.get("past_lives") is Dictionary else {}
	var count := int(book.get("count", 0))
	if count > 0:
		out.append("前世档案：已记 %d 世" % count)
	out.append("")
	out.append(RULE)
	out.append("")
	return out


# ---------- 本机设置 ----------

static func _settings_section(ctx: Dictionary) -> Array:
	var out := []
	out.append("## 本机设置")
	out.append("")
	var bindings: Dictionary = ctx.get("bindings", {}) if ctx.get("bindings") is Dictionary else {}
	if bindings.is_empty():
		out.append("按键：全部默认")
	else:
		var changed := []
		for action in bindings:
			changed.append("%s→%s" % [str(action), str(bindings[action])])
		out.append("改过的键位：%s" % "，".join(changed))
	out.append("动态世情：%s" % ("开" if bool(ctx.get("director", true)) else "关"))
	out.append("")
	out.append(RULE)
	out.append("")
	return out


# ---------- 留给玩家的问题 ----------

static func _questions_section() -> Array:
	var out := []
	out.append("## 请顺手回答三句（不答也行）")
	out.append("")
	for q in QUESTIONS:
		out.append("**%s**" % q)
		out.append("")
		out.append("　")
		out.append("")
	return out

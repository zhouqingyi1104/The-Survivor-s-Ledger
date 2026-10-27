extends SceneTree
## 玩法说明的规则测试：每条都有内容、键位跟着改键走、关键规则一条都不能漏。
## 运行：godot --headless --path . --script res://tests/manual.gd
##
## 说明是玩家唯一的规则来源（游戏里没有别的"教程"），漏掉一条关键规则，
## 新玩家就会以为什么都不会发生——所以这里对着"必须讲到的规则"逐条断言。

const Data = preload("res://scripts/core/data.gd")
const InputCfg = preload("res://scripts/core/input_cfg.gd")
const State = preload("res://scripts/core/state.gd")
const Manual = preload("res://scripts/core/manual.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	Data.ensure()
	test_shape()
	test_facts_covered()
	test_keys_follow_binding()
	test_no_advice()
	print("[manual] %d 项检查，失败 %d 处" % [checks, failures])
	quit(0 if failures == 0 else 1)


# ---------- 一、结构 ----------

func test_shape() -> void:
	var sections := Manual.sections()
	check(sections.size() >= 3, "说明只有 %d 组，太少" % sections.size())
	var titles := {}
	var rows := 0
	for section in sections:
		var title := str(section.get("title", ""))
		check(title != "", "有一组没有标题")
		check(not titles.has(title), "组标题重复：%s" % title)
		titles[title] = true
		var list: Array = section.get("rows", [])
		check(not list.is_empty(), "「%s」这一组是空的" % title)
		for row in list:
			var text := Manual.render_row(row)
			check(text.strip_edges() != "", "「%s」里有一行是空的" % title)
			check(text.length() <= 60, "「%s」有一行太长（%d 字）：%s" % [title, text.length(), text])
			rows += 1
	check(rows <= 24, "说明一共 %d 行，太长了没人读" % rows)


# ---------- 二、关键规则必须讲到 ----------

func test_facts_covered() -> void:
	var all := ""
	for section in Manual.sections():
		for row in section.rows:
			all += Manual.render_row(row) + "\n"
	var must := {
		"20": "劫满要活多少日",
		"22:00": "尸潮在几点",
		"18:00": "天黑在几点",
		"体温": "体温会掉、会冻死",
		"尸毒": "尸毒不会自己好",
		"精力": "精力限制一天能做几件事",
		"砸穿": "三面会被砸穿",
	}
	for key in must:
		check(all.contains(key), "说明里漏了：%s（%s）" % [key, must[key]])
	check(all.contains("守到死"), "没有说明「守到死」这个模式")
	check(all.contains("三次"), "没有说明残页能给几次机会")


# ---------- 三、键位跟着改键走 ----------

func test_keys_follow_binding() -> void:
	var used := Manual.actions_used()
	check(used.size() >= 5, "常用键只列了 %d 个" % used.size())
	for action in used:
		check(action in InputCfg.ORDER, "说明里引用了不存在的动作：%s" % action)
		check(InputCfg.first_key_name(action) != "", "动作 %s 没有默认键，说明里会显示成 —" % action)

	# 改键以后说明里的键位必须跟着变（否则玩家按着说明按不出东西）
	InputCfg.boot()
	var before := Manual.render_row({"action": "journal", "text": "劫余录"})
	check(before.begins_with(InputCfg.first_key_name("journal")), "渲染结果没带上当前键位：%s" % before)
	var bound := InputCfg.rebind("journal", KEY_Y)
	check(bound, "改键失败（Y 可能已被占用），这条用例要换键")
	var after := Manual.render_row({"action": "journal", "text": "劫余录"})
	check(after.begins_with("Y"), "改键后说明里的键位没跟着变：%s" % after)
	InputCfg.restore()
	check(Manual.render_row({"action": "journal", "text": "劫余录"}) == before, "恢复默认后说明没跟着回去")


# ---------- 四、只讲规则，不给策略 ----------

func test_no_advice() -> void:
	var all := ""
	for section in Manual.sections():
		for row in section.rows:
			all += Manual.render_row(row) + "\n"
	# "该买多少米/几捆柴"这类建议不能写进说明：算不准就会误导，策略让玩家自己长出来
	for word in ["买", "推荐", "建议买", "斗米", "斤柴"]:
		check(not all.contains(word), "说明里混进了策略建议：「%s」" % word)


func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok: return
	failures += 1
	push_error("断言失败：" + msg)

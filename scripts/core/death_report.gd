extends RefCounted
## 死因复盘：死的那一刻，玩家要看得懂**是谁、在什么时候、把哪一项熬干**的。
##
## 改前是事后按属性猜：先看渴、再看饿、再看瘟、再看冻，全都对不上就写「力竭而亡」。
## 于是夜里被咬死的人可能被写成「饿死」（饱腹刚好为 0），破院被扑死的人只能得到
## 一句没有日子、没有原因的「力竭而亡」。
##
## 现在死因来自扣血时的账本（`State.hurt`），属性猜测只作老存档的兜底。
## 文件头上不 preload State 会被反复用到（时间、属性、设施、库存），所以单向依赖：
## 本文件 → state.gd。state.gd 不反向引用本文件，避免 preload 成环。

const State = preload("res://scripts/core/state.gd")
const Inv = preload("res://scripts/core/inv.gd")

## 账本里的伤害来源：name 用在复盘表，kill 用在死因那句。
const TAGS := {
	"starve": {"name": "受饿", "kill": "饿死"},
	"thirst": {"name": "渴", "kill": "渴死"},
	"plague": {"name": "尸瘟", "kill": "尸瘟入骨，没能熬过去"},
	"freeze": {"name": "酷寒", "kill": "冻死"},
	"cold": {"name": "受冻", "kill": "冻死"},
	"overrun": {"name": "院破被扑", "kill": "院门被撞破，被扑死"},
	"bite": {"name": "夜战失血", "kill": "夜战失血而死"},
	"sortie": {"name": "出门迎战", "kill": "出门迎战，力尽而死"},
	"raid": {"name": "溃兵夜袭", "kill": "死于溃兵刀下"},
	"wound": {"name": "受伤", "kill": "伤重不治"},
	"event": {"name": "意外", "kill": "死于意外"},
}


## 判词：现场写好的那句优先（「尸潮破门，死在第 3 夜」），
## 没给就用账本算，账本也是空的（老存档 / 没插桩的路径）才退回属性猜测。
static func verdict(run: Dictionary, explicit := "") -> String:
	if explicit != "":
		return explicit
	var top := main_source(run)
	if top.is_empty():
		return guess(run)
	return "%s，%s。" % [when_text(run), str(top.kill)]


## 属性猜测：只在没有账本时用。保留是因为 v20 以前的老存档没有扣血记录。
static func guess(run: Dictionary) -> String:
	var when := when_text(run)
	if State.attr(run, "water") <= 0:
		return "%s，渴死。" % when
	if State.attr(run, "food") <= 0:
		return "%s，饿死。" % when
	if bool(run.get("plague", false)):
		return "%s，尸瘟入骨。" % when
	if State.attr(run, "warmth") < 30:
		return "%s，冻死。" % when
	return "%s，气血耗尽。" % when


## 本世死时的时刻，形如「第 13 日·03:20」。
static func when_text(run: Dictionary) -> String:
	return State.time_label(run)


## 账本里最重的那一项：{"tag","name","kill","amount"}；没有账本返回空字典。
## 平手时取"最后那一击"——两样各扣了 41，真正把血打光的是后落下的那一下。
static func main_source(run: Dictionary) -> Dictionary:
	var table: Dictionary = run.get("hp_log", {}) if run.get("hp_log") is Dictionary else {}
	var last_tag := ""
	if run.get("last_hurt") is Dictionary:
		last_tag = str(run.get("last_hurt", {}).get("tag", ""))
	var best_tag := ""
	var best_amount := 0.0
	for tag in table:
		var amount := float(table[tag])
		if amount <= 0.0:
			continue
		var heavier := amount > best_amount + 0.001
		var tie_with_last := absf(amount - best_amount) <= 0.001 and str(tag) == last_tag
		if best_tag == "" or heavier or tie_with_last:
			best_tag = str(tag)
			best_amount = amount
	if best_tag == "":
		return {}
	return {"tag": best_tag, "name": name_of(best_tag),
		"kill": str(TAGS.get(best_tag, {}).get("kill", "气血耗尽")), "amount": best_amount}


## 死因构成：按量降序、只留 >0 的项。界面直接铺成一行。
## 平手时把判词认定的那一项排前面，免得"判词说冻死、提醒却讲饿"。
static func shares(run: Dictionary, limit := 4) -> Array:
	var table: Dictionary = run.get("hp_log", {}) if run.get("hp_log") is Dictionary else {}
	var main_tag := str(main_source(run).get("tag", ""))
	var out := []
	for tag in table:
		var amount := float(table[tag])
		if amount < 1.0:
			continue
		out.append({"tag": str(tag), "name": name_of(str(tag)), "amount": int(round(amount))})
	out.sort_custom(func(a, b):
		if int(a.amount) != int(b.amount):
			return int(a.amount) > int(b.amount)
		return str(a.tag) == main_tag)
	return out.slice(0, limit)


## 死因里认不出来的来源也别吞掉，原样显示，方便以后插桩补名字。
static func name_of(tag: String) -> String:
	var def: Dictionary = TAGS.get(tag, {})
	return str(def.get("name", tag))


## 本世实际掉掉的总气血。从整本账算，不受界面只显示前四项的影响。
static func total_lost(run: Dictionary) -> int:
	var table: Dictionary = run.get("hp_log", {}) if run.get("hp_log") is Dictionary else {}
	var sum := 0.0
	for tag in table:
		sum += maxf(0.0, float(table[tag]))
	return int(round(sum))


## 生死簿残页要的那一整份复盘。
##   verdict 判词 / when 时刻 / total 本世总失血 / shares 构成（最多四项）
##   last 最后一击 / steps 死之前两条真实记录 / hints 由真实数据推出来的提醒（可能为空）
static func report(run: Dictionary) -> Dictionary:
	var last: Dictionary = run.get("last_hurt", {}) if run.get("last_hurt") is Dictionary else {}
	return {
		"verdict": str(run.get("death_cause", "")),
		"when": when_text(run),
		"total": total_lost(run),
		"shares": shares(run),
		"last": _last_line(run, last),
		"steps": _steps(run, 2),
		"hints": hints(run, str(main_source(run).get("tag", ""))),
	}


## 最后一击：「第 13 日·03:20 酷寒 −6（气血 5 → 0）」。没有账本返回空串。
static func _last_line(run: Dictionary, last: Dictionary) -> String:
	if last.is_empty():
		return ""
	var tag := str(last.get("tag", ""))
	var amount := int(round(float(last.get("amount", 0.0))))
	var before := int(round(float(last.get("before", 0.0))))
	# run.t 是"劫后第一天 6:00 起的分钟数"，换回日子再借 time_label 排版
	var at := int(last.get("at", 0))
	var day := at / 1440 + 1
	var moment: String = State.time_label({"phase": "post", "pday": day, "t": at})
	return "%s %s −%d（气血 %d → %d）" % [moment, name_of(tag), amount, before, maxi(0, before - amount)]


## 死之前三条真实记录：日志末尾，去掉最后那句「气血已尽」。
static func _steps(run: Dictionary, want: int = 3) -> Array:
	var log: Array = run.get("log", [])
	var out := []
	for i in range(log.size() - 1, -1, -1):
		var line := str(log[i])
		if line.contains("气血已尽"):
			continue
		out.append(line)
		if out.size() >= want:
			break
	out.reverse()
	return out


## 一句能落地的提醒：只引用真实存在的库存、设施、破损情况，宁缺勿编。
static func hints(run: Dictionary, main_tag: String) -> Array:
	var out := []
	var home: Dictionary = run.get("home", {}) if run.get("home") is Dictionary else {}
	match main_tag:
		"freeze", "cold":
			var wood := Inv.count(home, "firewood")
			var coal := Inv.count(home, "charcoal")
			if not bool(run.get("heated", false)):
				var tail := ""
				var bits := []
				if wood > 0: bits.append("%d 根柴" % wood)
				if coal > 0: bits.append("%d 块炭" % coal)
				if not bits.is_empty():
					tail = "，仓里还剩 %s 没烧" % "、".join(bits)
				elif int(run.get("pday", 0)) > 1:
					tail = "，仓里连柴和炭都没有了——冷夜前得先去柴铺"
				out.append("这一夜没生火" + tail + "。")
				if not State.has_facility(run, "cellar"):
					out.append("地窖能把冷夜的掉温减半，这一世没修。")
			elif bool(run.get("heat_weak", false)):
				out.append("一捆柴只够烧半夜，后半夜还是掉了温。")
		"starve":
			var food := Inv.total(home, Inv.GRAINS) + Inv.total(home, Inv.food_ids(home))
			if food > 0:
				out.append("死时仓里还有 %d 份吃的没做成饭（做一次饭要一个时辰）。" % food)
			else:
				out.append("仓里已经没有吃的了——炊饼和米得在备劫时先囤。")
		"thirst":
			var water := Inv.count(home, "water")
			if water > 0:
				out.append("死时行囊里还有 %d 瓢清水。" % water)
			elif State.has_facility(run, "water_vat"):
				out.append("水缸还在，打一次水只要一刻钟。")
			else:
				out.append("这一世没置水缸，喝水只能去井边打。")
		"overrun", "bite", "sortie", "raid":
			var gone := []
			for part in [["door", "院门"], ["window", "窗"], ["wall", "院墙"]]:
				var cur := int(run.get(part[0], {}).get("cur", 1)) if run.get(part[0]) is Dictionary else 1
				if cur <= 0:
					gone.append(str(part[1]))
			if not gone.is_empty():
				out.append("%s 被砸穿到 0 之后一直没补，尸群可以直接进院子。" % "、".join(gone))
		"plague":
			out.append("尸毒每小时都在扣血——药铺的避瘟散能压住，染上当天就该去。")
	# 只留两条：生死簿残页一行一条，多了会把版面撑破，也记不住
	return out.slice(0, 2)

extends RefCounted
## 每次到访的可选现场调查。阶段成果只属于本次现场，不与主线目标相互锁定。
const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const State = preload("res://scripts/core/state.gd")

# title, situation, careful action, item, careful effect
const CONTENT := {
	"rice_ruin": [
		["辨认粮袋", "柜台下干湿袋混在一起，标签沾满泥。", "逐袋辨认并拣出干粮", "rice", "loot"],
		["挪开账房粮袋", "账房的麻袋堆堵住一段通路，旁边还有绕行路。", "包住袋口并挪开粮袋", "millet", "quiet"],
		["查验漏雨", "后院屋檐漏水，伙计留下的干粮悬在梁下。", "查验布包里的干粮", "flatbread", "loot"]],
	"city_god": [
		["查看香客遗物", "香客院的包袱散在积雪中。", "逐一查看并收好遗物", "mugwort", "loot"],
		["整理殿前供器", "碎供器散在殿前，翻找时碰撞会惊动外面的东西。", "包好供器，减少翻找声响", "talisman_paper", "quiet"],
		["清点偏殿供品", "偏殿供品被布遮住，有些已经受潮。", "揭布检查仍能用的供品", "flatbread", "loot"]],
	"school": [
		["寻找散页", "讲堂的书页被风吹进桌底。", "按页整理并捡起纸张", "talisman_paper", "loot"],
		["扶正书架", "歪倒的书架挡住一段通路，也可以绕行；木榫随时会响。", "稳住木榫再移开书架", "wood", "quiet"],
		["检查斋舍", "斋舍床铺下压着教习的旧笔记。", "翻检铺盖并保存残卷", "book_farm", "loot"]],
	"pharmacy_ruin": [
		["核对处方", "诊台留有水渍处方，药名有的模糊不清。", "核对清楚可辨药材", "mugwort", "loot"],
		["安置药碾", "炮制间药碾附近散落的碎瓷容易碰响。", "垫布包住碎瓷，减少翻找声", "cinnabar", "quiet"],
		["检验药罐", "药罐上封泥开裂，不能一股脑混在一起。", "逐罐查验，挑出干燥药材", "mugwort", "loot"],
		["检查掌柜卧房", "床边药箱里有一块干净布包。", "打开药箱，检查布包", "salve", "loot"],
		["辨别药渣", "火塘边的药渣里混着可用药包。", "分拣残渣，确认剩药", "plague_powder", "loot"]],
	"lumber": [
		["查看工棚", "工棚里有散落的木楔和修理物。", "仔细挑出还能用的零件", "nails", "loot"],
		["卸开木架", "一排松动的木架堵住一段运木道，旁边还有绕行路。", "先固定木架，再慢慢卸开", "wood", "quiet"],
		["分拣锯棚", "锯棚的碎木混着潮湿木屑。", "挑出能烧的干木", "firewood", "loot"],
		["检查铁匠角", "铁匠角的工具散在铁屑中。", "拨开铁屑寻找旧钉", "nails", "loot"],
		["察看木库", "木库里几截木头压在一起。", "拆开木垛，选择能带走的木料", "wood", "loot"]],
	"mortuary": [
		["查点停棺簿", "簿册夹着镇尸用的旧符纸。", "查清记录并收好符纸", "talisman", "loot"],
		["安置灵幡", "风吹得灵幡和铜铃撞在一起。", "系住灵幡，压低响声", "ink_line", "quiet"],
		["检查香炉", "前厅香炉积满灰，里面埋着旧符。", "慢慢拨灰取出旧符", "talisman", "loot"],
		["查看守庄人柜", "柜门上有干涸的朱印，抽屉勉强能打开。", "检查抽屉里的供物", "lamp_oil", "loot"],
		["整理棺前绳索", "棺前绳索散落，稍不留神便会拖响木板。", "整理绳索，消除已发出的部分声响", "ink_line", "relief"],
		["检视供案", "偏房供案的油盏尚有余油。", "确认油盏没有渗漏", "lamp_oil", "loot"],
		["查验封棺印", "封棺印残缺，棺边有一只小木盒。", "辨认封印并取出木盒", "dog_blood", "loot"],
		["检查停尸角", "停尸角的席子下露出符纸一角。", "轻揭席子检查符纸", "talisman", "loot"]],
	"granary": [
		["清点验牌", "破粮车旁的验牌和粮袋散落一地。", "对照验牌拣出完整粮袋", "millet", "loot"],
		["垫住粮道", "粮道木板松脱，翻找时碰到会发响。", "垫住松板，减少之后翻找声响", "rice", "quiet"],
		["检查车底", "倒伏粮车下夹着几个小袋。", "稳住车身再取出袋子", "rice", "loot"],
		["查看仓吏房", "仓吏房的粮票和口粮搁在一起。", "逐一核对残存口粮", "jerky", "loot"],
		["搬开堵门杂物", "仓道上堆着破架和空筐，旁边还有绕行路。", "分批搬开杂物并避免碰撞", "millet", "relief"],
		["筛查西仓", "西仓粮袋破口处混入沙土。", "筛出仍可食用的杂粮", "millet", "loot"],
		["查验东仓", "东仓角落里有浸水的稻袋。", "挑出内部干燥的粮食", "rice", "loot"],
		["检查粮栅边", "粮栅旁的布包被压在横木下。", "托住横木取出布包", "glutinous", "loot"]],
	"taoist_temple": [
		["查看山门", "山门旁有被雪掩住的供包。", "扫开积雪检查供包", "talisman", "loot"],
		["固定风铃", "前庭风铃随风作响，容易惊动山道上的东西。", "系住风铃，掩藏脚步声", "cinnabar", "quiet"],
		["整理经阁", "经阁残卷落在一堆香灰中。", "拨开香灰保存残卷", "book_daoist", "loot"],
		["辨认灵田", "灵田边几株药草尚未被雪盖住。", "辨清药草，采收能用的部分", "lingzhi", "loot"],
		["整理符案", "符案上的镇纸掉落，铜器碰撞作响。", "稳住铜器，平息已有动静", "talisman", "relief"],
		["检查丹炉", "丹炉周围散着药屑和小瓷瓶。", "检查干净的瓷瓶", "cinnabar", "loot"],
		["查访静室", "观主静室的书匣藏在帘后。", "检查书匣并保留残页", "book_daoist", "loot"],
		["辨认阵角", "阵角的朱砂褪色，几张符压在石块下。", "查看阵角并收起旧符", "talisman", "loot"]],
}


static func profile(pid: String) -> Dictionary:
	if not CONTENT.has(pid): return {}
	var grade := "easy" if pid in ["rice_ruin", "city_god", "school"] else ("medium" if pid in ["pharmacy_ruin", "lumber"] else "hard")
	# 行走时间由真实现场时钟推进；这里只列一次行动本身的游戏内耗时。
	var minutes := 15 if grade == "easy" else (30 if grade == "medium" else 43)
	var estimated := "3–5小时" if grade == "easy" else ("4–8小时" if grade == "medium" else "8–12小时")
	var stages := []
	for i in CONTENT[pid].size():
		var row: Array = CONTENT[pid][i]
		var effect := str(row[4])
		var obstacle: bool = (pid in ["rice_ruin", "school", "lumber"] and i == 1) or (pid == "granary" and i == 4)
		var item := Data.describe_items({str(row[3]): 1})
		var gain := "发现%s，留在现场，可按负重取放" % item if effect == "loot" else ("本趟普通翻找外泄最多减少16，不获得物资" if effect == "quiet" else "当前外泄最多减少20，不获得物资")
		var clear_text := "；移除现场障碍" if obstacle else ""
		var remain_text := "；障碍保留，需绕行" if obstacle else ""
		stages.append({"id": "s%d" % i, "title": row[0], "text": row[1], "obstacle": obstacle, "choices": [
			{"id": "careful", "text": row[2], "minutes": minutes, "description": "%d分钟；%s%s。完成后不可改选。" % [minutes, gain, clear_text], "item": row[3], "effect": effect},
			{"id": "quick", "text": "快速翻取%s" % item, "minutes": minutes - 10, "description": "%d分钟；发现%s留在现场，阳气外泄最多增加12，满值会引来尸群%s。完成后不可改选。" % [minutes - 10, item, remain_text], "item": row[3], "effect": "quick"}]})
	return {"grade": grade, "estimated": estimated, "stages": stages}


static func state(run: Dictionary) -> Dictionary:
	var ex: Dictionary = run.get("explore", {})
	if ex.is_empty(): return {}
	if not ex.get("journey", null) is Dictionary: ex["journey"] = {}
	var s: Dictionary = ex.journey
	if not s.get("completed", null) is Dictionary: s["completed"] = {}
	if not s.get("caches", null) is Dictionary: s["caches"] = {}
	return s


static func choice(pid: String, stage_id: String, choice_id: String) -> Dictionary:
	for stage in profile(pid).get("stages", []):
		if str(stage.id) == stage_id:
			for c in stage.choices:
				if str(c.id) == choice_id: return c
	return {}


static func settle(run: Dictionary, stage_id: String, c: Dictionary) -> Dictionary:
	var ex: Dictionary = run.explore
	var s := state(run)
	s.completed[stage_id] = str(c.id)
	var effect := str(c.effect)
	var message := ""
	if effect == "quiet":
		ex["journey_quiet"] = true
		message = "已处理现场声响：本趟普通翻找外泄最多减少16。"
	elif effect == "relief":
		var before := int(ex.exposure)
		ex.exposure = maxi(0, before - 20)
		message = "现场整理完毕：阳气外泄减少%d。" % (before - int(ex.exposure))
	else:
		var items := {str(c.item): 1}
		s.caches[stage_id] = items
		message = "发现%s，留在现场供你挑选。" % Data.describe_items(items)
		if effect == "quick":
			var before := int(ex.exposure)
			ex.exposure = mini(100, int(ex.exposure) + 12)
			message += " 阳气外泄增加%d。" % (int(ex.exposure) - before)
	for stage in profile(str(ex.point)).get("stages", []):
		if str(stage.id) == stage_id and stage.obstacle:
			message += " 障碍已清除。" if str(c.id) == "careful" else " 障碍仍在，需绕行。"
			break
	ex.notes.append(message)
	return {"text": message}


static func transfer(run: Dictionary, stage_id: String, item: String, amount: int, take: bool) -> int:
	var ex: Dictionary = run.get("explore", {})
	if ex.is_empty() or ex.get("caught", false) or ex.get("curfew_due", false) or run.get("pending_event", "") != "" or amount <= 0: return 0
	var s := state(run)
	if not s.completed.has(stage_id) or not s.caches.has(stage_id): return 0
	var cache: Dictionary = s.caches[stage_id]
	var source: Dictionary = cache if take else ex.bag
	var dest: Dictionary = ex.bag if take else cache
	var qty := mini(amount, Inv.count(source, item))
	if qty <= 0: return 0
	if take:
		var w := float(Data.item(item).get("weight", 0))
		if w > 0: qty = mini(qty, maxi(0, int(floor((float(State.role(run).carry) - Inv.weight(ex.bag)) / w))))
	if qty <= 0: return 0
	Inv.add(source, item, -qty)
	Inv.add(dest, item, qty)
	return qty

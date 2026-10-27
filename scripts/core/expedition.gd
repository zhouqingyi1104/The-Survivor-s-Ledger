extends RefCounted
## 每次外出独立的现场线索与机关；离开后清空，下一趟重新探索。

const INSPECT_MINUTES := 5
const ANSWER_MINUTES := 10
const WRONG_EXPOSURE := 8
const SIGNATURES := {"rice_ruin": "米仓", "city_god": "供桌", "school": "藏书阁", "pharmacy_ruin": "药柜", "lumber": "木垛", "mortuary": "前厅棺木", "granary": "东仓", "taoist_temple": "丹房"}

const PROFILES := {
	"rice_ruin": {"title": "米行粮栅", "clues": [{"title": "残缺账簿", "text": "账簿写着：湿袋放东，干袋放西；东边的锁已经锈死。"}, {"title": "仓边木牌", "text": "掌柜留下字条：要找干粮，先从对应仓门拨开木栓。"}], "question": "要找干粮，应拨开哪边的仓栓？", "choices": [{"id": "east", "text": "东仓栓"}, {"id": "west", "text": "西仓栓"}, {"id": "middle", "text": "中间横栓"}]},
	"city_god": {"title": "城隍庙供案", "clues": [{"title": "残碑", "text": "碑文记着：敬神不用荤腥，寒岁唯求清净。"}, {"title": "香案旧签", "text": "旧签写着：清净之供，以一盏清水为先。"}], "question": "应将哪件供物放回缺口？", "choices": [{"id": "meat", "text": "肉碟"}, {"id": "wine", "text": "酒盏"}, {"id": "water", "text": "清水盏"}]},
	"school": {"title": "县学书阁", "clues": [{"title": "讲席残卷", "text": "残卷写着：温故而知新，可以为师矣。"}, {"title": "书阁门额", "text": "门额残字是「温故而□新」，机关要补上缺字。"}], "question": "缺字应是哪一个？", "choices": [{"id": "learn", "text": "学"}, {"id": "know", "text": "知"}, {"id": "read", "text": "读"}]},
	"pharmacy_ruin": {"title": "药铺暗格", "clues": [{"title": "药师处方", "text": "处方说外伤先取止血药，不用清热与驱寒之药。"}, {"title": "药格标签", "text": "药格旧签：三七止血，黄芩清热，干姜驱寒。"}], "question": "应拨动哪个药格？", "choices": [{"id": "ginger", "text": "干姜"}, {"id": "ginseng", "text": "三七"}, {"id": "skullcap", "text": "黄芩"}]},
	"lumber": {"title": "木场绞盘", "clues": [{"title": "木匠手记", "text": "横木压住了路，抬起它前须先松开承重楔。"}, {"title": "绞架刻记", "text": "架上刻字：红楔承重，黑楔固定绳，白楔固定架。"}], "question": "应先松哪枚木楔？", "choices": [{"id": "black", "text": "黑楔"}, {"id": "white", "text": "白楔"}, {"id": "red", "text": "红楔"}]},
	"mortuary": {"title": "义庄侧门", "clues": [{"title": "停棺簿", "text": "簿上记着：无名者停西厢，东厢只存空棺。"}, {"title": "门边纸条", "text": "守庄人写道：要到无名者身边，拉开对应厢门的门闩。"}], "question": "该拉开哪道厢门的门闩？", "choices": [{"id": "east", "text": "东厢"}, {"id": "west", "text": "西厢"}, {"id": "hall", "text": "正厅"}]},
	"granary": {"title": "官仓栅门", "clues": [{"title": "粮车验牌", "text": "验牌写着：甲车运谷，乙车运盐，丙车运柴。"}, {"title": "仓吏告示", "text": "旧告示：粮仓门栓只认运谷车的牌号。"}], "question": "该拨到哪个车牌？", "choices": [{"id": "jia", "text": "甲"}, {"id": "yi", "text": "乙"}, {"id": "bing", "text": "丙"}]},
	"taoist_temple": {"title": "青云观符门", "clues": [{"title": "观中残卷", "text": "残卷说日出之方属木，符门的木位可开启侧径。"}, {"title": "方位石刻", "text": "石刻标注：日出为东，日落为西，北面是山。"}], "question": "应拨向哪一方？", "choices": [{"id": "north", "text": "北"}, {"id": "west", "text": "西"}, {"id": "east", "text": "东"}]},
}
const ANSWERS := {"rice_ruin": "west", "city_god": "water", "school": "know", "pharmacy_ruin": "ginseng", "lumber": "red", "mortuary": "west", "granary": "jia", "taoist_temple": "east"}


static func profile(pid: String) -> Dictionary:
	if not PROFILES.has(pid): return {}
	var p: Dictionary = PROFILES[pid].duplicate(true)
	p["inspect_minutes"] = INSPECT_MINUTES
	p["answer_minutes"] = ANSWER_MINUTES
	p["wrong_exposure"] = WRONG_EXPOSURE
	return p


## 老的在途存档没有此字段；读取时补齐，当前版本也不需要迁移。
static func state(run: Dictionary) -> Dictionary:
	var ex: Dictionary = run.get("explore", {})
	if ex.is_empty(): return {}
	if not ex.get("expedition", null) is Dictionary:
		# 老在途存档可能已翻过特色目标并把物资留在现场。
		# 新机关不能把玩家已经抵达的地方重新封住。
		var already_reached := false
		var signature := str(SIGNATURES.get(str(ex.get("point", "")), ""))
		for spot in ex.get("spots", []):
			if spot is Dictionary and signature != "" and str(spot.get("name", "")) == signature and not spot.has("mainline") and not spot.has("neighbor") and (spot.get("done", false) or spot.has("loot")):
				already_reached = true
				break
		ex["expedition"] = {"unlocked": already_reached}
	var s: Dictionary = ex.expedition
	if not s.get("clues", null) is Array or s.clues.size() != 2:
		s["clues"] = [false, false]
	if not s.has("unlocked"): s["unlocked"] = false
	if not s.has("attempts"): s["attempts"] = 0
	return s


static func correct(pid: String, choice_id: String) -> bool:
	return ANSWERS.has(pid) and str(ANSWERS[pid]) == choice_id


## 任务目标不受普通搜寻区域的机关约束。
static func target_locked(run: Dictionary, idx: int) -> bool:
	var ex: Dictionary = run.get("explore", {})
	if ex.is_empty() or idx < 0 or idx >= ex.get("spots", []).size(): return false
	var spot: Dictionary = ex.spots[idx]
	if spot.has("mainline") or spot.has("neighbor"): return false
	var pid := str(ex.get("point", ""))
	if not PROFILES.has(pid): return false
	return str(spot.get("name", "")) == str(SIGNATURES.get(pid, "")) and not bool(state(run).get("unlocked", false))

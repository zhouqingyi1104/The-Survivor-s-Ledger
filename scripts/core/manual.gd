extends RefCounted
## 玩法说明：游戏里唯一一处把规则讲清楚的地方。
##
## 只写**确定的规则**，不写建议。「该买多少米」是策略，因人而异；写死在说明里，
## 玩家照着买却发现不够，比没有说明更糟。所以这里全是"会发生什么"，不是"你该做什么"。
##
## 按键一律走 InputCfg.first_key_name()：玩家改过键，说明里的键位要跟着变，
## 不能写死 J/N/Q。

const InputCfg = preload("res://scripts/core/input_cfg.gd")
const State = preload("res://scripts/core/state.gd")


## 四组说明。行可以是纯文本，也可以是 {"action": "...", "text": "..."}（自动带上当前键位）。
static func sections() -> Array:
	return [
		{
			"title": "目标",
			"rows": [
				"活过 %d 日算劫满。「守到死」模式没有终点，能撑多久算多久。" % State.STORY_DAYS,
				"死了不算完：生死簿残页给三次机会，可以翻回昨日或带着记忆重来。",
				"活下来靠的不是杀，是备：粮水柴炭、门窗院墙、守具符纸。",
			],
		},
		{
			"title": "常用的几个键",
			"rows": [
				{"action": "journal", "text": "劫余录：今世目标、今日要务、各种入口。"},
				{"action": "inventory", "text": "看家里的存货。"},
				{"action": "interact", "text": "走到物件旁边用一下（灶台、井、床、门）。"},
				{"action": "wait", "text": "等一刻：把时间推到下一个节点，空档时用。"},
				{"action": "sleep", "text": "就寝，一觉到天亮。"},
				{"action": "speed_pause", "text": "暂停 / 继续；1、2、3 切换流速。"},
				{"action": "cancel", "text": "关掉当前的面板。"},
			],
		},
		{
			"title": "一天是怎么走的",
			"rows": [
				"天亮开局，白天自己安排；天黑前后有几个固定的坎，走过去事情就会发生。",
				"做事先付料，做完才算数；做到一半被打断退不退料，开工前会写明。",
				"08:00　可能有人来（邻人、生意、麻烦）。",
				"18:00　天黑。20:00　该生火了。21:00　宵禁，外面不能久留。",
				"22:00　尸潮，通常打三轮。23:40　溃兵可能来砸门。",
				"天亮　结算这一天的功过，进入下一日。",
			],
		},
		{
			"title": "会要命的那几样",
			"rows": [
				"渴掉血最快，饿慢一点，冻得更慢但一夜就能掉光——所以水、粮、柴炭是底。",
				"体温低于 30 开始受冻，低于 15 是酷寒。生火能撑到夜里，地窖能减半掉温。",
				"院门、窗、墙各有血量。被砸穿到 0 的那一面，尸群会直接进来咬人。",
				"夜里也能现做守具，只管今夜与明夜，营造等级不加夜数。",
				"精力决定这一天能做几件事：做事、赶路、守夜都要花。",
				"尸毒不会自己好，会每小时咬你一口。",
			],
		},
	]


## 把一行渲染成"键位：说明"。没有 action 的行原样返回。
static func render_row(row) -> String:
	if row is Dictionary:
		var action := str(row.get("action", ""))
		var key := InputCfg.first_key_name(action)
		return "%s　%s" % [key if key != "" else "—", str(row.get("text", ""))]
	return str(row)


## 说明里提到的所有动作名（测试用它核对"每个键都真的存在"）。
static func actions_used() -> Array:
	var out := []
	for section in sections():
		for row in section.rows:
			if row is Dictionary:
				out.append(str(row.get("action", "")))
	return out

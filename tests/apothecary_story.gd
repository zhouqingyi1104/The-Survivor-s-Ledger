extends SceneTree

const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Story = preload("res://scripts/core/apothecary_story.gd")
var checks := 0
var failures := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func refused(run: Dictionary, action: String) -> void:
	var before := run.duplicate(true)
	check(Story.act(run, action) != "" and before == run, "拒绝的行动改变了药签、库存或时钟：" + action)


func restored(run: Dictionary) -> Dictionary:
	var save: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify({"run": run, "snapshots": {}})))
	return Migrate.save(save).run


func in_post(run: Dictionary, day: int) -> void:
	while run.phase == "pre":
		Pre.end_day(run)
	run.dawn_due = false
	run.plan_due = false
	run.pday = day
	run.t = (day - 1) * 1440 + 120


func _initialize() -> void:
	for role: String in ["herbalist", "scholar", "escort", "watchman"]:
		var run := State.new_run(role, State.new_meta(), 5103)
		refused(run, "unfold")
		check(Pre.travel(run, "pharmacy") == "", "第一天能到药铺")
		refused(run, "identify")
		check(Story.act(run, "unfold") == "" and Story.stage(run) == "fold", "只有主动翻开才能收下半签")
		refused(run, "unfold")
		run.day = State.PRE_DAYS
		run.hour = State.CURFEW_HOUR
		if role != "herbalist":
			refused(run, "identify")
			run.hour -= 1
		var silver: int = run.silver
		check(Story.act(run, "identify") == "" and run.hour == State.CURFEW_HOUR and run.silver == silver, "学徒可于宵禁当场辨认，其余身份留一个时辰")
		refused(run, "identify")
		check(Story.stage(restored(run)) == "signed", "存读档后药签仍有印")
		in_post(run, 1)
		refused(run, "keep")
		in_post(run, 2)
		for complication in [{"explore": {"point":"rice_ruin"}}, {"home_floor":"guest_zhou"}, {"pending_event":"surprise"}, {"sleeping":true}, {"t":2160}]:
			var blocked := run.duplicate(true)
			blocked.merge(complication, true)
			refused(blocked, "send")
		refused(run, "missing")
		var stash := Inv.count(run.home, "salve")
		var oil := Inv.count(run.home, "lamp_oil")
		var stash_run := restored(run)
		check(Story.act(stash_run, "keep") == "" and Inv.count(stash_run.home, "salve") == stash + 1, "自留款项精确到账")
		refused(stash_run, "send")
		refused(restored(stash_run), "keep")
		refused(stash_run, "reply")
		var q := Trade.quote(run, "traveler")
		var trust := int(Trade.contact(run, "traveler").trust)
		check(Story.act(run, "send") == "" and Inv.count(run.home, "salve") == stash and Inv.count(run.home, "lamp_oil") == oil, "转赠不能同时把药或回礼收到家")
		check(int(Trade.contact(run, "traveler").trust) == mini(5, trust + 1), "转赠应影响真实交易关系")
		check(Trade.quote(run, "traveler").used == q.used, "一笔旧寄药不占当日现货")
		refused(run, "send")
		refused(run, "keep")
		refused(run, "reply")
		run = restored(run)
		in_post(run, 5)
		check(Story.act(run, "reply") == "" and Inv.count(run.home, "lamp_oil") == oil + 1, "迟到也能凭旧档收信与灯油")
		check(str(run.log.back()).contains("渡灯油"), "回信应有日志")
		refused(restored(run), "reply")
	var missed := State.new_run("scholar", State.new_meta(), 248)
	Pre.travel(missed, "pharmacy")
	Story.act(missed, "unfold")
	in_post(missed, 2)
	refused(missed, "identify")
	refused(missed, "keep")
	var home: Dictionary = missed.home.duplicate()
	check(Story.act(missed, "ask") == "" and Story.stage(missed) == "unsigned" and missed.home == home, "没赶上盖印仍可查去向")
	refused(missed, "ask")
	var legacy := restored(State.new_run("herbalist", State.new_meta(), 248))
	in_post(legacy, 2)
	refused(legacy, "keep")
	refused(legacy, "ask")
	check(Story.stage(legacy) == "", "旧灾后存档和新人生不会自动得到前世药签")
	print("[apothecary_story] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

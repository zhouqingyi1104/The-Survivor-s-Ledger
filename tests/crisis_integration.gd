extends Node
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Companion = preload("res://scripts/core/companion.gd")
const Director = preload("res://scripts/core/director.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Past = preload("res://scripts/core/past_lives.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func at(run: Dictionary, day: int, minute := 180) -> void:
	run.pday = day
	run.t = (day - 1) * 1440 + minute

func sample() -> Dictionary:
	var run := State.new_run("escort", State.new_meta(), 77341)
	Pre.start_disaster(run)
	Neighbor.state(run).stage = "closed"
	Director.state(run).enabled = false
	run.home = {"rice": 50, "wood": 10, "firewood": 10, "nails": 10, "mugwort": 10, "water": 10, "flatbread": 10}
	return run

func warned(kind: String, real := true) -> Dictionary:
	var run := sample()
	check(Crisis.propose(run, {"kind": kind, "actor": "ning", "warning_day": 2, "real": real}, 1), "Catalogue proposal not installed")
	at(run, 2)
	Post.crisis_refresh(run)
	check(Crisis.view(run).kind == kind, "Visible warning differs from planned catalogue")
	return run

func action(run: Dictionary, id: String) -> String:
	return Post.crisis_action(run, id, str(Crisis.view(run).token))

func test_water_paths_and_emergency() -> void:
	var run := warned("well_freeze")
	at(run, 4, 710)
	var before := Inv.count(run.home, "water")
	check(Post.draw_water(run) == "", "Pre-impact water draw could not start")
	Post.advance(run, 15)
	check(Crisis.view(run).stage == "impact", "Actual time did not activate freeze")
	check(Inv.count(run.home, "water") == before, "Water completed across freeze despite blocked well")
	check(not run.well_used, "Failed draw incorrectly exhausted successful daily quota")
	check(Post.draw_water(run) != "", "Player bypassed frozen well")
	run.plots = [{"crop": "cabbage", "days": 0, "watered_t": 0}]
	var watered := int(run.plots[0].watered_t)
	var line := Companion._job(run, "water", "验收帮手")
	check(line.contains("危机") or line.contains("井") or line.contains("水"), "Companion did not explain failed water job")
	check(Inv.count(run.home, "water") == before and int(run.plots[0].watered_t) == watered, "Companion bypassed freeze through water or automatic irrigation")
	check(action(run, "emergency") == "", "Actual emergency work could not start")
	check(not Crisis.well_block(run).is_empty(), "Emergency restored well before work completed")
	Post.advance(run, 90)
	check(Crisis.well_block(run).is_empty() and Crisis.view(run).outcome == "repaired", "Emergency completion did not restore well")
	check(Post.draw_water(run) == "", "Restored well remained unusable")
	Post.advance(run, 15)
	check(Inv.count(run.home, "water") > before, "Restored real water action yielded nothing")

func test_credit_and_frozen_market() -> void:
	var run := warned("fuel_shortage")
	Trade.influence(run, "zhou", 3, "验收此前信用")
	var quote := Trade.quote(run, "zhou")
	check(Post.trade_action(run, "zhou", "credit", quote.id) == "", "Real pre-crisis loan failed")
	var debt: Dictionary = Trade.context(run).debt.duplicate(true)
	at(run, 4, 700)
	var frozen: Dictionary = Trade.quote(run, "traveler").duplicate(true)
	Post.advance(run, 20)
	check(Trade.quote(run, "traveler").req == frozen.req and Trade.quote(run, "traveler").give == frozen.give, "Crisis rewrote already visible daily quote")
	check(Trade.context(run).debt.req == debt.req and Trade.context(run).debt.give == debt.give, "Crisis rewrote signed loan goods")
	at(run, 5)
	Post.trade_refresh(run)
	var changed := Trade.quote(run, "traveler")
	check(changed.req.rice == int(frozen.req.rice) + 1 and changed.reason.contains("米"), "Unprepared fuel shortage did not change a fresh quote")
	var herb := warned("herb_shortage")
	at(herb, 5)
	Post.trade_refresh(herb)
	var medicine := Trade.quote(herb, "ning")
	check(not medicine.give.has("mugwort") and medicine.give.has("water"), "Herb shortage did not alter available goods")
	check(medicine.req.rice == 3, "Herb shortage surcharge missing")
	check(action(herb, "emergency") == "", "Herb remedy did not start")
	Post.advance(herb, 90)
	check(Trade.quote(herb, "ning").give == medicine.give, "Recovery retroactively rewrote today's signed quote")
	at(herb, 6)
	check(Trade.quote(herb, "ning").give.has("mugwort"), "Recovered next-day market did not restore herbs")

func test_choices_and_director() -> void:
	var protected_run := warned("well_freeze")
	var d := Director.state(protected_run)
	d.queue = [{"old": true}]
	check(action(protected_run, "investigate") == "", "Investigation could not start")
	check(Crisis.view(protected_run).confirmed == "unknown", "Starting investigation immediately revealed hidden truth")
	check(d.queue.is_empty(), "Started investigation did not invalidate unseen AI plans")
	Post.advance(protected_run, 30)
	check(Crisis.view(protected_run).confirmed == "real", "Completed investigation did not reveal evidence")
	check(action(protected_run, "prepare") == "", "Preparation could not start")
	check(not Crisis.view(protected_run).protected, "Preparation activated before construction completed")
	Post.advance(protected_run, 60)
	at(protected_run, 4, 720)
	Post.crisis_refresh(protected_run)
	check(Crisis.well_block(protected_run).is_empty() and Crisis.view(protected_run).outcome == "averted", "True prepared branch did not avert crisis")
	var wait_run := warned("well_freeze")
	check(action(wait_run, "ignore") == "", "Free deliberate wait unavailable")
	at(wait_run, 4, 720)
	Post.crisis_refresh(wait_run)
	check(not Crisis.well_block(wait_run).is_empty(), "Prepared and ignored branches converged to same actual outcome")
	var aided := warned("well_freeze")
	Trade.observe_neighbor(aided, "donate_home")
	var favors := int(Trade.contact(aided, "ning").favors)
	var token: String = Trade.quote(aided, "ning").id
	check(action(aided, "aid") == "", "Real earned favor not usable for crisis aid")
	check(int(Trade.contact(aided, "ning").favors) == favors - 1, "Crisis aid did not consume an actual favor")
	Post.advance(aided, 30)
	check(Trade.act(aided, "ning", "cash", token) != "", "Spending crisis favor left an old market button valid")
	check(Crisis.view(aided).protected, "Completed favor aid failed to prepare crisis")
	check(not Past.state(aided).trace.is_empty(), "Executed crisis choices absent from future past-life facts")
	var false_run := warned("well_freeze", false)
	check(action(false_run, "investigate") == "", "False rumor investigation unavailable")
	Post.advance(false_run, 30)
	check(Crisis.view(false_run).outcome == "false_alarm", "Investigation did not disprove false rumor")
	var s := Director.snapshot(false_run)
	check(s.state.crisis.active.confirmed == "false" and not s.state.crisis.active.has("real"), "AI facts leaked a private truth field")

func test_split_advances_finish_on_time() -> void:
	# Starting 61 minutes before impact promises a valid 60-minute preparation.
	# Splitting the clock into 1 + 60 must not round its finish onto the deadline.
	var prepared := warned("well_freeze")
	at(prepared, 4, 659)
	check(action(prepared, "prepare") == "", "Valid last-minute preparation was rejected")
	Post.advance(prepared, 1)
	Post.advance(prepared, 60)
	check(Crisis.view(prepared).outcome == "averted", "Split clock rounded valid preparation into impact")
	var inspected := warned("well_freeze")
	at(inspected, 4, 689)
	check(action(inspected, "investigate") == "", "Valid last-minute inspection was rejected")
	Post.advance(inspected, 1)
	Post.advance(inspected, 30)
	check(Crisis.view(inspected).investigated, "Split clock lost timely investigation completion")
	var repaired := warned("well_freeze")
	at(repaired, 6, 29)
	Post.crisis_refresh(repaired)
	check(action(repaired, "emergency") == "", "Valid last-minute remedy was rejected")
	Post.advance(repaired, 1)
	Post.advance(repaired, 90)
	check(Crisis.view(repaired).outcome == "repaired", "Split clock rounded remedy onto natural expiration")

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	test_water_paths_and_emergency()
	test_credit_and_frozen_market()
	test_choices_and_director()
	test_split_advances_finish_on_time()
	print("Crisis integration: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

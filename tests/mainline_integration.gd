extends Node
## Related systems only: real field work/return, wave overlays and locked contracts.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Story = preload("res://scripts/core/mainline.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Defense = preload("res://scripts/core/defense.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Director = preload("res://scripts/core/director.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Data = preload("res://scripts/core/data.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok
func at(run: Dictionary, day: int, minute := 180) -> void:
	run.pday = day
	run.t = (day - 1) * 1440 + minute
func sample() -> Dictionary:
	var run := State.new_run("escort", State.new_meta(), 701987)
	Pre.start_disaster(run)
	Neighbor.state(run).stage = "closed"
	Director.state(run).enabled = false
	Crisis.state(run).next_warning_day = 100000
	Npcs.state(run).next_day = 100000
	Story.state(run)
	run.home = {"rice": 50, "water": 50, "wood": 30, "nails": 20, "firewood": 30, "lamp_oil": 10, "talisman": 20, "dog_blood": 10, "mugwort": 20}
	return run
func action(run: Dictionary, id: String) -> bool:
	var result := Post.mainline_action(run, id, str(Story.view(run).token))
	return check(result == "", "Mainline action failed: " + id + " " + result)
func finish_work(run: Dictionary) -> bool:
	if not check(not run.busy.is_empty(), "Expected actual busy work"): return false
	var remaining := maxi(0, int(run.busy.end) - int(run.t))
	Post.advance(run, remaining)
	return check(run.busy.is_empty(), "Work did not finish at its actual time")
func objective_index(run: Dictionary, id: String) -> int:
	for k in run.explore.spots.size():
		if run.explore.spots[k].get("mainline", "") == id: return k
	return -1
func field_evidence(run: Dictionary, pid: String, id: String) -> bool:
	if not check(Post.act_explore(run, pid) == "", "Could not depart for " + pid): return false
	var index := objective_index(run, id)
	if not check(index >= 0, "Physical mainline target absent " + id): return false
	var before := int(run.t)
	var result := Post.search(run, index)
	if not check(result.get("mainline", false) and int(run.t) == before and not run.busy.is_empty(), "Special search did not start actual visible work"): return false
	Post.advance(run, 19)
	check(run.explore.get("mainline_cargo", {}).is_empty(), "Field evidence arrived one minute early")
	Post.advance(run, 1)
	check(int(run.t) == before + 20, "Special search did not finish after actual twenty minutes")
	check(not Story.state(run).evidence[id], "Field search granted home-confirmed proof before return")
	check(not run.explore.get("mainline_cargo", {}).is_empty(), "Finished search did not produce actual carried evidence")
	Post.finish_explore(run)
	if not finish_work(run): return false
	return check(run.explore.is_empty() and run.busy.is_empty() and Story.state(run).evidence[id], "Successful sixty-minute return failed to confirm evidence")
func prepared(disrupt := true) -> Dictionary:
	var run := sample()
	at(run, 3)
	Post.trade_refresh(run)
	if not action(run, "host") or not finish_work(run): return {}
	at(run, 5)
	if not field_evidence(run, "mortuary", "mortuary"): return {}
	if not action(run, "disrupt" if disrupt else "copy") or not finish_work(run): return {}
	at(run, 8)
	if not field_evidence(run, "taoist_temple", "temple"): return {}
	check(Story.state(run).stage == "routes", "Both actual investigations failed to unlock route choices")
	return run
func test_actual_evidence_and_cooldown() -> void:
	var run := sample()
	run.known_clues = Data.table("clues").keys()
	check(not Story.state(run).evidence.mortuary and not Story.state(run).evidence.temple, "Inherited clues created current-life proof")
	check(Explore.point_block(run, "taoist_temple") != "", "Core travel bypassed the locked temple flag")
	at(run, 3)
	Post.trade_refresh(run)
	if not action(run, "host") or not finish_work(run): return
	at(run, 5)
	run.points.mortuary = {"looted_until": 11, "visits": 1}
	check(Explore.point_block(run, "mortuary") == "", "Loot cooldown permanently blocked the unique investigation")
	check(Post.act_explore(run, "mortuary") == "", "Could not make an investigation-only visit")
	check(run.explore.only_investigate and run.explore.spots.all(func(s): return s.has("mainline") or s.has("neighbor")), "Investigation-only visit refreshed ordinary loot")
	var index := objective_index(run, "mortuary")
	Post.search(run, index)
	if not finish_work(run): return
	var cargo: String = str(run.explore.get("mainline_cargo", ""))
	check(not cargo.is_empty(), "No evidence to start return-time counterexample")
	var departure := int(run.t)
	var field: Dictionary = run.explore.duplicate(true)
	Explore.finish(run)
	check(Story.begin_return(run, field), "Actual carried proof could not begin return")
	Post.advance(run, 59)
	check(not Story.state(run).evidence.mortuary and not run.busy.is_empty(), "Proof teleported home before sixty minutes")
	Post.advance(run, 1)
	check(Story.state(run).evidence.mortuary and int(run.t) == departure + 60, "Final return minute did not confirm actual proof")
	check(int(run.points.mortuary.looted_until) == 11, "Mainline-only visit refreshed or extended ordinary loot cooldown")
	var now: Dictionary = run.home.duplicate(true)
	check(Story.complete(run, {"action": "return_mortuary"}) == "" and run.home == now, "Replayed return awarded extra materials")
func test_caught_evidence_is_lost_and_retryable() -> void:
	var run := sample()
	at(run, 3)
	Post.trade_refresh(run)
	if not action(run, "host") or not finish_work(run): return
	at(run, 5)
	Post.act_explore(run, "mortuary")
	Post.search(run, objective_index(run, "mortuary"))
	if not finish_work(run): return
	check(not run.explore.get("mainline_cargo", {}).is_empty(), "Capture fixture had no actual proof")
	Explore._caught(run, Data.table("map_points").mortuary)
	check(run.explore.caught and run.explore.get("mainline_cargo", {}).is_empty(), "Caught survivor retained task evidence")
	Post.finish_explore(run)
	check(not Story.state(run).evidence.mortuary, "Lost proof was still confirmed at home")
	run.plague = false
	run.attrs.hp = run.attrs.hp_max
	run.attrs.energy = 100
	check(Explore.point_block(run, "mortuary") == "", "Failure closed all investigation retry opportunities")
	check(Post.act_explore(run, "mortuary") == "" and objective_index(run, "mortuary") >= 0, "Actual investigation could not be retried after loss")
func test_real_waves_and_configuration_lock() -> void:
	var changed := prepared()
	var plain := prepared(false)
	if changed.is_empty() or plain.is_empty(): return
	var source := JSON.stringify(Data.table("waves"))
	var before := Defense.wave_for_run(plain, 11)
	var reduced := Defense.wave_for_run(changed, 11)
	check("armored" in before.mods and not "armored" in reduced.mods, "Real completed mortuary intervention did not alter future wave")
	check(int(reduced.count) == int(before.count), "Removing armor silently changed the base crowd count")
	at(changed, 11, 960)
	changed.wave_due = true
	changed.devices = [{"id": "bagua_mirror", "dur": 99}, {"id": "bagua_mirror", "dur": 99}, {"id": "bagua_mirror", "dur": 99}]
	Post.resolve_wave(changed)
	check(changed.night.wave == reduced, "Post real night start used a different wave than the forecast")
	var locked: Dictionary = changed.night.wave.duplicate(true)
	Story.state(changed).interventions.disrupt_t = -1
	check(Defense.wave_for_run(changed, 11) == locked and changed.night.wave == locked, "Late mainline change rewrote an already-started night")
	check(JSON.stringify(Data.table("waves")) == source, "Mainline wave overlay mutated shared baseline configuration")
func test_ritual_affects_final_night() -> void:
	var run := prepared()
	if run.is_empty(): return
	at(run, 12)
	run.attrs.energy = 100
	if not action(run, "prepare_ritual") or not finish_work(run): return
	at(run, 13)
	run.points.taoist_temple.looted_until = 18
	check(Post.act_explore(run, "taoist_temple") == "", "Loot cooldown prevented real ritual access")
	var index := objective_index(run, "ritual")
	if not check(index >= 0, "Prepared ritual has no physical array target"): return
	var t := int(run.t)
	Post.search(run, index)
	check(int(Story.state(run).interventions.ritual_t) < 0 and not run.busy.is_empty() and int(run.t) == t, "Ritual happened before visible work began")
	check(int(run.busy.end) == t + 90, "Ritual did not require ninety real minutes")
	Post.advance(run, 89)
	check(int(Story.state(run).interventions.ritual_t) < 0, "Ritual activated one minute early")
	Post.advance(run, 1)
	check(int(Story.state(run).interventions.ritual_t) == t + 90, "Completed physical ritual did not take effect")
	Post.finish_explore(run)
	var baseline := Defense.wave_for_day(20)
	var wave := Defense.wave_for_run(run, 20)
	check(not "blood_moon" in wave.mods and int(wave.count) == int(round(float(baseline.count) * 0.8)), "Actual final wave ignored completed ritual")
	check(Defense._count(wave) < Defense._count(baseline), "Ritual final population was not actually reduced")
	run.talents.append("lingjue")
	at(run, 20, 120)
	check("".join(Defense.forecast(run)).contains(str(Defense._count(wave))), "Forecast still reported old final-wave strength")
	run.devices = [{"id": "bagua_mirror", "dur": 99}, {"id": "bagua_mirror", "dur": 99}, {"id": "bagua_mirror", "dur": 99}]
	at(run, 20, 960)
	run.wave_due = true
	Post.resolve_wave(run)
	check(run.night.wave == wave and int(run.night.total) == Defense._count(wave), "Real final night disagreed with actual reduced forecast")
	while not run.night.done: Defense.next_round(run)
	check(run.phase == "post", "Residual final wave fixture did not survive")
	run.dawn_due = true
	run.t = 20 * 1440
	Post.ack_dawn(run)
	check(run.phase == "ending" and Story.ending(run).kind == "ritual", "Survived ritual residual wave did not lead to ritual ending")
func test_escape_is_real_and_preserves_contracts() -> void:
	var run := prepared(false)
	if run.is_empty(): return
	at(run, 12)
	run.attrs.energy = 100
	Trade.influence(run, "zhou", 3, "Actual trusted contact")
	var quote := Trade.quote(run, "zhou")
	check(Post.trade_action(run, "zhou", "credit", quote.id) == "", "Could not establish an existing signed debt")
	var debt: Dictionary = Trade.state(run).debt.duplicate(true)
	if not action(run, "prepare_escape") or not finish_work(run): return
	check(Trade.state(run).debt == debt, "Mainline preparation rewrote existing signed debt")
	at(run, 18, 120)
	Post.trade_refresh(run)
	var confirmed_debt: Dictionary = Trade.state(run).debt.duplicate(true)
	if not action(run, "escape"): return
	Post.advance(run, 119)
	check(run.phase == "post", "Escape ended before actual journey completed")
	check(Post.advance(run, 1) == "ending" and run.phase == "ending", "Actual last minute did not reach escape ending")
	check(Story.ending(run).kind == "escape" and int(Story.ending(run).bonus) == 0, "Early escape received hold-twenty-nights bonus")
	check(Trade.state(run).debt == confirmed_debt, "Escape silently cancelled the remaining signed debt")

func test_fatal_field_capture_settles_immediately() -> void:
	for id in ["mortuary", "ritual"]:
		var run := prepared(false) if id == "ritual" else sample()
		if run.is_empty(): return
		if id == "mortuary":
			at(run, 3)
			Post.trade_refresh(run)
			if not action(run, "host") or not finish_work(run): return
			at(run, 5)
		else:
			at(run, 12)
			run.attrs.energy = 100
			if not action(run, "prepare_ritual") or not finish_work(run): return
			at(run, 13)
		check(Post.act_explore(run, "mortuary" if id == "mortuary" else "taoist_temple") == "", "Could not enter fatal-capture fixture")
		run.attrs.hp = 1
		run.attrs.energy = 50
		run.explore.exposure = 99
		var before := int(run.t)
		var result := Post.search(run, objective_index(run, id))
		check(result.get("caught", false) and run.phase == "dead" and State.attr(run, "hp") == 0, "Fatal field capture returned an alive zero-HP character: " + id)
		check(int(run.t) == before and run.busy.is_empty() and Story.state(run).work.is_empty(), "Fatal field capture kept free work or advanced time")
		check(State.attr(run, "energy") == (40 if id == "ritual" else 46), "Fatal search escaped its actual stated energy cost")
		check(int(Story.state(run).interventions.ritual_t) == -1 and not Story.state(run).evidence.mortuary if id == "mortuary" else int(Story.state(run).interventions.ritual_t) == -1, "Fatal search granted investigation or ritual success")
func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	test_actual_evidence_and_cooldown()
	test_caught_evidence_is_lost_and_retryable()
	test_real_waves_and_configuration_lock()
	test_ritual_affects_final_night()
	test_escape_is_real_and_preserves_contracts()
	test_fatal_field_capture_settles_immediately()
	print("Mainline integration: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

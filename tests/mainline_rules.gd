extends Node
const Core = preload("res://scripts/core/mainline.gd")
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const Data = preload("res://scripts/core/data.gd")
const Past = preload("res://scripts/core/past_lives.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func at(run: Dictionary, day: int, minute := 120) -> void:
	run.t = (day - 1) * 1440 + minute
	run.pday = day

func sample() -> Dictionary:
	var run := State.new_run("escort", State.new_meta(), 723)
	Pre.start_disaster(run)
	run.home = {"rice": 30, "water": 30, "firewood": 30, "wood": 30, "nails": 30, "talisman": 30, "talisman_paper": 30, "lamp_oil": 30, "dog_blood": 30}
	Core.state(run)
	return run

func action(run: Dictionary, id: String) -> String:
	return Core.act(run, id, str(Core.view(run).token))

func finish(run: Dictionary) -> String:
	var busy: Dictionary = run.busy.duplicate(true)
	run.t = int(busy.end)
	run.pday = int(run.t) / 1440 + 1
	run.busy = {}
	return Core.complete(run, busy.data)

func contact() -> Dictionary:
	var run := sample()
	at(run, 3)
	check(Core.poll(run) != "" and Core.state(run).stage == "contact", "Guaranteed contact did not publish")
	return run

func mortuary() -> Dictionary:
	var run := contact()
	check(action(run, "host") == "", "Host could not start")
	check(finish(run) != "" and Core.state(run).stage == "mortuary", "Host did not complete")
	return run

func visit(run: Dictionary, pid: String) -> Dictionary:
	var spots := [{"name": "普通角落", "done": false}, {"name": "邻居药账", "done": false, "neighbor": "account"}]
	Core.add_objective(run, pid, spots)
	run.explore = {"point": pid, "spots": spots, "bag": {}, "exposure": 0, "caught": false, "notes": []}
	return spots[0]

func search(run: Dictionary, spot: Dictionary) -> Dictionary:
	var result := Core.search_objective(run, spot)
	if result.get("started", false): State.add_attr(run, "energy", -4) # Post common cost.
	return result

func investigate_and_return(run: Dictionary, pid: String) -> void:
	var spot := visit(run, pid)
	check(search(run, spot).get("started", false), "Could not begin onsite investigation")
	check(finish(run) != "", "Onsite investigation did not complete")
	var ex: Dictionary = run.explore.duplicate(true)
	run.explore = {}
	check(Core.begin_return(run, ex), "Could not start real return with evidence")
	check(finish(run) != "", "Evidence return did not finish")

func routes(disrupt := false) -> Dictionary:
	var run := mortuary()
	investigate_and_return(run, "mortuary")
	check(action(run, "disrupt" if disrupt else "copy") == "", "Evidence disposal could not begin")
	check(finish(run) != "", "Evidence disposal did not complete")
	investigate_and_return(run, "taoist_temple")
	check(Core.state(run).stage == "routes", "Actual two-site proof did not unlock routes")
	return run

func test_contact_fallback_and_inherited() -> void:
	var run := sample()
	check(run.version == Migrate.VERSION and Core.state(run).start_day == 3, "New mainline version/start wrong")
	check(not Core.context(run).published and Core.options(run).is_empty(), "Future mainline exposed actionable content")
	check(action(run, "host") != "", "Unpublished host accepted")
	at(run, 3, 119)
	check(Core.poll(run) == "", "Guaranteed contact published early")
	run.t += 1
	run.pday = 99
	check(Core.poll(run) != "" and Core.state(run).stage == "contact", "Contact trusted stale pday instead of clock")
	check(Core.poll(run) == "", "Repeated poll published contact twice")
	var energy := State.attr(run, "energy")
	var old_water := int(run.home.water)
	check(action(run, "host") == "", "On-time host blocked")
	check(run.home.water == old_water - 1 and run.home.firewood == 29 and State.attr(run, "energy") == energy - 4, "Host failed real costs")
	check(Core.state(run).stage == "contact" and not run.flags.get("learned_talisman", false), "Host taught before completion")
	var data: Dictionary = run.busy.data.duplicate(true)
	check(Core.complete(run, data) == "", "Host completed early")
	check(action(run, "host") != "", "Double host accepted")
	check(finish(run) != "" and run.flags.learned_talisman and run.home.talisman == 31 and run.home.talisman_paper == 32, "Finished host missed finite rewards")
	check(Core.complete(run, data) == "" and run.home.talisman == 31, "Host reward replayed")
	var refused := contact()
	var before: Dictionary = refused.home.duplicate(true)
	check(action(refused, "refuse") == "" and refused.home == before and Core.state(refused).stage == "fallback", "Refusal spent material or killed fallback")
	check(action(refused, "self_route") != "", "Self route opened before day5")
	at(refused, 5)
	check(action(refused, "self_route") == "" and refused.home.rice == 29, "Self route failed real rice cost")
	check(finish(refused) != "" and Core.state(refused).stage == "mortuary" and not refused.flags.get("learned_talisman", false) and refused.home.talisman == 30, "Fallback gave host teaching/rewards or failed progress")
	var timed := contact()
	at(timed, 12, 720)
	check(Core.poll(timed) != "" and Core.state(timed).stage == "fallback", "Missed contact had no self-investigation route")
	var inherited := sample()
	inherited.known_clues = Data.table("clues").keys()
	inherited.clues_new = inherited.known_clues.duplicate()
	Past.state(inherited).inherited = [{"fact": "你前世熄灭了七灯。"}]
	at(inherited, 3)
	Core.poll(inherited)
	check(not Core.state(inherited).evidence.mortuary and not Core.state(inherited).evidence.temple and Core.state(inherited).route == "", "Inherited clues/memory became current-life proof")
	check(Core.wave_effect(inherited, 20).remove_mods.is_empty(), "Past-life ritual changed current wave")

func test_onsite_and_return_proof() -> void:
	var run := mortuary()
	var spot := visit(run, "mortuary")
	check(spot.mainline == "mortuary" and run.explore.spots.any(func(s): return s.get("neighbor", "") == "account"), "Mainline target swallowed neighbor objective")
	var size: int = run.explore.spots.size()
	Core.add_objective(run, "mortuary", run.explore.spots)
	check(run.explore.spots.size() == size, "Repeated target insertion duplicated target")
	var before := State.attr(run, "energy")
	var res := search(run, spot)
	check(res.mainline and res.started and res.gain == 35 and res.has("found") and res.has("clue"), "Investigation result contract wrong")
	check(int(run.busy.end) - int(run.busy.start) == 20 and State.attr(run, "energy") == before - 4 and run.explore.exposure == 35, "Investigation missing real time/energy/exposure")
	check(not Core.state(run).evidence.mortuary and not run.explore.has("mainline_cargo"), "Search start immediately produced proof")
	check(search(run, spot).get("blocked", "") != "", "Busy/done target accepted duplicate search")
	check(Core.complete(run, run.busy.data) == "", "20 minute investigation completed before time")
	check(finish(run) != "" and run.explore.mainline_cargo == "mortuary" and not Core.state(run).evidence.mortuary, "Onsite finish incorrectly counted as returned proof")
	var ex: Dictionary = run.explore.duplicate(true)
	check(not Core.begin_return(run, ex), "Return started without leaving site")
	run.explore = {}
	check(Core.begin_return(run, ex), "Legitimate return did not start")
	check(int(run.busy.end) - int(run.busy.start) == 60, "Evidence return not timed60")
	check(not Core.state(run).evidence.mortuary and Core.complete(run, run.busy.data) == "", "Return granted evidence before completion")
	check(finish(run) != "" and Core.state(run).evidence.mortuary and Core.state(run).stage == "mortuary_choice", "Finished return did not submit current-life proof")
	check(not Core.begin_return(run, ex), "Replayed field evidence started a second return")
	var forged := mortuary()
	check(not Core.begin_return(forged, {"point": "mortuary", "mainline_cargo": "mortuary", "caught": false}), "Unexecuted fabricated cargo became returnable proof")
	var lost := mortuary()
	var lost_spot := visit(lost, "mortuary")
	search(lost, lost_spot)
	finish(lost)
	lost.explore.caught = true
	check(Core.lost_cargo(lost) != "" and not lost.explore.has("mainline_cargo") and not Core.state(lost).evidence.mortuary, "Pursuit failed to lose unreturned evidence")
	check(Core.lost_cargo(lost) == "", "Pursuit loss logged twice")
	var lost_ex: Dictionary = lost.explore.duplicate(true)
	lost.explore = {}
	check(not Core.begin_return(lost, lost_ex), "Caught cargo returned as proof")
	var retry := visit(lost, "mortuary")
	check(search(lost, retry).get("started", false), "Lost proof could not be retried")
	var interrupted := mortuary()
	var interrupted_spot := visit(interrupted, "mortuary")
	search(interrupted, interrupted_spot)
	interrupted.busy = {}
	check(Core.poll(interrupted) != "" and Core.state(interrupted).work.is_empty() and not interrupted_spot.done and not interrupted.explore.has("mainline_cargo"), "Interrupted investigation granted proof or prevented retry")
	var rejected := mortuary()
	visit(rejected, "mortuary")
	var bad := search(rejected, {"name": "伪造点", "mainline": "mortuary", "done": false})
	check(bad.get("blocked", "") != "" and rejected.busy.is_empty(), "Nonexistent onsite objective accepted")

func test_choices_and_actual_wave_effects() -> void:
	for choice in ["disrupt", "copy", "seal"]:
		var run := mortuary()
		investigate_and_return(run, "mortuary")
		var supplies: Dictionary = run.home.duplicate(true)
		check(action(run, choice) == "", "Mortuary disposal unavailable")
		if choice == "seal":
			check(run.home == supplies and Core.state(run).stage == "hold" and Core.state(run).route == "hold" and Core.options(run).is_empty(), "Seal failed zero-cost irreversible hold")
			continue
		check(Core.wave_effect(run, 11).remove_mods.is_empty(), "Incomplete disruption affected wave")
		check(finish(run) != "" and Core.state(run).stage == "temple" and run.flags.temple_open, "Mortuary disposal did not open actual temple route")
		if choice == "disrupt":
			check(run.home.talisman == int(supplies.talisman) - 1 and run.home.lamp_oil == int(supplies.lamp_oil) - 1, "Disruption not paid")
			check(Core.wave_effect(run, 11).remove_mods == ["armored"] and Core.wave_effect(run, 17).remove_mods == ["armored"], "Finished disruption did not change both future armored nights")
			check(Core.wave_effect(run, 14).remove_mods.is_empty() and Core.wave_effect(run, 20).count_mul == 1.0, "Disruption changed unrelated nights")
			run.wave_day = 11
			check(Core.wave_effect(run, 11).remove_mods.is_empty(), "Intervention rewrote a started night")
		else:
			check(run.home == supplies and Core.wave_effect(run, 11).remove_mods.is_empty(), "Copy consumed materials or silently disrupted wave")
	var at_start := sample()
	Core.state(at_start).interventions.disrupt_t = 10 * 1440 + 960
	check(Core.wave_effect(at_start, 11).remove_mods.is_empty(), "Equal-start disruption retroactively changed wave")
	Core.state(at_start).interventions.disrupt_t -= 1
	check(Core.wave_effect(at_start, 11).remove_mods == ["armored"], "One-minute-before valid disruption missed future wave")

func test_three_routes_and_endings() -> void:
	var hold := routes()
	check(action(hold, "hold") == "" and Core.state(hold).route == "hold", "Explicit hold did not lock route")
	check(action(hold, "prepare_escape") != "" and action(hold, "prepare_ritual") != "", "Locked hold allowed a second route")
	at(hold, 20, 1439)
	check(not Core.finish_dawn(hold), "Hold ended before day21 actual dawn")
	hold.t += 1
	check(Core.finish_dawn(hold) and hold.phase == "ending" and Core.ending(hold).kind == "hold" and Core.ending(hold).bonus == 10 and Core.ending(hold).can_continue, "Hold outcome/reward/continuation wrong")
	check(not Core.finish_dawn(hold), "Ending replayed at same dawn")
	check(Core.continued(hold) == "" and Core.state(hold).stage == "endless" and Core.state(hold).ending.is_empty(), "Hold could not continue or retained ending")
	var escaped := routes()
	check(action(escaped, "prepare_escape") != "", "Escape preparations opened before day12")
	at(escaped, 12)
	check(action(escaped, "prepare_escape") == "" and escaped.home.rice == 27 and escaped.home.water == 26 and escaped.home.wood == 28 and escaped.home.nails == 29, "Escape preparation did not pay physical materials")
	check(Core.state(escaped).route == "" and Core.state(escaped).stage == "routes", "Escape route locked before prep completion")
	check(finish(escaped) != "" and Core.state(escaped).route == "escape" and Core.state(escaped).stage == "escape_ready", "Completed escape kit did not lock route")
	check(action(escaped, "escape") != "", "Escape opened before day18")
	at(escaped, 18)
	check(action(escaped, "escape") == "" and escaped.phase == "post", "Escape start ended immediately")
	check(finish(escaped) != "" and escaped.phase == "ending" and Core.ending(escaped).kind == "escape" and Core.ending(escaped).bonus == 0 and not Core.ending(escaped).can_continue, "Actual escape ending incorrect")
	check(Core.continue_block(escaped) != "" and Core.continued(escaped) != "", "Escape teleported back to home")
	var ritual := routes(true)
	at(ritual, 12)
	var before: Dictionary = ritual.home.duplicate(true)
	check(action(ritual, "prepare_ritual") == "", "Ritual preparations unavailable")
	check(ritual.home.talisman == int(before.talisman) - 2 and ritual.home.lamp_oil == int(before.lamp_oil) - 1 and ritual.home.dog_blood == int(before.dog_blood) - 1, "Ritual kit missing actual costs")
	check(finish(ritual) != "" and Core.state(ritual).stage == "ritual_ready", "Ritual prep did not open field objective")
	check(Core.wave_effect(ritual, 20).remove_mods.is_empty(), "Prepared kit alone extinguished lamps")
	var spot := visit(ritual, "taoist_temple")
	var energy := State.attr(ritual, "energy")
	check(search(ritual, spot).get("started", false), "Field ritual could not start")
	check(int(ritual.busy.end) - int(ritual.busy.start) == 90 and State.attr(ritual, "energy") == energy - 10 and ritual.explore.exposure == 45, "Field ritual missing actual90/energy10/exposure45")
	check(finish(ritual) != "" and Core.state(ritual).stage == "sealed" and ritual.phase == "post", "Field completion did not seal or ended before residual horde")
	check(Core.wave_effect(ritual, 20).remove_mods == ["blood_moon"] and is_equal_approx(float(Core.wave_effect(ritual, 20).count_mul), 0.8), "Ritual did not change real final wave contract")
	check(Core.wave_effect(ritual, 23).remove_mods.is_empty() and Core.wave_effect(ritual, 23).count_mul == 1.0, "Ritual changed endless nights")
	ritual.explore = {}
	at(ritual, 21, 0)
	check(Core.finish_dawn(ritual) and Core.ending(ritual).kind == "ritual" and Core.ending(ritual).bonus == 10 and not Core.ending(ritual).can_continue, "Survived residual tide did not finish ritual ending")
	var endless := routes()
	endless.endless = true
	at(endless, 12)
	check(action(endless, "prepare_escape") != "" and action(endless, "prepare_ritual") == "", "Endless blocked investigation/ritual or allowed escape")
	finish(endless)
	at(endless, 21, 0)
	check(not Core.finish_dawn(endless) and endless.phase == "post", "Endless forced day20 story ending")
	var legacy := sample()
	legacy.phase = "ending"
	legacy.mainline = {}
	check(Core.ending(legacy).kind == "hold" and Core.continue_block(legacy) == "", "Legacy ending lost hold fallback")

func test_deadlines_interruption_and_persistence() -> void:
	var contact_late := contact()
	contact_late.t = Core.CONTACT_END - 30
	var material: Dictionary = contact_late.home.duplicate(true)
	check(action(contact_late, "host") != "" and contact_late.home == material, "Too-late hosting consumed material")
	var interrupted := contact()
	action(interrupted, "host")
	var spent: Dictionary = interrupted.home.duplicate(true)
	interrupted.busy = {}
	check(Core.poll(interrupted) != "" and Core.state(interrupted).stage == "contact" and interrupted.home == spent and not interrupted.flags.get("learned_talisman", false), "Interrupted hosting refunded materials or granted rewards")
	var late := routes()
	at(late, 19, 720 - 90 - 119)
	var before: Dictionary = late.home.duplicate(true)
	check(action(late, "prepare_escape") != "" and late.home == before, "Escape prep left insufficient actual120 and still charged")
	at(late, 19, 720 - 120 - 60 - 90)
	check(action(late, "prepare_ritual") != "" and late.home == before, "Ritual prep failed strict travel+field deadline")
	var missed := routes()
	at(missed, 12)
	action(missed, "prepare_escape")
	finish(missed)
	var paid: Dictionary = missed.home.duplicate(true)
	at(missed, 19, 720)
	check(Core.poll(missed) != "" and Core.state(missed).stage == "failed" and Core.state(missed).route == "hold" and missed.home == paid and missed.phase == "post", "Missed escape failed to fall back without refund/death")
	var exact := routes()
	at(exact, 12)
	action(exact, "prepare_escape")
	finish(exact)
	at(exact, 19, 600)
	check(action(exact, "escape") == "", "Escape that can finish exactly at end incorrectly blocked")
	exact.t = Core.FINAL_END
	check(Core.poll(exact) == "" and Core.state(exact).stage == "escape_ready", "Deadline poll killed an exactly on-time valid escape")
	check(finish(exact) != "" and exact.phase == "ending", "Exactly on-time completed escape failed")
	var guards := contact()
	for id in ["busy", "sleeping", "explore", "neighbor_travel", "pending_event", "dawn_due", "plan_due", "wave_due", "wave_report", "fight", "night"]:
		var blocked: Dictionary = guards.duplicate(true)
		if id in ["sleeping", "neighbor_travel", "dawn_due", "plan_due", "wave_due"]: blocked[id] = true
		elif id == "pending_event": blocked[id] = "taoist"
		else: blocked[id] = {"fixture": true}
		var home: Dictionary = blocked.home.duplicate(true)
		check(action(blocked, "host") != "" and blocked.home == home, "Access guard bypass: " + id)
	var poor: Dictionary = guards.duplicate(true)
	poor.home = {}
	check(action(poor, "host") != "", "Missing materials accepted")
	var tired: Dictionary = guards.duplicate(true)
	tired.attrs.energy = 0
	check(action(tired, "host") != "", "Missing energy accepted")
	var future: Dictionary = guards.duplicate(true)
	future.t -= 1
	check(action(future, "host") != "", "Future plan action accepted on earlier clock")
	var other := contact()
	check(Core.act(other, "host", str(Core.view(guards).token)) != "", "Previous-life token accepted")
	check(Core.act(guards, "script", str(Core.view(guards).token)) != "", "Unknown action accepted")
	action(guards, "host")
	var saved: Dictionary = Data.normalize(JSON.parse_string(JSON.stringify(guards)))
	var rewound: Dictionary = guards.duplicate(true)
	check(Core.context(saved) == Core.context(guards) and saved.busy == guards.busy, "Save roundtrip lost pending work")
	finish(saved)
	check(Core.state(rewound).stage == "contact" and Core.state(saved).stage == "mortuary", "Completion mutated rewind snapshot")
	var old := sample()
	old.version = 16
	old.erase("mainline")
	at(old, 12)
	old.pday = 1
	var migrated := Migrate.save({"run": old.duplicate(true), "snapshots": {"11": old.duplicate(true)}})
	check(migrated.run.version == Migrate.VERSION and migrated.snapshots["11"].version == Migrate.VERSION, "Mainline migration skipped current/snapshots")
	check(Core.state(migrated.run).start_day == 13 and Core.state(migrated.snapshots["11"]).start_day == 13 and Core.poll(migrated.run) == "", "Old save backfilled story/used stale pday")
	for index in 25:
		Core.state(rewound).stage = "contact"
		rewound.busy = {}
		Core.state(rewound).work = {}
		action(rewound, "refuse")
	check(Core.context(rewound).history.size() == 16, "Mainline history escaped bound")
	var daily := sample()
	daily.flags.daily = "2026-10-24"
	daily.known_clues = Data.table("clues").keys()
	var rng := int(daily.rng_n)
	at(daily, 3)
	Core.poll(daily)
	check(Core.state(daily).stage == "contact" and not Core.state(daily).evidence.temple and int(daily.rng_n) == rng, "Daily or past clues changed independent story rules/shared RNG")

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	test_contact_fallback_and_inherited()
	test_onsite_and_return_proof()
	test_choices_and_actual_wave_effects()
	test_three_routes_and_endings()
	test_deadlines_interruption_and_persistence()
	print("Mainline rules: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

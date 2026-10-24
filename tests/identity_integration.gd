extends Node
## Real Post clock, recipes, wave start and route work. No player file or model.
const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Story = preload("res://scripts/core/mainline.gd")
const Identity = preload("res://scripts/core/identity_paths.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
const Crisis = preload("res://scripts/core/crisis.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Director = preload("res://scripts/core/director.gd")
const Defense = preload("res://scripts/core/defense.gd")
const Data = preload("res://scripts/core/data.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok

func at(run: Dictionary, day: int, minute := 180) -> void:
	run.pday = day
	run.t = (day - 1) * 1440 + minute
	for attr in ["food", "water", "warmth", "energy", "mood"]: run.attrs[attr] = 100

func sample(role: String, legacy := "") -> Dictionary:
	var run := State.new_run(role, State.new_meta(), 80141)
	Pre.start_disaster(run)
	Neighbor.state(run).stage = "closed"
	Director.state(run).enabled = false
	Past.state(run).schedule = []
	Npcs.state(run).next_day = 100000
	Crisis.state(run).next_warning_day = 100000
	Story.state(run)
	run.home = {"rice": 40, "water": 40, "firewood": 40, "wood": 40, "nails": 40, "talisman": 40, "talisman_paper": 40, "cinnabar": 40, "lamp_oil": 40, "dog_blood": 40, "mugwort": 40, "plague_powder": 40, "caltrops": 40}
	if legacy != "":
		# Source selection/forged archives are covered in identity_memory. Here only
		# fix one valid inherited qualification and exercise the actual world path.
		Past.state(run).generation = 2
		Identity.state(run).inherited = [{"tag": legacy, "source_life": 1, "source_id": "integration-prior-life"}]
	at(run, 3)
	Post.trade_refresh(run)
	return run

func action(run: Dictionary, id: String) -> bool:
	return check(Post.mainline_action(run, id, str(Story.view(run).token)) == "", "Mainline action rejected: " + id)

func finish_work(run: Dictionary) -> bool:
	if not check(not run.busy.is_empty(), "Expected actual work"): return false
	var left := int(run.busy.end) - int(run.t)
	Post.advance(run, left)
	return check(run.busy.is_empty(), "Real clock did not complete work")

func proof(run: Dictionary, point: String, key: String) -> bool:
	if not check(Post.act_explore(run, point) == "", "Could not depart " + point): return false
	var index := -1
	for i in run.explore.spots.size():
		if run.explore.spots[i].get("mainline", "") == key: index = i
	if not check(index >= 0, "Special site missing"): return false
	if not check(Post.search(run, index).get("started", false), "Could not start onsite investigation"): return false
	if not finish_work(run): return false
	Post.finish_explore(run)
	check(not Story.state(run).evidence[key], "Evidence granted before return")
	if not finish_work(run): return false
	return check(Story.state(run).evidence[key], "Finished return failed to grant proof")

func mortuary(role: String, legacy := "") -> Dictionary:
	var run := sample(role, legacy)
	action(run, "host")
	finish_work(run)
	at(run, 4) # The existing physical mortuary opens on day4.
	proof(run, "mortuary", "mortuary")
	return run

func select(run: Dictionary, id: String) -> void:
	var before: Dictionary = run.home.duplicate(true)
	var token := str(Identity.view(run).token)
	check(Post.identity_action(run, id, token) == "", "Real identity action failed " + id)
	check(Identity.state(run).chosen == "" and not run.busy.is_empty(), "Identity granted before completion")
	check(Post.identity_action(run, id, token) != "", "Old identity token double spent")
	check(run.home != before, "Identity action spent no supplies")
	var left := int(run.busy.end) - int(run.t)
	Post.advance(run, left - 1)
	check(Identity.state(run).chosen == "", "Identity completed one minute early")
	Post.advance(run, 1)
	check(Identity.state(run).chosen == id and Story.state(run).stage == "temple", "Completed identity failed to open actual temple")
	check(action_rejected(run, "copy"), "Public copy stacked after identity method")
	check(not Director.state(run).history.is_empty(), "Identity missing real Director history")

func action_rejected(run: Dictionary, id: String) -> bool:
	return Post.mainline_action(run, id, str(Story.view(run).token)) != ""

func make_routes(run: Dictionary) -> void:
	at(run, 6)
	proof(run, "taoist_temple", "temple")
	at(run, 12)
	Post.trade_refresh(run)

func test_recipes_and_costs() -> void:
	for row in [["scholar", "scholar_collate", "", "scribe_talisman", "talisman", 2], ["herbalist", "herbalist_lure", "", "efficient_plague", "plague_powder", 1], ["herbalist", "herbalist_ink", "gave_medicine", "medicinal_talisman", "talisman", 1]]:
		var run := mortuary(row[0], row[2])
		check(Post.act_craft(run, row[3]) != "", "Unlearned identity recipe fabricated")
		select(run, row[1])
		check(Identity.has(run, row[3]), "Completed recipe not learned")
		var energy := State.attr(run, "energy")
		run.attrs.energy = 5.5
		var input_before: Dictionary = run.home.duplicate(true)
		check(Post.act_craft(run, row[3]) != "" and run.home == input_before, "Identity recipe accepted less than its real six energy cost")
		run.attrs.energy = energy
		var n := Inv.count(run.home, row[4])
		check(Post.act_craft(run, row[3]) == "", "Actual identity recipe failed")
		Post.advance(run, 59)
		check(Inv.count(run.home, row[4]) == n, "Identity product arrived early")
		Post.advance(run, 1)
		check(Inv.count(run.home, row[4]) == n + int(row[5]), "Identity recipe output mismatch")
		if row[1] == "herbalist_ink":
			check(not Identity.has(run, "efficient_plague"), "Mutually exclusive herbalism methods stacked")
			check(Post.act_craft(run, row[3]) == "", "Could not start second valid legacy recipe")
			var paid: Dictionary = run.home.duplicate(true)
			run.flags.daily = "2026-10-24"
			check(Post.act_craft(run, row[3]) != "", "Late daily flag bypassed legacy recipe guard")
			Post.advance(run, 60)
			check(run.home == paid, "Invalid legacy recipe produced goods or refunded paid materials at completion")
	var guard := mortuary("escort")
	var hp := State.attr(guard, "hp")
	select(guard, "escort_intercept")
	check(State.attr(guard, "hp") == hp - 12, "Interception failed to preserve injury")
	var wave := Defense.wave_for_run(guard, 11)
	check(not "armored" in wave.mods and Story.state(guard).interventions.disrupt_t >= 0, "Interception did not remove actual armor")
	var foreign := mortuary("escort")
	foreign.flags.learned_talisman = true
	check(Post.act_craft(foreign, "scribe_talisman") != "", "Generic talisman flag unlocked scholar recipe")

func test_wave_and_intel() -> void:
	var herbs := mortuary("herbalist")
	var config: Dictionary = Data.table("waves").duplicate(true)
	select(herbs, "herbalist_lure")
	for day in [11, 17]:
		var w := Defense.wave_for_run(herbs, day)
		var baseline := Defense.wave_for_day(day)
		check(w.count == int(round(baseline.count * 0.9)) and "armored" in w.mods, "Herbalism did not reduce real count while keeping armor")
	at(herbs, 11, 960)
	herbs.wave_due = true
	var predicted := Defense.wave_for_run(herbs, 11)
	Post.resolve_wave(herbs)
	check(herbs.night.wave == predicted, "Forecast and actual night differ")
	Identity.state(herbs).chosen = ""
	check(Defense.wave_for_run(herbs, 11) == predicted, "Started night changed after identity state changed")
	check(Data.table("waves") == config, "Identity modified shared wave table")
	var watch := mortuary("watchman", "returned_evidence")
	check(Post.identity_intel(watch).is_empty(), "Inherited qualification alone disclosed exact enemy intelligence")
	select(watch, "watchman_intel")
	var intel := Post.identity_intel(watch)
	check(intel.size() == 3 and str(intel[0]).contains(str(Defense._count(Defense.wave_for_run(watch, 11)))), "Unlocked intelligence disagrees with actual wave")
	check(not Identity.has(watch, "light_escape"), "Watchman gained both exclusive routes")

func test_new_routes() -> void:
	for row in [["watchman", "watchman_lane", "", "prepare_light_escape", 18, 150, "light"], ["escort", "escort_convoy", "escaped_city", "prepare_convoy", 17, 180, "convoy"]]:
		var run := mortuary(row[0], row[2])
		select(run, row[1])
		check(action_rejected(run, row[3]), "Identity experience bypassed current temple evidence")
		make_routes(run)
		var supplies: Dictionary = run.home.duplicate(true)
		action(run, row[3])
		check(Story.state(run).route == "", "Preparation locked route before completion")
		finish_work(run)
		check(Story.state(run).escape_method == row[6] and run.home != supplies, "Wrong route method/cost")
		check(action_rejected(run, "prepare_ritual"), "Escape preparation allowed simultaneous ritual")
		at(run, row[4], 119)
		check(action_rejected(run, "escape"), "Identity route escaped before its window")
		at(run, row[4], 120)
		check(str(Story.view(run).goal).contains(str(row[5])), "Current goal hides changed travel duration")
		action(run, "escape")
		check(int(run.busy.end) - int(run.busy.start) == int(row[5]), "Actual escape ignored changed duration")
		Post.advance(run, int(row[5]) - 1)
		check(run.phase == "post", "Escape ended before work finished")
		Post.advance(run, 1)
		check(run.phase == "ending" and Story.ending(run).kind == "escape" and Story.ending(run).bonus == 0, "Identity escape wrong outcome/reward")
	var paper := mortuary("scholar", "sealed_lamps")
	select(paper, "scholar_diagram")
	make_routes(paper)
	paper.home.erase("dog_blood")
	check(action_rejected(paper, "prepare_ritual"), "Missing dog blood accepted ordinary ritual")
	action(paper, "prepare_paper_ritual")
	check(int(paper.busy.end) - int(paper.busy.start) == 150, "Paper ritual used wrong work time")
	finish_work(paper)
	check(Story.state(paper).stage == "ritual_ready" and Story.state(paper).interventions.ritual_t < 0, "Paper preparation sealed lamps remotely")
	at(paper, 13)
	check(Post.act_explore(paper, "taoist_temple") == "", "Cannot visit actual ritual site")
	var index := -1
	for i in paper.explore.spots.size():
		if paper.explore.spots[i].get("mainline", "") == "ritual": index = i
	check(index >= 0 and Post.search(paper, index).get("started", false), "Paper ritual failed to start onsite")
	Post.advance(paper, 89)
	check(Story.state(paper).interventions.ritual_t < 0, "Paper ritual sealed before onsite completion")
	Post.advance(paper, 1)
	check(Story.state(paper).stage == "sealed" and not "blood_moon" in Defense.wave_for_run(paper, 20).mods, "Actual paper ritual did not weaken final wave")

func test_migration_and_time() -> void:
	var run := sample("watchman", "returned_evidence")
	run.version = 17
	var migrated := Migrate.save({"run": run.duplicate(true), "snapshots": {"2": run.duplicate(true)}})
	check(migrated.run.version == Migrate.VERSION and migrated.run.identity.is_empty() and migrated.snapshots["2"].identity.is_empty(), "Legacy run gained future inheritance during migration")
	var late := mortuary("watchman")
	select(late, "watchman_lane")
	make_routes(late)
	late.t = Story.FINAL_END - 269 # 120 preparation + 150 travel does not fit.
	late.pday = 19
	var supplies: Dictionary = late.home.duplicate(true)
	check(action_rejected(late, "prepare_light_escape") and late.home == supplies, "Short identity route deadline consumed supplies")
	var daily := mortuary("escort", "escaped_city")
	select(daily, "escort_convoy")
	make_routes(daily)
	action(daily, "prepare_convoy")
	finish_work(daily)
	at(daily, 17, 120)
	daily.flags.daily = "2026-10-24"
	check(action_rejected(daily, "escape"), "Daily mode activated a previously locked legacy route")
	check(Identity.context(daily).chosen == "" and Post.identity_intel(daily).is_empty(), "Daily late flag disclosed legacy abilities")
	var plain := mortuary("scholar")
	action(plain, "copy")
	finish_work(plain)
	check(Post.identity_action(plain, "scholar_collate", str(Identity.view(plain).token)) != "", "Identity stacked after ordinary copy")
	var meta := State.new_meta()
	var prior := State.new_run("herbalist", meta, 818)
	at(prior, 2)
	Past.record(prior, "ning", "medicine", "你曾实际把药交给阿宁。", 1)
	check(Past.archive(prior, meta), "Could not seal actual medicine source")
	Game.meta = meta
	Game.new_game("herbalist", "normal", [], [], [], false, true)
	check(Past.daily(Game.run) and Identity.state(Game.run).inherited.is_empty(), "Real Game.new_game late daily flag retained private legacy sources")
	Game.new_game("herbalist", "normal", [], [], [], false, false)
	check(not Identity.state(Game.run).inherited.is_empty(), "Ordinary real new_game lost the same verified legacy")

func _ready() -> void:
	Game.no_save = true
	Game.speed = 0
	test_recipes_and_costs()
	if failures: get_tree().quit(1); return
	test_wave_and_intel()
	if failures: get_tree().quit(1); return
	test_new_routes()
	if failures: get_tree().quit(1); return
	test_migration_and_time()
	print("Identity integration: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

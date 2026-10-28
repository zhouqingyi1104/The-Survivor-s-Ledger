extends Node
const Defense = preload("res://scripts/core/defense.gd")
const Post = preload("res://scripts/core/post.gd")
const State = preload("res://scripts/core/state.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const Story = preload("res://scripts/core/mainline.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error(label)

func sample(day := 1, minute := 200) -> Dictionary:
	var run := State.new_run("scholar", State.new_meta(), 108)
	run.phase = "post"
	run.pday = day
	run.t = (day - 1) * Post.DAY + minute
	run.home = {"wood": 10, "nails": 5, "caltrops": 3}
	run.devices = []
	run.attrs.energy = 100
	run.guard_spot = ""
	run.today["actions"] = []
	return run

func test_device_power() -> void:
	var run := sample()
	run.devices = [{"id": "armor_hook", "dur": 2}, {"id": "horde_rope", "dur": 2}]
	var armor := Defense.wave_for_day(11)
	var horde := Defense.wave_for_day(8)
	var plain := Defense.wave_for_day(2)
	var mix := {"day": 23, "count": 20, "mods": ["armored", "horde"]}
	check(Defense.device_bonus(run, "gate", armor) == 4 and Defense.device_bonus(run, "window", armor) == 0, "armor applies to gate only")
	check(Defense.device_bonus(run, "window", horde) == 4 and Defense.device_bonus(run, "gate", horde) == 0, "horde applies to window only")
	check(Defense.device_bonus(run, "gate", plain) == 0 and Defense.device_bonus(run, "window", plain) == 0, "plain receives no bonus")
	check(Defense.device_bonus(run, "gate", mix) == 4 and Defense.device_bonus(run, "window", mix) == 4, "multi-mod activation")
	check(Defense.surface_power(run, "gate", armor).total == 6 and Defense.surface_power(run, "gate", plain).total == 2, "matched power vs ordinary")
	check(Defense.surface_power(run, "window", horde).total == 6 and Defense.surface_power(run, "window", plain).total == 2, "horde power vs ordinary")
	run.devices.append({"id": "armor_hook", "dur": 1})
	check(Defense.device_bonus(run, "gate", armor) == 8 and Defense.surface_power(run, "gate", armor).total == 12, "multiple devices follow existing stacking")
	var trial := sample(11)
	trial.devices = [{"id": "armor_hook", "dur": 2}]
	check("armored" in Defense.wave_for_run(trial, 11).mods, "initial armor")
	Story.state(trial).interventions.disrupt_t = 2
	check(not "armored" in Defense.wave_for_run(trial, 11).mods and Defense.device_bonus(trial, "gate", Defense.wave_for_run(trial, 11)) == 0, "completed interception removes bonus")
	Story.state(trial).interventions.disrupt_t = -1
	Defense.start_night(trial, Defense.wave_for_run(trial, 11))
	Story.state(trial).interventions.disrupt_t = 2
	check("armored" in Defense.wave_for_run(trial, 11).mods and Defense.surface_power(trial, "gate").total == 6, "started wave locks modifiers")

func test_preview_and_round() -> void:
	for day in [2, 5, 8, 11, 14, 17, 20, 23]:
		var run := sample(day)
		run.devices = [{"id": "armor_hook", "dur": 2}, {"id": "horde_rope", "dur": 2}]
		run.home.lamp_oil = 1
		var wave := Defense.wave_for_run(run, day)
		var before := run.duplicate(true)
		var whole := Defense.preview_night(run, wave)
		check(run == before, "preview is read-only day %d" % day)
		var sum := 0
		for i in Defense.rounds():
			var split := Defense.round_split(wave, i)
			for sid in Defense.SURFACES: sum += int(split[sid])
		check(sum == int(whole.total), "distribution preserves population day %d" % day)
		var expected := 0
		Defense.start_night(run, wave)
		for i in Defense.rounds():
			var pv := Defense.preview_round(run, wave, i)
			var rep := Defense.next_round(run)
			for sid in Defense.SURFACES:
				var p: Dictionary = pv.surfaces[sid]
				var a: Dictionary = rep.surfaces[sid]
				check(p.count == a.count and p.killed == a.killed and p.left == a.left and p.dmg == a.dmg and p.enter == a.enter and p.bonus == a.bonus, "preview matches day %d round %d %s" % [day, i, sid])
				expected += int(a.left)
		check(expected == int(whole.left), "whole static simulation matches day %d" % day)
	# An existing sortie is a one-round reduction, never a repeating discount.
	var remaining := sample(11)
	remaining.devices = [{"id": "armor_hook", "dur": 2}]
	var rem_wave := Defense.wave_for_run(remaining, 11)
	Defense.start_night(remaining, rem_wave)
	Defense.next_round(remaining)
	remaining.night.sortie = {"gate": 2}
	var rem_preview := Defense.preview_night(remaining, rem_wave)
	var rem_total := 0
	for idx in range(1, Defense.rounds()):
		var split := Defense.round_split(rem_wave, idx)
		for sid in Defense.SURFACES: rem_total += maxi(0, int(split[sid]) - (2 if idx == 1 and sid == "gate" else 0))
	check(int(rem_preview.total) == rem_total, "already-started night counts only remaining rounds and one sortie")
	for role in ["scholar", "watchman"]:
		for oil in [0, 1]:
			var light := State.new_run(role, State.new_meta(), 108)
			light.phase = "post"
			light.pday = 5
			light.home = {"lamp_oil": oil}
			light.devices = [{"id": "peach_stake", "dur": 2}]
			var light_wave := Defense.wave_for_run(light, 5)
			var light_preview := Defense.preview_night(light, light_wave)
			Defense.start_night(light, light_wave)
			check(is_equal_approx(float(light_preview.gate.power), snappedf(float(Defense.surface_power(light, "gate", light_wave).total), 0.1)), "dark lamp forecast for %s oil=%d" % [role, oil])
	var open := sample(11)
	open.devices = [{"id": "armor_hook", "dur": 2}]
	open.door_open = true
	var wave := Defense.wave_for_run(open, 11)
	Defense.start_night(open, wave)
	var preview := Defense.preview_round(open, wave, 0)
	var actual := Defense.next_round(open)
	check(preview.surfaces.gate.bonus == 0 and actual.surfaces.gate.bonus == 0 and actual.live_gate > 0, "open gate does not apply defense bonus")
	check(preview.surfaces.gate.dmg == 0 and preview.surfaces.gate.killed == 0, "open gate prediction does not invent blocked kills")
	var broken := sample(11)
	broken.door.cur = 0
	broken.devices = [{"id": "armor_hook", "dur": 2}]
	Defense.start_night(broken, wave)
	check(Defense.preview_round(broken, wave, 0).surfaces.gate.bonus == 0 and Defense.next_round(broken).surfaces.gate.bonus == 0, "broken side has no bonus")

func test_build_and_interrupt() -> void:
	for id in ["armor_hook", "horde_rope"]:
		var run := sample()
		var initial: Dictionary = run.home.duplicate(true)
		var energy := float(run.attrs.energy)
		check(Post.act_build(run, id) == "" and run.busy.kind == "build", id + " starts")
		check(int(run.busy.end) - int(run.t) == 90 and float(run.attrs.energy) == energy - 10, id + " real time and energy")
		check(run.busy.data.paid_cost == ( {"wood":2, "caltrops":1} if id == "armor_hook" else {"wood":2, "nails":1}), id + " saved actual cost")
		check(Post.act_build(run, id) != "", id + " no duplicate click")
		Post.advance(run, 89)
		check(run.devices.is_empty(), id + " unfinished")
		Post.advance(run, 1)
		check(run.devices.size() == 1 and run.devices[0].id == id and int(run.devices[0].dur) == 2, id + " finished after 90 min")
		var interrupted := sample()
		Post.act_build(interrupted, id)
		Post.start_fight(interrupted, 1, false)
		check(interrupted.busy.is_empty() and interrupted.home == initial and interrupted.devices.is_empty(), id + " actual fight refunds paid materials")
		check(float(interrupted.attrs.energy) == energy - 10, id + " fight does not refund energy")
		Post._interrupt_targeted_device(interrupted)
		check(interrupted.home == initial, id + " no duplicate refund")
		var poor := sample()
		poor.home.wood = 0
		var poor_before := poor.duplicate(true)
		check(Post.act_build(poor, id) != "" and poor == poor_before, id + " insufficient materials atomic")
		var at_wave := sample(2, 950)
		Post.act_build(at_wave, id)
		check(Post.advance(at_wave, 10) == "wave" and at_wave.busy.is_empty() and at_wave.home == initial, id + " wave interruption refund")
		var at_raid := sample(3, 1050)
		at_raid.raid_tonight = true
		Post.act_build(at_raid, id)
		var stop := Post.advance(at_raid, 10)
		check(stop == "raid" and at_raid.busy.is_empty(), id + " raid interruption")
		var at_dawn := sample(3, 1430)
		Post.act_build(at_dawn, id)
		check(Post.advance(at_dawn, 10) == "dawn" and at_dawn.busy.is_empty() and at_dawn.home == initial, id + " dawn interruption refund")
		var at_death := sample()
		Post.act_build(at_death, id)
		at_death.attrs.hp = 0
		check(Post.advance(at_death, 1) == "dead" and at_death.busy.is_empty() and at_death.home == initial, id + " death interrupts and refunds")
	var old := sample()
	Post.act_build(old, "peach_stake")
	Post.start_fight(old, 1, false)
	check(old.busy.get("kind", "") == "build", "legacy device fight behavior unchanged")

func test_save_and_night() -> void:
	var run := sample()
	var initial: Dictionary = run.home.duplicate(true)
	var snaps := {}
	run.rebirths_left = 1
	Ledger.snapshot(run, snaps)
	Post.act_build(run, "armor_hook")
	Post.advance(run, 20)
	var path := "user://m2-targeted-%d.json" % OS.get_process_id()
	var saved := SaveFile.write(path, {"run": run, "snapshots": snaps})
	var loaded := SaveFile.read(path)
	check(bool(saved.ok) and loaded.source == "main", "save/load while constructing")
	var resumed: Dictionary = Migrate.upgrade(loaded.data.run)
	Post.start_fight(resumed, 1, false)
	check(int(resumed.home.wood) == 10 and int(resumed.home.nails) == 5 and int(resumed.home.caltrops) == 3 and resumed.busy.is_empty(), "save keeps exact refund snapshot")
	run.pday = 2
	var rewound := Ledger.rewind(run, snaps, State.new_meta())
	check(rewound.home == initial and rewound.devices.is_empty(), "rewind restores old materials and no device")
	SaveFile.forget(path)
	var night := sample(11, 960)
	var wave := Defense.wave_for_run(night, 11)
	Defense.start_night(night, wave)
	Defense.next_round(night)
	night.night.acted = false
	check(Post.night_build(night, "armor_hook") == "" and night.busy.kind == "ward", "night build starts")
	check(int(night.busy.end) - int(night.t) == 20, "night build takes 20 minutes")
	var after_pay: Dictionary = night.home.duplicate(true)
	Post.start_fight(night, 1, true)
	check(night.busy.is_empty() and int(night.home.wood) == int(after_pay.wood) + 2 and int(night.home.caltrops) == int(after_pay.caltrops) + 1, "night build interrupted refunds")
	var killed := sample(11, 960)
	var killed_initial: Dictionary = killed.home.duplicate(true)
	Defense.start_night(killed, Defense.wave_for_run(killed, 11))
	Defense.next_round(killed)
	killed.night.acted = false
	killed.t += 30
	check(Post.night_build(killed, "armor_hook") == "", "night construction can start before next round")
	killed.window.cur = 0
	killed.attrs.hp = 1
	killed.t += 10
	Post.nod_round(killed)
	check(killed.phase == "dead" and killed.busy.is_empty() and killed.home == killed_initial, "lethal wave interrupts and refunds unfinished night construction")
	var unsafe := sample()
	unsafe.facilities.append("cellar")
	unsafe.home_floor = "cellar"
	var unsafe_home: Dictionary = unsafe.home.duplicate(true)
	check(Post.act_build(unsafe, "horde_rope") == "", "indoor construction starts")
	unsafe.fight = {"foes": []}
	var recovered := Migrate.upgrade(unsafe)
	check(recovered.home_floor == "courtyard" and recovered.busy.is_empty() and recovered.home == unsafe_home, "unsafe indoor fight save restores to courtyard and refunds once")
	var worn := sample(11)
	worn.devices = [{"id": "armor_hook", "dur": 2}]
	Defense.start_night(worn, wave)
	for i in Defense.rounds(): Defense.next_round(worn)
	Defense.finish_night(worn)
	check(int(worn.devices[0].dur) == 1, "one night wears once")
	Defense.start_night(worn, wave)
	for i in Defense.rounds(): Defense.next_round(worn)
	Defense.finish_night(worn)
	check(worn.devices.is_empty(), "two nights expire device")

func test_time_and_entry_guards() -> void:
	var skilled := sample()
	skilled.prof.build = 25
	check(Post.act_build(skilled, "armor_hook") == "", "skilled daytime starts")
	Post.advance(skilled, 90)
	check(skilled.devices.size() == 1 and int(skilled.devices[0].dur) == 3, "skilled daytime grants existing extra night")
	var night := sample(11, 960)
	night.prof.build = 25
	Defense.start_night(night, Defense.wave_for_run(night, 11))
	Defense.next_round(night)
	check(Post.act_build(night, "armor_hook") != "", "night workbench cannot bypass one action")
	check(Post.night_build(night, "armor_hook") == "", "night action starts")
	night.t = int(night.busy.end)
	Post._check_busy(night)
	check(night.devices.size() == 1 and int(night.devices[0].dur) == 2, "night work does not get daytime skill bonus")
	var tired := sample()
	tired.attrs.energy = 9
	var before := tired.duplicate(true)
	check(Post.act_build(tired, "horde_rope") != "" and tired == before, "day work requires actual 10 energy and no payment on failure")
	var fighting := sample()
	Post.start_fight(fighting, 1, false)
	var during := fighting.duplicate(true)
	check(Post.act_build(fighting, "armor_hook") != "" and fighting == during, "cannot build while fighting")
	var pressure := sample(11)
	pressure.devices = [{"id": "armor_hook", "dur": 2}, {"id": "armor_hook", "dur": 2}]
	pressure.guard_spot = "window"
	Defense.wave_for_run(pressure, 11)
	var original := pressure.duplicate(true)
	check(Post._spot_for(pressure, "weak") == "window", "weak policy compares unguarded round-by-round leaks")
	check(pressure == original, "policy comparison does not change player guard")
	var breached := sample(11)
	breached.door.cur = 0
	breached.guard_spot = "gate"
	var baseline := breached.duplicate()
	baseline.guard_spot = ""
	var wave := Defense.wave_for_run(breached, 11)
	var no_guard := Defense.preview_night(baseline, wave)
	check(int(no_guard.gate.left) > int(no_guard.window.left), "breached gate would win by incoming count")
	var spot := Post._spot_for(breached, "weak")
	var guarded := baseline.duplicate()
	guarded.guard_spot = spot
	check(spot != "gate" and int(Defense.preview_night(guarded, wave).left) < int(no_guard.left), "weak policy defends intact surface with real benefit, not breached gate")
	breached.door.cur = breached.door.max
	breached.door_open = true
	check(Post._spot_for(breached, "weak") != "gate", "weak policy avoids open gate where devices cannot act")
	breached.window.cur = 0
	breached.wall.cur = 0
	check(Post._spot_for(breached, "weak") == "", "only open gate and broken sides have no guard location")
	breached.door_open = false
	breached.door.cur = 0
	check(Post._spot_for(breached, "weak") == "", "all sides broken have no guard location")
	breached.plan_due = true
	check(Post.choose_policy(breached, "manual") == "" and breached.guard_spot == "", "manual policy records empty guard position")
	check(str(breached.log.back()).contains("三面都守不了"), "policy log explains no guard location")
	var fixed_gate := sample(11)
	check(Post._spot_for(fixed_gate, "gate") == "gate", "hold chooses intact closed gate")
	fixed_gate.door.cur = 0
	check(Post._spot_for(fixed_gate, "gate") == "", "hold does not pretend to guard a broken gate or redirect")
	fixed_gate.door.cur = fixed_gate.door.max
	fixed_gate.door_open = true
	check(Post._spot_for(fixed_gate, "gate") == "", "hold does not pretend to guard an open gate or redirect")
	fixed_gate.plan_due = true
	check(Post.choose_policy(fixed_gate, "hold") == "" and fixed_gate.guard_spot == "" and str(fixed_gate.log.back()).contains("院门守不了"), "hold reports chosen gate cannot be guarded")
	fixed_gate.door_open = false
	check(Post._spot_for(fixed_gate, "gate") == "gate", "hold resumes guarding after gate closes")
	var old := sample()
	var migrated := Migrate.upgrade(old.duplicate(true))
	check(migrated.devices.is_empty() and migrated.home == old.home, "legacy migration grants no free devices or payment")


func _ready() -> void:
	Game.no_save = true
	test_device_power()
	test_preview_and_round()
	test_build_and_interrupt()
	test_save_and_night()
	test_time_and_entry_guards()
	print("[M2_TARGETED_DEFENSE] ", passed, "/", passed + failed, " failed=", failed)
	get_tree().quit(1 if failed else 0)

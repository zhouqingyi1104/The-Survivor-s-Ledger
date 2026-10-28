extends Node
const NH = preload("res://scripts/core/neighbor_home.gd")
const Post = preload("res://scripts/core/post.gd")
const State = preload("res://scripts/core/state.gd")
const Npcs = preload("res://scripts/core/npc_autonomy.gd")
const Trade = preload("res://scripts/core/social_trade.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const Migrate = preload("res://scripts/core/migrate.gd")
const Floors = preload("res://scripts/core/home_floor.gd")
const Home = preload("res://scripts/core/home.gd")
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error(label)
func fixture() -> Dictionary:
	var r := State.new_run("scholar", State.new_meta(), 459)
	r.phase = "post"
	r.pday = 1
	r.t = 200
	r.today["actions"] = []
	r.home = {"wood": 5, "nails": 3, "rice": 5}
	return r
func _ready() -> void:
	Game.no_save = true
	var empty := {}
	check(not NH.view(empty).knocked and empty.is_empty(), "legacy view is safe and read-only")
	var r := fixture()
	var before := r.duplicate(true)
	check(NH.act(r, "trade") != "" and r == before, "cannot act before knocking")
	check(NH.knock(r) == "" and NH.view(r).knocked and NH.view(r).deadline_t == 2160, "knock identifies west neighbor and fixes deadline")
	r.t += 20
	check(NH.knock(r) == "" and NH.view(r).deadline_t == 2160, "repeat knock does not extend deadline")
	var blocked := r.duplicate(true)
	blocked.home_floor = "attic"
	check(NH.knock(blocked) != "" and NH.act(blocked, "refuse") != "", "must be at courtyard")
	blocked = r.duplicate(true)
	blocked.fight = {"total": 1}
	check(NH.act(blocked, "refuse") != "", "fight prevents selection")
	blocked = r.duplicate(true)
	blocked.t = 720
	check(NH.act(blocked, "refuse") != "", "night prevents selection")
	blocked = r.duplicate(true)
	blocked.home.nails = 0
	before = blocked.duplicate(true)
	check(NH.act(blocked, "repair") != "" and blocked == before, "insufficient materials failure is atomic")
	var snaps := {}
	r.rebirths_left = 1
	Ledger.snapshot(r, snaps)
	var started := int(r.t)
	check(NH.act(r, "repair") == "" and r.busy.kind == "neighbor_wall" and r.home.wood == 3 and r.home.nails == 2 and not NH.view(r).wall_repaired, "repair reserves exact materials and cannot complete early")
	check(NH.act(r, "repair") != "", "cannot double spend during work")
	Post.advance(r, 59)
	check(int(r.t) == started + 59 and not NH.view(r).wall_repaired, "real clock and unfinished work")
	var path := "user://c6-rules-%d.json" % OS.get_process_id()
	check(SaveFile.write(path, {"run": r, "snapshots": snaps}).ok, "save during construction")
	var loaded: Dictionary = SaveFile.read(path).data.run
	check(loaded.busy.end == started + 60 and NH.view(loaded).stage == "working", "load preserves work and deadline")
	Post.advance(loaded, 1)
	check(NH.view(loaded).wall_repaired and NH.view(loaded).choice == "repair" and not NH.view(loaded).settled, "repair completes exactly at work end; next day pending")
	check(Trade.contact(loaded, "zhou").trust == 0, "no early relationship reward")
	var target := int(NH.view(loaded).due_t)
	loaded.pday = 2
	loaded.t = target - 1
	Npcs.state(loaded).actors.zhou.stock = {"wood": 5, "rice": 5}
	Npcs.state(loaded).actors.zhou.plan = {}
	Npcs.state(loaded).next_day = 2
	loaded.crisis.active = {}
	loaded.crisis.next_warning_day = 10
	Post.trade_refresh(loaded)
	check(not NH.view(loaded).settled, "no early next-day consequence")
	loaded.t = target
	Post.trade_refresh(loaded)
	check(NH.view(loaded).settled and Trade.contact(loaded, "zhou").trust == 2, "completion settles trust once")
	check(Npcs.state(loaded).actors.zhou.plan.mode == "share", "settlement precedes same-minute NPC decision")
	Post.trade_refresh(loaded)
	check(Trade.contact(loaded, "zhou").trust == 2, "repeated poll cannot duplicate trust")
	var rewound := Ledger.rewind(loaded, snaps, State.new_meta())
	check(NH.view(rewound).stage == "open" and not NH.view(rewound).wall_repaired and rewound.home.wood == 5, "rewind restores request and resources")
	var traded := fixture()
	NH.knock(traded)
	Npcs.state(traded).actors.zhou.stock = {"wood": 2, "rice": 3}
	check(NH.act(traded, "trade") == "" and traded.home.rice == 4 and traded.home.wood == 6 and Npcs.state(traded).actors.zhou.stock == {"wood": 1, "rice": 4}, "trade transfers actual finite stocks")
	check(Npcs.state(traded).history.any(func(f): return f.actor == "zhou" and f.action == "neighbor_exchange"), "exchange is recorded in actual NPC history")
	check(NH.act(traded, "trade") != "" and traded.home.wood == 6, "trade cannot be replayed")
	traded.t = NH.view(traded).due_t
	traded.pday = 2
	Post.trade_refresh(traded)
	check(Trade.contact(traded, "zhou").trust == 1 and not NH.view(traded).wall_repaired, "trade next-day consequence does not invent repair")
	var poor := fixture()
	NH.knock(poor)
	Npcs.state(poor).actors.zhou.stock = {"wood": 0, "rice": 3}
	before = poor.duplicate(true)
	check(NH.act(poor, "trade") != "" and poor == before, "empty NPC wood blocks atomic exchange")
	poor.npcs.actors.zhou.stock = {"wood": 2, "rice": 20}
	before = poor.duplicate(true)
	check(NH.act(poor, "trade") != "" and poor == before, "NPC stock cap blocks atomic exchange")
	var refuse := fixture()
	NH.knock(refuse)
	before = refuse.home.duplicate(true)
	check(NH.act(refuse, "refuse") == "" and refuse.home == before, "refusal consumes no goods")
	refuse.t = NH.view(refuse).due_t
	refuse.pday = 2
	Post.trade_refresh(refuse)
	check(Trade.contact(refuse, "zhou").trust == -1 and Trade.contact(refuse, "zhou").breaches == 0, "refusal changes real trust without false breach")
	var capped := fixture()
	Trade.state(capped).actors.zhou.trust = 4
	NH.knock(capped)
	NH.act(capped, "repair")
	capped.t += 60
	Post._check_busy(capped)
	capped.t = NH.view(capped).due_t
	capped.pday = 2
	Post.trade_refresh(capped)
	check(Trade.contact(capped, "zhou").trust == 5 and "变化 +1" in NH.view(capped).result and "信任 +1" in Trade.state(capped).history.back().result, "upper cap records actual partial change")
	var bottom := fixture()
	Trade.state(bottom).actors.zhou.trust = -5
	NH.knock(bottom)
	NH.act(bottom, "refuse")
	bottom.t = NH.view(bottom).due_t
	bottom.pday = 2
	Post.trade_refresh(bottom)
	check(Trade.contact(bottom, "zhou").trust == -5 and "变化 +0" in NH.view(bottom).result and Trade.state(bottom).history.any(func(h): return h.action == "neighbor_home" and "这次没变" in h.result), "lower cap records actual zero change")
	var timeout := fixture()
	NH.knock(timeout)
	timeout.t = int(NH.view(timeout).deadline_t) - 1
	timeout.pday = 2
	Post.trade_refresh(timeout)
	check(NH.view(timeout).stage == "open" and NH.act(timeout, "repair") != "", "cannot start repair that would finish after deadline")
	timeout.t += 1
	Post.trade_refresh(timeout)
	check(NH.view(timeout).choice == "timeout" and not NH.view(timeout).settled, "exact deadline expires without a choice")
	timeout.pday = 3
	timeout.t = NH.view(timeout).due_t
	Post.trade_refresh(timeout)
	check(NH.view(timeout).settled and Trade.contact(timeout, "zhou").trust == -1, "timeout has next-day consequence")
	var crossing := fixture()
	NH.knock(crossing)
	crossing.neighbor = {"stage": "closed", "ending": "fixture", "resolution": "", "history": []}
	crossing.t = int(NH.view(crossing).deadline_t) - 1
	crossing.pday = 2
	check(Post.advance(crossing, 2) == "" and NH.view(crossing).choice == "timeout", "actual clock crossing expires request")
	var late_load := crossing.duplicate(true)
	late_load.t = NH.view(late_load).due_t + 200
	late_load.pday = 3
	Post.trade_refresh(late_load)
	check(NH.view(late_load).settled and Trade.contact(late_load, "zhou").trust == -1, "late loaded settlement catches up once")
	var interrupted := fixture()
	NH.knock(interrupted)
	check(NH.act(interrupted, "repair") == "", "interrupt fixture starts")
	Post.start_fight(interrupted, 1, false)
	check(interrupted.busy.is_empty() and interrupted.home.wood == 5 and interrupted.home.nails == 3 and NH.view(interrupted).stage == "open", "fight returns materials and reopens request")
	NH.interrupt(interrupted)
	check(interrupted.home.wood == 5, "interrupt refund is idempotent")
	var raid := fixture()
	NH.knock(raid)
	NH.act(raid, "repair")
	raid.t = Post.RAID_AT - 1
	raid.busy.start = raid.t - 30
	raid.busy.end = raid.t + 30
	raid.raid_tonight = true
	check(Post.advance(raid, 1) == "raid" and raid.busy.is_empty() and NH.view(raid).stage == "open" and raid.home.wood == 5 and not NH.view(raid).wall_repaired, "real raid interrupts repair before settlement")
	var exact := fixture()
	NH.knock(exact)
	exact.t = NH.view(exact).deadline_t - 60
	exact.pday = 2
	check(NH.act(exact, "repair") == "", "repair can end exactly at deadline")
	exact.t += 60
	Post.trade_refresh(exact)
	Post._check_busy(exact)
	check(NH.view(exact).choice == "repair" and NH.view(exact).wall_repaired, "completion at deadline takes precedence over timeout")
	var legacy := Migrate.upgrade(fixture())
	check(NH.view(legacy).stage == "unmet", "old saves need no fabricated encounter")
	var guest := fixture()
	check(Post.change_floor(guest, "guest_zhou") != "" and Floors.current(guest) == "courtyard", "uninvited entry refused")
	var guest_snaps := {}
	guest.rebirths_left = 1
	Ledger.snapshot(guest, guest_snaps)
	var jar := Home.add(guest, "pickle_jar", 1, 1, 0)
	var rack := Home.add(guest, "smoke_rack", 3, 1, 0)
	guest.home.cabbage = 3
	guest.home.salt = 1
	guest.home.rat = 2
	guest.home.firewood = 1
	NH.knock(guest)
	check("院门" in NH.view(guest).result and Post.change_floor(guest, "guest_zhou") == "" and Floors.current(guest) == "guest_zhou", "invitation grants real guest space")
	var guest_before := guest.duplicate(true)
	check(Post.use_item(guest, "rice") != "" and guest == guest_before, "cannot consume home stock in guest space")
	check(Post.can_act(guest) != "" and Post.act_furnish(guest, "armchair", -2, 0, 0) != "" and Post.sleep(guest) != "" and Post.act_garden(guest) != "", "cannot start home work or sleep while visiting")
	check(Home.spot_block(guest, "armchair", -2, 0, 0) != "" and Home.add(guest, "armchair", -2, 0, 0).is_empty(), "core placement rejects guest space")
	check(NH.act(guest, "repair") != "" and NH.act(guest, "trade") != "" and NH.act(guest, "refuse") != "", "choices remain at wall outside")
	check(Post.trade_action(guest, "zhou", "cash", "") != "" and Post.npc_action(guest, "zhou", "support", "") != "" and Post.identity_action(guest, "x", "") != "", "cannot write remote home actions from guest space")
	guest_before = guest.duplicate(true)
	check(Home.pickle(guest, int(jar.uid), "cabbage", 2) != "" and Home.smoke(guest, int(rack.uid), "rat", 2) != "" and guest == guest_before, "guest cannot start processing against courtyard stock")
	check(Post.change_floor(guest, "attic") != "" and Post.change_floor(guest, "courtyard") == "", "guest space must return to courtyard")
	check(Post.change_floor(guest, "guest_zhou") == "", "reenter guest space")
	var floor_jobs := fixture()
	floor_jobs.facilities.append("cellar")
	var cellar_jar := Home.add(floor_jobs, "pickle_jar", -2, 0, 0, "cellar")
	var cellar_rack := Home.add(floor_jobs, "smoke_rack", 2, 0, 0, "cellar")
	floor_jobs.home = {"cabbage": 3, "salt": 1, "rat": 2, "firewood": 1}
	var jobs_before := floor_jobs.duplicate(true)
	check(Home.pickle(floor_jobs, int(cellar_jar.uid), "cabbage", 2) != "" and Home.smoke(floor_jobs, int(cellar_rack.uid), "rat", 2) != "" and floor_jobs == jobs_before, "processing cannot run across owned floors")
	Post.change_floor(floor_jobs, "cellar")
	check(Home.pickle(floor_jobs, int(cellar_jar.uid), "cabbage", 2) == "" and Home.smoke(floor_jobs, int(cellar_rack.uid), "rat", 2) == "", "processing works on furniture's actual floor")
	var indoor_saved := Migrate.upgrade(guest.duplicate(true))
	check(Floors.current(indoor_saved) == "guest_zhou", "valid invited save restores visit")
	var no_invite := guest.duplicate(true)
	no_invite.erase("neighbor_home")
	no_invite = Migrate.upgrade(no_invite)
	check(Floors.current(no_invite) == "courtyard" and no_invite.home_floor == "courtyard", "save without invitation returns safely")
	guest.pday = 2
	var guest_rewind := Ledger.rewind(guest, guest_snaps, State.new_meta())
	check(Floors.current(guest_rewind) == "courtyard" and not NH.view(guest_rewind).knocked, "rewind before invitation returns to courtyard")
	var afterhours := fixture()
	NH.knock(afterhours)
	afterhours.t = 720
	check(Post.change_floor(afterhours, "guest_zhou") != "", "18:00 entry refused")
	afterhours.home_floor = "guest_zhou"
	afterhours = Migrate.upgrade(afterhours)
	check(afterhours.home_floor == "courtyard", "afterhours saved visit returns safely")
	var dusk := fixture()
	NH.knock(dusk)
	dusk.t = 719
	Post.change_floor(dusk, "guest_zhou")
	var prior_home: Dictionary = dusk.home.duplicate(true)
	check(Post.advance(dusk, 1) == "" and dusk.home_floor == "courtyard" and dusk.home == prior_home, "real dusk checkpoint returns home without resource loss")
	var visitor_raid := fixture()
	NH.knock(visitor_raid)
	Post.change_floor(visitor_raid, "guest_zhou")
	Post.start_fight(visitor_raid, 1, false)
	check(visitor_raid.home_floor == "courtyard" and not visitor_raid.fight.is_empty(), "fight returns visitor before combat")
	var zhou_day := fixture()
	var zhou_state := Npcs.state(zhou_day)
	zhou_state.actors.zhou.stock = {"rice": 1, "wood": 5}
	var old_fact := {"day": 1, "t": 600, "actor": "zhou", "action": "execute_gather", "result": "老周按先前安排外出觅粮，自己的米粮增加 2。"}
	zhou_state.history.append(old_fact.duplicate(true))
	zhou_day.t = 1560
	zhou_day.pday = 2
	Npcs.poll(zhou_day)
	var zhou_plan: Dictionary = zhou_state.actors.zhou.plan
	check(zhou_plan.status == "pending" and zhou_plan.focus == "rice" and int(zhou_plan.due_t) == 2040 and "想办法弄粮" in zhou_plan.reason and not "出门" in zhou_plan.reason, "new low-food plan is location neutral with original due time")
	check(int(zhou_state.actors.zhou.stock.rice) == 0, "daily meal stock deduction unchanged")
	zhou_day.t = 2040
	Npcs.poll(zhou_day)
	check(zhou_plan.status == "done" and int(zhou_state.actors.zhou.stock.rice) == 2 and "筹措口粮" in zhou_state.actors.zhou.last_result and not "外出" in zhou_state.actors.zhou.last_result, "16:00 execution keeps same stock gain without location claim")
	check(zhou_state.history.any(func(h): return h == old_fact), "older recorded event is never rewritten")
	SaveFile.forget(path)
	print("[C6_RULES] ", passed, "/", passed + failed, " failed=", failed)
	get_tree().quit(1 if failed else 0)

extends RefCounted
## B4：可复算、只跑指定样本的整局测量。所有难度覆盖只存在于当前进程。

const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")
const Events = preload("res://scripts/core/events.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Inv = preload("res://scripts/core/inv.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Director = preload("res://scripts/core/director.gd")
const ROLES := ["scholar", "escort", "herbalist", "watchman"]
const ARMS := ["legacy", "trips", "agenda"]
const PARAM_KEYS := ["silver_mul", "hp_mul", "food_mul", "water_mul", "cold_add", "wave_mul"]
## 路线图样本建议区间；采集有效不代表这些平衡目标已通过。
const TARGETS := {"mild": [0.90, 1.0], "normal": [0.60, 0.75], "harsh": [0.35, 0.50], "doom": [0.15, 0.30]}

## 故意失败的夹具只在此宿主记账，不污染真实测试的失败数/首错。
class EventFailureHost extends RefCounted:
	var balance_active := true
	var balance_first_error := ""
	var balance_events: Array = []
	var pac_events := 0
	var failures := 0

	func check(ok: bool, message: String) -> void:
		if not ok and balance_first_error == "":
			failures += 1
			balance_first_error = message


static func dispatch(host, args: PackedStringArray) -> bool:
	var test_name := _value(args, "--test-only", "")
	if test_name != "":
		if test_name != "test_difficulty":
			push_error("不支持的 --test-only：" + test_name)
			host.quit(1)
			return true
		host.test_difficulty()
		host.check(test_name in host.tested, "定向测试没有跑完：" + test_name)
		print("定向测试 %s：%s（断言失败 %d）" % [test_name, "PASS" if host.failures == 0 else "FAIL", host.failures])
		host.quit(0 if host.failures == 0 else 1)
		return true
	if not "--balance-only" in args and not "--balance-self-test" in args and not "--balance-event-test" in args and not "--balance-travel-test" in args:
		return false
	host.balance_active = true
	host.policy = "hold"
	if "--balance-travel-test" in args:
		_travel_self_test(host)
	elif "--balance-event-test" in args:
		_event_self_test(host)
	elif "--balance-self-test" in args:
		_self_test(host)
	else:
		_measure(host, args)
	# GDScript 运行时错误可能中止被调函数但让调用方继续；不能因此假通过或挂住。
	if not host.balance_finished:
		host.check(false, "B4 定向入口未执行到结果结算（请检查首个脚本错误）")
		host.quit(1)
	return true


static func _value(args: PackedStringArray, key: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(key + "="):
			return arg.substr(key.length() + 1)
	return fallback


static func _configure(host, arm: String) -> void:
	host.bot_max_trips = 1 if arm == "legacy" else 2
	host.bot_chores = arm == "agenda"


## 与旧机器人相同：始终选择第一个当前可用项；失败绝不算作一次已回答事件。
static func handle_event(host, run: Dictionary) -> bool:
	if host.balance_active and host.balance_first_error != "":
		return false
	var id := str(run.get("pending_event", ""))
	var event: Dictionary = Events.entry(run)
	if id == "" or event.is_empty():
		host.check(false, "事件不存在：" + id)
		return false
	var choices: Array = event.get("choices", [])
	if choices.is_empty():
		host.check(false, "事件没有选项：" + id)
		return false
	var pick := -1
	for idx in choices.size():
		if Events.choice_ok(run, choices[idx]):
			pick = idx
			break
	if pick < 0:
		host.check(false, "事件没有可用选项：%s day=%d" % [id, int(run.pday)])
		return false
	var choice: Dictionary = choices[pick]
	var before := {}
	if host.balance_active:
		before = {"id": id, "day": int(run.pday), "t": int(run.t), "choice_index": pick,
			"source": "world" if id.begins_with("world:") else ("neighbor" if event.get("story", "") == "neighbor" else "ordinary"),
			"choice": str(choice.get("text", "")), "req": choice.get("req", {}).duplicate(true),
			"energy_cost": maxf(0.0, -float(choice.get("fx", {}).get("energy", 0))),
			"silver_before": int(run.silver), "energy_before": float(run.attrs.energy),
			"home": run.home.duplicate(true)}
	var error := Events.choose(run, pick)
	if error != "":
		host.check(false, "事件回答失败：%s choice=%d / %s" % [id, pick, error])
		return false
	if str(run.pending_event) != "":
		host.check(false, "事件回答后仍有待处理事项：%s choice=%d pending=%s" % [id, pick, str(run.pending_event)])
		return false
	host.pac_events += 1
	if host.balance_active:
		var home_before: Dictionary = before.home
		before.erase("home")
		before["silver_after"] = int(run.silver)
		before["silver_delta"] = int(run.silver) - int(before.silver_before)
		before["energy_after"] = float(run.attrs.energy)
		before["energy_delta"] = float(run.attrs.energy) - float(before.energy_before)
		var materials := {}
		var ids := home_before.keys()
		for item in run.home:
			if item not in ids:
				ids.append(item)
		ids.sort()
		for item in ids:
			var amount_before := int(home_before.get(item, 0))
			var amount_after := int(run.home.get(item, 0))
			if amount_before != amount_after or before.req.has(item) or choice.get("fx", {}).get("items", {}).has(item):
				materials[str(item)] = {"before": amount_before, "after": amount_after, "delta": amount_after - amount_before}
		before["items"] = materials
		host.balance_events.append(before)
	return true


static func _measure(host, args: PackedStringArray) -> void:
	var samples_text := _value(args, "--balance-samples", "24")
	var seed_text := _value(args, "--balance-seed", "4000")
	var arm := _value(args, "--balance-arm", "agenda")
	var difficulty := _value(args, "--balance-difficulty", "")
	var output := _value(args, "--balance-out", "res://build/b4-qa/baseline.json")
	var overrides_path := _value(args, "--balance-overrides", "")
	var allowed_keys := ["--balance-samples", "--balance-seed", "--balance-arm", "--balance-difficulty", "--balance-out", "--balance-overrides"]
	for arg in args:
		if arg == "--balance-only":
			continue
		var key := str(arg).split("=")[0]
		host.check(key in allowed_keys and "=" in arg, "未知或缺值的测量参数：" + arg)
	host.check(samples_text.is_valid_int() and int(samples_text) > 0 and int(samples_text) % ROLES.size() == 0,
		"--balance-samples 必须为正的4倍数（四身份等量）")
	host.check(seed_text.is_valid_int(), "--balance-seed 必须为整数")
	host.check(arm in ARMS, "--balance-arm 只支持 legacy|trips|agenda")
	host.check(_safe_output(output), "测量输出必须位于 res://build/b4-qa/ 或 user://b4-qa/ 下")
	var diffs := []
	for row in Data.table("difficulty"):
		if difficulty == "" or difficulty == str(row.id):
			diffs.append(str(row.id))
	host.check(not diffs.is_empty(), "没有指定的难度：" + difficulty)
	if host.failures > 0:
		host.balance_finished = true
		host.quit(1)
		return
	var original: Array = Data.table("difficulty").duplicate(true)
	var overrides := _apply_overrides(host, overrides_path)
	if host.failures > 0:
		host.balance_finished = true
		host.quit(1)
		return
	_configure(host, arm)
	var snapshot := {
		"schema": 2, "arm": arm, "samples_per_difficulty": int(samples_text), "seed_start": int(seed_text),
		"roles": ROLES, "role_assignment": "roles[sample_index % 4]", "seed_assignment": "seed_start + sample_index",
		"difficulty_filter": difficulty, "difficulties": diffs, "user_args": Array(args),
		"engine": Engine.get_version_info(), "project": ProjectSettings.get_setting("application/config/name"),
		"original_difficulty_table": original, "effective_difficulty_table": Data.table("difficulty").duplicate(true),
		"events_sha256": FileAccess.get_sha256("res://data/events.json"),
		"effective_params": {}, "overrides_path": overrides_path, "overrides": overrides,
		"strategy": {"policy": "hold", "max_daily_trips": host.bot_max_trips, "chores": host.bot_chores,
			"event_policy": "first_currently_affordable_choice", "event_evidence": "successful_choose_and_pending_cleared_with_actual_costs",
			"travel_policy": "resume_remaining_travel_after_events", "interrupted_search": "retry_same_spot_without_unfinished_rewards",
			"exploration_policy": "reachable_spots_no_journey", "chores_priority": "after_maintenance_cooking_garden_crafting_trips_before_reading",
			"shopping": host.SHOPPING.duplicate(true), "fresh_meta": true, "talents": [], "boons": [], "vows": [], "companions": [],
			"free_resources": false, "endless": false, "max_day_iterations": 40, "max_action_iterations_per_day": 900},
	}
	for id in diffs:
		snapshot.effective_params[id] = State.diff_params(str(id))
	var report := {"parameters": snapshot, "games": [], "summary": [], "first_error": "", "status": "RUNNING",
		"status_scope": "measurement_only", "measurement_status": "RUNNING", "sample_targets_met": false,
		"sample_win_rates_monotonic": null}
	for id in diffs:
		var games := []
		for k in int(samples_text):
			var result: Dictionary = host.play(ROLES[k % ROLES.size()], int(seed_text) + k, str(id))
			result["arm"] = arm
			games.append(result)
			report.games.append(result)
			if host.failures > 0 or not bool(result.terminal):
				break
		var summary := _summary(str(id), games, int(samples_text))
		report.summary.append(summary)
		print("[B4] %s %s 劫满 %d/%d 身死 %d 未完成 %d 差事 %d 外出 %d 事件 %d 银两开局/采购后均 %.0f/%.0f" % [
			str(id), arm, summary.wins, summary.completed, summary.deaths, summary.incomplete,
			summary.chores_completed, summary.explorations, summary.events_resolved, summary.mean_silver_start, summary.mean_silver_after_shopping])
		if host.failures > 0:
			break
	report.first_error = host.balance_first_error
	report.status = "PASS" if host.failures == 0 and report.games.size() == diffs.size() * int(samples_text) else "FAIL"
	report.measurement_status = report.status
	var target_report := _targets(report.summary)
	report.sample_targets_met = bool(target_report.met) and report.measurement_status == "PASS"
	report.sample_win_rates_monotonic = target_report.monotonic
	_write(host, output, report)
	print("[B4] 采集%s / 目标%s → %s；%d 局，断言失败 %d" % [report.measurement_status,
		"PASS" if report.sample_targets_met else "未达", output, report.games.size(), host.failures])
	host.balance_finished = true
	host.quit(0 if report.status == "PASS" and host.failures == 0 else 1)


## 只接受 difficulty-id -> 参数覆盖，不覆盖文件、不发放物资；先校验整份再应用。
static func _apply_overrides(host, path: String) -> Dictionary:
	if path == "":
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	host.check(parsed is Dictionary, "难度覆盖文件必须是 JSON 对象：" + path)
	if not parsed is Dictionary:
		return {}
	var known := []
	for row in Data.table("difficulty"):
		known.append(str(row.id))
	for id in parsed:
		host.check(str(id) in known and parsed[id] is Dictionary, "覆盖文件含未知难度或非对象：" + str(id))
		if not parsed[id] is Dictionary:
			continue
		for key in parsed[id]:
			var v = parsed[id][key]
			var number := v is int or v is float
			host.check(str(key) in PARAM_KEYS and number, "覆盖文件含未知参数或非数值：%s.%s" % [str(id), str(key)])
			if number:
				host.check(is_finite(float(v)) and (str(key) == "cold_add" or float(v) > 0.0), "覆盖参数须有限且乘数为正：%s.%s" % [str(id), str(key)])
	if host.failures > 0:
		return {}
	for row in Data.table("difficulty"):
		if parsed.has(str(row.id)):
			for key in parsed[str(row.id)]:
				row.params[key] = Data.normalize(parsed[str(row.id)][key])
	return Data.normalize(parsed)


static func _summary(id: String, games: Array, planned: int) -> Dictionary:
	var summary := {"difficulty": id, "planned": planned, "sample_count": games.size(), "completed": 0, "wins": 0, "deaths": 0,
		"incomplete": 0, "invariant_failures": 0, "win_rate": null, "chores_completed": 0, "chores_attempted": 0,
		"target_min": TARGETS[id][0], "target_max": TARGETS[id][1], "target_met": null,
			"explorations": 0, "events_resolved": 0, "mean_days": 0.0, "mean_hp": 0.0, "mean_silver_start": 0.0, "mean_silver_after_shopping": 0.0, "deaths_by_cause": {}}
	for r in games:
		if str(r.phase) == "ending" and bool(r.terminal):
			summary.wins += 1
			summary.completed += 1
		elif str(r.phase) == "dead" and bool(r.terminal):
			summary.deaths += 1
			summary.completed += 1
			summary.deaths_by_cause[str(r.cause)] = int(summary.deaths_by_cause.get(str(r.cause), 0)) + 1
		else:
			summary.incomplete += 1
		summary.invariant_failures += int(r.invariant_failures)
		summary.chores_completed += int(r.chores_completed)
		summary.chores_attempted += int(r.chores_attempted)
		summary.explorations += int(r.explorations)
		summary.events_resolved += int(r.get("events_resolved", 0))
		summary.mean_days += float(r.days)
		summary.mean_hp += float(r.hp)
		summary.mean_silver_start += float(r.silver_start)
		summary.mean_silver_after_shopping += float(r.silver_left)
	if not games.is_empty():
		for key in ["mean_days", "mean_hp", "mean_silver_start", "mean_silver_after_shopping"]:
			summary[key] = float(summary[key]) / games.size()
	# 未完成局不能进入胜率分母，也不能被算成死亡；不完整批次不发布胜率。
	if summary.completed == planned and summary.incomplete == 0 and summary.invariant_failures == 0:
		summary.win_rate = summary.wins / float(planned)
		summary.target_met = float(summary.win_rate) >= float(summary.target_min) and float(summary.win_rate) <= float(summary.target_max)
	return summary


## 仅比较本批已测难度，按难度顺序比较；有不完整汇总时不作单调结论。
static func _targets(summaries: Array) -> Dictionary:
	var rates := {}
	var all_met := not summaries.is_empty()
	for summary in summaries:
		if summary.win_rate == null or summary.target_met == null:
			return {"met": false, "monotonic": null}
		rates[str(summary.difficulty)] = float(summary.win_rate)
		all_met = all_met and bool(summary.target_met)
	var previous := 1.0
	var monotonic := not summaries.is_empty()
	for id in TARGETS:
		if rates.has(id):
			monotonic = monotonic and float(rates[id]) <= previous
			previous = float(rates[id])
	return {"met": all_met and monotonic, "monotonic": monotonic if not summaries.is_empty() else null}


static func _safe_output(output: String) -> bool:
	var absolute := ProjectSettings.globalize_path(output).simplify_path().replace("\\", "/").to_lower()
	for base in ["res://build/b4-qa/", "user://b4-qa/"]:
		var prefix := ProjectSettings.globalize_path(base).simplify_path().replace("\\", "/").to_lower().trim_suffix("/") + "/"
		if absolute.begins_with(prefix) and absolute.ends_with(".json"):
			return true
	return false


static func _write(host, output: String, report: Dictionary) -> void:
	host.check(_safe_output(output), "测量输出越出测试目录：" + output)
	if not _safe_output(output):
		return
	var absolute := ProjectSettings.globalize_path(output)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	host.check(error == OK, "无法建立测量输出目录：" + str(error))
	if error != OK:
		return
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	host.check(file != null, "无法写测量结果：" + output)
	if file != null:
		file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
		file.close()


## 短入口只检验事件机器人；不启动整局、导演服务或玩家存档。
static func _event_self_test(host) -> void:
	host.balance_events = []
	host.pac_events = 0
	var completed := 0
	var fixtures := [
		{"id": "oe_fuel_bundles", "energy": 0, "silver": 40, "home": {}, "pick": 1,
			"req": {"silver": 40}, "energy_cost": 0, "after_silver": 0, "after_energy": 0, "after_home": {"firewood": 1}},
		{"id": "oe_salted_jar", "energy": 2, "silver": 0, "home": {"cabbage": 1}, "pick": 1,
			"req": {"cabbage": 1}, "energy_cost": 2, "after_silver": 0, "after_energy": 0, "after_home": {"pickles": 1}},
		{"id": "oe_grain_jar", "energy": 4, "silver": 0, "home": {}, "pick": 0,
			"req": {}, "energy_cost": 4, "after_silver": 0, "after_energy": 0, "after_home": {"millet": 1}},
		{"id": "oe_ash_sieve", "energy": 0, "silver": 0, "home": {}, "pick": 2,
			"req": {}, "energy_cost": 0, "after_silver": 0, "after_energy": 0, "after_home": {}},
	]
	for fixture in fixtures:
		var run := _event_fixture(str(fixture.id))
		run.home = fixture.home.duplicate(true)
		run.silver = int(fixture.silver)
		run.attrs.energy = float(fixture.energy)
		if not handle_event(host, run):
			break
		host.check(str(run.pending_event) == "" and str(fixture.id) in run.seen_events, "事件未真实清理并记已见：" + str(fixture.id))
		host.check(int(run.silver) == int(fixture.after_silver) and float(run.attrs.energy) == float(fixture.after_energy)
			and run.home == fixture.after_home, "真实支付/精力退路结果不符：" + str(fixture.id))
		host.check(host.balance_events.size() == completed + 1 and host.pac_events == completed + 1, "事件未按实际成功次数计数")
		if host.failures > 0:
			break
		var record: Dictionary = host.balance_events.back()
		host.check(record.id == fixture.id and record.day == 3 and record.t == 3000 and record.source == "ordinary"
			and record.choice_index == fixture.pick, "事件策略/身份/时点采集错误：" + str(fixture.id))
		host.check(record.req == fixture.req and float(record.energy_cost) == float(fixture.energy_cost), "事件请求成本与实际成本混淆")
		host.check(int(record.silver_before) == int(fixture.silver) and int(record.silver_after) == int(fixture.after_silver)
			and int(record.silver_delta) == int(fixture.after_silver) - int(fixture.silver), "银钱前后值未真实记录")
		host.check(float(record.energy_before) == float(fixture.energy) and float(record.energy_after) == float(fixture.after_energy)
			and float(record.energy_delta) == float(fixture.after_energy) - float(fixture.energy), "精力前后值未真实记录")
		var expected_items := {}
		var ids: Array = fixture.home.keys()
		for item in fixture.after_home:
			if item not in ids:
				ids.append(item)
		for item in ids:
			var old := int(fixture.home.get(item, 0))
			var now := int(fixture.after_home.get(item, 0))
			expected_items[item] = {"before": old, "after": now, "delta": now - old}
		host.check(record.items == expected_items, "事件物资前后值未真实记录：" + str(fixture.id))
		if host.failures > 0:
			break
		completed += 1
	if host.failures == 0:
		if _event_failure_test(host):
			completed += 1
		else:
			host.check(false, "事件负例没有执行到清理结算")
	host.check(completed == fixtures.size() + 1, "事件定向自测未全部完成")
	print("[B4 event-test] %s completed=%d/%d（断言失败 %d）" % [
		"PASS" if host.failures == 0 else "FAIL", completed, fixtures.size() + 1, host.failures])
	host.balance_finished = true
	host.quit(0 if host.failures == 0 else 1)


static func _event_fixture(id: String) -> Dictionary:
	var run := State.new_run("scholar", State.new_meta(), 4000, "normal")
	run.phase = "post"
	run.pday = 3
	run.t = 3000
	run.pending_event = id
	run.home = {}
	run.silver = 0
	run.attrs.energy = 0.0
	return run


static func _event_failure_test(host) -> bool:
	var events: Dictionary = Data.table("events")
	var fixture_id := "__b4_no_choice"
	host.check(not events.has(fixture_id), "事件负例夹具覆盖了真实事件")
	if host.failures > 0:
		return false
	# 如果旧机器人误选最后项，将授予米2；正常路径必须在 choose 之前立即停下。
	events[fixture_id] = {"title": "B4 negative fixture", "choices": [
		{"text": "cannot afford", "req": {"silver": 50}, "fx": {"items": {"rice": 2}}, "result": "must not happen"}]}
	var empty_id := "__b4_empty_choices"
	host.check(not events.has(empty_id), "空选项夹具覆盖了真实事件")
	if host.failures > 0:
		events.erase(fixture_id)
		return false
	events[empty_id] = {"title": "B4 empty fixture", "choices": []}
	for id in [fixture_id, empty_id, "__b4_missing_event"]:
		var probe := EventFailureHost.new()
		var run := _event_fixture(str(id))
		var before := JSON.stringify(run, "", true, true)
		var resolved := handle_event(probe, run)
		host.check(not resolved and probe.failures == 1 and probe.balance_first_error != "", "无可用/空/缺失事件未立即首失败：" + str(id))
		host.check(JSON.stringify(run, "", true, true) == before and run.home.is_empty(), "失败事件改动状态或授物：" + str(id))
		host.check(probe.pac_events == 0 and probe.balance_events.is_empty(), "失败事件被虚计为成功：" + str(id))
		var first_error: String = probe.balance_first_error
		var second := handle_event(probe, run)
		host.check(not second and probe.failures == 1 and probe.balance_first_error == first_error,
			"首次事件失败之后仍继续处理/覆盖首错：" + str(id))
		if host.failures > 0:
			break
	events.erase(fixture_id)
	events.erase(empty_id)
	return host.failures == 0


## 每例只有一个可达普通容器；这是耗时边界夹具，不改变整局搜寻策略。
static func _travel_self_test(host) -> void:
	var original_events: Array = host.balance_events.duplicate(true)
	var original_pac: int = host.pac_events
	var original_trips: Dictionary = host.bot_trip_counts.duplicate(true)
	var completed := 0
	for search_at in [100, 110]: # 07:40 恰好完成 / 07:50 未完成。
		host.balance_events = []
		host.pac_events = 0
		host.bot_trip_counts = {"3": 1}
		if not _travel_case(host, int(search_at)):
			break
		completed += 1
	# 不还原真实 failures/first_error；只有样本计数需要与其它短入口隔离。
	host.balance_events = original_events
	host.pac_events = original_pac
	host.bot_trip_counts = original_trips
	host.check(completed == 2, "机器人旅行边界自测未全部完成")
	print("[B4 travel-test] %s completed=%d/2（断言失败 %d）" % [
		"PASS" if host.failures == 0 else "FAIL", completed, host.failures])
	host.balance_finished = true
	host.quit(0 if host.failures == 0 else 1)


static func _travel_case(host, search_at: int) -> bool:
	var initial := State.new_run("escort", State.new_meta(), 4000, "normal")
	Pre.start_disaster(initial)
	initial.pday = 3
	initial.t = 2 * Post.DAY + 20
	Neighbor.state(initial).stage = "closed"
	Director.state(initial).enabled = false
	var departed := int(initial.t)
	host.check(Post.act_explore(initial, "rice_ruin") == "" and int(initial.t) == departed + 60
		and initial.busy.is_empty() and initial.pending_event == "", "短夹具未真实走完出发60分钟")
	if host.failures > 0: return false
	# 柜台是米行现有、未被机关锁定的普通点；保留真实危险、负重与搜寻奖励规则。
	initial.explore.spots = [{"name": "柜台", "done": false}]
	Post.advance(initial, search_at - Post.day_minute(initial))
	host.check(Post.day_minute(initial) == search_at and initial.pending_event == "" and initial.busy.is_empty(),
		"短夹具没有到达指定翻找起点")
	if host.failures > 0: return false
	var expected: Dictionary = initial.duplicate(true)
	var actual: Dictionary = initial.duplicate(true)
	var shadow := EventFailureHost.new()
	var xp_before := int(expected.prof.search)
	var energy_before := float(expected.attrs.energy)
	var result := Post.search(expected, 0)
	host.check(int(expected.t) == 2 * Post.DAY + Post.EVENT_AT and expected.pending_event != "",
		"普通翻找未在08:00真实遇事：" + str(search_at))
	if search_at == 100:
		host.check(not result.has("blocked") and expected.explore.spots[0].done and not result.get("found", {}).is_empty()
			and int(expected.prof.search) == xp_before + 2, "恰好完成未结算真实物资/经验")
		host.check(absf(float(expected.attrs.energy) - (energy_before - float(Post.RATE.energy) / 3.0 - 4.0)) < 0.00001,
			"恰好完成翻找没有恰好支付一次固定精力与20分钟流逝")
		if not result.get("found", {}).is_empty():
			var item := str(result.found.keys()[0])
			host.check(Explore.take(expected, 0, item, 1) == 0 and expected.explore.bag.is_empty(), "未回答事件便能取走恰好完成的物资")
	else:
		host.check(result.has("blocked") and not expected.explore.spots[0].done and not expected.explore.spots[0].has("loot")
			and int(expected.prof.search) == xp_before, "未满20分钟已授物、完成或经验")
		host.check(absf(float(expected.attrs.energy) - (energy_before - float(Post.RATE.energy) / 6.0)) < 0.00001,
			"未完成翻找仍扣了固定精力，或未支付实际10分钟流逝")
	if host.failures > 0: return false
	host.check(handle_event(shadow, expected) and shadow.failures == 0 and shadow.pac_events == 1,
		"手动对照不能真实回答晨间事件")
	if host.failures > 0: return false
	if search_at == 110:
		var retry_started := int(expected.t)
		var retry_energy := float(expected.attrs.energy)
		result = Post.search(expected, 0)
		host.check(not result.has("blocked") and int(expected.t) == retry_started + 20
			and expected.explore.spots[0].done and not result.get("found", {}).is_empty(), "事件后同点重试未真实耗满20分钟并获得物资")
		host.check(absf(float(expected.attrs.energy) - (retry_energy - float(Post.RATE.energy) / 3.0 - 4.0)) < 0.00001,
			"重试完成翻找没有恰好支付一次固定精力与20分钟流逝")
	if host.failures > 0: return false
	for item in result.get("found", {}):
		var amount := int(result.found[item])
		host.check(Explore.take(expected, 0, str(item), amount) == amount, "手动对照未完整选择可携带物资")
	var carried: Dictionary = expected.explore.bag.duplicate(true)
	host.check(not carried.is_empty() and Inv.weight(carried) <= Explore.carry(expected), "短夹具没有真正携带现场所得")
	var home_before: Dictionary = expected.home.duplicate(true)
	var return_started := int(expected.t)
	var summary := Post.finish_explore(expected)
	var home_after := home_before.duplicate(true)
	Inv.add_all(home_after, carried)
	host.check(summary.get("bag", {}) == carried and expected.home == home_after and expected.explore.is_empty()
		and expected.busy.is_empty() and not expected.get("neighbor_travel", false) and int(expected.t) == return_started + 60,
		"手动返程未真实60分钟或物资未恰好归仓一次")
	var after_return := JSON.stringify(expected, "", true, true)
	host.check(Post.finish_explore(expected).is_empty() and JSON.stringify(expected, "", true, true) == after_return,
		"重复返程再次入库或耗时")
	if host.failures > 0: return false
	host.do_explore(actual)
	host.check(actual.pending_event == "" and actual.explore.is_empty() and actual.busy.is_empty()
		and int(actual.t) == 2 * Post.DAY + (180 if search_at == 100 else 200), "机器人提前返家或没有完成重试/返程")
	host.check(host.pac_events == 1 and host.balance_events.size() == 1 and host.bot_trip_counts == {"3": 1}
		and actual.today.actions.count("explore") == 1 and int(actual.points.rice_ruin.visits) == 1,
		"机器人重复计事件、重启外出或改变已记录趟数")
	host.check(JSON.stringify(host.balance_events, "", true, true) == JSON.stringify(shadow.balance_events, "", true, true),
		"机器人事件选择/成本与手动首可用策略不同")
	# 从同一份现场克隆，无新增会话nonce；整份状态包含银钱、精力、RNG、经验与库存。
	host.check(JSON.stringify(actual, "", true, true) == JSON.stringify(expected, "", true, true),
		"机器人未匹配手动真实耗时/取物/返程状态：" + str(search_at))
	return host.failures == 0


static func _self_test(host) -> void:
	_configure(host, "agenda")
	var first: Dictionary = host.play("scholar", 4000, "normal")
	if host.failures > 0:
		host.balance_finished = true
		host.quit(1)
		return
	var repeat: Dictionary = host.play("scholar", 4000, "normal")
	host.check(JSON.stringify(first, "", true, true) == JSON.stringify(repeat, "", true, true), "相同配置种子不能复现逐局结果")
	host.check(int(first.chores_completed) > 0 and int(first.chores_attempted) >= int(first.chores_completed), "agenda 机器人未真实完成差事")
	host.check(int(first.silver_start) > int(first.silver_left) and not first.tally.bought.is_empty(), "机器人未受真实开局银两约束采购")
	for n in first.explorations_by_day.values():
		host.check(int(n) <= 2, "两趟机器人一天外出超过2次")
	_configure(host, "legacy")
	var legacy: Dictionary = host.play("scholar", 4000, "normal")
	host.check(int(legacy.chores_attempted) == 0 and int(legacy.chores_completed) == 0, "legacy 意外执行差事")
	for n in legacy.explorations_by_day.values():
		host.check(int(n) <= 1, "legacy 一天外出超过1次")
	_configure(host, "trips")
	var trips: Dictionary = host.play("scholar", 4000, "normal")
	host.check(int(trips.chores_attempted) == 0 and int(trips.chores_completed) == 0, "trips 意外执行差事")
	var has_second := false
	for n in trips.explorations_by_day.values():
		host.check(int(n) <= 2, "trips 一天外出超过2次")
		has_second = has_second or int(n) == 2
	host.check(has_second, "trips 机器人没有真的跑第二趟")
	var unfinished := {"phase": "post", "terminal": false, "invariant_failures": 0, "chores_completed": 0, "chores_attempted": 0,
		"explorations": 0, "days": 1, "hp": 30, "silver_start": 10, "silver_left": 0}
	var summary := _summary("normal", [unfinished], 1)
	host.check(summary.incomplete == 1 and summary.wins == 0 and summary.deaths == 0 and summary.win_rate == null and summary.target_met == null,
		"未完成局被伪装成死亡/劫满或进入胜率")
	_summary_self_test(host, unfinished)
	print("[B4 self-test] %s：同seed复现、实际差事、真实采购、legacy/trips开关、第二趟、未完成分类、目标边界与倒挂（断言失败 %d）" % [
		"PASS" if host.failures == 0 else "FAIL", host.failures])
	host.balance_finished = true
	host.quit(0 if host.failures == 0 else 1)


static func _summary_self_test(host, template: Dictionary) -> void:
	# 各档24局的区间边界，包含刚好差一局的反例。
	for row in [["mild", 21, false], ["mild", 22, true], ["normal", 14, false], ["normal", 15, true],
		["normal", 18, true], ["normal", 19, false], ["harsh", 8, false], ["harsh", 9, true],
		["harsh", 12, true], ["harsh", 13, false], ["doom", 3, false], ["doom", 4, true], ["doom", 7, true], ["doom", 8, false]]:
		var games := []
		for k in 24:
			var game := template.duplicate(true)
			game.phase = "ending" if k < int(row[1]) else "dead"
			game.terminal = true
			game["cause"] = "测试死因"
			games.append(game)
		var summary := _summary(str(row[0]), games, 24)
		host.check(summary.target_met == bool(row[2]), "目标边界不正确：%s %d/24" % [str(row[0]), int(row[1])])
	var ordered := _targets([
		{"difficulty": "mild", "win_rate": 22.0 / 24, "target_met": true},
		{"difficulty": "normal", "win_rate": 16.0 / 24, "target_met": true},
		{"difficulty": "harsh", "win_rate": 10.0 / 24, "target_met": true},
		{"difficulty": "doom", "win_rate": 6.0 / 24, "target_met": true}])
	host.check(ordered.met and ordered.monotonic, "目标均达标且无倒挂未被识别")
	var inverted := _targets([{"difficulty": "mild", "win_rate": 0.5, "target_met": false},
		{"difficulty": "normal", "win_rate": 0.75, "target_met": true}])
	host.check(not inverted.met and not inverted.monotonic, "难度胜率倒挂未被识别")
	var incomplete := _targets([_summary("normal", [template], 1)])
	host.check(not incomplete.met and incomplete.monotonic == null, "未完成汇总发布了目标/单调通过结论")

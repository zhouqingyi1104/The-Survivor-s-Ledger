extends RefCounted
## B4：可复算、只跑指定样本的整局测量。所有难度覆盖只存在于当前进程。

const Data = preload("res://scripts/core/data.gd")
const State = preload("res://scripts/core/state.gd")
const ROLES := ["scholar", "escort", "herbalist", "watchman"]
const ARMS := ["legacy", "trips", "agenda"]
const PARAM_KEYS := ["silver_mul", "hp_mul", "food_mul", "water_mul", "cold_add", "wave_mul"]
## 路线图样本建议区间；采集有效不代表这些平衡目标已通过。
const TARGETS := {"mild": [0.90, 1.0], "normal": [0.60, 0.75], "harsh": [0.35, 0.50], "doom": [0.15, 0.30]}


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
	if not "--balance-only" in args and not "--balance-self-test" in args:
		return false
	host.balance_active = true
	host.policy = "hold"
	if "--balance-self-test" in args:
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
		"schema": 1, "arm": arm, "samples_per_difficulty": int(samples_text), "seed_start": int(seed_text),
		"roles": ROLES, "role_assignment": "roles[sample_index % 4]", "seed_assignment": "seed_start + sample_index",
		"difficulty_filter": difficulty, "difficulties": diffs, "user_args": Array(args),
		"engine": Engine.get_version_info(), "project": ProjectSettings.get_setting("application/config/name"),
		"original_difficulty_table": original, "effective_difficulty_table": Data.table("difficulty").duplicate(true),
		"effective_params": {}, "overrides_path": overrides_path, "overrides": overrides,
		"strategy": {"policy": "hold", "max_daily_trips": host.bot_max_trips, "chores": host.bot_chores,
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
		print("[B4] %s %s 劫满 %d/%d 身死 %d 未完成 %d 差事 %d 外出 %d 银两开局/采购后均 %.0f/%.0f" % [
			str(id), arm, summary.wins, summary.completed, summary.deaths, summary.incomplete,
			summary.chores_completed, summary.explorations, summary.mean_silver_start, summary.mean_silver_after_shopping])
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
		"explorations": 0, "mean_days": 0.0, "mean_hp": 0.0, "mean_silver_start": 0.0, "mean_silver_after_shopping": 0.0, "deaths_by_cause": {}}
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

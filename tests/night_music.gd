extends Node
## C4：守夜配乐资源、实际播放器及受控战斗/切页；Dummy 音频输出不代表真人听感。

const State = preload("res://scripts/core/state.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Post = preload("res://scripts/core/post.gd")
const Defense = preload("res://scripts/core/defense.gd")
const Director = preload("res://scripts/core/director.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")

var main: Control
var checks := 0
var failures := 0
var finished := 0


func _ready() -> void:
	get_tree().create_timer(150).timeout.connect(func():
		push_error("night_music 超时")
		get_tree().quit(1))
	Game.no_save = true
	Game.speed = 0
	StoryDirector.set_process(false)
	Game.meta = State.new_meta()
	Game.meta.seen_manual = true
	Game.run = {}
	Game.go("title")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(8)
	var only := ""
	var first := ""
	var start := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
		elif arg.begins_with("--from="):
			first = arg.trim_prefix("--from=")
			start = false
	var selected := 0
	for test in [test_resource, test_refresh, test_fast_switches, test_volume, test_day_night, test_first_round, test_second_round, test_third_round, test_live_fight, test_leave]:
		if str(test.get_method()) == first: start = true
		if not start: continue
		if only != "" and str(test.get_method()) != only: continue
		selected += 1
		await test.call()
		if failures > 0: break
	if failures == 0:
		check(selected > 0 and finished == selected, "测试中途退出：只完成 %d/%d" % [finished, selected])
	main.queue_free()
	await frames(4)
	print("[night_music] %d 项检查，完成 %d/%d，失败 %d 处" % [checks, finished, selected, failures])
	get_tree().quit(0 if failures == 0 else 1)


func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok


func frames(count := 6) -> void:
	for k in count:
		await get_tree().process_frame


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func close_modals() -> void:
	for key in main._modals.keys():
		main.close_modal(key)
	await frames(2)


func fixture(night := false) -> void:
	await close_modals()
	Game.run = State.new_run("scholar", Game.meta, 9031)
	Pre.start_disaster(Game.run)
	Director.state(Game.run).enabled = false
	# 跳到第四日的音频夹具不重演第二日求药，免得邻人 poll 在边界前拦住时钟。
	Neighbor.state(Game.run).stage = "closed"
	Game.run.pending_event = ""
	Game.run.pday = 4
	Game.run.t = 3 * Post.DAY + (Post.DUSK_AT + 60 if night else 240)
	Game.run.night_policy = "manual"
	Game.snapshots = {}
	Game.refresh()
	await frames(12)


func music_is(track: String, label: String, settled := false) -> bool:
	if not check(Sfx.music_name() == track, label + "：曲名错误（" + Sfx.music_name() + "）"): return false
	var playing := 0
	for player in Sfx._music:
		if player.playing: playing += 1
	if track == "":
		return check(playing == 0, label + "：静音页淡出后仍有配乐播放器播放")
	var current: AudioStreamPlayer = Sfx._music[0]
	if not check(current.playing and current.stream != null, label + "：当前曲名对应的播放器没有实际播放"): return false
	if not check(current.stream.resource_path == Sfx.MUSIC % track, label + "：播放器实际流与曲名不一致"): return false
	if not check(current.bus == "Music" and current.stream.get_length() > 0.0, label + "：流长度无效或绕过 Music 总线"): return false
	if not check(current.stream is AudioStreamOggVorbis and current.stream.loop, label + "：实际配乐未循环"): return false
	if settled:
		if not check(playing == 1, label + "：交叉淡化结束后仍有旧曲播放"): return false
		if not check(absf(current.volume_db - Sfx._music_db) < 0.15, label + "：淡入没有到达请求音量"): return false
	return true


func test_resource() -> void:
	var path: String = Sfx.MUSIC % "night_watch"
	if not check(ResourceLoader.exists(path), "缺少守夜曲资源"): return
	var file := FileAccess.open(path, FileAccess.READ)
	if not check(file != null, "守夜 Ogg 文件不可读"): return
	var header := file.get_buffer(128)
	file.close()
	# Vorbis identification packet：类型 1 + 'vorbis' + 版本 4 字节 + 声道/采样率。
	var packet := -1
	for i in maxi(0, header.size() - 16):
		if header.slice(i, i + 7) == PackedByteArray([1, 118, 111, 114, 98, 105, 115]):
			packet = i
			break
	if not check(packet >= 0, "守夜文件不是可识别的 Vorbis identification packet"): return
	if not check(int(header[packet + 11]) == 2, "守夜曲不是双声道"): return
	var rate := int(header[packet + 12]) | (int(header[packet + 13]) << 8) | (int(header[packet + 14]) << 16) | (int(header[packet + 15]) << 24)
	if not check(rate == 44100, "守夜曲采样率不是 44.1kHz"): return
	Sfx.music("night_watch", -18.0, 0.05)
	await wait(0.15)
	if not music_is("night_watch", "资源解码", true): return
	if not check(absf(Sfx._music[0].stream.get_length() - 56.0) < 0.05, "守夜曲解码时长不为 56 秒"): return
	finished += 1


func test_refresh() -> void:
	await fixture(true)
	await wait(3.2)
	if not music_is("night_watch", "守夜刷新前", true): return
	var current: AudioStreamPlayer = Sfx._music[0]
	var stream: AudioStream = current.stream
	var position := current.get_playback_position()
	var run_before: Dictionary = Game.run.duplicate(true)
	var meta_before: Dictionary = Game.meta.duplicate(true)
	Dialogs.settings(true)
	await frames(4)
	for i in 3:
		Game.refresh()
		await wait(0.12)
	if not check(Sfx._music[0] == current and current.stream == stream, "设置/重复刷新替换了当前播放器或音频流"): return
	if not check(current.get_playback_position() > position + 0.15, "设置/重复刷新把守夜曲从头重播"): return
	if not check(Game.run == run_before and Game.meta == meta_before, "配乐/设置刷新改变了这一局或跨轮回数据"): return
	if not music_is("night_watch", "设置/重复刷新后", true): return
	await close_modals()
	finished += 1


func test_fast_switches() -> void:
	await close_modals()
	Game.go("title")
	await frames(3)
	Sfx.music("night_watch", -18.0, 0.1)
	await wait(0.18)
	if not music_is("night_watch", "快速切曲初始", true): return
	for track in ["dragon_dance", "", "lotus_pond", "night_watch", "", "night_watch"]:
		Sfx.music(track, -18.0, 0.25)
		await wait(0.04)
	await wait(0.4)
	if not music_is("night_watch", "快速切曲/静音再恢复", true): return
	Sfx.music("", 0.0, 0.12)
	await wait(0.2)
	if not music_is("", "快速切曲最终静音", true): return
	Sfx.music("night_watch", -18.0, 0.1)
	await wait(0.18)
	if not music_is("night_watch", "旧淡出完成后再次恢复", true): return
	finished += 1


func test_volume() -> void:
	var meta_before: Dictionary = Game.meta.duplicate(true)
	var expected: Dictionary = meta_before.duplicate(true)
	if not expected.has("settings"): expected.settings = {}
	expected.settings.music = 0.63
	Sfx.music("night_watch", -18.0, 0.05)
	await wait(0.12)
	var other_buses := {}
	for name in ["Sfx", "Ambience"]:
		var idx := AudioServer.get_bus_index(name)
		other_buses[name] = [AudioServer.is_bus_mute(idx), AudioServer.get_bus_volume_db(idx)]
	var music_bus := AudioServer.get_bus_index("Music")
	Sfx.set_volume("music", 0.0)
	if not check(AudioServer.is_bus_mute(music_bus), "配乐滑块 0 没有静音 Music 总线"): return
	if not check(Sfx._music[0].playing, "总线静音意外停止了守夜曲，恢复将从头重播"): return
	Sfx.set_volume("music", 0.63)
	if not check(not AudioServer.is_bus_mute(music_bus) and absf(AudioServer.get_bus_volume_db(music_bus) - linear_to_db(0.63)) < 0.01, "配乐滑块恢复没有还原音量"): return
	for name in other_buses:
		var idx := AudioServer.get_bus_index(name)
		if not check([AudioServer.is_bus_mute(idx), AudioServer.get_bus_volume_db(idx)] == other_buses[name], "配乐音量改变了 " + name + " 总线"): return
	if not check(Game.meta == expected, "配乐设置新增了预期 settings.music 之外的存档字段"): return
	Game.meta = meta_before
	Sfx.apply_volumes()
	finished += 1


func test_day_night() -> void:
	await fixture()
	await wait(3.2)
	if not music_is("lotus_pond", "宅院白天", true): return
	if not check(absf(Sfx._music_db - -13.0) < 0.01, "宅院白天音量改变"): return
	Game.run.t = 3 * Post.DAY + Post.DUSK_AT - 1
	main._screen.advance(1)
	if not check(Post.is_night(Game.run), "入夜夹具未跨过边界：" + JSON.stringify({"t": Game.run.t, "event": Game.run.pending_event, "blocked": Post.blocked(Game.run), "phase": Game.run.phase})): return
	await wait(3.2)
	if not music_is("night_watch", "真实跨过入夜边界", true): return
	# 受控清晨状态；不在音频回归里推进/重跑整夜数值。
	Game.run.pday = 5
	Game.run.t = 4 * Post.DAY
	Game.refresh()
	await wait(3.2)
	if not music_is("lotus_pond", "天亮恢复白天曲", true): return
	finished += 1


func prepare_round(index: int, open_gate := false) -> void:
	await fixture(true)
	var run: Dictionary = Game.run
	for key in ["door", "window", "wall"]:
		run[key] = {"cur": 1000, "max": 1000}
	run.attrs.hp = 100
	Defense.start_night(run, {"day": 4, "count": 48, "mods": []})
	for i in index:
		Defense.next_round(run)
	run.door_open = open_gate
	if open_gate:
		run.night.charm = {"window": 100, "wall": 100}
	run.t = 3 * Post.DAY + Defense.round_minute(index) - 1
	Game.refresh()
	await frames(8)


func show_then_rest(label: String) -> bool:
	var screen: Control = main._screen
	if not check(screen._show != null and Game.hold_screen, label + "：受控夹具没有开始演出"): return false
	if not music_is("dragon_dance", label + "演出中"): return false
	await wait(1.3)
	if not music_is("dragon_dance", label + "演出淡入后", true): return false
	if not check(absf(Sfx._music_db - -7.0) < 0.01, label + "战曲音量改变"): return false
	screen._show.skip()
	await frames(6)
	if not check(screen._show == null and not Game.hold_screen and Game.run.fight.is_empty(), label + "：跳过没有释放演出或夹具意外进入活战"): return false
	await wait(3.2)
	return music_is("night_watch", label + "轮间休整", true)


func test_first_round() -> void:
	await fixture(true)
	Game.run.pday = 2
	Game.run.t = Post.DAY + Post.WAVE_AT
	Game.run.wave_due = true
	Game.refresh()
	await frames(12)
	if not await show_then_rest("首轮"): return
	finished += 1


func test_second_round() -> void:
	await prepare_round(1)
	main._screen.advance(1)
	if not await show_then_rest("第二轮"): return
	finished += 1


func test_third_round() -> void:
	await prepare_round(2)
	main._screen.advance(1)
	if not await show_then_rest("第三轮"): return
	finished += 1


func test_live_fight() -> void:
	await prepare_round(1, true)
	var screen: Control = main._screen
	screen.advance(1)
	if not check(screen._show != null and not Game.run.fight.is_empty(), "开门第二轮没有演出/即时迎敌"): return
	if not music_is("dragon_dance", "开门演出中"): return
	screen._show.skip()
	await frames(6)
	if not check(screen._show == null and not Game.run.fight.is_empty(), "演出结束前即时迎敌意外消失"): return
	await wait(1.3)
	if not music_is("dragon_dance", "演出结束但活战仍在", true): return
	# 让实际 NightFight.step → screen._step_fight → Post.end_fight 完成一次结算。
	for foe in Game.run.fight.foes:
		foe.dead = true
	Game.run.fight.kills = Game.run.fight.total
	screen._step_fight(Game.run, 0.01)
	await frames(6)
	if not check(Game.run.fight.is_empty(), "即时迎敌结算没有清空活战"): return
	await wait(3.2)
	if not music_is("night_watch", "活战结束后的休整", true): return
	finished += 1


func test_leave() -> void:
	await fixture(true)
	await wait(3.2)
	if not music_is("night_watch", "离院前", true): return
	Explore.begin(Game.run, "rice_ruin")
	Game.refresh()
	await frames(12)
	if not check(Game.screen == "explore", "外出夹具没有切到废墟"): return
	await wait(2.7)
	if not music_is("", "外出废墟", true): return
	Game.run.explore = {}
	Game.refresh()
	await frames(12)
	await wait(3.2)
	if not music_is("night_watch", "回院后再身死前", true): return
	Game.run.phase = "dead"
	Game.run.death_cause = "音频回归受控身死夹具"
	Game.refresh()
	await frames(10)
	await wait(2.7)
	if not check(Game.screen == "dead", "身死夹具没有切页"): return
	if not music_is("", "死亡页", true): return
	Game.go("title")
	await frames(8)
	await wait(2.7)
	if not music_is("lotus_pond", "标题页", true): return
	if not check(absf(Sfx._music_db - -4.0) < 0.01, "标题页音量改变"): return
	Game.run.phase = "ending"
	Game.refresh()
	await frames(8)
	await wait(2.7)
	if not check(Game.screen == "ending", "结局夹具没有切页"): return
	if not music_is("lotus_pond", "结局页", true): return
	finished += 1

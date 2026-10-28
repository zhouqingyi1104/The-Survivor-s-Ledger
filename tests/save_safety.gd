extends Node
## 存档安全测试：写盘三步（临时档→备份→替换）、断电半截档、坏档退备份、彻底删除，
## 以及 Game 层真的读档时会不会静默把一局弄丢。
## 运行：godot --headless --path . res://tests/save_safety.tscn
## 所有路径都是 user:// 下按进程号临时建的，跑完删掉，不碰玩家真存档和根目录 Memory.md。

const SaveFile = preload("res://scripts/core/save_file.gd")
const State = preload("res://scripts/core/state.gd")
const Migrate = preload("res://scripts/core/migrate.gd")

var checks := 0
var failures := 0
var base := ""


func _ready() -> void:
	base = "user://test_save_safety_%d" % OS.get_process_id()
	_section_core()
	_section_game()
	_cleanup()
	print("[save_safety] %d 项检查，失败 %d 处" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


# ---------- 一、写盘与读档本身 ----------

func _section_core() -> void:
	var p := _path("basic.json")

	# 1. 全新写入：主档能解析，不凭空造备份，不留临时档
	var r := SaveFile.write(p, {"run": {"pday": 3}, "snapshots": {}})
	check(r.ok, "首次写入失败：%s" % str(r))
	check(FileAccess.file_exists(p), "首次写入没落主档")
	check(not FileAccess.file_exists(p + ".bak"), "首次写入不该造出备份")
	check(not FileAccess.file_exists(p + ".tmp"), "写完后临时档没清掉")
	var got := SaveFile.read(p)
	check(got.source == "main", "正常档没从主档读：%s" % str(got.source))
	check(got.note == "main_ok", "正常档标成了 %s" % str(got.note))
	check(int(got.data.run.pday) == 3, "读回的内容不对：%s" % str(got.data))

	# 2. 第二份写入：备份就是上一版，主档是新版
	r = SaveFile.write(p, {"run": {"pday": 5}, "snapshots": {}})
	check(r.ok, "第二次写入失败：%s" % str(r))
	check(FileAccess.file_exists(p + ".bak"), "第二次写入没留备份")
	var bak = JSON.parse_string(FileAccess.get_file_as_string(p + ".bak"))
	check(typeof(bak) == TYPE_DICTIONARY and int(bak.run.pday) == 3, "备份不是上一版：%s" % (str(bak) if bak != null else "<null>"))
	check(int(SaveFile.read(p).data.run.pday) == 5, "主档没换上新版")

	# 3. 断电模拟：主档只剩半截 JSON，必须退备份而不是整局消失
	_store(p, '{"run": {"pday": 5}, "snap')
	got = SaveFile.read(p)
	check(got.source == "backup", "半截主档没退备份：%s" % str(got.source))
	check(got.note == "main_bad", "半截主档没标 main_bad：%s" % str(got.note))
	check(int(got.data.run.pday) == 3, "退备份后读到的不是上一版：%s" % str(got.data))

	# 4. 空文件、非对象 JSON、空对象都算坏档
	for bad in ["", "[1, 2, 3]", "\"text\"", "{}", "null"]:
		_store(p, bad)
		var one := SaveFile.read(p)
		check(one.source == "backup", "坏档「%s」没退备份：%s" % [bad, str(one.source)])
	check(not SaveFile.status(p).main, "坏档在主档位被当成了好档")
	check(SaveFile.status(p).backup, "备份明明是好的却报坏")

	# 5. 主档坏了也照写：坏主档轮换进 .bak，但下一次写入就把它换成好的，不会越滚越坏
	_store(p, "{")
	r = SaveFile.write(p, {"run": {"pday": 7}, "snapshots": {}})
	check(r.ok, "坏主档之上写入失败：%s" % str(r))
	check(int(SaveFile.read(p).data.run.pday) == 7, "坏主档之上没写成新内容")
	r = SaveFile.write(p, {"run": {"pday": 8}, "snapshots": {}})
	var fixed = SaveFile.read(p + ".bak")
	check(r.ok and fixed.source == "main" and int(fixed.data.run.pday) == 7,
		"坏备份没有被下一次写入换掉：%s" % str(fixed.data))

	# 6. 两份都坏 / 主档没了只剩备份 / 两份都没有
	var q := _path("both_bad.json")
	_store(q, "{")
	_store(q + ".bak", "}")
	var dead := SaveFile.read(q)
	check(dead.data.is_empty() and dead.source == "" and dead.note == "main_bad",
		"两份都坏时的交代不对：%s / %s" % [str(dead.source), str(dead.note)])
	# 主档没了、备份是好的：读备份，并说明主档丢了
	_store(q + ".bak", "{\"run\": {\"pday\": 2}}")
	_rm(q)
	var orphan := SaveFile.read(q)
	check(orphan.source == "backup" and orphan.note == "main_missing",
		"只剩备份时没读备份：%s / %s" % [str(orphan.source), str(orphan.note)])
	_rm(q + ".bak")
	var none := SaveFile.read(q)
	check(none.data.is_empty() and none.note == "none", "什么都没存时的交代不对：%s" % str(none.note))

	# 7. 写到不存在的目录：报 write 失败，且不留下半份备份
	var nowhere := _path("no_such_dir/x.json")
	var bad_write := SaveFile.write(nowhere, {"run": {}})
	check(not bad_write.ok, "写不进去却报成功了")
	check(bad_write.step == "write", "失败步骤标成了 %s" % str(bad_write.step))
	check(not FileAccess.file_exists(nowhere + ".bak"), "写失败还留下了备份")

	# 8. forget：主档、备份、临时档一起没
	_rm_files(q)
	SaveFile.write(q, {"run": {"pday": 1}})
	SaveFile.write(q, {"run": {"pday": 2}})
	_store(q + ".tmp", "{}")
	check(FileAccess.file_exists(q) and FileAccess.file_exists(q + ".bak"), "造场景失败")
	SaveFile.forget(q)
	check(not FileAccess.file_exists(q), "forget 没删主档")
	check(not FileAccess.file_exists(q + ".bak"), "forget 没删备份——旧局会从备份里活过来")
	check(not FileAccess.file_exists(q + ".tmp"), "forget 没删临时档")

	# 9. 真实体量往返：一局玩到第 20 日、带 20 页生死簿快照
	var real := _path("real.json")
	var big := {"run": {"pday": 20, "version": Migrate.VERSION, "inv": {}}, "snapshots": {}}
	for day in range(1, 21):
		big.snapshots[str(day)] = {"pday": day, "version": Migrate.VERSION, "plots": [], "inv": {"rice": day}}
	var t0 := Time.get_ticks_usec()
	r = SaveFile.write(real, big)
	var spent := (Time.get_ticks_usec() - t0) / 1000.0
	check(r.ok, "大体量写入失败：%s" % str(r))
	var back := SaveFile.read(real)
	check(back.source == "main", "大体量没读回主档")
	check((back.data.snapshots as Dictionary).size() == 20, "快照页数不对：%d" % (back.data.snapshots as Dictionary).size())
	check(Migrate.save(back.data).run.pday == 20, "读回后过一遍迁移就坏了")
	print("[save_safety] 第20日存档 %d 字节，一次写入 %.1f ms（含回读校验）" % [
		FileAccess.get_file_as_string(real).length(), spent])


# ---------- 二、Game 层真的读档 ----------

func _section_game() -> void:
	Game.save_path = _path("g_save.json")
	Game.meta_path = _path("g_meta.json")
	Game.no_save = false
	Game.save_notice = ""
	Game.meta = State.new_meta()
	Game.run = {}
	Game.snapshots = {}
	_rm_files(Game.save_path)
	_rm_files(Game.meta_path)

	# 10. 开局落盘，且不再留临时档
	var err := Game.new_game("scholar")
	check(err == "", "开局失败：%s" % err)
	check(FileAccess.file_exists(Game.save_path), "开局后没写主档")
	check(not FileAccess.file_exists(Game.save_path + ".tmp"), "每次存档都留下了临时档")
	check(Game.save_status().main, "刚写完的档自己都不认")

	# 11. 主档写坏：读档走备份，并且明确告诉玩家退了一步
	Game.save_game()
	_store(Game.save_path, "{\"run\": {\"pday\": ")
	Game.run = {}
	var ok := Game.continue_game()
	check(ok, "主档坏时没读到备份")
	check(not Game.run.is_empty(), "退备份读回来的 run 是空的")
	check(Game.save_notice != "", "退了备份却什么都没说")
	check(Game.has_save(), "有备份时标题界面不该把入口藏掉")

	# 12. 两份都坏：不冒充成功，也不把原文件删掉
	_store(Game.save_path, "{")
	_store(Game.save_path + ".bak", "}{")
	Game.run = {}
	ok = Game.continue_game()
	check(not ok, "两份都坏时不该返回成功")
	check(Game.run.is_empty(), "两份都坏却造出了一个 run")
	check(FileAccess.file_exists(Game.save_path), "读不出来却把存档删了")
	check(Game.save_notice != "", "两份都坏却没有交代")
	check(Game.has_save(), "两份都坏时也该让玩家点进去看个究竟")

	# 13. 合上旧卷 / 新开一卷之后，备份不能把旧局救回来
	_rm_files(Game.save_path)
	Game.new_game("scholar")
	Game.save_game()
	check(FileAccess.file_exists(Game.save_path + ".bak"), "造场景失败：这份存档该有备份")
	Game.close_book()
	check(not FileAccess.file_exists(Game.save_path), "合上旧卷后主档还在")
	check(not FileAccess.file_exists(Game.save_path + ".bak"), "合上旧卷后备份还在，旧局会活过来")
	check(not Game.has_save(), "合上旧卷后还挂着「续写此录」")

	# 14. 读不出的底稿改名留底，不直接盖掉
	var bad_meta := _path("bad_meta.json")
	_store(bad_meta, "{not json")
	Game._preserve_broken(bad_meta)
	check(not FileAccess.file_exists(bad_meta), "坏底稿没被挪走")
	check(FileAccess.file_exists(bad_meta + ".bad"), "坏底稿没留底")

	# 15. 界面上的字：有损存档要在标题里说人话
	var label := preload("res://scripts/ui/screens/title_screen.gd").new()
	Game.save_path = _path("label.json")
	_rm_files(Game.save_path)
	var title_run := State.new_run("scholar", Game.meta, 42)
	SaveFile.write(Game.save_path, {"run": title_run, "snapshots": {}})
	title_run.pday = 2
	SaveFile.write(Game.save_path, {"run": title_run, "snapshots": {}})
	check(label._continue_label() == "续写此录", "正常存档的标题文案不对：%s" % label._continue_label())
	_store(Game.save_path, "{")
	check(label._continue_label() == "续写此录 · 从备份", "只剩备份时文案不对：%s" % label._continue_label())
	_store(Game.save_path + ".bak", "}{")
	check(label._continue_label() == "续写此录 · 读不出", "两份都坏时文案不对：%s" % label._continue_label())
	label.free()


# ---------- 小工具 ----------

func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok: return
	failures += 1
	push_error("断言失败：" + msg)


func _path(name: String) -> String:
	return "%s_%s" % [base, name]


func _store(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return
	f.store_string(text)
	f.close()


func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _rm_files(path: String) -> void:
	SaveFile.forget(path)


func _cleanup() -> void:
	var dir := DirAccess.open("user://")
	if dir == null: return
	var tag := base.get_file()
	for f in dir.get_files():
		if f.begins_with(tag):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + f))

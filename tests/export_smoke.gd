extends Node
## 打包冒烟：确认打包后档案与存档不会写到只读的 res://（pck 里面写不进去）。
## 开发环境下也跑得通（那时档案就在项目根），两种环境各自断言自己的那一条。
##
## 开发：godot --headless --path . res://tests/export_smoke.tscn
## 打包：劫余录.exe --headless --main-pack <verify.pck> res://tests/export_smoke.tscn
##
## 只写本次运行的独立探针，不覆盖或删除玩家的 user://Memory.md 与存档。

const State = preload("res://scripts/core/state.gd")
const Data = preload("res://scripts/core/data.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
const MemoryFile = preload("res://scripts/core/life_memory_file.gd")

var checks := 0
var failures := 0


func _ready() -> void:
	# 0. 这次到底跑在什么里面：res:// 能不能写，就是"打包了没有"的事实依据
	var readonly: bool = Game.res_is_readonly()
	print("[export_smoke] 打包特性=%s，res:// 可写=%s，判定只读=%s" % [
		str(OS.has_feature("template")), str(Game.res_writable()), str(readonly)])
	check(not FileAccess.file_exists("res://.write_probe"), "探测文件没清掉")

	# 1. 路径规则本身：只读就落 user://，能写就落项目根
	check(Game.memory_path_for(true) == "user://Memory.md", "只读时档案路径不是 user://")
	check(Game.memory_path_for(false) == "res://Memory.md", "可写时档案路径不是项目根")

	# 2. 实例上的解析结果要和判定对得上
	var resolved: String = Game.resolved_memory_path()
	print("[export_smoke] 档案实际落在：%s" % resolved)
	check(resolved == Game.memory_path_for(readonly), "档案路径与只读判定不一致：%s" % resolved)

	# 3. 数据表与中文资源都在 pck 里（导出的常见漏项）
	Data.ensure()
	check(not Data.table("roles").is_empty(), "身份表没进包")
	check(not Data.table("shops").is_empty(), "铺子表没进包")
	check(not Data.table("items").is_empty(), "物品表没进包")

	# 4. 存档写得进去（user:// 在任何环境都可写）
	var probe_id := "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	# Fixed numeric ID is used only to exercise collision refusal in this test.
	var forced_id := OS.get_environment("LEDGER_EXPORT_SMOKE_PROBE_ID")
	if forced_id.is_valid_int() and forced_id.length() <= 18 and not forced_id.begins_with("-"):
		probe_id = forced_id
	var probe := "user://export_smoke_save_%s.json" % probe_id
	for path in [probe, probe + SaveFile.BAK, probe + SaveFile.TMP]:
		if _probe_exists(path):
			check(false, "探针路径已存在，拒绝覆盖：%s" % path)
			get_tree().quit(1)
			return
	var wrote := SaveFile.write(probe, {"run": {"pday": 2}, "snapshots": {}})
	check(bool(wrote.ok), "打包后存不了档：%s" % str(wrote))
	var back := SaveFile.read(probe)
	check(int(back.data.get("run", {}).get("pday", 0)) == 2, "打包后读回来的存档不对")
	SaveFile.forget(probe)

	# 5. 对同一 user:// 目录内的独立文件测试写入，绝不操作玩家档案。
	var player_memory := "user://Memory.md"
	var had_memory := FileAccess.file_exists(player_memory)
	var memory_hash := FileAccess.get_sha256(player_memory) if had_memory else ""
	var memory_probe := "user://export_smoke_memory_%s.md" % probe_id
	if _probe_exists(memory_probe) or _probe_exists(memory_probe + ".tmp"):
		check(false, "档案探针已存在，拒绝覆盖：%s" % memory_probe)
	else:
		var meta := State.new_meta()
		meta.past_lives = {}
		var err := MemoryFile.sync(meta, memory_probe)
		check(err == OK, "写不进独立档案探针：错误 %d" % err)
		check(FileAccess.file_exists(memory_probe), "独立档案探针没生成")
		if FileAccess.file_exists(memory_probe):
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(memory_probe)) == OK, "清理独立档案探针失败")
		if FileAccess.file_exists(memory_probe + ".tmp"):
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(memory_probe + ".tmp")) == OK, "清理独立档案临时探针失败")
	check(FileAccess.file_exists(player_memory) == had_memory, "玩家档案存在状态发生变化")
	if had_memory:
		check(FileAccess.get_sha256(player_memory) == memory_hash, "玩家档案内容发生变化")

	print("[export_smoke] %d 项检查，失败 %d 处" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok: return
	failures += 1
	push_error("断言失败：" + msg)


func _probe_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))

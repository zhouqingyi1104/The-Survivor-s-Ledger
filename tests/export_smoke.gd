extends Node
## 打包冒烟：确认打包后档案与存档不会写到只读的 res://（pck 里面写不进去）。
## 开发环境下也跑得通（那时档案就在项目根），两种环境各自断言自己的那一条。
##
## 开发：godot --headless --path . res://tests/export_smoke.tscn
## 打包：劫余录.exe --headless --main-pack <verify.pck> res://tests/export_smoke.tscn
##
## 会写文件：导出环境里真的往 user://Memory.md 写一次（那正是要验的那条），跑完删掉。

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
	var probe := "user://export_smoke_save.json"
	SaveFile.forget(probe)
	var wrote := SaveFile.write(probe, {"run": {"pday": 2}, "snapshots": {}})
	check(bool(wrote.ok), "打包后存不了档：%s" % str(wrote))
	var back := SaveFile.read(probe)
	check(int(back.data.get("run", {}).get("pday", 0)) == 2, "打包后读回来的存档不对")
	SaveFile.forget(probe)

	# 5. 前世档案真的写得进去（打包环境里这是 res:// 会炸的那一条）
	if readonly:
		var meta := State.new_meta()
		meta.past_lives = {}          # 空账本也要能落一份
		var err := MemoryFile.sync(meta, resolved)
		check(err == OK, "打包后写不进前世档案：错误 %d" % err)
		check(FileAccess.file_exists("user://Memory.md"), "打包后 user://Memory.md 没生成")
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://Memory.md"))
	else:
		print("[export_smoke] 开发环境跳过真实的档案写入（不碰项目根的 Memory.md）")

	print("[export_smoke] %d 项检查，失败 %d 处" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok: return
	failures += 1
	push_error("断言失败：" + msg)

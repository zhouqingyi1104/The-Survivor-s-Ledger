extends Node3D
const Decoration = preload("res://scripts/core/home_decoration.gd")
const Visual = preload("res://scripts/world/home_decoration.gd")
const State = preload("res://scripts/core/state.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
const SaveFile = preload("res://scripts/core/save_file.gd")
var failures := 0
var count := 0

func check(label: String, condition: bool) -> void:
	count += 1
	if not condition:
		failures += 1
		print("FAIL ", label)

func _ready() -> void:
	Game.no_save = true
	var run := State.new_run("scholar", State.new_meta(), 42)
	run.phase = "post"
	run.home = {"wood": 50, "nails": 10}
	var root := Node3D.new()
	add_child(root)
	Visual.sync(root, run)
	check("old save defaults", not run.has("decoration") and root.get_child_count() == 0)
	var before := run.duplicate(true)
	check("unknown rejected", Decoration.apply(run, "floor", "bogus") != "" and run == before)
	check("same rejected", Decoration.apply(run, "floor", "original") != "" and run == before)
	var fighting := run.duplicate(true)
	fighting.fight = {"foes": []}
	var fight_before := fighting.duplicate(true)
	check("fight blocked", Decoration.apply(fighting, "wall", "warm") == "战斗中不能装修。" and fighting == fight_before)
	fighting.fight = {}
	check("fight ended permits", Decoration.apply(fighting, "wall", "warm") == "" and int(fighting.home.wood) == int(fight_before.home.wood) - 2)
	var poor := run.duplicate(true)
	poor.home = {"wood": 0, "nails": 0}
	var poor_before := poor.duplicate(true)
	check("insufficient atomic", Decoration.apply(poor, "lamps", "red") != "" and poor == poor_before)
	for pair in [["wall", "warm"], ["floor", "brick"], ["lamps", "red"], ["plants", "plum"]]:
		var wood := int(run.home.wood)
		var nails := int(run.home.nails)
		var cost: Dictionary = Decoration.OPTIONS[pair[0]].choices[pair[1]].cost
		check("apply " + pair[0], Decoration.apply(run, pair[0], pair[1]) == "")
		check("cost " + pair[0], int(run.home.wood) == wood - int(cost.get("wood", 0)) and int(run.home.nails) == nails - int(cost.get("nails", 0)))
		Visual.sync(root, run)
		check("visual " + pair[0], root.get_child_count() > 0)
	var children := root.get_child_count()
	Visual.sync(root, run)
	check("repeat sync", root.get_child_count() == children)
	check("no collision", not _has_physics(root))
	var save_path := "user://c3-decoration-%d.json" % OS.get_process_id()
	var saved := SaveFile.write(save_path, {"run": run})
	var loaded := SaveFile.read(save_path)
	check("save file", bool(saved.ok) and loaded.source == "main")
	var roundtrip: Dictionary = loaded.data.get("run", {})
	SaveFile.forget(save_path)
	check("save JSON", Decoration.selected(roundtrip, "plants") == "plum" and Decoration.selected(roundtrip, "wall") == "warm")
	var snapshots := {}
	run.pday = 1
	run.rebirths_left = 1
	Ledger.snapshot(run, snapshots)
	check("switch", Decoration.apply(run, "wall", "blue") == "")
	run.pday = 2
	var rewound := Ledger.rewind(run, snapshots, State.new_meta())
	check("rewind", Decoration.selected(rewound, "wall") == "warm")
	check("new game isolated", Decoration.selected(State.new_run("scholar", State.new_meta(), 43), "wall") == "original")
	var wood_before := int(run.home.wood)
	check("restore free", Decoration.apply(run, "wall", "original") == "" and int(run.home.wood) == wood_before)
	check("UI module loads", load("res://scripts/ui/home_decoration.gd") != null)
	print("DECORATION ", count - failures, "/", count, " FAIL ", failures)
	get_tree().quit(1 if failures else 0)

func _has_physics(node: Node) -> bool:
	if node is CollisionObject3D or node is NavigationRegion3D:
		return true
	for child in node.get_children():
		if _has_physics(child): return true
	return false

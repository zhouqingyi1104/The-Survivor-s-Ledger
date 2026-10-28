extends Node3D
const World = preload("res://scripts/world/home_world.gd")
const State = preload("res://scripts/core/state.gd")
const Decor = preload("res://scripts/world/home_decoration.gd")

func _ready() -> void:
	Game.no_save = true
	get_window().size = Vector2i(1280, 720)
	var w = World.new()
	add_child(w)
	await get_tree().process_frame
	var run := State.new_run("scholar", State.new_meta(), 42)
	run.phase = "post"
	w.sync(run)
	var visual := Node3D.new()
	w.add_child(visual)
	var camera := Camera3D.new()
	w.add_child(camera)
	camera.position = Vector3(14, 19, 20)
	camera.look_at(Vector3(0, 0, 0), Vector3.UP)
	camera.fov = 42
	camera.current = true
	var out := OS.get_environment("C3_SHOTS")
	DirAccess.make_dir_recursive_absolute(out)
	for preset in ["noon", "night"]:
		w.set_preset(preset)
		for item in [["original", "", ""], ["wall", "wall", "warm"], ["floor", "floor", "brick"], ["lamps", "lamps", "gold"], ["plants", "plants", "plum"]]:
			run.decoration = {}
			if item[1] != "": run.decoration[item[1]] = item[2]
			Decor.sync(visual, run)
			for i in range(16): await get_tree().process_frame
			var path := out.path_join("%s-%s.png" % [preset, item[0]])
			var error := get_viewport().get_texture().get_image().save_png(path)
			if error != OK:
				print("FAIL screenshot ", path, " ", error)
				get_tree().quit(1)
				return
			print("SAVED ", path)
	get_tree().quit()

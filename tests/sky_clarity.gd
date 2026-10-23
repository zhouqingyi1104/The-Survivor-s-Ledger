extends Node3D
## Render the same courtyard and camera with old and current fog, without saves.
const HomeWorld = preload("res://scripts/world/home_world.gd")
const SkyKit = preload("res://scripts/world/sky.gd")

func _ready() -> void:
	Game.no_save = true
	var out := OS.get_environment("TEMP").path_join("unknownGame-clarity")
	DirAccess.make_dir_recursive_absolute(out)
	var world = HomeWorld.new()
	add_child(world)
	var camera := Camera3D.new()
	camera.fov = 42.0
	add_child(camera)
	camera.position = Vector3(0, 25, 18)
	camera.look_at(Vector3(0, 1, 0))
	var hero = HomeWorld.Figure.new()
	hero.hero = true
	world.add_child(hero)
	hero.setup("scholar")
	var density_scale: float = world.sky.fog_mul
	for preset in ["dawn", "noon", "night"]:
		for version in ["before", "after"]:
			world.sky.fog_mul = 1.0 if version == "before" else density_scale
			world.set_preset(preset, 400)
			for frame in 12:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path := out.path_join("%s-%s.png" % [preset, version])
			get_viewport().get_texture().get_image().save_png(path)
			print(path, " fog=", world.sky.env.fog_density)
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit()

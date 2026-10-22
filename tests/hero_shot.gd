extends Node3D
## 开发用：把主角（仙气女身）摆出来，从几个角度各拍一张，检查飘带、灵光、发髻的位置和比例。
## 左边药铺学徒（本来就女身），右边落第书生（原本男身，看换过来之后冠帽还正不正）。
## 运行：godot --path . res://tests/hero_shot.tscn -- --out=<目录>

const Figure = preload("res://scripts/world/character.gd")
const K = preload("res://scripts/world/kit.gd")

## [体型, 身份]
const ROLES := [["moon", "herbalist"], ["maid", "scholar"]]

## [名字, 机位, 看向, 是不是走动]
const VIEWS := [
	["idle_front", Vector3(0, 1.55, 4.2), Vector3(0, 1.05, 0), false],
	["idle_back", Vector3(0, 1.75, -3.6), Vector3(0, 1.05, 0), false],
	["walk_side", Vector3(3.4, 1.7, 0.4), Vector3(0, 1.05, 0), true],
	["face", Vector3(1.05, 1.5, 1.5), Vector3(1.2, 1.42, 0), false],
]


func _ready() -> void:
	var out := "user://hero_shots"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")

	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, -140, 0)
	fill.light_energy = 0.55
	add_child(fill)

	K.box(self, Vector3(40, 0.2, 40), K.mat(Color("#cfc9bb"), 0.95), Vector3(0, -0.1, 0))

	var figs := []
	for i in ROLES.size():
		var f := Figure.new()
		add_child(f)
		f.hero = true
		f.force_body = ROLES[i][0]
		f.setup(ROLES[i][1])
		f.position = Vector3(-1.3 + i * 2.6, 0, 0)
		figs.append(f)

	var cam := Camera3D.new()
	cam.fov = 42.0
	add_child(cam)
	cam.current = true

	DirAccess.make_dir_recursive_absolute(out)
	for v in VIEWS:
		for f in figs:
			f.moving = bool(v[3])
			f.move_speed = 3.2 if v[3] else 0.0
		cam.global_position = v[1]
		cam.look_at(v[2], Vector3.UP)
		for k in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(out.path_join("%s.png" % v[0]))
		print("saved ", v[0])
	get_tree().quit()

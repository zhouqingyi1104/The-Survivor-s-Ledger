extends Node3D
## 开发用：把临川城摆出来，镜头挨个对着铺子拍一张，检查模型朝向和比例。
## 运行：godot --path . res://tests/city_shots.tscn -- --out=<目录>

const CityWorld = preload("res://scripts/world/city_world.gd")

const VIEWS := [
	["grocery", Vector3(-19, 5, 12), Vector3(-19, 2, -5)],
	["pawnshop", Vector3(-39, 5, 12), Vector3(-39, 2, -5)],
	["market", Vector3(9, 5, 12), Vector3(9, 2, -5)],
	["bookshop", Vector3(29, 5, 12), Vector3(29, 2, -5)],
	["builder", Vector3(44, 5, 12), Vector3(44, 2, -5)],
	["temple", Vector3(0, 9, 4), Vector3(0, 4, -20)],
	["gazebo", Vector3(-8.5, 6, 22), Vector3(-8.5, 1, 11)],
	["wide", Vector3(0, 30, 34), Vector3(0, 0, -4)],
]


func _ready() -> void:
	var out := "user://city_shots"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var city: Node3D = CityWorld.new()
	add_child(city)
	city.setup_walker("scholar")
	var run := {"loc": "rice_shop", "hour": 9, "day": 1}
	for id in CityWorld.PLACES:
		city._labels[id].text = id
	city._place_walker("rice_shop")
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 300.0
	add_child(cam)
	cam.current = true
	var t := clampf((9 - 3) / 6.0, 0.0, 1.0)
	CityWorld.SkyKit.blend(city.sky, "dawn", "noon", t * 2.0, 220)
	DirAccess.make_dir_recursive_absolute(out)
	for v in VIEWS:
		cam.global_position = v[1]
		cam.look_at(v[2], Vector3.UP)
		for k in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(out.path_join("%s.png" % v[0]))
		print("saved ", v[0])
	get_tree().quit()

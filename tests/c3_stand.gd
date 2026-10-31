extends Node3D
## C3: candidate facing and approach must be usable, not merely the footprint.
const World = preload("res://scripts/world/home_world.gd")
const Home = preload("res://scripts/core/home.gd")
const State = preload("res://scripts/core/state.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	Game.no_save = true
	var run := State.new_run("scholar", State.new_meta(), 123)
	Home.ensure_layout(run)
	var world := World.new()
	add_child(world)
	await get_tree().process_frame
	world.sync(run)
	for i in 180:
		await get_tree().physics_frame
		if not NavigationServer3D.map_get_path(world.get_world_3d().navigation_map, World.SPAWN, World.SPOTS.well.stand, true).is_empty():
			break
	var map := world.get_world_3d().navigation_map
	print("[C3_NAV_READY] ", NavigationServer3D.map_get_iteration_id(map), " regions=", NavigationServer3D.map_get_regions(map).size(), " polys=", world.nav_region.navigation_mesh.get_polygon_count(), " well_path=", NavigationServer3D.map_get_path(map, World.SPAWN, World.SPOTS.well.stand, true))
	var bench := Home.core(run, "bench")
	var uid := int(bench.uid)
	var conflict := world.move_spot_block(run, uid, 5.25, -5.5, 270)
	check(conflict == "家具正面离其他工作台太近。", "bench beside desk allowed overlapping work positions: " + conflict)
	for rot in [0, 90, 180, 270]:
		var valid := false
		var blocked_front := false
		var reasons := {}
		for xi in range(-38, 39):
			for zi in range(-30, 25):
				var x := float(xi) * 0.25
				var z := float(zi) * 0.25
				if Home.spot_block(run, "bench", x, z, rot, uid) != "":
					continue
				var reason := world.move_spot_block(run, uid, x, z, rot)
				reasons[reason] = int(reasons.get(reason, 0)) + 1
				if reason == "": valid = true
				if not blocked_front and reason in ["家具正面没有站人的地方。", "家具正面被挡住了。", "走不到家具正面。"]:
					blocked_front = true
					print("[C3_FRONT] rot=", rot, " pos=", Vector2(x, z), " reason=", reason)
				if valid and blocked_front: break
			if valid and blocked_front: break
		print("[C3_REASONS] ", rot, " ", reasons)
		check(valid, "no usable bench placement at rotation " + str(rot))
		check(blocked_front, "no facing obstacle rejected at rotation " + str(rot))
	print("[C3_STAND] ", checks - failures, "/", checks, " failed=", failures)
	get_tree().quit(1 if failures else 0)

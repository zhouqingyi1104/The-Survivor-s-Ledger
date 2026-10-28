extends Node3D
const World = preload("res://scripts/world/home_world.gd")
const Home = preload("res://scripts/core/home.gd")
const State = preload("res://scripts/core/state.gd")
const Floors = preload("res://scripts/core/home_floor.gd")
const Player = preload("res://scripts/world/player.gd")
var checks := 0
var failed := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error(message)
func _ready() -> void:
	Game.no_save = true
	var run := State.new_run("scholar", State.new_meta(), 123)
	Home.ensure_layout(run)
	run.facilities.append("cellar")
	run.home.wood = 100
	run.home.nails = 100
	run.attic = {"stage": "complete"}
	var world := World.new()
	add_child(world)
	await get_tree().process_frame
	world.sync(run)
	for i in 4: await get_tree().physics_frame
	for floor_id in ["cellar", "attic"]:
		run.home_floor = floor_id
		world.set_floor(floor_id)
		world.sync(run)
		var origin: Vector3 = world.floor_origin()
		check(world._inside_pick_bounds(origin), floor_id + ": room center not clickable")
		check(not world._inside_pick_bounds(Vector3.ZERO), floor_id + ": courtyard still clickable")
		check(world.nearest_spot(world.floor_spawn(floor_id)) == "floor_exit", floor_id + ": return not nearest")
		var map := world.get_world_3d().navigation_map
		var start: Vector3 = world.floor_spawn(floor_id)
		var end: Vector3 = world.spot_info("floor_use").stand
		world.prepare_navigation()
		var path := NavigationServer3D.map_get_path(map, start, end, true)
		check(not path.is_empty() and path[-1].distance_to(end) < 0.8, floor_id + ": no path to use: " + str(path))
		var hero := Player.new()
		world.add_child(hero)
		hero.setup("scholar")
		hero.position = start
		world.prepare_navigation()
		hero.walk_to(end)
		check(hero._path.size() > 1 and (hero._path[0] as Vector3).distance_to(start) < 1.0, floor_id + ": player path did not start in room")
		await get_tree().create_timer(0.3).timeout
		check(hero.position.distance_to(start) > 0.1, floor_id + ": player did not begin walking")
		hero.queue_free()
		await get_tree().physics_frame
		check(world.build_spot_block(run, "rice_jar", origin.x, 0.0, 0) != "", floor_id + ": corridor can be blocked")
		var pt := origin + Vector3(2, 0, 0)
		var placement_reason := world.build_spot_block(run, "rice_jar", pt.x, pt.z, 0)
		check(placement_reason == "", floor_id + ": clear placement rejected: " + placement_reason)
		var f := Home.add(run, "rice_jar", 2, 0, 0)
		world.sync(run)
		for i in 3: await get_tree().physics_frame
		var mesh: Node3D = world.spot_nodes.get("f_%d" % int(f.uid))
		check(mesh != null and mesh.global_position.distance_to(pt) < 0.01, floor_id + ": furniture not drawn in room")
		var cam := Camera3D.new()
		world.add_child(cam)
		cam.position = pt + Vector3(0, 10, 0)
		cam.look_at(pt, Vector3.FORWARD)
		cam.current = true
		await get_tree().process_frame
		var hit := world.pick(cam, cam.unproject_position(pt))
		check(str(hit.get("spot", "")) == "f_%d" % int(f.uid), floor_id + ": furniture not picked")
		var move_hit := world.pick_move_ground(cam, cam.unproject_position(pt), int(f.uid))
		check(move_hit.has("ground"), floor_id + ": cannot move through source")
		cam.queue_free()
		run.home_floor = "courtyard"
		world.set_floor("courtyard")
		check(world.surroundings.visible and world.sky.sun.visible and world.sky.snow.visible, floor_id + ": outside visuals not restored")
		check(not world._floor_rooms[floor_id].root.visible, floor_id + ": room visible after return")
	run.home_floor = "courtyard"
	world.set_floor("courtyard")
	for i in 3: await get_tree().physics_frame
	check(world._inside_pick_bounds(Vector3.ZERO), "courtyard pick not restored")
	check(world.surroundings.visible, "surroundings not restored")
	check(world.sky.sun.visible, "daylight not restored")
	check(world.sky.snow.visible, "weather visibility not restored")
	check(not world._floor_rooms.cellar.root.visible and not world._floor_rooms.attic.root.visible, "rooms visible after return")
	check(not world._inside_pick_bounds(Vector3(-40, 0, 0)), "room pick exposed from courtyard")
	print("[C5_WORLD] ", checks - failed, "/", checks, " failed=", failed)
	get_tree().quit(1 if failed else 0)

extends Node3D

const World = preload("res://scripts/world/home_world.gd")
const Home = preload("res://scripts/core/home.gd")
const State = preload("res://scripts/core/state.gd")
const Player = preload("res://scripts/world/player.gd")
var checks := 0
var failed := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error(message)

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _paths(world: Node3D, label: String) -> void:
	var map := world.get_world_3d().navigation_map
	for id in World.SPOTS:
		var target: Vector3 = World.SPOTS[id].stand
		var path := NavigationServer3D.map_get_path(map, World.SPAWN, target, true)
		check(not path.is_empty() and _flat(path[-1], target) < 0.7, label + " no path to " + id)
	for id in Home.CORE_IDS:
		var f := Home.core(world._current_run, id)
		check(not f.is_empty(), label + " missing core " + id)
		if f.is_empty():
			continue
		var target := Home.stand(f)
		var path := NavigationServer3D.map_get_path(map, World.SPAWN, target, true)
		check(not path.is_empty() and _flat(path[-1], target) < 0.7, label + " no path to " + id)

func _go(world: Node3D, player: CharacterBody3D, target: Vector3, label: String) -> void:
	var map := world.get_world_3d().navigation_map
	for i in 120:
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			break
		await get_tree().physics_frame
	var path := NavigationServer3D.map_get_path(map, player.global_position, target, true)
	check(not path.is_empty() and _flat(path[-1], target) < 0.7, label + " nav path does not reach target")
	player.walk_to(target)
	for i in 600:
		await get_tree().physics_frame
		if not player.is_walking(): break
	check(_flat(player.global_position, target) < 0.7, label + " player did not reach target; pos=" + str(player.global_position))

func _ready() -> void:
	Game.no_save = true
	Game.run = {}
	var run := State.new_run("scholar", State.new_meta(), 123)
	Home.ensure_layout(run)
	var world := World.new()
	add_child(world)
	await get_tree().process_frame
	var moving := Home.add(run, "planter", -4.5, 3.5, 0)
	world.sync(run)
	var player := Player.new()
	world.add_child(player)
	player.setup("scholar")
	player.position = World.SPAWN
	for i in 5: await get_tree().physics_frame
	_paths(world, "before")
	await _go(world, player, World.SPOTS.well.stand, "before")
	player.position = World.SPAWN
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	var target := Vector3.ZERO
	var found := false
	for x in range(-18, 19):
		for z in range(-15, 14):
			var p := Vector3(x * 0.5, 0, z * 0.5)
			if _flat(p, Vector3(float(moving.x), 0, float(moving.z))) > 1.5 and world.move_spot_block(run, int(moving.uid), p.x, p.z, 90) == "":
				target = p
				found = true
				break
		if found: break
	check(found, "no movable spot")
	if found:
		check(Home.move(run, int(moving.uid), target.x, target.z, 90) == "", "move failed")
		world.sync(run)
		for i in 5: await get_tree().physics_frame
		_paths(world, "after")
		await _go(world, player, World.SPOTS.well.stand, "after")
	# Four attempts to line up furniture across the central approach must be rejected.
	for i in 4:
		var chair := Home.add(run, "armchair", -100.0 - i * 2, -100.0, 0)
		check(world.move_spot_block(run, int(chair.uid), -0.75 + i * 0.5, -1.0, 0) != "", "multi furniture blocked central route")
	# Fill three independently permitted positions, rebuilding navigation after each.
	for chair in Home.list(run, "armchair").slice(0, 3):
		var placed := false
		for x in range(-18, 19):
			for z in range(-15, 14):
				var px := x * 0.5
				var pz := z * 0.5
				if world.move_spot_block(run, int(chair.uid), px, pz, 0) == "":
					Home.move(run, int(chair.uid), px, pz, 0)
					placed = true
					break
			if placed: break
		check(placed, "could not place additional chair")
		world.sync(run)
		for i in 4: await get_tree().physics_frame
	_paths(world, "three chairs")
	print("[C2_NAV] ", checks - failed, "/", checks, " failed=", failed)
	get_tree().quit(1 if failed else 0)

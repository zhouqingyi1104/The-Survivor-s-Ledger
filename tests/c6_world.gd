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

func _ready() -> void:
	Game.no_save = true
	var run := State.new_run("scholar", State.new_meta(), 123)
	Home.ensure_layout(run)
	var world := World.new()
	add_child(world)
	await get_tree().process_frame
	world.sync(run)
	for i in 4: await get_tree().physics_frame
	var info: Dictionary = world.SPOTS.neighbor_home
	check(world.spot_nodes.has("neighbor_home"), "missing neighbor interaction")
	check(info.name == "西邻院墙", "identity disclosed before recognition")
	check(world.nearest_spot(info.stand) == "neighbor_home", "neighbor wall not recognized nearby")
	check(world._inside_pick_bounds(info.stand), "neighbor stand outside playable courtyard")
	var map := world.get_world_3d().navigation_map
	var path := PackedVector3Array()
	# Wait up to five seconds for the asynchronously baked courtyard to join the map.
	for i in 300:
		world.prepare_navigation()
		path = NavigationServer3D.map_get_path(map, World.SPAWN, info.stand, true)
		if path.size() > 1 and path[0].distance_to(World.SPAWN) < 0.8 and path[-1].distance_to(info.stand) < 0.8:
			break
		await get_tree().physics_frame
	check(path.size() > 1 and path[0].distance_to(World.SPAWN) < 0.8 and path[-1].distance_to(info.stand) < 0.8, "neighbor stand unreachable: " + str(path))
	var hero := Player.new()
	world.add_child(hero)
	hero.setup("scholar")
	hero.position = World.SPAWN
	hero.walk_to(info.stand)
	check(hero._path.size() > 1, "player received no route to neighbor")
	await get_tree().create_timer(0.3).timeout
	check(hero.position.distance_to(World.SPAWN) > 0.1, "player failed to start walking")
	var cam := Camera3D.new()
	world.add_child(cam)
	var target := Vector3(-9.65, 1.48, 3.6)
	cam.position = target + Vector3(4, 6, 4)
	cam.look_at(target)
	cam.current = true
	await get_tree().physics_frame
	var hit := world.pick(cam, cam.unproject_position(target))
	check(str(hit.get("spot", "")) == "neighbor_home", "neighbor interaction not picked: " + str(hit))
	world.set_floor("cellar")
	check(not world._spot_on_floor("neighbor_home"), "neighbor interaction active inside cellar")
	world.set_floor("courtyard")
	check(world._spot_on_floor("neighbor_home"), "neighbor interaction unavailable after return")
	check(not world._inside_pick_bounds(Vector3(-12, 0, 3)), "background alley unexpectedly opened")
	var old_run: Dictionary = run.duplicate(true)
	world._sync_neighbor_visual(run)
	check(run == old_run, "neighbor visual projection mutated run or RNG")
	check(world.spot_info("neighbor_home").name == "西邻院墙", "unknown neighbor name exposed")
	check(world._neighbor_visual.get_child_count() == 0, "initial neighbor displayed outcome")
	run.neighbor_home = {"knocked": true, "choice": "repair", "wall_repaired": false, "settled": false}
	world._sync_neighbor_visual(run)
	check(world.spot_info("neighbor_home").name == "老周家的院墙", "confirmed identity not displayed")
	check(world._neighbor_visual.get_child_count() == 0, "unfinished repair shown as complete")
	run.neighbor_home.wall_repaired = true
	world._sync_neighbor_visual(run)
	check(world._neighbor_visual.get_child_count() == 6, "completed repair not projected on both sides")
	run.neighbor_home.settled = true
	world._sync_neighbor_visual(run)
	check(world._neighbor_visual.get_child_count() == 8, "settled repair result not projected")
	check((world._neighbor_visual.get_child(7) as Label3D).text == "邻宅 · 修好", "wrong repair result label")
	for choice in ["trade", "refuse", "timeout"]:
		run.neighbor_home = {"knocked": true, "choice": choice, "wall_repaired": false, "settled": false}
		world._sync_neighbor_visual(run)
		check(world._neighbor_visual.get_child_count() == 0, choice + ": outcome shown before settlement")
		run.neighbor_home.settled = true
		world._sync_neighbor_visual(run)
		check(world._neighbor_visual.get_child_count() == 2 and world._neighbor_visual.get_child(1) is Label3D, choice + ": outcome did not appear")
		if choice == "timeout": check((world._neighbor_visual.get_child(1) as Label3D).text == "邻宅 · 未回应", "unanswered request mislabeled")
	world._sync_neighbor_visual(old_run)
	check(world._neighbor_visual.get_child_count() == 0, "rewind failed to restore neighbor visual")
	world.set_floor("guest_zhou")
	world.sync(old_run)
	for i in 4: await get_tree().physics_frame
	check(world._floor == "guest_zhou" and world._floor_rooms.guest_zhou.root.visible, "guest room not shown")
	check(world.spot_nodes.has("guest_talk") and world.spot_nodes.has("floor_exit") and not world.spot_nodes.has("floor_use"), "guest has wrong interaction points")
	check(not world._spot_on_floor("neighbor_home") and world._spot_on_floor("guest_talk"), "guest floor exposed courtyard interactions")
	var guest_origin: Vector3 = world.floor_origin()
	var guest_stand: Vector3 = world.spot_info("guest_talk").stand
	world.prepare_navigation()
	var guest_path := NavigationServer3D.map_get_path(map, world.floor_spawn("guest_zhou"), guest_stand, true)
	check(guest_path.size() > 1 and guest_path[0].distance_to(world.floor_spawn("guest_zhou")) < 0.8 and guest_path[-1].distance_to(guest_stand) < 0.8, "guest conversation unreachable: " + str(guest_path))
	var guest_target := guest_origin + Vector3(0, 1, -2.2)
	cam.position = guest_target + Vector3(3, 6, 4)
	cam.look_at(guest_target)
	await get_tree().physics_frame
	check(str(world.pick(cam, cam.unproject_position(guest_target)).get("spot", "")) == "guest_talk", "guest character not physically pickable")
	hero.stop()
	hero.position = world.floor_spawn("guest_zhou")
	hero.walk_to(guest_stand)
	var guest_deadline := Time.get_ticks_msec() + 12000
	while hero.is_walking() and Time.get_ticks_msec() < guest_deadline:
		await get_tree().physics_frame
	check(Vector2(hero.position.x - guest_stand.x, hero.position.z - guest_stand.z).length() < 0.8, "player failed to walk to guest conversation")
	check(world.build_spot_block(old_run, "rice_jar", guest_origin.x + 2.0, guest_origin.z, 0) != "", "guest could place household furniture")
	check(not world._floor_rooms.guest_zhou.repaired_wall.visible, "guest wall repaired without the work")
	var repaired_run := old_run.duplicate(true)
	repaired_run.neighbor_home = {"knocked": true, "wall_repaired": true}
	world.sync(repaired_run)
	check(world._floor_rooms.guest_zhou.repaired_wall.visible, "guest room missing completed repair")
	world.sync(old_run)
	check(not world._floor_rooms.guest_zhou.repaired_wall.visible, "guest room did not revert with old save")
	world.set_floor("courtyard")
	check(not world._floor_rooms.guest_zhou.root.visible and not world.spot_nodes.has("guest_talk"), "guest room still active after return")
	# A legacy layout may already have furniture where the new default stand is.
	var legacy := old_run.duplicate(true)
	var old_piece := Home.add(legacy, "water_vat", -8.9, 3.6, 0)
	world.sync(legacy)
	for i in 4: await get_tree().physics_frame
	var alternative: Vector3 = world.spot_info("neighbor_home").stand
	check(alternative.distance_to(info.stand) > 0.3, "legacy furniture did not move the standing point")
	check(Vector2(alternative.x + 9.68, alternative.z - 3.6).length() < 3.5, "alternative stand too far from wall")
	world.prepare_navigation()
	path = NavigationServer3D.map_get_path(map, World.SPAWN, alternative, true)
	check(path.size() > 1 and Vector2(path[0].x - World.SPAWN.x, path[0].z - World.SPAWN.z).length() < 0.5 and Vector2(path[-1].x - alternative.x, path[-1].z - alternative.z).length() < 0.25, "no real route to alternative stand: " + str(path))
	check(Home.find(legacy, int(old_piece.uid)).x == -8.9, "legacy furniture moved or removed")
	hero.stop()
	hero.position = World.SPAWN
	hero.walk_to(alternative)
	await get_tree().create_timer(0.3).timeout
	check(hero.position.distance_to(World.SPAWN) > 0.1, "player could not start walking toward alternative stand")
	var arrival_deadline := Time.get_ticks_msec() + 12000
	while hero.is_walking() and Time.get_ticks_msec() < arrival_deadline:
		await get_tree().physics_frame
	check(Vector2(hero.position.x - alternative.x, hero.position.z - alternative.z).length() < 0.8, "player failed to reach alternative stand")
	print("[C6_WORLD] ", checks - failed, "/", checks, " failed=", failed)
	get_tree().quit(1 if failed else 0)

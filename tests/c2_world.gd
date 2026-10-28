extends Node3D

const World = preload("res://scripts/world/home_world.gd")
const Home = preload("res://scripts/core/home.gd")
const State = preload("res://scripts/core/state.gd")
var checks := 0
var failed := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error(message)

func _ready() -> void:
	Game.no_save = true
	Game.run = {}
	var run := State.new_run("scholar", State.new_meta(), 123)
	Home.ensure_layout(run)
	var world := World.new()
	add_child(world)
	await get_tree().process_frame
	var f := Home.add(run, "planter", -4.5, 3.5, 0)
	var uid: int = f.uid
	var plot: Dictionary = run.plots.back()
	plot.crop = "cabbage"
	plot.days = 1.0
	world.sync(run)
	for i in 3:
		await get_tree().physics_frame
	var source: Node3D = world.spot_nodes.get("f_%d" % uid)
	check(source != null and source.get_node_or_null("planter_crop") != null, "planted pot has no crop")
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(-4.5, 10, 3.5)
	camera.look_at(Vector3(-4.5, 0, 3.5), Vector3.FORWARD)
	camera.current = true
	await get_tree().process_frame
	var screen := camera.unproject_position(Vector3(-4.5, 0, 3.5))
	var hit := world.pick(camera, screen)
	check(str(hit.get("spot", "")) == "f_%d" % uid, "ordinary ray did not hit planter")
	var through := world.pick_move_ground(camera, screen, uid)
	check(through.has("ground") and (through.ground as Vector3).distance_to(Vector3(-4.5, 0, 3.5)) < 0.1, "moving ray did not pass through own planter")
	var idx: int = run.plots.size() - 1
	check(world.plot_tag_position(run, idx).distance_to(Vector3(-4.5, 0.9, 3.5)) < 0.01, "pot tag is not on furniture")
	check(world.move_spot_block(run, uid, 0.0, 3.0, 0) != "", "main route allowed")
	check(world.move_spot_block(run, uid, -3.0, 1.5, 0) != "", "well collision allowed")
	check(world.move_spot_block(run, -1, 0, 0, 0) != "", "missing uid accepted")
	var chosen := Vector3.ZERO
	var found := false
	for x in range(-18, 19):
		for z in range(-15, 14):
			var px := x * 0.5
			var pz := z * 0.5
			if Vector2(px + 4.5, pz - 3.5).length() > 1.5 and world.move_spot_block(run, uid, px, pz, 90) == "":
				chosen = Vector3(px, 0, pz)
				found = true
				break
		if found: break
	check(found, "no valid target in courtyard")
	if found:
		check(Home.move(run, uid, chosen.x, chosen.z, 90) == "", "move rejected")
		world.sync(run)
		await get_tree().physics_frame
		source = world.spot_nodes.get("f_%d" % uid)
		check(source.global_position.distance_to(chosen) < 0.01, "planter did not move")
		var body: StaticBody3D
		for child in source.get_children():
			if child is StaticBody3D: body = child
		var size: Vector3 = (body.get_child(0) as CollisionShape3D).shape.size
		check(absf(size.x - 1.4) < 0.01 and absf(size.z - 0.6) < 0.01, "rotated collider must use local zero-degree size")
		check(source.get_node_or_null("planter_crop") != null, "crop disappeared after move")
		check(world.plot_tag_position(run, idx).distance_to(chosen + Vector3(0, 0.9, 0)) < 0.01, "tag did not move")
		check(int(plot.pot) == uid and plot.crop == "cabbage" and float(plot.days) == 1.0, "plot state changed")
		var person := CharacterBody3D.new()
		var person_shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.3
		capsule.height = 1.7
		person_shape.shape = capsule
		person_shape.position.y = 0.85
		person.add_child(person_shape)
		world.add_child(person)
		person.position = chosen
		await get_tree().physics_frame
		await get_tree().physics_frame
		check(world.move_spot_block(run, uid, chosen.x, chosen.z, 90) == "人站在这里，先让开。", "player overlap accepted")
		person.queue_free()
	for i in 3:
		var other := Home.add(run, "planter", -7.0 + i, 5.0, 0)
		run.plots.back().crop = "cabbage"
		check(int(run.plots.back().pot) == int(other.uid), "new pot association missing")
	world.sync(run)
	check(world.plot_tag_position(run, run.plots.size() - 1) != null, "extra pot tag missing")
	print("[C2_WORLD] ", checks - failed, "/", checks, " failed=", failed)
	get_tree().quit(1 if failed else 0)

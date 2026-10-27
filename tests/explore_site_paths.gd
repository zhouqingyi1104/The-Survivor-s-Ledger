extends Node

const World = preload("res://scripts/world/ruin_world.gd")
const Data = preload("res://scripts/core/data.gd")
const Explore = preload("res://scripts/core/explore.gd")
const SITES := ["rice_ruin", "city_god", "school", "pharmacy_ruin", "lumber", "mortuary", "granary", "taoist_temple"]
const STEP := 0.5
const Y := 0.9
var failures := 0
var checks := 0
var body: CharacterBody3D
var shape := CapsuleShape3D.new()
var space: PhysicsDirectSpaceState3D
var world: Node3D

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func clear_at(cell: Vector2i) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, Vector3(cell.x * STEP, Y, cell.y * STEP))
	q.exclude = [body.get_rid()]
	return space.intersect_shape(q, 1).is_empty()

func find_path(start: Vector2i, target: int) -> Array:
	var pending: Array[Vector2i] = [start]
	var previous := {start: start}
	var cursor := 0
	var goal := start
	var found := false
	while cursor < pending.size():
		var p: Vector2i = pending[cursor]
		cursor += 1
		if world.nearest(Vector3(p.x * STEP, 0, p.y * STEP)) == target:
			goal = p
			found = true
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if absi(n.x) > 36 or n.y < -36 or n.y > 14 or previous.has(n) or not clear_at(n):
				continue
			previous[n] = p
			pending.append(n)
	if not found: return []
	var path := [goal]
	while goal != start:
		goal = previous[goal]
		path.push_front(goal)
	return path

func follow(path: Array, site: String, target: int) -> Vector2i:
	var cell: Vector2i = path[0]
	for i in range(1, path.size()):
		var next: Vector2i = path[i]
		var movement := Vector3((next.x - cell.x) * STEP, 0, (next.y - cell.y) * STEP)
		if body.move_and_collide(movement) != null:
			check(false, "%s: capsule collided en route to %d at %s" % [site, target, str(next)])
			return cell
		cell = next
	check(world.nearest(body.position) == target, "%s: movement did not reach %d" % [site, target])
	return cell

func _ready() -> void:
	shape.radius = 0.3
	shape.height = 1.7
	DirAccess.make_dir_recursive_absolute(OS.get_temp_dir().path_join("unknownGame-explore-sites"))
	for site in SITES:
		world = World.new()
		add_child(world)
		var names: Array = Data.table("map_points")[site].spots.duplicate()
		var signature: String = Explore.SITE_SPOTS[site]
		names.erase(signature)
		names.push_front(signature)
		while names.size() < 4: names.append("遗留物")
		names.resize(4)
		names.append("守庄人药账" if site == "mortuary" else "遗留物")
		names.append("炼尸阵的运尸簿" if site == "mortuary" else ("七星灯阵眼 · 按图封阵" if site == "taoist_temple" else "残留物"))
		var spots := []
		for name in names: spots.append({"name": name, "done": false})
		world.setup(site, spots)
		var ex := {"point": site, "spots": spots, "caught": false}
		var run := {"explore": ex, "mainline": {}}
		world.sync(run)
		check(world._spots[0].label.text.contains("· 特色"), site + ": missing signature marker")
		for setting in ["done", "neighbor", "mainline"]:
			spots[0][setting] = true
			world.sync(run)
			check(not world._spots[0].label.text.contains("· 特色"), site + ": marker on " + setting)
			if setting == "done": spots[0].done = false
			else: spots[0].erase(setting)
		spots[0].done = false
		for setting in ["caught", "site_used", "curfew_due"]:
			ex[setting] = true
			world.sync(run)
			check(not world._spots[0].label.text.contains("· 特色"), site + ": marker despite " + setting)
			ex[setting] = false
		# 捕获时会生成追逐者；测试完标记后单独清理以免影响画面。
		if world._hunter != null:
			world._hunter.queue_free()
			world._hunter = null
		world.sync(run)
		body = CharacterBody3D.new()
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		world.add_child(body)
		world.player_ref = body
		body.position = Vector3(0, Y, 4.0)
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.position = Vector3(0, 17, 17)
		camera.look_at(Vector3(0, 0, 0), Vector3.UP)
		camera.fov = 48.0
		camera.current = true
		await get_tree().physics_frame
		await get_tree().process_frame
		space = world.get_world_3d().direct_space_state
		var start := Vector2i(0, 8)
		check(clear_at(start), site + ": start obstructed")
		# Mainline/neighbor goals and the exit remain available before the gate.
		for target in [4, 5, -2]:
			var path := find_path(start, target)
			check(not path.is_empty(), "%s: no public route to %d while locked" % [site, target])
			if not path.is_empty(): start = follow(path, site, target)
		check(find_path(start, 0).is_empty(), site + ": locked signature can be interacted with")
		ex.expedition.unlocked = true
		world.sync(run)
		await get_tree().physics_frame
		for target in [0, 1, 2, 3, 4, 5, -2]:
			var path := find_path(start, target)
			check(not path.is_empty(), "%s: no route to %d" % [site, target])
			if path.is_empty(): continue
			start = follow(path, site, target)
		if DisplayServer.get_name() != "headless":
			await get_tree().process_frame
			await get_tree().process_frame
			var shot := get_viewport().get_texture().get_image()
			check(shot.save_png(OS.get_temp_dir().path_join("unknownGame-explore-sites").path_join(site + ".png")) == OK, site + ": screenshot failed")
		world.queue_free()
		await get_tree().process_frame
	print("Explore site paths: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

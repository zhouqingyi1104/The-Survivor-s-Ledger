extends Node

const World = preload("res://scripts/world/ruin_world.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Figure = preload("res://scripts/world/character.gd")
const SITES := ["rice_ruin", "city_god", "school", "pharmacy_ruin", "lumber", "mortuary", "granary", "taoist_temple"]
const STEP := 0.5
const Y := 0.9
var failures := 0
var checks := 0
var body: CharacterBody3D
var shape := CapsuleShape3D.new()
var world: Node3D
var space: PhysicsDirectSpaceState3D

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func clear_at(cell: Vector2i) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, Vector3(cell.x * STEP, Y, cell.y * STEP))
	query.exclude = [body.get_rid()]
	return space.intersect_shape(query, 1).is_empty()

func flood(start: Vector2i) -> Dictionary:
	var pending: Array[Vector2i] = [start]
	var previous := {start: start}
	var cursor := 0
	while cursor < pending.size():
		var p: Vector2i = pending[cursor]
		cursor += 1
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var n: Vector2i = p + d
			if absi(n.x) > 36 or n.y < -36 or n.y > 14 or previous.has(n) or not clear_at(n): continue
			previous[n] = p
			pending.append(n)
	return previous

func goal(previous: Dictionary, kind: String, value) -> Variant:
	for cell in previous:
		var p := Vector3(cell.x * STEP,0,cell.y * STEP)
		if kind == "feature" and world.nearest_feature(p) == value: return cell
		if kind == "spot" and world.nearest(p) == value: return cell
		if kind == "physical" and p.distance_to(value) < 1.3: return cell
	return null

func walk(previous: Dictionary, start: Vector2i, dest: Vector2i, context: String) -> void:
	var path := [dest]
	while dest != start:
		dest = previous[dest]
		path.push_front(dest)
	body.position = Vector3(start.x * STEP,Y,start.y * STEP)
	for i in range(1,path.size()):
		var movement := Vector3((path[i].x-path[i-1].x)*STEP,0,(path[i].y-path[i-1].y)*STEP)
		if body.move_and_collide(movement) != null:
			check(false, context + " collision on actual capsule path")
			return
	check(true, context + " capsule path")

func _ready() -> void:
	shape.radius = 0.3
	shape.height = 1.7
	DirAccess.make_dir_recursive_absolute(OS.get_temp_dir().path_join("unknownGame-expedition-world"))
	for site in SITES:
		world = World.new()
		add_child(world)
		var spots := [{"name": Explore.SITE_SPOTS[site], "done": false}, {"name":"普通物资甲", "done":false}, {"name":"普通物资乙", "done":false}, {"name":"普通物资丙", "done":false}, {"name":"邻居任务", "done":false, "neighbor":"cabinet"}, {"name":"主线任务", "done":false, "mainline":"mortuary"}]
		world.setup(site, spots)
		var ex := {"point":site, "spots":spots, "caught":false, "expedition":{"clues":[false,false],"unlocked":false}}
		var run := {"explore": ex, "mainline": {}}
		world.sync(run)
		body = CharacterBody3D.new()
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		var figure: Node3D = Figure.new()
		body.add_child(figure)
		figure.position.y = -Y
		figure.setup("scholar")
		world.add_child(body)
		body.position = Vector3(0,Y,4)
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.position = world.feature_positions.gate + Vector3(0,10,9)
		camera.look_at(world.feature_positions.gate, Vector3.UP)
		camera.fov = 48
		camera.current = true
		await get_tree().physics_frame
		space = world.get_world_3d().direct_space_state
		var start := Vector2i(0,8)
		check(clear_at(start), site + ": entrance obstructed")
		var before := flood(start)
		check(world.locked_spot_index == 0, site + ": signature is not locked")
		var locked_target: Vector3 = world._spots[0].pos
		check(goal(before,"physical",locked_target) == null, site + ": can physically bypass closed gate")
		check(world.nearest(locked_target) != 0, site + ": locked spot is interactable")
		for key in ["clue_0","clue_1","gate"]:
			var g = goal(before,"feature",key)
			check(g != null, site + ": unreachable " + key)
			if g != null: walk(before,start,g,site + " " + key)
		for index in [1,2,3,4,5,-2]:
			var g = goal(before,"spot",index)
			check(g != null, "%s: unreachable public spot %s" % [site,index])
			if g != null: walk(before,start,g,"%s public spot %s" % [site,index])
		var beyond: Vector3 = world.gate_center + world.gate_normal * 0.7
		check(world.nearest_feature(beyond) != "gate", site + ": gate interactable through wall")
		ex.expedition.unlocked = true
		world.sync(run)
		await get_tree().physics_frame
		var after := flood(start)
		var target = goal(after,"spot",0)
		check(target != null, site + ": unlocked target inaccessible")
		if target != null: walk(after,start,target,site + " locked target")
		if DisplayServer.get_name() != "headless":
			ex.expedition.unlocked = false
			world.sync(run)
			await get_tree().physics_frame
			body.position = world.feature_positions.gate + Vector3(0,Y,0)
			await get_tree().process_frame
			await get_tree().process_frame
			check(get_viewport().get_texture().get_image().save_png(OS.get_temp_dir().path_join("unknownGame-expedition-world").path_join(site + ".png")) == OK, site + ": screenshot")
		world.queue_free()
		await get_tree().process_frame
	print("Expedition world: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)

extends Node
## Check the actual walk() route for every ordered pair of city destinations.
const City = preload("res://scripts/world/city_world.gd")

class Ground extends City:
	func _ready() -> void:
		_ground()

func _ready() -> void:
	await get_tree().process_frame
	var city = City.new()
	city.walker = City.Figure.new()
	var failures := 0
	var cases := 0
	for source in City.PLACES:
		for destination in City.PLACES:
			if source == destination:
				continue
			cases += 1
			city.walk(source, destination)
			var start: Vector3 = City.PLACES[source][0]
			var finish: Vector3 = City.PLACES[destination][0]
			var za: float = City.PLACES[source][2]
			var zb: float = City.PLACES[destination][2]
			var length := 0.0
			var previous := start
			var safe_crossing := true
			for point in city._path:
				length += previous.distance_to(point)
				# A segment crossing the river must stay on the bridge axis.
				if minf(previous.z, point.z) < 2.0 and maxf(previous.z, point.z) > 8.0:
					safe_crossing = safe_crossing and is_zero_approx(previous.x) and is_zero_approx(point.x)
				previous = point
			var expected := absf(start.z - za) + absf(finish.z - zb)
			if za == zb:
				expected += absf(start.x - finish.x)
			else:
				expected += absf(start.x) + absf(za - zb) + absf(finish.x)
			if not is_equal_approx(length, expected) or previous != finish or not safe_crossing:
				failures += 1
				push_error("Bad route %s -> %s: %s" % [source, destination, city._path])
	for hz in [30, 60, 120]:
		cases += 1
		if not _run_to_shop(city, hz):
			failures += 1
			push_error("起步、转弯、收步或到店位置异常：%d Hz" % hz)
	city.walker.free()
	city.free()
	var ground := Ground.new()
	add_child(ground)
	for bank: int in [-1, 1]:
		for x: float in [-2.15, -0.74, 0.0, 0.74, 2.15]:
			cases += 1
			var probe := Vector3(x, 0.0, City.RIVER_Z + bank * 3.45)
			var surface := _rendered_height(ground, probe)
			var on_bridge := absf(x) < 1.0
			var correct := absf(surface - ground._street_height(probe)) < 0.01 if on_bridge else surface >= 0.285
			if is_zero_approx(x):
				print("桥口 z=%.2f 实际网格 %.3f m，落脚 %.3f m" % [probe.z, surface, ground._street_height(probe)])
			if not correct:
				failures += 1
				push_error("桥口 %.2f, %.2f 的可见石面高度异常：%.3f m" % [x, probe.z, surface])
	ground.free()
	print("City routes: %d cases, %d failures" % [cases, failures])
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)


func _rendered_height(ground: Node3D, probe: Vector3) -> float:
	var high := -INF
	var start := probe + Vector3.UP * 0.45
	var end := probe + Vector3.DOWN * 0.05
	for piece: MeshInstance3D in ground.find_children("*", "MeshInstance3D", true, false):
		if piece.mesh == null or not piece.is_visible_in_tree():
			continue
		var local_start := piece.to_local(start)
		var local_end := piece.to_local(end)
		if piece.get_aabb().intersects_segment(local_start, local_end) == null:
			continue
		var surface := piece.mesh.generate_triangle_mesh()
		if surface:
			var hit := surface.intersect_segment(local_start, local_end)
			if not hit.is_empty():
				high = maxf(high, piece.to_global(hit.position).y)
	return high


func _run_to_shop(city: City, hz: int) -> bool:
	city._place_walker("pawnshop")
	city.walk("pawnshop", "builder")
	var dt := 1.0 / hz
	var peak := 0.0
	var first_speed := 0.0
	var last_speed := 0.0
	for frame in hz * 25:
		var previous_yaw: float = city.walker.rotation.y
		city._process(dt)
		if absf(angle_difference(previous_yaw, city.walker.rotation.y)) > PI / 4.0:
			return false
		if not city.walking:
			var finish: Vector3 = City.PLACES.builder[0]
			finish.y = City.PAVING_TOP
			print("桥市当铺至营造坊 %d Hz，%.2f 秒" % [hz, (frame + 1) * dt])
			var stopped_at_door: bool = city.walker.position.is_equal_approx(finish) and not city.walker.moving
			var eased_at_ends := first_speed > 0.0 and first_speed < peak * 0.5 and last_speed < peak * 0.5
			return stopped_at_door and eased_at_ends and is_equal_approx(peak, city.walk_speed)
		var speed: float = city.walker.move_speed
		if frame == 0: first_speed = speed
		peak = maxf(peak, speed)
		last_speed = speed
	return false

extends Node
## Check the actual walk() route for every ordered pair of city destinations.
const City = preload("res://scripts/world/city_world.gd")

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
	city.walker.free()
	city.free()
	print("City routes: %d cases, %d failures" % [cases, failures])
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)

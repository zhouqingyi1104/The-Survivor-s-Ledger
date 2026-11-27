extends RefCounted
## 楼层完工时带来的原有陈设。玩家家具占用一角时只让出该组，挪空后可以复原。
const K = preload("res://scripts/world/kit.gd")
const Home = preload("res://scripts/core/home.gd")
const Cellar = preload("res://scripts/world/cellar_storage.gd")
const Attic = preload("res://scripts/world/attic_living.gd")

const AREAS := {
	"cellar": {
		"sorting": Rect2(-2.73, -0.86, 1.82, 1.12),
		"pantry": Rect2(1.125, -2.20, 2.05, 1.04),
		"delivery": Rect2(-3.00, 1.11, 1.84, 1.14),
		"carrier": Rect2(1.70, 1.35, 1.70, 0.70),
	},
	"attic": {
		"berth": Rect2(-3.50, -1.98, 2.20, 3.20),
		"sewing": Rect2(0.80, -0.36, 2.12, 1.32),
	},
}
const CELLAR_BODIES := {
	"sorting": Vector3(1.76, 0.89, 0.96),
	"pantry": Vector3(1.98, 1.88, 0.81),
	"delivery": Vector3(1.76, 0.68, 1.04),
	"carrier": Vector3(1.65, 0.63, 0.67),
}
const SORTING_STAND := Vector3(1.50, 0, 0.0)
const SORTING_TAG := Vector3(0.42, 1.55, 0.16)

var groups: Dictionary = {}
var bodies: Array[RID] = []
var waiting_for_clearance := false


## 自摆的家具留一条从侧面穿回中轴的路；旧卷也使用相同的通行宽度。
static func _access_strip(item: Dictionary) -> Rect2:
	var stand := Home.stand(item)
	return Rect2(minf(0.0, stand.x), stand.z, absf(stand.x), 0.0).grow(0.60)


func replaces_group(floor_id: String, id: String, point: Vector3, rotation: int) -> bool:
	var area := Home.rect_of(id, point.x, point.z, rotation)
	var access := _access_strip({"id": id, "x": point.x, "z": point.z, "rot": rotation})
	for group in groups:
		var occupied: Rect2 = AREAS[floor_id][group]
		if occupied.intersects(area) or occupied.intersects(access):
			return true
	return false


func sync(room: Node3D, floor_id: String, run: Dictionary, people: PackedVector2Array) -> bool:
	waiting_for_clearance = false
	var unlocked := Home.Floors.unlocked(run, floor_id)
	if not unlocked and groups.is_empty():
		return false
	var reserved: Array[Rect2] = []
	for item in run.get("furniture", []):
		if str(item.get("floor", "courtyard")) != floor_id:
			continue
		reserved.append(Home.rect_of(item.id, item.x, item.z, item.rot))
		reserved.append(_access_strip(item))
	var changed := false
	for id: String in AREAS[floor_id]:
		var area: Rect2 = AREAS[floor_id][id]
		var claimed := not unlocked or reserved.any(func(rect: Rect2) -> bool: return rect.intersects(area))
		if groups.has(id):
			if claimed:
				var old: Node3D = groups[id]
				room.remove_child(old)
				old.queue_free()
				groups.erase(id)
				changed = true
		elif not claimed:
			var occupied := false
			for person in people:
				if area.grow(0.35).has_point(person):
					occupied = true
					waiting_for_clearance = true
					break
			if not occupied:
				groups[id] = _build(room, floor_id, id, area.get_center())
				changed = true
	if floor_id == "cellar":
		Cellar.sync_stock(groups, run.get("home", {}))
	if changed:
		bodies.clear()
		for group: Node3D in groups.values():
			for body: StaticBody3D in group.find_children("*", "StaticBody3D", true, false):
				bodies.append(body.get_rid())
	return changed


func _build(room: Node3D, floor_id: String, id: String, center: Vector2) -> Node3D:
	var group := K.node(room, Vector3(center.x, 0, center.y), Vector3.ZERO, id)
	if floor_id == "cellar":
		Cellar.build_group(id, group)
		var size: Vector3 = CELLAR_BODIES[id]
		var body := K.collider(group, size, Vector3.UP * (0.10 + size.y * 0.5))
		if id == "sorting":
			body.set_meta("spot", "floor_use")
			K.text3d(group, "整理台", Vector3(0.57, 1.91, -0.10), 44, Color("#f2d89c"), true, 0.005)
	else:
		Attic.build_group(id, group)
		Attic.block_group(id, group)
	return group

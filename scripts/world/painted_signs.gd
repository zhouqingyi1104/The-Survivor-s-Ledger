extends RefCounted
## 店额和柱联的漆面。基座、吊耳和街市文字仍属于各自建筑。

const K = preload("res://scripts/world/kit.gd")
const Marks = preload("res://scripts/ui/travel_marks.gd")
const PLAQUE := preload("res://assets/art/wayfinding/plaque-face.svg")
const VERSES := preload("res://assets/art/wayfinding/pillar-verses.svg")
static var _materials := {}


static func _face(parent: Node3D, sheet: Texture2D, index: int, grid: Vector2i, size: Vector2, pos: Vector3) -> void:
	if not _materials.has(sheet):
		_materials[sheet] = {}
	var variants: Dictionary = _materials[sheet]
	if not variants.has(index):
		var paint := StandardMaterial3D.new()
		paint.albedo_texture = sheet
		paint.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		paint.texture_repeat = false
		paint.roughness = 0.93
		paint.metallic_specular = 0.16
		paint.uv1_scale = Vector3(1.0 / grid.x, 1.0 / grid.y, 1)
		paint.uv1_offset = Vector3(float(index % grid.x) / grid.x, float(index / grid.x) / grid.y, 0)
		if sheet == Marks.SHEET:
			paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		variants[index] = paint
	var quad := QuadMesh.new()
	quad.size = size
	var panel := K._mesh(parent, quad, variants[index], pos)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func shop(plaque: Node3D, id: StringName, width: float) -> void:
	_face(plaque, PLAQUE, 0, Vector2i.ONE, Vector2(width - 0.05, 0.61), Vector3(0, 0, 0.049))
	var device := Marks.KEYS.find(id)
	if device >= 0:
		var side := minf(0.35, width * 0.13)
		_face(plaque, Marks.SHEET, device, Vector2i(4, 4), Vector2(side, side),
				Vector3(-(width - 0.05) * 0.37, 0, 0.054))


static func verse(post: Node3D, leaf: int, size: Vector2, pos: Vector3) -> void:
	_face(post, VERSES, leaf, Vector2i(4, 1), size, pos)

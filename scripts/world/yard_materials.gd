extends RefCounted
## 井院和桥头自家使用相同的本地扫描材质。井边的水迹只属于灾后宅院。

const Assets = preload("res://scripts/world/assets.gd")
const GROUND := preload("res://scripts/world/courtyard_ground.gdshader")
const DIRT := "res://assets/third_party/polyhaven/textures/brown_mud_dry/brown_mud_dry_"
const STONE := "res://assets/third_party/polyhaven/textures/rock_face_03/rock_face_03_"
const SNOW := preload("res://assets/third_party/polyhaven/textures/snow_02/snow_02_diff.jpg")

static var _materials := {}

static func street() -> BaseMaterial3D:
	return Assets.pbr("square_cobblestone", 4.2, Color("#a6a69f"))


static func ground(flagstone: bool, courtyard := true) -> ShaderMaterial:
	var key := Vector2i(int(flagstone), int(courtyard))
	if not _materials.has(key):
		var mat := ShaderMaterial.new()
		var prefix := STONE if flagstone else DIRT
		mat.shader = GROUND
		mat.set_shader_parameter("flagstone", flagstone)
		mat.set_shader_parameter("courtyard", courtyard)
		mat.set_shader_parameter("surface_color", load(prefix + "diff.jpg") if flagstone else Assets.PACKED_EARTH)
		mat.set_shader_parameter("surface_normal", load(prefix + "nor.jpg"))
		mat.set_shader_parameter("surface_arm", load(prefix + "arm.jpg"))
		mat.set_shader_parameter("snow_color", SNOW)
		_materials[key] = mat
	return _materials[key]

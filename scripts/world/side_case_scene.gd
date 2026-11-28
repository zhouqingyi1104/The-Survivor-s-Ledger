extends Node3D

const K = preload("res://scripts/world/kit.gd")
const Visitor = preload("res://scripts/world/chronicle_visitor.gd")
const Figure = preload("res://scripts/world/character.gd")
const Field = preload("res://scripts/world/field_props.gd")
const Stock = preload("res://scripts/world/household_models.gd")
const Cellar = preload("res://scripts/world/cellar_storage.gd")
const House = preload("res://scripts/world/home_house.gd")
const Assets = preload("res://scripts/world/assets.gd")

const ANIMATIONS := {
	"ledger": "Interact", "tile": "Fixing_Kneeling", "rope": "Fixing_Kneeling",
	"measure": "Interact", "timber": "Fixing_Kneeling", "basket": "PickUp_Table",
	"jar": "PickUp_Table", "cloth": "Interact", "seed": "PickUp_Table"
}

var partner: Figure
var evidence: Node3D


func setup(spot: Dictionary) -> void:
	var prop := str(spot.prop)
	var station := K.node(self, Vector3.UP * 0.06)
	# 瓦、旧缆与木枋就地查验。纸册和小件摆到桌上，动作接近手边的高度。
	var top := 0.0
	if not prop in ["tile", "rope", "timber"]:
		top = Field._tabletop(station, false)
	evidence = K.node(station, Vector3.UP * top)
	_make_evidence(prop)
	K.merge_static(evidence, [])
	partner = Visitor.spawn_actor(self, str(spot.person))
	partner.position = Vector3(0.86, 0.06, -0.44)
	partner.face(-partner.position)
	partner.work_anim = str(ANIMATIONS[prop])


func sync(working: bool, done: bool, caught: bool) -> void:
	evidence.visible = not done
	partner.working = working and not done
	partner.visible = not caught


func _make_evidence(prop: String) -> void:
	match prop:
		"ledger":
			Field.book(evidence, Vector3(-0.09, 0, -0.03), -12)
			K.box(evidence, Vector3(0.23, 0.004, 0.11), K.PAPER, Vector3(0.23, 0.004, 0.07), Vector3(0, 18, 0))
			K.cyl(evidence, 0.012, 0.009, 0.29, K.WOOD, Vector3(0.22, 0.025, -0.11), Vector3(78, 18, 0), 8)
		"tile":
			var tile := House._clay_tile(0.48, 0.57)
			for i in 3:
				K._mesh(evidence, tile, House.roof_tiles(), Vector3((i - 1) * 0.27, 0.04 + i * 0.024, (i % 2) * 0.13), Vector3(0, 11 * i - 8, -5))
		"rope":
			var cord := K.mat(Color("#98845c"), 0.95)
			for i in 3:
				var coil := TorusMesh.new()
				coil.inner_radius = 0.24 + i * 0.032
				coil.outer_radius = coil.inner_radius + 0.043
				coil.rings = 28
				coil.ring_segments = 8
				var strand := K._mesh(evidence, coil, cord, Vector3(i * 0.032, 0.025 + i * 0.029, 0), Vector3(0, 9 * i, 0))
				strand.scale.z = 0.72
			Cellar._line(evidence, Vector3(0.28, 0.04, 0), Vector3(0.53, 0.05, 0.23), 0.021, cord)
			K.cyl(evidence, 0.055, 0.07, 0.72, K.WOOD, Vector3(0.41, 0.32, 0.16), Vector3(-5, 0, 8), 9)
		"measure":
			Cellar._steelyard(evidence)
		"timber":
			Stock.place(evidence, &"Timber", Vector3.ZERO).rotation.y = 1.30
			for i in 3:
				K.box(evidence, Vector3(0.082, 0.06, 0.32), K.WOOD_LIGHT, Vector3(-0.22 + i * 0.12, 0.03, 0.22), Vector3(0, 7 * i, 0))
		"basket":
			Stock.place(evidence, &"Basket", Vector3.ZERO).scale = Vector3.ONE * 0.78
		"jar":
			Assets.prop(evidence, "ceramic_pot", Vector3(-0.15, 0, 0.025), -15, 0.90, false)
			Assets.prop(evidence, "ceramic_vase_02", Vector3(0.20, 0, -0.06), 22, 0.69, false)
		"cloth":
			Stock.place(evidence, &"Cloth0", Vector3.ZERO).scale = Vector3.ONE * 0.72
			Stock.place(evidence, &"Cloth0", Vector3(0.045, 0.061, 0.04)).scale = Vector3.ONE * 0.57
		"seed":
			K.box(evidence, Vector3(0.54, 0.035, 0.36), House.TIMBER, Vector3.UP * 0.022)
			for x in [-0.26, 0, 0.26]:
				K.box(evidence, Vector3(0.018, 0.084, 0.36), House.TRIM, Vector3(x, 0.052, 0))
			for z in [-0.175, 0.175]:
				K.box(evidence, Vector3(0.53, 0.084, 0.018), House.TRIM, Vector3(0, 0.052, z))
			for i in 16:
				var x := (i % 4 - 1.5) * 0.115
				var z := (i / 4 - 1.5) * 0.065
				K.cyl(evidence, 0.018, 0.014, 0.022, Color("#af935c") if x < 0 else Color("#74503a"), Vector3(x, 0.053, z), Vector3(0, i * 17, 29), 7)

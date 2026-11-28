extends Node3D

const K = preload("res://scripts/world/kit.gd")
const Figure = preload("res://scripts/world/character.gd")
const Stock = preload("res://scripts/world/household_models.gd")
const Cellar = preload("res://scripts/world/cellar_storage.gd")

# 中路西沿是既有不可摆家具的通道。来人只接收拾取射线，不占玩家或导航的碰撞层。
const PLACE := Vector3(-0.69, 0, 0.45)
const STAND := Vector3(0.12, 0, 1.22)
const SPOT := "chronicle_visitor"
const PEOPLE := {
	"桂娘": ["井匠", "villager_f", Color("#486b69"), 1.0, "bucket"],
	"石榴": ["记门户的孩子", "villager_f", Color("#9b5849"), 0.78, "book"],
	"陶婆": ["接生婆", "herbalist", Color("#645569"), 0.96, "basket"],
	"孟九": ["窑工", "escort", Color("#725e4b"), 1.04, "brick"],
	"许墨生": ["抄书匠", "scholar", Color("#546575"), 1.0, "book"],
	"罗篙": ["摆渡人", "villager", Color("#536c70"), 1.05, "pole"],
	"柳纫": ["裁缝", "villager_f", Color("#775669"), 1.0, "cloth"],
	"秋禾": ["种菜人", "herbalist", Color("#65764d"), 0.98, "basket"],
	"洪菱": ["渡船船主", "villager_f", Color("#916048"), 0.94, "pole"],
}

var event_id := ""
var caption := ""
var tag := Vector3.ZERO


static func spawn_actor(parent: Node3D, person: String) -> Figure:
	var look: Array = PEOPLE[person]
	var actor := Figure.new()
	parent.add_child(actor)
	actor.setup(look[1], look[2])
	actor.scale = Vector3.ONE * float(look[3])
	return actor


func setup(event: Dictionary) -> void:
	event_id = str(event.id)
	# 末日三人同来，由排在称呼首位的洪菱传话。
	var person := str(event.person).get_slice("、", 0)
	var look: Array = PEOPLE[person]
	caption = "%s · %s" % [person, look[0]]
	position = PLACE
	var height := float(look[3])
	tag = PLACE + Vector3.UP * (2.05 * height)
	var actor := spawn_actor(self, person)
	actor.face(STAND - PLACE)
	match str(look[4]):
		"bucket":
			var pail := K.node(self, Vector3(-0.34, 0.04, 0.16))
			Cellar._bucket(pail, K.mat(Color("#4b4d48"), 0.72, 0.38))
			K.merge_static(pail, [])
		"basket":
			Stock.place(self, &"Basket", Vector3(-0.32, 0.05, 0.12)).scale = Vector3.ONE * 0.8
		"book":
			var hand := actor._bone("hand_l")
			K.box(hand, Vector3(0.17, 0.028, 0.24), Color("#57616c"), Vector3(0, 0.01, 0.09))
			K.box(hand, Vector3(0.158, 0.018, 0.225), Color("#cfbf98"), Vector3(0, 0.011, 0.09))
		"brick":
			K.box(actor._bone("hand_l"), Vector3(0.112, 0.065, 0.22), Color("#786958"), Vector3(0, 0, 0.07))
		"cloth":
			Stock.place(actor._bone("hand_l"), &"Cloth0", Vector3(0, -0.03, 0.01)).scale = Vector3.ONE * 0.35
		"pole":
			K.cyl(self, 0.025, 0.038, 2.12, K.WOOD_LIGHT, Vector3(-0.32, 1.08, 0.08), Vector3(5, 0, -6), 10)
	var hit := Area3D.new()
	hit.collision_layer = 2
	hit.collision_mask = 0
	hit.monitoring = false
	hit.monitorable = false
	hit.set_meta("spot", SPOT)
	add_child(hit)
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.85 * height
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	hit.add_child(collision)

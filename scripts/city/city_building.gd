class_name CityBuilding
extends StaticBody3D
## A greybox city building. Builds its own box mesh, collision, sign label and
## door marker at runtime from exports (so the hand-authored city .tscn files
## only set primitives — no fragile node refs).
##
## `building_type` is the future hook: shops/banks/taverns all funnel through
## interact() -> EventBus.city_building_interacted. When a real facility UI
## exists (shipyard screen, bank, tavern), it listens for its type and opens.
## Until then the city shows a "not yet open" toast.

const TYPE_INFO := {
	"market":    {"size": Vector3(10, 6, 8),  "color": Color(0.75, 0.6, 0.35)},
	"shipyard":  {"size": Vector3(14, 8, 10), "color": Color(0.5, 0.45, 0.4)},
	"tavern":    {"size": Vector3(8, 5, 7),   "color": Color(0.6, 0.4, 0.25)},
	"bank":      {"size": Vector3(8, 7, 7),   "color": Color(0.7, 0.7, 0.75)},
	"governor":  {"size": Vector3(12, 9, 9),  "color": Color(0.8, 0.75, 0.6)},
	"church":    {"size": Vector3(9, 14, 12), "color": Color(0.85, 0.82, 0.75)},
	"warehouse": {"size": Vector3(12, 6, 9),  "color": Color(0.55, 0.5, 0.45)},
	"house":     {"size": Vector3(6, 4, 6),   "color": Color(0.7, 0.62, 0.5)},
}

@export_enum("market", "shipyard", "tavern", "bank", "governor", "church", "warehouse", "house")
var building_type: String = "house"
## Optional custom sign text; empty = capitalized type name.
@export var sign_text: String = ""

var door_position: Vector3:
	get:
		var size: Vector3 = TYPE_INFO[building_type]["size"]
		return global_position + global_transform.basis.z * (size.z * 0.5 + 1.0)

func _ready() -> void:
	add_to_group("city_building")
	var info: Dictionary = TYPE_INFO[building_type]
	var size: Vector3 = info["size"]

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = info["color"]
	mat.roughness = 0.95
	box.material = mat
	mesh.mesh = box
	mesh.position.y = size.y * 0.5
	add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position.y = size.y * 0.5
	add_child(col)

	var label := Label3D.new()
	label.text = sign_text if sign_text != "" else building_type.capitalize()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.02
	label.position.y = size.y + 1.5
	label.font_size = 64
	add_child(label)

	# Door marker: small dark slab on the +Z face (buildings face +Z; rotate the
	# node in the city scene to face the street).
	var door := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(1.4, 2.4, 0.2)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.2, 0.14, 0.1)
	slab.material = dmat
	door.mesh = slab
	door.position = Vector3(0, 1.2, size.z * 0.5 + 0.05)
	add_child(door)

func interact() -> String:
	EventBus.city_building_interacted.emit(_city_id(), building_type)
	return "%s — not yet open" % (sign_text if sign_text != "" else building_type.capitalize())

func _city_id() -> StringName:
	var p := get_parent()
	while p:
		if p is CityScene:
			return (p as CityScene).city_id
		p = p.get_parent()
	return &""

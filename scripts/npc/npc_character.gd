class_name NPCCharacter
extends CharacterBody3D
## A walking city NPC (greybox box body until models exist). Wanders near its
## spawn point; the player interacts with E (same flow as buildings) to get a
## rotating placeholder line from its NPCDef. Replace lines with the dialogue
## framework when it lands.

const WALK_SPEED := 2.0
const GRAVITY := 20.0

var def: NPCDef

var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _wait := 0.0
var _line_i := 0
var _visual: Node3D

func _ready() -> void:
	add_to_group("npc")
	_home = global_position
	_target = _home

	_visual = Node3D.new()
	add_child(_visual)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 1.6, 0.7)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = def.color if def else Color(0.4, 0.5, 0.7)
	box.material = mat
	mesh.mesh = box
	mesh.position.y = 0.8
	_visual.add_child(mesh)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	col.shape = cap
	col.position.y = 0.8
	add_child(col)

	var label := Label3D.new()
	label.text = def.display_name if def else "???"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.01
	label.position.y = 2.1
	add_child(label)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	var to_target := _target - global_position
	to_target.y = 0.0
	if to_target.length() < 0.5:
		_wait -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if _wait <= 0.0:
			_pick_new_target()
	else:
		var dir := to_target.normalized()
		velocity.x = dir.x * WALK_SPEED
		velocity.z = dir.z * WALK_SPEED
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(-dir.x, -dir.z), 8.0 * delta)
	move_and_slide()

func _pick_new_target() -> void:
	_wait = randf_range(2.0, 6.0)
	var offset := Vector2.from_angle(randf_range(0.0, TAU)) * randf_range(2.0, 8.0)
	_target = _home + Vector3(offset.x, 0.0, offset.y)

## Same contract as CityBuilding.interact() — CityPlayer treats both alike.
func interact() -> String:
	if def == null or def.lines.is_empty():
		return "..."
	var line: String = def.lines[_line_i % def.lines.size()]
	_line_i += 1
	return "%s: \"%s\"" % [def.display_name, line]

var door_position: Vector3:
	get: return global_position

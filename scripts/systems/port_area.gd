class_name PortArea
extends Area3D
## Place at a port's harbor; assign its PortDef. Entering range lets the player
## dock (emits port_entered; a Port UI scene listens and opens).

@export var def: PortDef
@export var dock_radius: float = 40.0

func _ready() -> void:
	if def:
		global_position = def.world_position
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = dock_radius
	shape.shape = sphere
	add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if def and body is ShipController:
		GameState.current_port = def.id
		EventBus.port_entered.emit(def.id)

func _on_body_exited(body: Node3D) -> void:
	if def and body is ShipController:
		GameState.current_port = &""
		EventBus.port_left.emit(def.id)

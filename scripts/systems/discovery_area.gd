class_name DiscoveryArea
extends Area3D
## Place in the World scene at a discovery's location; assign its DiscoveryDef.
## When the player's ship enters, the discovery becomes "spotted" — the player
## then presses observe (E) to attempt confirmation.

@export var def: DiscoveryDef

func _ready() -> void:
	if def:
		global_position = def.world_position
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = def.spot_radius
		shape.shape = sphere
		add_child(shape)
	body_entered.connect(_on_body_entered)
	monitoring = true

func _on_body_entered(body: Node3D) -> void:
	if def and body is ShipController:
		DiscoveryDB.spot(def.id)

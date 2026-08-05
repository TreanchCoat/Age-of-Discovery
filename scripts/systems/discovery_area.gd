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
	body_exited.connect(_on_body_exited)
	monitoring = true

func _on_body_entered(body: Node3D) -> void:
	# is_player: pirates don't make discoveries on the player's behalf.
	if def and body is ShipController and body.is_player:
		DiscoveryDB.spot(def.id)

func _on_body_exited(body: Node3D) -> void:
	# Sailed off without confirming: drop the banner so E doesn't silently
	# no-op out of range. Re-entering re-spots it.
	if def and body is ShipController and body.is_player and not DiscoveryDB.is_found(def.id):
		EventBus.discovery_lost.emit(def.id)

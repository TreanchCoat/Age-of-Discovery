class_name ShallowArea
extends Area3D
## A ring of shallow water around a landmass. While the player's ship is inside,
## it sails slower and slowly scrapes its hull (see ShipController). Built from
## code in world.gd; sized a bit wider than the landmass it surrounds.

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_entered)
	body_exited.connect(_on_exited)

func _on_entered(body: Node3D) -> void:
	if body is ShipController:
		(body as ShipController).enter_shallows()

func _on_exited(body: Node3D) -> void:
	if body is ShipController:
		(body as ShipController).exit_shallows()

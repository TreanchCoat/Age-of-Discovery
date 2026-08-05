class_name NPCCaptain
extends Node
## Skeleton AI captain: drives its PARENT Node3D along waypoints with simple
## turn-rate steering — the chassis that naval-combat AI states (approach /
## engage / break off) will plug into.
##
## Current placeholder motion moves the parent directly (constant speed, yaw
## toward waypoint). When combat lands, this class should instead FEED SHIP
## INPUTS (wheel/sails/pace) to a refactored ShipController input-provider, so
## AI ships obey the same wind physics as the player. The public API (states,
## waypoints, target) is meant to survive that swap — build against it.

enum State { IDLE, PATROL, APPROACH, FLEE }

@export var speed := 5.0
@export var turn_rate := 0.8           # rad/s
@export var waypoints: Array[Vector3] = []
@export var loop_patrol := true

var state := State.IDLE
var target: Node3D = null              # APPROACH/FLEE reference (player, later)

var _wp_i := 0

func _ready() -> void:
	if get_parent() is Node3D:
		get_parent().add_to_group("npc_ship")
	if not waypoints.is_empty():
		state = State.PATROL

func _physics_process(delta: float) -> void:
	var body := get_parent() as Node3D
	if body == null:
		return
	var goal: Vector3
	match state:
		State.PATROL:
			if waypoints.is_empty():
				return
			goal = waypoints[_wp_i]
			if body.global_position.distance_to(goal) < 15.0:
				_wp_i += 1
				if _wp_i >= waypoints.size():
					_wp_i = 0 if loop_patrol else waypoints.size() - 1
		State.APPROACH:
			if target == null:
				state = State.IDLE
				return
			goal = target.global_position
		State.FLEE:
			if target == null:
				state = State.IDLE
				return
			goal = body.global_position + (body.global_position - target.global_position)
		_:
			return

	# Yaw toward goal at turn_rate; sail forward. (Placeholder physics.)
	var to_goal := goal - body.global_position
	to_goal.y = 0.0
	if to_goal.length() < 1.0:
		return
	var desired_yaw := atan2(-to_goal.x, -to_goal.z)
	body.rotation.y = rotate_toward(body.rotation.y, desired_yaw, turn_rate * delta)
	body.global_position += -body.global_transform.basis.z * speed * delta

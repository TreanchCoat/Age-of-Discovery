class_name WindSystem
extends Node
## Global wind that drifts over time. Add one to the World scene.
## Direction is a unit Vector2 on the XZ plane (x = east, y = south/+z).

@export var change_interval_hours: int = 3
@export var strength: float = 1.0  # 0 calm .. 2 storm

var direction := Vector2.RIGHT
var debug_locked := false  # when true, ignore natural drift (set by the debug UI)

var _target_angle := 0.0

func _ready() -> void:
	randomize()
	_target_angle = randf_range(0.0, TAU)
	direction = Vector2.from_angle(_target_angle)
	EventBus.hour_passed.connect(_on_hour)

func _on_hour(hour: int) -> void:
	if debug_locked:
		return
	if hour % change_interval_hours == 0:
		_target_angle += randf_range(-PI / 3.0, PI / 3.0)
		strength = clampf(strength + randf_range(-0.3, 0.3), 0.2, 2.0)

## Point the wind a specific way (debug). dir: Vector2 (x east, y south); the
## wind will blow *toward* it. Smoothly rotates there and stays put.
func set_direction_to(dir: Vector2) -> void:
	if dir.length() < 0.001:
		return
	_target_angle = dir.angle()

func _process(delta: float) -> void:
	# Smoothly rotate toward target
	var current := direction.angle()
	var new_angle := lerp_angle(current, _target_angle, delta * 0.1)
	direction = Vector2.from_angle(new_angle)

## How aligned is a ship heading (XZ forward) with the wind? 1 tailwind, -1 headwind.
func alignment(ship_forward: Vector3) -> float:
	var fwd2 := Vector2(ship_forward.x, ship_forward.z).normalized()
	return fwd2.dot(direction)

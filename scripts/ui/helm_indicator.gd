class_name HelmIndicator
extends Control
## Steering-wheel readout: the ship's-wheel sprite, rotated by the helm (ship.wheel).
## Centered helm = upright; turning the wheel spins the sprite. A fixed gold notch at
## the top is a reference so you can read how hard the helm is over.

var ship: ShipController
const MAX_ANGLE := 2.6  # radians of wheel rotation at full lock (~150 degrees)
const WHEEL_TEX := preload("res://assets/UI/wheel_ship_1.png")

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var c := size / 2.0
	var ang := 0.0
	if ship:
		ang = -ship.wheel * MAX_ANGLE
	# Fit the wheel sprite into the control, centred, and spin it with the helm.
	var tex_size := Vector2(WHEEL_TEX.get_size())
	var fit := minf(size.x, size.y)
	var s := fit / maxf(tex_size.x, tex_size.y)
	draw_set_transform(c, ang, Vector2(s, s))
	draw_texture(WHEEL_TEX, -tex_size / 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Fixed reference notch at the top (doesn't move).
	var r := fit / 2.0 - 6.0
	draw_line(c + Vector2(0.0, -r), c + Vector2(0.0, -r + 9.0), Color(0.9, 0.7, 0.2), 3.0)

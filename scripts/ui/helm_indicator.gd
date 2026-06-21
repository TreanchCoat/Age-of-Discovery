class_name HelmIndicator
extends Control
## Greybox steering-wheel readout: a circle with a cross inside that rotates with
## the ship's helm (ship.wheel). Centered helm = upright "+"; turning the wheel
## spins the cross, with a fixed gold notch at the top as a reference point.

var ship: ShipController
const MAX_ANGLE := 2.6  # radians of cross rotation at full lock (~150 degrees)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 6.0
	var rim := Color(0.95, 0.95, 0.92, 0.9)
	# Wheel rim
	draw_arc(c, r, 0.0, TAU, 64, rim, 3.0, true)
	# Fixed reference notch at the top (doesn't move)
	draw_line(c + Vector2(0.0, -r), c + Vector2(0.0, -r + 9.0), Color(0.9, 0.7, 0.2), 3.0)
	# Rotating cross (four spokes 90 degrees apart)
	var ang := 0.0
	if ship:
		ang = -ship.wheel * MAX_ANGLE
	for k in 4:
		var a := ang + float(k) * (PI / 2.0)
		draw_line(c, c + Vector2(cos(a), sin(a)) * r, rim, 3.0)
	# Hub
	draw_circle(c, 5.0, rim)

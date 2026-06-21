class_name CompassUI
extends Control
## Compass: a fixed N/E/S/W rose (north = world -Z, up) with a red needle that
## points along the ship's heading (the bow direction).

var ship: Node3D

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 12.0
	var rim := Color(0.9, 0.9, 0.85, 0.9)
	# Background disc + rim
	draw_circle(c, r + 8.0, Color(0.05, 0.08, 0.12, 0.75))
	draw_arc(c, r, 0.0, TAU, 48, rim, 2.0, true)

	# Cardinal letters
	var font := ThemeDB.fallback_font
	var fs := 13
	_label(font, fs, "N", c + Vector2(0.0, -r), Color(0.9, 0.5, 0.4))
	_label(font, fs, "S", c + Vector2(0.0, r), rim)
	_label(font, fs, "E", c + Vector2(r, 0.0), rim)
	_label(font, fs, "W", c + Vector2(-r, 0.0), rim)

	# Heading needle
	if ship == null:
		return
	var fwd := -ship.global_transform.basis.z
	var hv := Vector2(fwd.x, fwd.z)
	if hv.length() < 0.01:
		return
	hv = hv.normalized()
	draw_line(c - hv * (r - 16.0), c + hv * (r - 4.0), Color(0.9, 0.25, 0.2), 3.0)
	draw_circle(c, 3.0, rim)

func _label(font: Font, fs: int, s: String, at: Vector2, col: Color) -> void:
	var sz := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, Vector2(at.x - sz.x / 2.0, at.y + fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

class_name MinimapUI
extends Control
## Always-on minimap (top-right). North-up, centered on the player: the player is
## a triangle in the middle pointing along its heading; cities are dots placed
## relative to the player (clamped to the edge when out of range).

var ship: Node3D
var wind: WindSystem
@export var range_units := 1400.0   # world units from map center to its edge
@export var map_texture: Texture2D = null      # terrain image drawn as the background
@export var world_size := Vector2(3236.0, 4000.0)  # world units the map texture spans (X,Z)
@export var world_center := Vector2(0.0, 0.0)      # world XZ at the centre of the map texture

var _ports: Array[PortDef] = []

func _ready() -> void:
	var dir := DirAccess.open("res://data/ports")
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".tres"):
			var p := load("res://data/ports/" + file) as PortDef
			if p:
				_ports.append(p)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var c := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - 4.0
	var pps := radius / range_units   # pixels per world unit

	# Background: the terrain map, windowed to the area around the ship (north-up),
	# so you can read your position against the real coastline. Falls back to a panel.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.08, 0.12, 0.85))
	if ship and map_texture:
		var sp0 := ship.global_position
		var tex := Vector2(map_texture.get_size())
		var win := range_units * 2.0
		var u0 := (sp0.x - range_units - world_center.x) / world_size.x + 0.5
		var v0 := (sp0.z - range_units - world_center.y) / world_size.y + 0.5
		var src := Rect2(u0 * tex.x, v0 * tex.y, (win / world_size.x) * tex.x, (win / world_size.y) * tex.y)
		draw_texture_rect_region(map_texture, Rect2(Vector2.ZERO, size), src, Color(1, 1, 1, 0.85))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.9, 0.85, 0.5), false, 2.0)

	if ship == null:
		return
	var sp := ship.global_position

	# City dots (world x -> right, world z -> down). Clamp to edge if out of range.
	for p in _ports:
		var rel := Vector2(p.world_position.x - sp.x, p.world_position.z - sp.z) * pps
		if rel.length() > radius:
			rel = rel.normalized() * radius
		draw_circle(c + rel, 4.0, Color(0.35, 0.55, 0.95))

	# Player triangle at center, pointing along the ship's heading
	var fwd := -ship.global_transform.basis.z
	var ang := atan2(fwd.z, fwd.x)
	var tri := PackedVector2Array([
		c + Vector2(9.0, 0.0).rotated(ang),
		c + Vector2(-6.0, 6.0).rotated(ang),
		c + Vector2(-6.0, -6.0).rotated(ang),
	])
	draw_colored_polygon(tri, Color(0.95, 0.85, 0.3))

	# Wind indicator (top-left corner): a cyan arrow pointing the way the wind blows.
	if wind and wind.direction.length() > 0.01:
		var o := Vector2(15.0, 15.0)
		var d := wind.direction.normalized()
		var tip := o + d * 9.0
		var wcol := Color(0.45, 0.85, 1.0)
		draw_line(o - d * 9.0, tip, wcol, 2.0)
		draw_line(tip, tip - d.rotated(0.5) * 5.0, wcol, 2.0)
		draw_line(tip, tip - d.rotated(-0.5) * 5.0, wcol, 2.0)

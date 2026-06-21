class_name WorldMapUI
extends CanvasLayer
## Toggleable world map (M key, action "toggle_map") with fog of war.
##
## Fog: an Image-backed texture; as the ship sails, circles are punched
## transparent around its position. Revealed area persists via GameState.flags
## (stored as compressed PNG bytes, so it saves/loads with everything else).
##
## Background: currently a flat "parchment" color — an empty map, as designed.
## When you have real map art, set `map_texture` and it draws underneath the fog.

@export var map_texture: Texture2D = null     # future: real map art
@export var world_extent := 2000.0            # world units from center to map edge
@export var fog_resolution := 512             # fog image size (px)
@export var reveal_radius_px := 14            # px revealed around ship per update

var _root: Control
var _map_rect: Control
var _fog_image: Image
var _fog_texture: ImageTexture
var _markers: Control
var _ship_marker: Polygon2D
var _ship: Node3D = null

func _ready() -> void:
	layer = 20
	_init_fog()
	_build_ui()
	_root.hide()
	EventBus.discovery_made.connect(func(_id): _rebuild_markers())
	# Reveal fog around the ship once per game hour (cheap, good enough).
	EventBus.hour_passed.connect(func(_h): _reveal_at_ship())

func register_ship(ship: Node3D) -> void:
	_ship = ship
	_reveal_at_ship()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		_root.visible = not _root.visible
		if _root.visible:
			_reveal_at_ship()
			_rebuild_markers()
			_fog_texture.update(_fog_image)

## --- Fog -----------------------------------------------------------------

func _init_fog() -> void:
	var saved: PackedByteArray = GameState.flags.get("fog_png", PackedByteArray())
	_fog_image = Image.new()
	if saved.is_empty() or _fog_image.load_png_from_buffer(saved) != OK:
		_fog_image = Image.create(fog_resolution, fog_resolution, false, Image.FORMAT_RGBA8)
		_fog_image.fill(Color(0.05, 0.05, 0.08, 0.95))
	_fog_texture = ImageTexture.create_from_image(_fog_image)

func _reveal_at_ship() -> void:
	if _ship == null:
		return
	var px := _world_to_fog_px(_ship.global_position)
	var r := reveal_radius_px
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y > r * r:
				continue
			var p := px + Vector2i(x, y)
			if p.x < 0 or p.y < 0 or p.x >= fog_resolution or p.y >= fog_resolution:
				continue
			# soft edge: outer 30% of the circle only thins the fog
			var d := sqrt(float(x * x + y * y)) / float(r)
			var current := _fog_image.get_pixelv(p)
			var target_a := 0.0 if d < 0.7 else current.a * 0.5
			current.a = minf(current.a, target_a)
			_fog_image.set_pixelv(p, current)
	_fog_texture.update(_fog_image)
	GameState.flags["fog_png"] = _fog_image.save_png_to_buffer()

func _world_to_fog_px(world_pos: Vector3) -> Vector2i:
	var u := (world_pos.x / world_extent + 1.0) * 0.5
	var v := (world_pos.z / world_extent + 1.0) * 0.5
	return Vector2i(int(u * fog_resolution), int(v * fog_resolution))

func _world_to_map_pos(world_pos: Vector3) -> Vector2:
	var size := _map_rect.size
	var u := (world_pos.x / world_extent + 1.0) * 0.5
	var v := (world_pos.z / world_extent + 1.0) * 0.5
	return Vector2(u * size.x, v * size.y)

## --- UI ------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	_map_rect = AspectRatioContainer.new()
	_map_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	(_map_rect as AspectRatioContainer).ratio = 1.0
	_root.add_child(_map_rect)

	var stack := Control.new()
	stack.custom_minimum_size = Vector2(600, 600)
	_map_rect.add_child(stack)
	_map_rect = stack  # markers/fog positioned relative to this square

	# Background: real map art if provided, otherwise empty parchment.
	if map_texture:
		var tex := TextureRect.new()
		tex.texture = map_texture
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stack.add_child(tex)
	else:
		var parchment := ColorRect.new()
		parchment.color = Color(0.82, 0.74, 0.58)
		parchment.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(parchment)

	_markers = Control.new()
	_markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_markers)

	var fog_rect := TextureRect.new()
	fog_rect.texture = _fog_texture
	fog_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fog_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stack.add_child(fog_rect)

	var hint := Label.new()
	hint.text = "World Map — M to close"
	hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_root.add_child(hint)

func _rebuild_markers() -> void:
	for c in _markers.get_children():
		c.queue_free()

	# Ports (always shown — captains know where ports are; fog still covers them
	# visually until visited, which reads as "heard of it, haven't been")
	var dir := DirAccess.open("res://data/ports")
	if dir:
		for file in dir.get_files():
			if file.ends_with(".tres"):
				var port := load("res://data/ports/" + file) as PortDef
				_add_marker(port.world_position, port.display_name, Color(0.2, 0.3, 0.7))

	# Found discoveries only
	for def in DiscoveryDB.all_defs():
		if DiscoveryDB.is_found(def.id):
			_add_marker(def.world_position, def.display_name, Color(0.8, 0.6, 0.1))

	# Ship
	if _ship:
		_ship_marker = Polygon2D.new()
		_ship_marker.polygon = PackedVector2Array([Vector2(0, -8), Vector2(5, 6), Vector2(-5, 6)])
		_ship_marker.color = Color(0.85, 0.15, 0.15)
		_ship_marker.position = _world_to_map_pos(_ship.global_position)
		_ship_marker.rotation = _ship.rotation.y * -1.0
		_markers.add_child(_ship_marker)

func _add_marker(world_pos: Vector3, text: String, color: Color) -> void:
	var dot := ColorRect.new()
	dot.color = color
	dot.size = Vector2(8, 8)
	dot.position = _world_to_map_pos(world_pos) - Vector2(4, 4)
	_markers.add_child(dot)
	var l := Label.new()
	l.text = text
	l.position = dot.position + Vector2(10, -6)
	l.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	_markers.add_child(l)

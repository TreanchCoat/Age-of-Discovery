class_name CityScene
extends Node3D
## A city: ONE scene, TWO modes.
##
##  - SEA VIEW (default): the buildings are visible so the skyline reads from
##    the water. Street-level extras (ground apron colliders, future props/NPCs)
##    live under the StreetLevel node, which stays disabled.
##  - STREET MODE: StreetLevel enabled + a CityPlayer spawned at PlayerSpawn.
##    Entered via enter_street_mode() — eventually called by the docking flow;
##    for now, running a city scene directly (F6) auto-enters for testing.
##
## Structure expected (built in city_*.tscn):
##   CityScene (this script)
##   ├── Buildings/          CityBuilding nodes — always visible (the skyline)
##   └── StreetLevel/        disabled at sea: Ground, PlayerSpawn (Marker3D),
##                           future props/NPCs/colliders
##
## Future LOD note (PROJECT_PLAN §4 Layer 3): Buildings get visibility_range
## tiers / a merged far-mass; StreetLevel stays gated behind street mode.

@export var city_id: StringName = &""
@export var display_name := ""
## Buildings are scaled up in sea view so the skyline holds its own next to the
## ship, and back to human scale (1.0) when you walk the streets.
@export var sea_view_scale := 2.5

var _street_level: Node3D
var _buildings: Node3D
var _player: CityPlayer
var _toast: Label
var _return_btn: Button
var _toast_timer: SceneTreeTimer

func _ready() -> void:
	_street_level = get_node_or_null(^"StreetLevel")
	_buildings = get_node_or_null(^"Buildings")
	_set_street_active(false)
	# Standalone run (F6 on the city scene): jump straight into street mode.
	if get_tree().current_scene == self:
		_make_test_environment()
		enter_street_mode()

func is_street_mode() -> bool:
	return _player != null

func enter_street_mode() -> void:
	if _player:
		return
	_set_street_active(true)
	_player = CityPlayer.new()
	add_child(_player)
	var spawn := get_node_or_null(^"StreetLevel/PlayerSpawn") as Node3D
	_player.global_position = spawn.global_position if spawn else global_position + Vector3.UP * 2.0
	_make_toast_ui()
	# "Return to ship" only makes sense when entered from the game (docked);
	# in a standalone F6 run the button still shows but city_left has no listener.
	if _return_btn:
		_return_btn.show()

func exit_street_mode() -> void:
	if _player == null:
		return
	_player.queue_free()
	_player = null
	_set_street_active(false)
	if _return_btn:
		_return_btn.hide()
	EventBus.city_left.emit(city_id)

func _set_street_active(active: bool) -> void:
	# Sea view: big skyline. Street: human scale.
	if _buildings:
		_buildings.scale = Vector3.ONE if active else Vector3.ONE * sea_view_scale
	if _street_level == null:
		return
	_street_level.visible = active
	_street_level.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	# Collisions on disabled ground would still block the ship if it clipped the
	# coast, so keep StreetLevel colliders out of the way while at sea.
	for body in _street_level.find_children("*", "CollisionShape3D", true, false):
		(body as CollisionShape3D).disabled = not active
	for csg in _street_level.find_children("*", "CSGShape3D", true, false):
		(csg as CSGShape3D).use_collision = active

## Small message line for building interactions ("Bank — not yet open").
func show_toast(text: String) -> void:
	if _toast == null:
		_make_toast_ui()
	_toast.text = text
	_toast.show()
	_toast_timer = get_tree().create_timer(2.5)
	_toast_timer.timeout.connect(func():
		if _toast:
			_toast.hide())

func _make_toast_ui() -> void:
	if _toast:
		return
	var layer := CanvasLayer.new()
	layer.name = "CityUI"
	add_child(layer)
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position.y -= 80
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.hide()
	layer.add_child(_toast)
	_return_btn = Button.new()
	_return_btn.text = "Return to ship"
	_return_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_return_btn.position = Vector2(12, 60)
	_return_btn.pressed.connect(exit_street_mode)
	layer.add_child(_return_btn)

## Minimal sun+sky+ground fallback so F6 test runs aren't pitch black.
func _make_test_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	env.environment = e
	add_child(env)

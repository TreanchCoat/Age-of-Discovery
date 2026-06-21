class_name SpyglassUI
extends CanvasLayer
## Makes discovery confirmation a small skill minigame instead of a keypress.
##
## Flow:
##  1. Ship enters a DiscoveryArea -> "Something on the horizon..." banner.
##  2. Player presses observe (E) -> spyglass overlay opens, game pauses.
##  3. A drifting focus ring wanders; the player presses E when the ring is
##     inside the sweet-spot circle. Sweet spot size scales with observation
##     skill; ring speed scales with the discovery difficulty.
##  4. Hit -> DiscoveryDB.confirm() (which still applies the skill roll bonus:
##     a good lens-up grants +10 to the roll). Miss -> ring resets, 3 tries.
##
## Replaces ShipController._try_observe — that fallback still works if this UI
## is absent from the scene.

@export var ship: Node3D

var _banner: Label
var _overlay: Control
var _ring: Control
var _sweet: Control
var _active_id: StringName = &""
var _tries := 0
var _angle := 0.0
var _ring_pos := Vector2.ZERO
var _ring_vel := Vector2.ZERO

const MAX_TRIES := 3
const VIEW_SIZE := 380.0

func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	EventBus.discovery_spotted.connect(_on_spotted)
	EventBus.discovery_made.connect(func(_id): _close())

func _build_ui() -> void:
	_banner = Label.new()
	_banner.text = "Something on the horizon... (E to raise the spyglass)"
	_banner.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_banner.position.y -= 60
	_banner.hide()
	add_child(_banner)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.hide()
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	# circular "lens" area
	var lens := Panel.new()
	lens.custom_minimum_size = Vector2(VIEW_SIZE, VIEW_SIZE)
	lens.set_anchors_preset(Control.PRESET_CENTER)
	_overlay.add_child(lens)

	_sweet = ColorRect.new()
	_sweet.color = Color(0.9, 0.8, 0.2, 0.35)
	lens.add_child(_sweet)

	_ring = ColorRect.new()
	_ring.color = Color(0.9, 0.2, 0.2, 0.8)
	_ring.size = Vector2(26, 26)
	lens.add_child(_ring)

	var hint := Label.new()
	hint.text = "Steady... press E when the red mark sits in the gold circle"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position.y -= 20
	_overlay.add_child(hint)

func _on_spotted(id: StringName) -> void:
	_active_id = id
	_banner.show()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("observe") or _active_id == &"":
		return
	if _overlay.visible:
		_attempt()
	elif _in_range():
		_open()

func _in_range() -> bool:
	var def := DiscoveryDB.get_def(_active_id)
	return def and ship and ship.global_position.distance_to(def.world_position) <= def.spot_radius * 1.2

func _open() -> void:
	var def := DiscoveryDB.get_def(_active_id)
	_tries = MAX_TRIES
	# Sweet spot: bigger with skill, smaller with difficulty.
	var skill := GameState.stats.observation
	var radius := clampf(40.0 + skill * 3.0 - def.difficulty * 1.5, 25.0, 90.0)
	_sweet.size = Vector2(radius, radius) * 2.0
	_sweet.position = Vector2(VIEW_SIZE / 2.0 - radius, VIEW_SIZE / 2.0 - radius)
	_ring_pos = Vector2(VIEW_SIZE / 2.0, VIEW_SIZE / 2.0)
	_ring_vel = Vector2.from_angle(randf_range(0, TAU)) * (60.0 + def.difficulty * 8.0)
	_banner.hide()
	_overlay.show()
	get_tree().paused = true

func _process(delta: float) -> void:
	if not _overlay.visible:
		return
	# Wandering drift: velocity slowly rotates + bounces off lens edges.
	_angle += delta
	_ring_vel = _ring_vel.rotated(sin(_angle * 1.7) * delta * 2.0)
	_ring_pos += _ring_vel * delta
	var margin := 13.0
	if _ring_pos.x < margin or _ring_pos.x > VIEW_SIZE - margin:
		_ring_vel.x *= -1.0
	if _ring_pos.y < margin or _ring_pos.y > VIEW_SIZE - margin:
		_ring_vel.y *= -1.0
	_ring_pos = _ring_pos.clamp(Vector2(margin, margin), Vector2(VIEW_SIZE - margin, VIEW_SIZE - margin))
	_ring.position = _ring_pos - _ring.size / 2.0

func _attempt() -> void:
	var sweet_center := _sweet.position + _sweet.size / 2.0
	var hit := _ring_pos.distance_to(sweet_center) <= _sweet.size.x / 2.0
	if hit:
		if DiscoveryDB.confirm(_active_id, 10):
			_active_id = &""
			_close()
			return
	_tries -= 1
	if _tries <= 0:
		# It slips away for now — re-enter the area to try again.
		DiscoveryDB.spotted.erase(_active_id)
		_active_id = &""
		_close()

func _close() -> void:
	_overlay.hide()
	_banner.hide()
	get_tree().paused = false

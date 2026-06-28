class_name ShipController
extends CharacterBody3D
## Player ship at sea. Age-of-sail feel: you steer; speed comes from sails + wind.
## Two sails, each toggled fully up/down independently and added together:
##   horizontal sail (square) — thrives with the wind astern; fades to nothing upwind
##   vertical sail (fore-and-aft) — thrives on the beam, keeps some thrust astern
## Both sails down -> no power -> the ship coasts to a stop.
## Input actions (set in project.godot):
##   turn_left (A), turn_right (D), toggle_horizontal_sail (F), toggle_vertical_sail (G), observe (E)

@export var wind: WindSystem  # assign in editor (node in World scene)

const SPEED_SCALE := 1.0  # knots -> world units/sec; tune to world scale
const WHEEL_TURN_RATE := 0.75   # how fast the helm swings to the held side (per sec)
const WHEEL_RETURN_RATE := 0.3  # how fast the helm drifts back to center when released (heavier = lower)
const MIN_STEERAGE := 0.3       # lowest turn authority even when stalled, so you can never get stuck in irons
const PACE_GAIN := 0.05         # speed fraction regained per second while sailing straight (+5%/s)
const PACE_TURN_LOSS := 0.08    # speed fraction bled per second while actively turning
const SAIL_CHANGE_RATE := 0.5   # how fast a sail raises/furls (per sec); furling decays thrust
const ZOOM_STEP := 0.12         # camera zoom change per mouse-wheel notch
const ZOOM_MIN := 0.5           # closest (0.5x the default chase offset)
const ZOOM_MAX := 2.5           # farthest
const SHALLOW_SPEED_MULT := 0.5     # how much shallows slow you (0.5 = half speed)
const SHALLOW_DAMAGE_PER_SEC := 1.5 # hull lost per second while scraping shallows
const LAND_DAMAGE_PER_SEC := 1.2    # hull lost per second of coast contact, scaled by speed
const COAST_NUDGE := 4.0            # sideways slide along the coast on a head-on bump

var horizontal_sail := 0.0          # actual set amount 0..1 (eases toward its target)
var horizontal_sail_target := 0.0   # commanded by the F key (toggled up/down)
var vertical_sail := 0.0
var vertical_sail_target := 0.0    # commanded by the G key
var current_speed := 0.0
var wheel := 0.0          # helm: -1 hard a-starboard .. 0 centered .. +1 hard a-port
var pace := 0.5           # speed fraction 0.5 .. 1.0: builds underway, bleeds when turning/stopped
var use_fallback_observe := true  # set false when SpyglassUI handles observing

var _camera: Camera3D
var _cam_base := Vector3.ZERO  # default chase-camera offset; scaled by zoom
var _zoom := 1.0
var _shallow_zones := 0        # how many shallow-water areas the ship is inside
var _scrape_accum := 0.0       # fractional hull damage waiting to be applied

func enter_shallows() -> void:
	_shallow_zones += 1

func exit_shallows() -> void:
	_shallow_zones = maxi(_shallow_zones - 1, 0)

func _ready() -> void:
	# Docking takes the ship off the water (hull hidden, controls frozen) while you
	# trade; "set sail" puts it back just outside the harbor and hands you the helm.
	EventBus.port_entered.connect(_on_dock)
	EventBus.undock_requested.connect(_on_undock)
	for child in get_children():
		if child is Camera3D:
			_camera = child
			_cam_base = child.position
			break

func _on_dock(_port_id: StringName) -> void:
	set_at_sea(false)

func _on_undock() -> void:
	# Respawn just outside the harbor we docked at, facing back out to open water.
	var port_id := GameState.current_port
	if port_id != &"":
		var port := load("res://data/ports/%s.tres" % String(port_id)) as PortDef
		if port:
			var away := global_position - port.world_position
			away.y = 0.0
			if away.length() < 1.0:
				away = -global_transform.basis.z
				away.y = 0.0
			global_position = port.world_position + away.normalized() * 70.0 + Vector3.UP * 1.5
			# Face back toward port, but keep the look target level so the hull
			# stays flat on the water (a lower target would pitch the bow down).
			var target := port.world_position
			target.y = global_position.y
			look_at(target, Vector3.UP)
	GameState.current_port = &""
	set_at_sea(true)

## Toggle the ship between "at sea" (visible, controllable) and "docked"
## (hull hidden, frozen). The chase camera stays active either way.
func set_at_sea(active: bool) -> void:
	set_physics_process(active)
	set_process_unhandled_input(active)
	# Hide every hull mesh, including those nested under the buoyancy HullPivot.
	_set_meshes_visible(self, active)
	if not active:
		horizontal_sail = 0.0
		horizontal_sail_target = 0.0
		vertical_sail = 0.0
		vertical_sail_target = 0.0
		current_speed = 0.0
		wheel = 0.0
		pace = 0.5
		velocity = Vector3.ZERO

## Toggle visibility of all MeshInstance3D descendants (hull may be nested under HullPivot).
func _set_meshes_visible(node: Node, v: bool) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.visible = v
		_set_meshes_visible(child, v)

func _physics_process(delta: float) -> void:
	var state := GameState.ship
	if state == null:
		return

	# Sails ease toward their commanded state, so furling lets thrust decay over
	# a moment instead of cutting out instantly.
	horizontal_sail = move_toward(horizontal_sail, horizontal_sail_target, SAIL_CHANGE_RATE * delta)
	vertical_sail = move_toward(vertical_sail, vertical_sail_target, SAIL_CHANGE_RATE * delta)

	# Helm: A/D swing the wheel toward that side; let go and it springs back to center.
	var helm_input := Input.get_axis("turn_right", "turn_left")
	var turning := absf(helm_input) > 0.01
	if turning:
		wheel = clampf(wheel + helm_input * WHEEL_TURN_RATE * delta, -1.0, 1.0)
	else:
		wheel = move_toward(wheel, 0.0, WHEEL_RETURN_RATE * delta)

	# Pace (50%..100%): builds only while actually making way with a sail set and
	# steering straight; bleeds while turning; falls back to 50% when stopped or
	# when both sails are commanded down.
	var sails_set := horizontal_sail_target > 0.5 or vertical_sail_target > 0.5
	if not sails_set or current_speed < 0.1:
		pace = move_toward(pace, 0.5, PACE_GAIN * delta)
	elif turning:
		pace = maxf(pace - PACE_TURN_LOSS * delta, 0.5)
	else:
		pace = minf(pace + PACE_GAIN * delta, 1.0)

	# Turning scales with speed, but never drops below MIN_STEERAGE so a stalled
	# ship can always crawl its bow off the wind instead of getting stuck in irons.
	var turn_factor := clampf(current_speed / 4.0, MIN_STEERAGE, 1.0)
	rotate_y(wheel * state.def.turn_rate * delta * turn_factor * pace)

	# Speed: each raised sail adds power scaled by how well it suits the wind angle.
	# Both down -> sail power 0. Pace ramps the result from 50% up to 100% underway.
	var align := wind.alignment(-global_transform.basis.z) if wind else 1.0
	var wind_str := wind.strength if wind else 1.0
	var target_speed := state.effective_speed(align, horizontal_sail, vertical_sail) * wind_str * SPEED_SCALE * pace
	if _shallow_zones > 0:
		target_speed *= SHALLOW_SPEED_MULT          # shallows drag you down
	current_speed = move_toward(current_speed, target_speed, delta * 2.0)

	velocity = -global_transform.basis.z * current_speed
	velocity.y = 0.0  # the sea is flat for now: never let the bow drive us under
	move_and_slide()

	# Damage: scraping shallows (slow drain) and hitting the coast (impact + nudge).
	if _shallow_zones > 0:
		_scrape_accum += SHALLOW_DAMAGE_PER_SEC * delta
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var hit := col.get_collider() as Node
		if hit and hit.is_in_group("land"):
			_scrape_accum += LAND_DAMAGE_PER_SEC * (0.3 + current_speed) * delta
			# Nudge along the coast so a head-on bump slides off instead of dead-stopping.
			var n := col.get_normal()
			var tangent := Vector3(-n.z, 0.0, n.x).normalized()
			if tangent.dot(-global_transform.basis.z) < 0.0:
				tangent = -tangent
			global_position += tangent * COAST_NUDGE * delta
			current_speed *= 0.9                      # grind off speed on contact
	if _scrape_accum >= 1.0:
		var whole := int(_scrape_accum)
		_scrape_accum -= float(whole)
		state.take_damage(whole)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_horizontal_sail"):
		horizontal_sail_target = 0.0 if horizontal_sail_target > 0.5 else 1.0
	if event.is_action_pressed("toggle_vertical_sail"):
		vertical_sail_target = 0.0 if vertical_sail_target > 0.5 else 1.0
	if event.is_action_pressed("observe") and use_fallback_observe:
		_try_observe()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_zoom(-ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_zoom(ZOOM_STEP)

func _apply_zoom(amount: float) -> void:
	if _camera == null:
		return
	_zoom = clampf(_zoom + amount, ZOOM_MIN, ZOOM_MAX)
	_camera.position = _cam_base * _zoom

func _try_observe() -> void:
	# Attempt to confirm any spotted discovery still in range.
	for id in DiscoveryDB.spotted.keys():
		var def := DiscoveryDB.get_def(id)
		if def and global_position.distance_to(def.world_position) <= def.spot_radius * 1.2:
			DiscoveryDB.confirm(id)

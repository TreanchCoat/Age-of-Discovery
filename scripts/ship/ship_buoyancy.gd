class_name ShipBuoyancy
extends Node
## Kinematic buoyancy: makes the *visible* hull conform to the FFT ocean surface
## without ever touching the physics body's transform.
##
## Why a separate visual pivot? ShipController drives thrust off the body's basis
## (`velocity = -basis.z * speed`) and steers with `rotate_y`. If we pitched/rolled
## the CharacterBody3D itself, its forward vector would tilt out of horizontal and
## sailing speed/steering would quietly corrupt. So:
##   - heave + pitch + roll are applied to `hull_pivot` (a Node3D wrapping the mesh)
##   - the body, its collision shape and the chase camera stay level
## That keeps thrust horizontal and the camera nausea-free (it inherits neither the
## tilt nor, by default, the bob).
##
## Surface height comes from `ocean.get_height(world_pos)` (the FFT readback). It
## returns 0.0 until the first GPU->CPU readback lands, so the hull simply rests at
## its spawn height for a frame or two — no special-casing needed.

@export var ocean: Node3D       # the Water node (must expose get_height(world_pos))
@export var hull_pivot: Node3D  # Node3D wrapping the hull mesh; we heave/tilt THIS
@export var ship: Node3D        # the ship root (frame of reference for the probes)
@export var wind: WindSystem    # optional: sea state -> tilt amount

@export_group("Hull dimensions")
## Bow-to-stern probe span (match the hull mesh Z). Probes sit at +/- half this.
@export var length := 12.0
## Port-to-starboard probe span (match the hull mesh X).
@export var beam := 4.0
## Vertical offset added to the sampled waterline (raise so the deck rides above water).
@export var draft := 1.5

@export_group("Feel")
## Clamp pitch/roll so she works the swell instead of capsizing on steep crests.
@export var max_tilt_deg := 10.0
## Vertical follow stiffness (higher = snappier heave).
@export var heave_smooth := 6.0
## Tilt follow stiffness (higher = snappier pitch/roll).
@export var tilt_smooth := 5.0
## Wind strength at/below which tilt flattens out (dead-calm => no list).
@export var calm_strength := 0.15
@export var enabled := true

var _heave := 0.0
var _pitch := 0.0
var _roll := 0.0
var _warned := false

func _physics_process(delta: float) -> void:
	if not enabled or ocean == null or hull_pivot == null or ship == null:
		return
	# While docked the ship stops physics-processing (set_at_sea(false)) and the hull
	# is hidden — don't bob a parked, invisible ship.
	if not ship.is_physics_processing():
		return
	if not ocean.has_method("get_height"):
		if not _warned:
			push_warning("ShipBuoyancy: ocean has no get_height(); buoyancy disabled.")
			_warned = true
		return

	# Sea-state scale: ~0 in a calm, 1 at full wind strength. Tilt only (heave always
	# pins the hull to the live surface so it never floats above flat water).
	var sea := 1.0
	if wind != null:
		sea = clampf((wind.strength - calm_strength) / maxf(0.001, 1.0 - calm_strength), 0.0, 1.0)

	# Probe in the ship's horizontal frame. The body is yaw-only (we never tilt it),
	# so its basis axes are already flat — no need to project.
	var origin := ship.global_position
	var fwd := -ship.global_transform.basis.z
	var right := ship.global_transform.basis.x
	var hl := length * 0.5
	var hb := beam * 0.5

	var bow := ocean.get_height(origin + fwd * hl)
	var stern := ocean.get_height(origin - fwd * hl)
	var star := ocean.get_height(origin + right * hb)
	var port := ocean.get_height(origin - right * hb)

	var avg := (bow + stern + star + port) * 0.25
	var lim := deg_to_rad(max_tilt_deg)
	# Pivot local axes align with the ship: rotation.x = pitch (bow up +), .z = roll
	# (starboard up +). atan2(height-diff, span) gives the surface slope angle.
	var pitch_t := clampf(atan2(bow - stern, length), -lim, lim) * sea
	var roll_t := clampf(atan2(star - port, beam), -lim, lim) * sea
	var heave_t := (avg + draft) - ship.global_position.y

	# Frame-rate-independent smoothing toward the targets.
	_heave = lerp(_heave, heave_t, 1.0 - exp(-heave_smooth * delta))
	_pitch = lerp(_pitch, pitch_t, 1.0 - exp(-tilt_smooth * delta))
	_roll = lerp(_roll, roll_t, 1.0 - exp(-tilt_smooth * delta))

	hull_pivot.position.y = _heave
	hull_pivot.rotation = Vector3(_pitch, 0.0, _roll)

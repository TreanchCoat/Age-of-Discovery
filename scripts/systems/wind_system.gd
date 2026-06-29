class_name WindSystem
extends Node
## Global wind that drifts over time. Add one to the World scene.
## Direction is a unit Vector2 on the XZ plane (x = east, y = south/+z).

@export var change_interval_hours: int = 3
@export var strength: float = 1.0  # 0 calm .. 2 storm

var direction := Vector2.RIGHT
var debug_locked := false  # when true, ignore natural drift (set by the debug UI)

var _target_angle := 0.0

# --- Ocean coupling: this same wind drives the FFT waves (one wind, not two). ---
const WAVE_UPDATE_INTERVAL := 0.5
@export var drive_waves := true   # uncheck in the debug panel to tune waves by hand
@export var wave_size := 1.0      # global multiplier on every cascade's wave height
@export var wave_angle_offset_deg := 0.0  # rotate the waves to line up with the wind arrow (calibration)
var _ocean = null
var _cascades: Array = []          # WaveCascadeParameters pulled from the ocean
var _base_wind_speeds: Array = []  # each cascade's tuned wind_speed at load (calm baseline)
var _base_displacement_scales: Array = []  # each cascade's tuned wave height at load
var _wave_accum := 0.0

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

	# Drive the ocean from this same wind (throttled — changing a cascade's wind
	# regenerates its spectrum, so we avoid doing it every frame).
	if drive_waves and not _cascades.is_empty():
		_wave_accum += delta
		if _wave_accum >= WAVE_UPDATE_INTERVAL:
			_wave_accum = 0.0
			_apply_to_ocean()

## How aligned is a ship heading (XZ forward) with the wind? 1 tailwind, -1 headwind.
func alignment(ship_forward: Vector3) -> float:
	var fwd2 := Vector2(ship_forward.x, ship_forward.z).normalized()
	return fwd2.dot(direction)

## Hand the wind the ocean it should drive. Caches each cascade's tuned wind_speed
## as the calm baseline, then keeps wind_direction/wind_speed synced to this wind.
func register_ocean(ocean) -> void:
	_ocean = ocean
	_cascades.clear()
	_base_wind_speeds.clear()
	_base_displacement_scales.clear()
	if ocean == null:
		return
	for p in ocean.parameters:
		_cascades.append(p)
		_base_wind_speeds.append(p.wind_speed)
		_base_displacement_scales.append(p.displacement_scale)
	_apply_to_ocean()
	_apply_wave_size()

func _apply_to_ocean() -> void:
	if _cascades.is_empty():
		return
	# +180: the FFT spectrum treats wind_direction as where waves come FROM, so without
	# this the swell ran opposite the gameplay wind (north wind -> waves heading south).
	var deg := rad_to_deg(direction.angle()) + 180.0 + wave_angle_offset_deg
	var str_scaled := clampf(strength, 0.3, 2.0)  # scale wave size with wind strength
	for i in _cascades.size():
		_cascades[i].wind_direction = deg
		_cascades[i].wind_speed = _base_wind_speeds[i] * str_scaled

## Global wave-height knob (debug). Scales every cascade off its tuned baseline,
## so 1.0 = as authored, 0 = flat, 2 = double height. Cheap: no spectrum regen.
func set_wave_size(v: float) -> void:
	wave_size = maxf(0.0, v)
	_apply_wave_size()

func _apply_wave_size() -> void:
	for i in _cascades.size():
		_cascades[i].displacement_scale = _base_displacement_scales[i] * wave_size

## Rotate the waves relative to the wind vector (debug calibration). Use this if the
## waves visually disagree with the minimap wind arrow; the offset is applied on top
## of the shared wind direction.
func set_wave_angle_offset(deg: float) -> void:
	wave_angle_offset_deg = deg
	_apply_to_ocean()

@tool
extends MeshInstance3D
## Handles updating the displacement/normal maps for the water material as well as
## managing wave generation pipelines.

const WATER_MAT := preload('res://assets/water/mat_water.tres')
const SPRAY_MAT := preload('res://assets/water/mat_spray.tres')
const WATER_MESH_HIGH8K := preload('res://assets/water/clipmap_high_8k.obj')
const WATER_MESH_HIGH := preload('res://assets/water/clipmap_high.obj')
const WATER_MESH_LOW := preload('res://assets/water/clipmap_low.obj')

enum MeshQuality { LOW, HIGH, HIGH8K }

@export_group('Wave Parameters')
@export_color_no_alpha var water_color : Color = Color(0.1, 0.15, 0.18) :
	set(value): water_color = value; RenderingServer.global_shader_parameter_set(&'water_color', water_color.srgb_to_linear())

@export_color_no_alpha var foam_color : Color = Color(0.73, 0.67, 0.62) :
	set(value): foam_color = value; RenderingServer.global_shader_parameter_set(&'foam_color', foam_color.srgb_to_linear())

## The parameters for wave cascades. Each parameter set represents one cascade.
## Recreates all compute piplines whenever a cascade is added or removed!
@export var parameters : Array[WaveCascadeParameters] :
	set(value):
		var new_size := len(value)
		# All below logic is basically just required for using in the editor!
		for i in range(new_size):
			# Ensure all values in the array have an associated cascade
			if not value[i]: value[i] = WaveCascadeParameters.new()
			if not value[i].is_connected(&'scale_changed', _update_scales_uniform):
				value[i].scale_changed.connect(_update_scales_uniform)
			value[i].spectrum_seed = Vector2i(rng.randi_range(-10000, 10000), rng.randi_range(-10000, 10000))
			value[i].time = 120.0 + PI*i # We make sure to choose a time offset such that cascades don't interfere!
		parameters = value
		_setup_wave_generator()
		_update_scales_uniform()
		_compute_used_cascades()  # 4.7: readback now runs on the render thread (see _process)

@export_group('Performance Parameters')

@export_enum('128x128:128', '256x256:256', '512x512:512', '1024x1024:1024') var map_size := 1024 :
	set(value):
		map_size = value
		_setup_wave_generator()

@export var mesh_quality := MeshQuality.HIGH :
	set(value):
		mesh_quality = value
		if mesh_quality == MeshQuality.LOW:
			mesh = WATER_MESH_LOW
		if mesh_quality == MeshQuality.HIGH:
			mesh = WATER_MESH_HIGH
		if mesh_quality == MeshQuality.HIGH8K:
			mesh = WATER_MESH_HIGH8K

## How many times the wave simulation should update per second.
## Note: This doesn't reduce the frame stutter caused by FFT calculation, only
##       minimizes GPU time taken by it!

@export_range(0, 60) var updates_per_second := 50.0 :
	set(value):
		next_update_time = next_update_time - (1.0/(updates_per_second + 1e-10) - 1.0/(value + 1e-10))
		updates_per_second = value

var wave_generator : WaveGenerator :
	set(value):
		if wave_generator: wave_generator.queue_free()
		wave_generator = value
		add_child(wave_generator)
var rng = RandomNumberGenerator.new()
var time := 0.0
var next_update_time := 0.0

var displacement_maps := Texture2DArrayRD.new()
var normal_maps := Texture2DArrayRD.new()

func _init() -> void:
	rng.set_seed(1234) # This seed gives big waves!

func _ready() -> void:
	RenderingServer.global_shader_parameter_set(&'water_color', water_color.srgb_to_linear())
	RenderingServer.global_shader_parameter_set(&'foam_color', foam_color.srgb_to_linear())

var update_textures:bool = true # 4.7: CPU readback (texture_get_data) is render-thread-only; we now run it via RenderingServer.call_on_render_thread so buoyancy (get_height) works. Set false to skip the readback entirely (visual ocean still renders).

var just_calculated_water:bool = false
func _process(delta : float) -> void:
	# Update waves once every 1.0/updates_per_second.
	just_calculated_water = false
	if updates_per_second == 0 or time >= next_update_time:
		var target_update_delta := 1.0 / (updates_per_second + 1e-10)
		var update_delta := delta if updates_per_second == 0 else target_update_delta + (time - next_update_time)
		next_update_time = time + target_update_delta
		_update_water(update_delta)
		just_calculated_water = true
	time += delta

	# Throttled GPU->CPU readback of the displacement maps so get_height() (buoyancy)
	# has fresh CPU data. texture_get_data is render-thread-only in 4.7, so the actual
	# read is dispatched onto the render thread. One frame of latency — fine for a boat.
	if update_textures and wave_generator != null:
		_readback_accum += delta
		if _readback_accum >= _readback_interval:
			_readback_accum = 0.0
			if _used_cascades.is_empty():
				_compute_used_cascades()
			RenderingServer.call_on_render_thread(_readback_displacements_render_thread)

func _setup_wave_generator() -> void:
	if parameters.size() <= 0: return
	for param in parameters:
		param.should_generate_spectrum = true

	wave_generator = WaveGenerator.new()
	wave_generator.map_size = map_size
	wave_generator.init_gpu(maxi(2, parameters.size())) # FIXME: This is needed because my RenderContext API sucks...

	displacement_maps.texture_rd_rid = RID()
	normal_maps.texture_rd_rid = RID()
	displacement_maps.texture_rd_rid = wave_generator.descriptors[&'displacement_map'].rid
	normal_maps.texture_rd_rid = wave_generator.descriptors[&'normal_map'].rid

	RenderingServer.global_shader_parameter_set(&'num_cascades', parameters.size())
	RenderingServer.global_shader_parameter_set(&'displacements', displacement_maps)
	RenderingServer.global_shader_parameter_set(&'normals', normal_maps)

func _update_scales_uniform() -> void:
	var map_scales : PackedVector4Array; map_scales.resize(len(parameters))
	for i in len(parameters):
		var params := parameters[i]
		var uv_scale := Vector2.ONE / params.tile_length
		map_scales[i] = Vector4(uv_scale.x, uv_scale.y, params.displacement_scale, params.normal_scale)
	# No global shader parameter for arrays :(
	WATER_MAT.set_shader_parameter(&'map_scales', map_scales)
	SPRAY_MAT.set_shader_parameter(&'map_scales', map_scales)

func _update_water(delta : float) -> void:
	if wave_generator == null: _setup_wave_generator()
	wave_generator.update(delta, parameters)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		displacement_maps.texture_rd_rid = RID()
		normal_maps.texture_rd_rid = RID()

# =============================================================================
#  displacement readback (GPU -> CPU) for buoyancy / get_height
# =============================================================================
# texture_get_data() is render-thread-only in Godot 4.4+. We dispatch the read
# onto the render thread via RenderingServer.call_on_render_thread() and stash the
# resulting Image behind a mutex; get_height() (called from gameplay on the main
# thread) reads that snapshot. One frame of latency, which is invisible for a boat.

var _readback_mutex := Mutex.new()
var _readback_images: Dictionary = {}   # cascade_index:int -> Image (height/displacement)
var _used_cascades: Array[int] = []     # cascades that actually displace (scale > 0)
var _readback_interval := 1.0 / 25.0    # ~25 Hz is plenty for ship bob
var _readback_accum := 0.0

## Cache which cascades contribute displacement, so we only read those layers.
func _compute_used_cascades() -> void:
	_used_cascades.clear()
	for i in range(len(parameters)):
		if parameters[i] and parameters[i].displacement_scale > 0.001:
			_used_cascades.append(i)

## RUNS ON THE RENDER THREAD. Reads each used displacement-map layer back to a CPU
## Image and publishes it under the mutex. Never call this from the main thread.
func _readback_displacements_render_thread() -> void:
	if wave_generator == null:
		return
	if not wave_generator.descriptors.has(&'displacement_map'):
		return
	var rid = wave_generator.descriptors[&'displacement_map'].rid
	if not rid.is_valid():
		return
	var device := RenderingServer.get_rendering_device()
	if device == null:
		return
	var sz := wave_generator.map_size
	for i in _used_cascades:
		var data := device.texture_get_data(rid, i)  # layer i == cascade i
		if data.is_empty():
			continue
		var img := Image.create_from_data(sz, sz, false, Image.FORMAT_RGBAH, data)
		_readback_mutex.lock()
		_readback_images[i] = img
		_readback_mutex.unlock()

func _world_to_uv(W:Vector2, tile_length:Vector2) -> Vector2:
	return Vector2(
		(W[0] - tile_length.x * floor(W[0] / tile_length.x)) / tile_length.x,
		(W[1] - tile_length.y * floor(W[1] / tile_length.y)) / tile_length.y)

## World-space wave height at an XZ position. Returns 0.0 until the first readback
## lands (e.g. update_textures == false, or the first frame or two after load).
## Sums every displacing cascade; iteratively inverts the horizontal (Gerstner)
## displacement so the sampled height matches the visually displaced vertex.
func get_height(world_pos:Vector3, steps:int=3) -> float:
	# Snapshot the current image refs under lock; readback replaces whole Images
	# (never mutates in place), so holding the refs after unlock is safe.
	_readback_mutex.lock()
	var imgs := _readback_images.duplicate()
	_readback_mutex.unlock()
	if imgs.is_empty():
		return 0.0

	var world_pos_xz := Vector2(world_pos.x, world_pos.z)
	var summed_height := 0.0
	for cascade_index in imgs.keys():
		var img: Image = imgs[cascade_index]
		if img == null:
			continue
		var displacement_scale: float = parameters[cascade_index].displacement_scale
		var tile_length: Vector2 = parameters[cascade_index].tile_length
		var x := world_pos_xz
		var y_raw := Color.BLACK
		# Iteratively approximate the UV whose displaced vertex lands on world_pos_xz.
		for i in range(steps):
			var uv := _world_to_uv(x, tile_length) * float(map_size)
			# get_pixelv needs a Vector2i; wrap into [0, map_size) (tile edges hit map_size).
			var px := Vector2i(posmod(int(uv.x), map_size), posmod(int(uv.y), map_size))
			y_raw = img.get_pixelv(px)
			x = world_pos_xz - Vector2(y_raw.r, y_raw.b)
		summed_height += y_raw.g * displacement_scale
	return summed_height

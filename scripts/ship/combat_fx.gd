class_name CombatFX
extends Object
## Procedural combat effects — muzzle smoke/flash, hull-splinter bursts, and
## positional audio. All greybox-grade (no textures/assets except the two
## generated WAVs in assets/audio); swap for real VFX later without touching
## the combat code, since everything routes through these three calls.

const BOOM_WAV := "res://assets/audio/cannon_boom.wav"
const HIT_WAV := "res://assets/audio/ship_hit.wav"

## Smoke puff + orange flash at one muzzle. Call per ball.
static func muzzle(anchor: Node, origin: Vector3, dir: Vector3) -> void:
	var scene := anchor.get_tree().current_scene
	if scene == null:
		return

	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 10
	p.lifetime = 1.1
	p.explosiveness = 0.9
	p.direction = dir
	p.spread = 22.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, 1.2, 0)   # smoke drifts up
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var mesh := SphereMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.75, 0.72, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.mesh = mesh
	p.position = origin
	scene.add_child(p)
	p.emitting = true
	anchor.get_tree().create_timer(1.8).timeout.connect(p.queue_free)

	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.62, 0.25)
	flash.light_energy = 5.0
	flash.omni_range = 14.0
	flash.position = origin
	scene.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.18)
	tw.tween_callback(flash.queue_free)

## Splinter burst where a ball strikes a hull.
static func impact(anchor: Node, pos: Vector3) -> void:
	var scene := anchor.get_tree().current_scene
	if scene == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 11.0
	p.gravity = Vector3(0, -14.0, 0)   # splinters fall
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.25, 0.25, 0.45)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.32, 0.2)
	mesh.material = mat
	p.mesh = mesh
	p.position = pos
	scene.add_child(p)
	p.emitting = true
	anchor.get_tree().create_timer(1.2).timeout.connect(p.queue_free)
	sound(anchor, pos, HIT_WAV, 2.0)

## One-shot positional sound; frees itself when done.
static func sound(anchor: Node, pos: Vector3, wav_path: String, volume_db := 0.0) -> void:
	var scene := anchor.get_tree().current_scene
	if scene == null:
		return
	var s := AudioStreamPlayer3D.new()
	s.stream = load(wav_path)
	s.volume_db = volume_db
	s.max_distance = 500.0
	s.position = pos
	scene.add_child(s)
	s.finished.connect(s.queue_free)
	s.play()

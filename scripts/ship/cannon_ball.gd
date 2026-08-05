class_name CannonBall
extends Area3D
## One iron ball in flight. Straight line with a gentle drop; hits the first
## ship (not the shooter) or land it touches, or splashes at end of range.
## Spawned by Broadside.fire_side(); adds itself to the world root.

var shooter: Node3D
var damage := 8
var speed := 60.0
var max_range := 90.0

var _dir := Vector3.FORWARD
var _travelled := 0.0

const DROP_PER_UNIT := 0.045   # slight ballistic sag over distance

static func launch(p_shooter: Node3D, origin: Vector3, dir: Vector3, def: CannonDef) -> void:
	var ball := CannonBall.new()
	ball.shooter = p_shooter
	ball.damage = def.damage
	ball.speed = def.ball_speed
	ball.max_range = def.fire_range * 1.15  # a little carry past listed range
	ball._dir = dir.normalized()
	ball.position = origin
	p_shooter.get_tree().current_scene.add_child(ball)

func _ready() -> void:
	monitoring = true
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	col.shape = sphere
	add_child(col)
	var mesh := MeshInstance3D.new()
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.35
	ball_mesh.height = 0.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.13)
	ball_mesh.material = mat
	mesh.mesh = ball_mesh
	add_child(mesh)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	var step := speed * delta
	global_position += _dir * step
	global_position.y -= DROP_PER_UNIT * step * (_travelled / maxf(max_range, 1.0) + 0.3)
	_travelled += step
	if _travelled >= max_range or global_position.y < -1.5:
		queue_free()  # splash (effect later)

func _on_body_entered(body: Node3D) -> void:
	if body == shooter:
		return
	if body is ShipController:
		body.receive_hit(damage, shooter)
		queue_free()
	elif body.is_in_group("land"):
		queue_free()

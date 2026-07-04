class_name CityPlayer
extends CharacterBody3D
## The walking captain — a cube, obviously, for now. WASD to walk (walk_* input
## actions), E (observe) to interact with the nearest building door.
## Spawned by CityScene.enter_street_mode(); owns its own follow camera.

const WALK_SPEED := 6.0
const TURN_SPEED := 10.0
const GRAVITY := 20.0
const INTERACT_RANGE := 4.0

# Camera: same scheme as the ship's chase cam (wheel zoom, hold-RMB orbit,
# middle-click reset). Constants mirror ship_controller.gd.
const ZOOM_STEP := 0.12
const ZOOM_MIN := 0.3
const ZOOM_MAX := 2.5
const CAM_ORBIT_SENS := 0.3
const CAM_PITCH_MIN := 5.0
const CAM_PITCH_MAX := 80.0
const CAM_DEFAULT_YAW := 0.0
const CAM_DEFAULT_PITCH := 35.0
const CAM_RADIUS := 15.0
const CAM_FOCUS_HEIGHT := 1.5

var _visual: Node3D
var _camera: Camera3D
var _zoom := 1.0
var _cam_yaw := CAM_DEFAULT_YAW
var _cam_pitch := CAM_DEFAULT_PITCH
var _orbiting := false

func _ready() -> void:
	# Cube body
	_visual = Node3D.new()
	add_child(_visual)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 1.7, 0.8)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.3, 0.2)
	box.material = mat
	mesh.mesh = box
	mesh.position.y = 0.85
	_visual.add_child(mesh)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)

	# Follow camera, ship-style: orbit with RMB, zoom with wheel, MMB to reset.
	_camera = Camera3D.new()
	_camera.name = "Camera"
	add_child(_camera)
	_update_camera()
	_camera.make_current()

func _physics_process(delta: float) -> void:
	var input := Vector2(
		Input.get_axis("walk_left", "walk_right"),
		Input.get_axis("walk_forward", "walk_back")
	)
	# Camera-relative movement (the camera orbits, so W = away from camera).
	var yaw := deg_to_rad(_cam_yaw)
	var forward := -Vector3(sin(yaw), 0.0, cos(yaw))
	var right := forward.cross(Vector3.UP)   # facing -Z -> right is +X
	var dir := right * input.x + forward * -input.y
	if dir.length() > 1.0:
		dir = dir.normalized()

	velocity.x = dir.x * WALK_SPEED
	velocity.z = dir.z * WALK_SPEED
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	# Face the walk direction (visual only; camera stays north-up).
	if dir.length_squared() > 0.01:
		var target_yaw := atan2(-dir.x, -dir.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, TURN_SPEED * delta)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("observe"):
		_try_interact()
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_apply_zoom(-ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_apply_zoom(ZOOM_STEP)
			MOUSE_BUTTON_RIGHT:
				_orbiting = event.pressed
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
			MOUSE_BUTTON_MIDDLE:
				if event.pressed:
					_cam_yaw = CAM_DEFAULT_YAW
					_cam_pitch = CAM_DEFAULT_PITCH
					_zoom = 1.0
					_update_camera()
	elif event is InputEventMouseMotion and _orbiting:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			# Release was swallowed (modal etc.) — recover, same as the ship.
			_orbiting = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return
		_cam_yaw = wrapf(_cam_yaw - event.relative.x * CAM_ORBIT_SENS, -180.0, 180.0)
		_cam_pitch = clampf(_cam_pitch - event.relative.y * CAM_ORBIT_SENS, CAM_PITCH_MIN, CAM_PITCH_MAX)
		_update_camera()

func _apply_zoom(amount: float) -> void:
	_zoom = clampf(_zoom + amount, ZOOM_MIN, ZOOM_MAX)
	_update_camera()

func _update_camera() -> void:
	if _camera == null:
		return
	var p := deg_to_rad(_cam_pitch)
	var y := deg_to_rad(_cam_yaw)
	var r := CAM_RADIUS * _zoom
	_camera.position = Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * r
	_camera.look_at(global_position + Vector3.UP * CAM_FOCUS_HEIGHT, Vector3.UP)

func _exit_tree() -> void:
	# Never leave the cursor captured when the player is freed mid-orbit.
	if _orbiting:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _try_interact() -> void:
	var best: CityBuilding = null
	var best_d := INTERACT_RANGE
	for b in get_tree().get_nodes_in_group("city_building"):
		var building := b as CityBuilding
		if building == null:
			continue
		var d := global_position.distance_to(building.door_position)
		if d < best_d:
			best_d = d
			best = building
	if best:
		var msg := best.interact()
		var city := _find_city()
		if city:
			city.show_toast(msg)

func _find_city() -> CityScene:
	var p := get_parent()
	while p:
		if p is CityScene:
			return p
		p = p.get_parent()
	return null

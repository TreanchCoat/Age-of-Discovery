class_name PortArea
extends Area3D
## Place at a port's harbor; assign its PortDef. Sailing into range shows a
## "Press E to dock" prompt; docking emits port_entered (market UI opens,
## autosave fires). Undocking respawns the ship outside; leaving range emits
## port_left. Docking is deliberately a choice, not automatic — matters once
## combat/pursuit exists.

@export var def: PortDef
@export var dock_radius: float = 40.0

var _ship_in_range: ShipController = null
var _prompt: Label

func _ready() -> void:
	if def:
		global_position = def.world_position
		# Optional children provided by port.tscn (label picks up the port name).
		var label := get_node_or_null(^"NameLabel") as Label3D
		if label:
			label.text = def.display_name
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = dock_radius
	shape.shape = sphere
	add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_make_prompt()

func _make_prompt() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position.y -= 110
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.hide()
	layer.add_child(_prompt)

func _on_body_entered(body: Node3D) -> void:
	if def and body is ShipController:
		_ship_in_range = body
		if GameState.current_port == &"":
			_prompt.text = "Press E to dock at %s" % def.display_name
			_prompt.show()

func _on_body_exited(body: Node3D) -> void:
	if def and body is ShipController:
		_ship_in_range = null
		_prompt.hide()
		if GameState.current_port == def.id:
			GameState.current_port = &""
			EventBus.port_left.emit(def.id)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("observe") and _ship_in_range and GameState.current_port == &"":
		_dock()

func _dock() -> void:
	_prompt.hide()
	GameState.current_port = def.id
	EventBus.port_entered.emit(def.id)

class_name DebugUI
extends CanvasLayer
## Developer panel — toggle with the ` (backtick) key. Wired up in world.gd with
## references to the wind, the ship, and the voyage-event system.

var wind: WindSystem
var ship: ShipController
var events: VoyageEventSystem

var _panel: PanelContainer
var _ports: Array[PortDef] = []

func _ready() -> void:
	layer = 50
	_load_ports()
	_build_ui()
	_panel.hide()

func _load_ports() -> void:
	var dir := DirAccess.open("res://data/ports")
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".tres"):
			var p := load("res://data/ports/" + file) as PortDef
			if p:
				_ports.append(p)

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_QUOTELEFT:
		_panel.visible = not _panel.visible

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_panel.offset_left = 16.0
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "DEBUG  ( ` to toggle )"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	# --- Wind ---
	_header(vbox, "Wind blows toward:")
	var dirs := [
		["N", Vector2(0, -1)], ["NE", Vector2(1, -1)], ["E", Vector2(1, 0)], ["SE", Vector2(1, 1)],
		["S", Vector2(0, 1)], ["SW", Vector2(-1, 1)], ["W", Vector2(-1, 0)], ["NW", Vector2(-1, -1)],
	]
	var grid := GridContainer.new()
	grid.columns = 4
	vbox.add_child(grid)
	for d in dirs:
		var b := Button.new()
		b.text = String(d[0])
		b.pressed.connect(_set_wind.bind(d[1]))
		grid.add_child(b)

	var srow := HBoxContainer.new()
	vbox.add_child(srow)
	for s in [["Calm", 0.2], ["Normal", 1.0], ["Storm", 2.0]]:
		var b := Button.new()
		b.text = String(s[0])
		b.pressed.connect(_set_strength.bind(float(s[1])))
		srow.add_child(b)
	_button(vbox, "Resume natural drift", _unlock)

	# --- Teleport ---
	_header(vbox, "Teleport to:")
	var trow := HBoxContainer.new()
	vbox.add_child(trow)
	for p in _ports:
		var b := Button.new()
		b.text = p.display_name
		b.pressed.connect(_teleport.bind(p.world_position))
		trow.add_child(b)

	# --- Ship ---
	_header(vbox, "Ship:")
	var shiprow := HBoxContainer.new()
	vbox.add_child(shiprow)
	_button(shiprow, "Repair hull", _repair)
	_button(shiprow, "Damage -20", _damage)
	_button(shiprow, "+500 gold", _gold)

	# --- Time / events ---
	_header(vbox, "Time / events:")
	var timerow := HBoxContainer.new()
	vbox.add_child(timerow)
	_button(timerow, "Skip 1 day", _skip_day)
	_button(timerow, "Force event", _force_event)

func _header(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	parent.add_child(l)

func _button(parent: Node, text: String, fn: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(fn)
	parent.add_child(b)

# --- Handlers ---

func _set_wind(dir: Vector2) -> void:
	if wind:
		wind.debug_locked = true
		wind.set_direction_to(dir)

func _set_strength(s: float) -> void:
	if wind:
		wind.debug_locked = true
		wind.strength = s

func _unlock() -> void:
	if wind:
		wind.debug_locked = false

func _teleport(pos: Vector3) -> void:
	if ship == null:
		return
	GameState.current_port = &""
	ship.set_at_sea(true)
	ship.global_position = Vector3(pos.x, 1.5, pos.z + 60.0)  # just south of the port, in open water
	ship.current_speed = 0.0
	ship.velocity = Vector3.ZERO

func _repair() -> void:
	if GameState.ship:
		GameState.ship.durability = GameState.ship.max_durability()

func _damage() -> void:
	if GameState.ship:
		GameState.ship.take_damage(20)

func _gold() -> void:
	GameState.gold += 500

func _skip_day() -> void:
	WorldClock.total_minutes += 1440.0

func _force_event() -> void:
	if events:
		events.debug_force_event()

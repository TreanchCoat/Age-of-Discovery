class_name DebugUI
extends CanvasLayer
## Developer panel — toggle with the ` (backtick) key. Wired up in world.gd with
## references to the wind, the ship, and the voyage-event system.

var wind: WindSystem
var ship: ShipController
var events: VoyageEventSystem
var ocean        # the FFT ocean Water node (set by world.gd)
var world        # the world node, for the "wind drives waves" toggle

var _panel: PanelContainer
var _ports: Array[PortDef] = []
var _cascade_index := 0
var _ocean_sliders := {}
var _ocean_values := {}
var _spray

const OCEAN_PARAMS := [
	["wind_speed", 0.0, 40.0, 0.5],
	["wind_direction", -180.0, 180.0, 1.0],
	["fetch_length", 10.0, 1000.0, 5.0],
	["swell", 0.0, 2.0, 0.05],
	["spread", 0.0, 1.0, 0.02],
	["detail", 0.0, 1.0, 0.02],
	["whitecap", 0.0, 2.0, 0.05],
	["foam_amount", 0.0, 10.0, 0.1],
	["displacement_scale", 0.0, 2.0, 0.05],
]
const OCEAN_SIZES := [128, 256, 512, 1024]

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
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = 16.0
	_panel.offset_top = 16.0
	add_child(_panel)

	# Scroll so the (now tall) panel never runs off the bottom of the screen.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 600)
	_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

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

	# --- Ocean waves ---
	if ocean:
		_build_ocean_section(vbox)

func _build_ocean_section(vbox: VBoxContainer) -> void:
	_header(vbox, "Ocean waves:")
	var auto_chk := CheckBox.new()
	auto_chk.text = "Wind drives waves (uncheck to tune manually)"
	auto_chk.button_pressed = true
	auto_chk.toggled.connect(_on_ocean_auto)
	vbox.add_child(auto_chk)

	var cas := OptionButton.new()
	for i in range(ocean.parameters.size()):
		cas.add_item("Cascade %d" % (i + 1))
	cas.item_selected.connect(_on_ocean_cascade)
	vbox.add_child(cas)

	for p in OCEAN_PARAMS:
		var pname := String(p[0])
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = pname
		lbl.custom_minimum_size = Vector2(140, 0)
		row.add_child(lbl)
		var sl := HSlider.new()
		sl.min_value = p[1]
		sl.max_value = p[2]
		sl.step = p[3]
		sl.custom_minimum_size = Vector2(180, 0)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val := Label.new()
		val.custom_minimum_size = Vector2(50, 0)
		sl.value_changed.connect(_on_ocean_param.bind(pname, val))
		row.add_child(sl)
		row.add_child(val)
		vbox.add_child(row)
		_ocean_sliders[pname] = sl
		_ocean_values[pname] = val

	var rrow := HBoxContainer.new()
	var rlbl := Label.new()
	rlbl.text = "resolution / mesh"
	rlbl.custom_minimum_size = Vector2(140, 0)
	rrow.add_child(rlbl)
	var res := OptionButton.new()
	for s in OCEAN_SIZES:
		res.add_item("%d" % s)
	res.item_selected.connect(_on_ocean_resolution)
	rrow.add_child(res)
	var mq := OptionButton.new()
	mq.add_item("Low")
	mq.add_item("High")
	mq.add_item("High 8K")
	mq.selected = int(ocean.mesh_quality)
	mq.item_selected.connect(_on_ocean_mesh_quality)
	rrow.add_child(mq)
	vbox.add_child(rrow)

	_spray = ocean.get_node_or_null("WaterSprayEmitter")
	var spray_chk := CheckBox.new()
	spray_chk.text = "Sea spray"
	spray_chk.button_pressed = _spray.visible if _spray else false
	spray_chk.toggled.connect(_on_ocean_spray)
	vbox.add_child(spray_chk)

	_refresh_ocean()

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

# --- Ocean handlers ---

func _on_ocean_auto(pressed: bool) -> void:
	if world:
		world.ocean_wind_auto = pressed

func _on_ocean_cascade(idx: int) -> void:
	_cascade_index = idx
	_refresh_ocean()

func _on_ocean_param(value: float, pname: String, val_label: Label) -> void:
	ocean.parameters[_cascade_index].set(pname, value)
	val_label.text = "%.2f" % value

func _on_ocean_resolution(idx: int) -> void:
	ocean.map_size = OCEAN_SIZES[idx]

func _on_ocean_mesh_quality(idx: int) -> void:
	ocean.mesh_quality = idx

func _on_ocean_spray(pressed: bool) -> void:
	if _spray:
		_spray.visible = pressed
		_spray.emitting = pressed

func _refresh_ocean() -> void:
	if ocean == null:
		return
	var c = ocean.parameters[_cascade_index]
	for pn in _ocean_sliders:
		var v: float = float(c.get(pn))
		_ocean_sliders[pn].value = v
		_ocean_values[pn].text = "%.2f" % v

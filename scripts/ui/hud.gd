class_name HUD
extends CanvasLayer
## The at-sea HUD, now a real scene (scenes/ui/hud.tscn) — lay widgets out in
## the editor, not in code. world.gd just instances it and calls setup().
##
## Owns: status line, sail readout, discovery flash, and a toast() method for
## transient feedback (voyage-event effects, etc.). The widget children
## (Minimap, Compass, Helm) keep their own scripts; setup() injects their
## runtime refs in code (never exported node refs — see PROJECT_PLAN golden
## rules). Adding a new widget: add the node in hud.tscn, give it a script,
## wire its refs in setup() if it needs any.

var _ship: ShipController
var _wind: WindSystem

var _status: Label
var _sail: Label
var _toast: Label
var _hull_bar: ProgressBar
var _hull_label: Label
var _hull_fill: StyleBoxFlat
var _cannon_label: Label

func _ready() -> void:
	_status = get_node_or_null(^"Status")
	_sail = get_node_or_null(^"SailInfo")
	_toast = get_node_or_null(^"Toast")
	if _toast:
		_toast.hide()
	_hull_bar = get_node_or_null(^"HullBar")
	_hull_label = get_node_or_null(^"HullLabel")
	if _hull_bar:
		# Dark trough + colored fill we can tint by damage level.
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.08, 0.08, 0.1, 0.75)
		_hull_bar.add_theme_stylebox_override("background", bg)
		_hull_fill = StyleBoxFlat.new()
		_hull_fill.bg_color = Color(0.35, 0.65, 0.3)
		_hull_bar.add_theme_stylebox_override("fill", _hull_fill)
	EventBus.hour_passed.connect(_on_tick)
	EventBus.gold_changed.connect(_on_tick)
	EventBus.port_entered.connect(_on_tick)
	EventBus.port_left.connect(_on_tick)
	EventBus.discovery_made.connect(_on_discovery_made)
	EventBus.ship_hit.connect(_on_ship_hit)
	# Cannon readiness readout, tucked under the hull bar.
	_cannon_label = Label.new()
	_cannon_label.position = Vector2(12, 88)
	add_child(_cannon_label)

## Inject runtime refs into self + widget children. Call right after instancing.
func setup(ship: ShipController, wind: WindSystem) -> void:
	_ship = ship
	_wind = wind
	var helm := get_node_or_null(^"Helm") as HelmIndicator
	if helm:
		helm.ship = ship
	var minimap := get_node_or_null(^"Minimap") as MinimapUI
	if minimap:
		minimap.ship = ship
		minimap.wind = wind
	var compass := get_node_or_null(^"Compass") as CompassUI
	if compass:
		compass.ship = ship
	_update_status()

## Transient bottom-center message ("Hull -15 · Morale -0.15", etc.).
func toast(text: String, seconds := 3.0) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.show()
	var t := get_tree().create_timer(seconds)
	t.timeout.connect(func():
		if _toast and _toast.text == text:
			_toast.hide())

func _on_tick(_arg = null) -> void:
	_update_status()

func _update_status() -> void:
	if _status == null:
		return
	var where := "At sea"
	if GameState.current_port != &"":
		where = "In port: " + String(GameState.current_port)
	_status.text = "%s | Gold: %d | %s" % [WorldClock.time_string(), GameState.gold, where]

func _on_discovery_made(id: StringName) -> void:
	var def := DiscoveryDB.get_def(id)
	if def and _status:
		_status.text = "DISCOVERY: %s — %s" % [def.display_name, def.lore]

func _process(_delta: float) -> void:
	if _ship == null or _sail == null:
		return
	var f := "%d%%" % roundi(_ship.horizontal_sail * 100.0)
	var b := "%d%%" % roundi(_ship.vertical_sail * 100.0)
	var wind_word := "-"
	if _wind:
		var align := _wind.alignment(-_ship.global_transform.basis.z)
		if align > 0.4:
			wind_word = "astern (favors horizontal sail)"
		elif align < -0.4:
			wind_word = "ahead (turn to catch it)"
		else:
			wind_word = "abeam (favors vertical sail)"
	var helm := "centered"
	if _ship.wheel > 0.05:
		helm = "port %.0f%%" % (_ship.wheel * 100.0)
	elif _ship.wheel < -0.05:
		helm = "starboard %.0f%%" % (-_ship.wheel * 100.0)
	var pos := _ship.global_position
	_sail.text = "Pos: %.0f, %.0f   Horizontal [F]: %s   Vertical [G]: %s   Helm: %s   Pace: %.0f%%   Wind: %s   Speed: %.1f" % [pos.x, pos.z, f, b, helm, _ship.pace * 100.0, wind_word, _ship.current_speed]
	_update_hull_bar()
	_update_cannons()

func _update_cannons() -> void:
	if _cannon_label == null or _ship == null or _ship.broadside == null:
		return
	if _ship.broadside.cannon_def() == null or GameState.ship.cannon_count <= 0:
		_cannon_label.text = ""
		return
	var port_t: float = _ship.broadside.reload_left(Broadside.Side.PORT)
	var stbd_t: float = _ship.broadside.reload_left(Broadside.Side.STARBOARD)
	var port_s := "READY [Q]" if port_t <= 0.0 else "%.1fs" % port_t
	var stbd_s := "READY [R]" if stbd_t <= 0.0 else "%.1fs" % stbd_t
	_cannon_label.text = "Guns — Port: %s   Starboard: %s" % [port_s, stbd_s]

func _on_ship_hit(attacker: Node3D, target: Node3D, damage: int) -> void:
	if target == _ship:
		toast("We're hit! Hull -%d" % damage)
	elif attacker == _ship:
		toast("Good shooting! -%d to the enemy" % damage)

func _update_hull_bar() -> void:
	if _hull_bar == null or GameState.ship == null or GameState.ship.def == null:
		return
	var cur: int = GameState.ship.durability
	var maxd: int = GameState.ship.max_durability()
	_hull_bar.max_value = maxd
	_hull_bar.value = cur
	if _hull_label:
		_hull_label.text = "Hull %d / %d" % [cur, maxd]
	if _hull_fill:
		var frac := float(cur) / maxf(float(maxd), 1.0)
		if frac > 0.5:
			_hull_fill.bg_color = Color(0.35, 0.65, 0.3)   # sound
		elif frac > 0.25:
			_hull_fill.bg_color = Color(0.8, 0.65, 0.2)    # battered
		else:
			_hull_fill.bg_color = Color(0.8, 0.25, 0.2)    # sinking soon

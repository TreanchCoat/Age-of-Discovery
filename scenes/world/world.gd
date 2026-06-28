extends Node3D
## Greybox world bootstrap: builds a flat sea, ports, discoveries, ship and HUD
## entirely from code so the project runs before any art exists.
## Replace pieces with real scenes as they're made.

var _status_label: Label
var _sail_label: Label
var _ship: ShipController
var _wind: WindSystem
var _ocean: Node3D            # the FFT ocean (Water node), instanced from ocean.tscn
var _ocean_cascades: Array = []   # WaveCascadeParameters, driven from the wind
var _base_wind_speeds: Array = [] # each cascade's tuned wind_speed (scaled by wind strength)
var _wind_accum := 0.0
var ocean_wind_auto := true       # debug panel can turn this off to tune waves by hand

func _ready() -> void:
	_make_environment()
	_make_sea()
	_spawn_land()
	var wind := WindSystem.new()
	wind.name = "Wind"
	add_child(wind)
	_wind = wind
	add_child(SupplySystem.new())
	_spawn_ports()
	_spawn_discoveries()
	var ship := _spawn_ship(wind)
	_ship = ship
	add_child(PortMarketUI.new())
	var map := WorldMapUI.new()
	add_child(map)
	map.register_ship(ship)
	var events := VoyageEventSystem.new()
	events.wind = wind
	add_child(events)
	var event_ui := VoyageEventUI.new()
	event_ui.system = events
	add_child(event_ui)
	var spyglass := SpyglassUI.new()
	spyglass.ship = ship
	ship.use_fallback_observe = false
	add_child(spyglass)
	var debug_ui := DebugUI.new()
	debug_ui.wind = wind
	debug_ui.ship = ship
	debug_ui.events = events
	debug_ui.ocean = _ocean
	debug_ui.world = self
	add_child(debug_ui)
	_make_hud()

func _make_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	env.environment = e
	add_child(env)

func _make_sea() -> void:
	# FFT ocean (ported GodotOceanWaves), instanced and made to follow the ship.
	# load() at runtime (not preload) so an ocean import problem can't break the
	# whole world script — it would just leave the sea empty.
	var scene: PackedScene = load("res://assets/water/ocean.tscn")
	if scene == null:
		push_warning("ocean.tscn failed to load")
		return
	var ocean = scene.instantiate()  # untyped: Water has no class_name, so reach .parameters dynamically
	add_child(ocean)
	_ocean = ocean
	# Cache the cascades + their tuned wind speeds so WindSystem can drive them.
	for p in ocean.parameters:
		_ocean_cascades.append(p)
		_base_wind_speeds.append(p.wind_speed)

func _apply_wind_to_ocean() -> void:
	if not ocean_wind_auto or _ocean_cascades.is_empty() or _wind == null:
		return
	var deg := rad_to_deg(_wind.direction.angle())
	var strength := clampf(_wind.strength, 0.3, 2.0)  # scale wave size with wind
	for i in _ocean_cascades.size():
		_ocean_cascades[i].wind_direction = deg
		_ocean_cascades[i].wind_speed = _base_wind_speeds[i] * strength

func _spawn_land() -> void:
	# Greybox landmasses near each city: a solid island (collides + damages) ringed
	# by a shallow-water band (slows + slowly scrapes the hull). Positioned clear of
	# each port's dock circle and the approach lane between the two cities.
	_make_landmass(Vector3(0, 0, -160), 100.0, 55.0)      # coast north of Lisbon
	_make_landmass(Vector3(-730, 0, 510), 95.0, 50.0)     # coast southwest of Funchal

func _make_landmass(center: Vector3, radius: float, shallow_width: float) -> void:
	var shallow_r := radius + shallow_width

	# Shallow water: a thin translucent disc you can see, plus a trigger area.
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = shallow_r
	disc_mesh.bottom_radius = shallow_r
	disc_mesh.height = 0.5
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.35, 0.7, 0.8, 0.4)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mesh.material = disc_mat
	disc.mesh = disc_mesh
	disc.position = center + Vector3(0, 0.3, 0)
	add_child(disc)

	var shallow := ShallowArea.new()
	var sa_shape := CollisionShape3D.new()
	var sa_cyl := CylinderShape3D.new()
	sa_cyl.radius = shallow_r
	sa_cyl.height = 40.0
	sa_shape.shape = sa_cyl
	shallow.add_child(sa_shape)
	shallow.position = center
	add_child(shallow)

	# Solid land: StaticBody3D in the "land" group so the ship collides + takes damage.
	var land := StaticBody3D.new()
	land.add_to_group("land")
	var land_col := CollisionShape3D.new()
	var land_cyl := CylinderShape3D.new()
	land_cyl.radius = radius
	land_cyl.height = 30.0
	land_col.shape = land_cyl
	land.add_child(land_col)
	var land_mesh := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = radius * 0.75
	lm.bottom_radius = radius
	lm.height = 30.0
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.42, 0.55, 0.32)
	lm.material = lmat
	land_mesh.mesh = lm
	land.add_child(land_mesh)
	land.position = center + Vector3(0, 5.0, 0)
	add_child(land)

func _spawn_ports() -> void:
	var dir := DirAccess.open("res://data/ports")
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var def := load("res://data/ports/" + file) as PortDef
		var area := PortArea.new()
		area.def = def
		add_child(area)
		# greybox marker
		var marker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(20, 30, 20)
		marker.mesh = box
		marker.position = def.world_position + Vector3.UP * 15
		add_child(marker)

func _spawn_discoveries() -> void:
	for def in DiscoveryDB.all_defs():
		var area := DiscoveryArea.new()
		area.def = def
		add_child(area)

func _spawn_ship(wind: WindSystem) -> ShipController:
	var ship := ShipController.new()
	ship.wind = wind
	# Visual hull lives under a HullPivot so buoyancy can heave/tilt it WITHOUT
	# tilting the body (which would corrupt thrust/steering — see ship_buoyancy.gd).
	var pivot := Node3D.new()
	pivot.name = "HullPivot"
	ship.add_child(pivot)
	# greybox hull
	var hull := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4, 3, 12)
	hull.mesh = box
	pivot.add_child(hull)
	# Collision stays on the body (level), not on the tilting pivot.
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	(col.shape as BoxShape3D).size = Vector3(4, 3, 12)
	ship.add_child(col)
	# chase camera (child of the body: gets neither tilt nor bob)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 25, 45)
	cam.rotation_degrees = Vector3(-25, 0, 0)
	ship.add_child(cam)
	ship.position = Vector3(0, 1.5, 60)  # just off Lisbon
	add_child(ship)
	# Buoyancy: conform the visual hull to the FFT ocean surface.
	if _ocean:
		var buoyancy := ShipBuoyancy.new()
		buoyancy.name = "Buoyancy"
		buoyancy.ocean = _ocean
		buoyancy.hull_pivot = pivot
		buoyancy.ship = ship
		buoyancy.wind = wind
		buoyancy.length = box.size.z
		buoyancy.beam = box.size.x
		ship.add_child(buoyancy)
	return ship

func _make_hud() -> void:
	var hud := CanvasLayer.new()
	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.position = Vector2(12, 12)
	hud.add_child(_status_label)
	_sail_label = Label.new()
	_sail_label.name = "SailInfo"
	_sail_label.position = Vector2(12, 36)
	hud.add_child(_sail_label)
	var helm := HelmIndicator.new()
	helm.name = "Helm"
	helm.ship = _ship
	helm.anchor_left = 0.5
	helm.anchor_right = 0.5
	helm.anchor_top = 1.0
	helm.anchor_bottom = 1.0
	helm.offset_left = -60.0
	helm.offset_right = 60.0
	helm.offset_top = -150.0
	helm.offset_bottom = -30.0
	hud.add_child(helm)
	var minimap := MinimapUI.new()
	minimap.name = "Minimap"
	minimap.ship = _ship
	minimap.wind = _wind
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.anchor_top = 0.0
	minimap.anchor_bottom = 0.0
	minimap.offset_left = -176.0
	minimap.offset_right = -16.0
	minimap.offset_top = 16.0
	minimap.offset_bottom = 176.0
	hud.add_child(minimap)
	var compass := CompassUI.new()
	compass.name = "Compass"
	compass.ship = _ship
	compass.anchor_left = 1.0
	compass.anchor_right = 1.0
	compass.anchor_top = 0.0
	compass.anchor_bottom = 0.0
	compass.offset_left = -274.0
	compass.offset_right = -184.0
	compass.offset_top = 16.0
	compass.offset_bottom = 106.0
	hud.add_child(compass)
	add_child(hud)
	_update_status()
	EventBus.hour_passed.connect(_on_status_tick)
	EventBus.gold_changed.connect(_on_status_tick)
	EventBus.port_entered.connect(_on_status_tick)
	EventBus.port_left.connect(_on_status_tick)
	EventBus.discovery_made.connect(_on_discovery_made)

func _on_status_tick(_arg) -> void:
	_update_status()

func _update_status() -> void:
	var where := "At sea"
	if GameState.current_port != &"":
		where = "In port: " + String(GameState.current_port)
	_status_label.text = "%s | Gold: %d | %s" % [WorldClock.time_string(), GameState.gold, where]

func _on_discovery_made(id: StringName) -> void:
	var def := DiscoveryDB.get_def(id)
	if def:
		_status_label.text = "DISCOVERY: %s — %s" % [def.display_name, def.lore]

func _process(delta: float) -> void:
	# Keep the ocean centred on the ship (snapped to whole units to avoid jitter).
	if _ocean and _ship:
		_ocean.global_position = Vector3(roundf(_ship.global_position.x), 0.0, roundf(_ship.global_position.z))
	# Drive the ocean's wind from WindSystem, throttled — changing it regenerates
	# the wave spectra, so we don't do it every frame.
	_wind_accum += delta
	if _wind_accum >= 0.5:
		_wind_accum = 0.0
		_apply_wind_to_ocean()
	if _ship == null or _sail_label == null:
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
	var hull := ""
	if GameState.ship and GameState.ship.def:
		hull = "   Hull: %d/%d" % [GameState.ship.durability, GameState.ship.max_durability()]
	_sail_label.text = "Horizontal [F]: %s   Vertical [G]: %s   Helm: %s   Pace: %.0f%%   Wind: %s   Speed: %.1f%s" % [f, b, helm, _ship.pace * 100.0, wind_word, _ship.current_speed, hull]

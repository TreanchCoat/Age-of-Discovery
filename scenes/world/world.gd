extends Node3D
## Greybox world bootstrap: builds a flat sea, ports, discoveries, ship and HUD
## entirely from code so the project runs before any art exists.
## Replace pieces with real scenes as they're made.

const SHIP_SCENE := preload("res://scenes/ship/ship.tscn")
const PORT_SCENE := preload("res://scenes/port/port.tscn")
const DEFAULT_SPAWN := Vector3(818, 1.5, -900)  # open water just off Lisbon

var _status_label: Label
var _sail_label: Label
var _ship: ShipController
var _wind: WindSystem
var _ocean: Node3D            # the FFT ocean (Water node), instanced from ocean.tscn
var _far_ocean: MeshInstance3D  # low-detail far ring sharing the water material (256..~2048)
var _cities := {}               # port_id -> CityScene instance
var _ambience: AudioStreamPlayer

func _ready() -> void:
	_make_environment()
	_make_sea()
	_spawn_land()
	var wind := WindSystem.new()
	wind.name = "Wind"
	add_child(wind)
	_wind = wind
	wind.register_ocean(_ocean)   # one wind drives both ship speed and the waves
	add_child(SupplySystem.new())
	_spawn_ports()
	_spawn_discoveries()
	var ship := _spawn_ship(wind)
	_ship = ship
	add_child(PortMarketUI.new())
	var map := WorldMapUI.new()
	add_child(map)
	map.map_texture = load("res://assets/terrain/region_preview.png")
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
	var pause := PauseMenu.new()
	pause.world = self
	add_child(pause)
	var objectives := ObjectiveSystem.new()
	add_child(objectives)
	var objective_ui := ObjectiveUI.new()
	objective_ui.system = objectives
	add_child(objective_ui)
	_make_audio()
	# Autosave every time we dock (current_port is set before this signal fires).
	EventBus.port_entered.connect(func(_p): autosave())
	# Market UI "Enter the city" -> street mode; "Return to ship" -> ship camera.
	EventBus.city_enter_requested.connect(_on_city_enter_requested)
	EventBus.city_left.connect(_on_city_left)
	_make_hud()
	# If the save was made while docked, current_port is set but no port_entered
	# ever fired this session — the game would be stuck "half-docked" (market
	# closed, dock prompts suppressed everywhere). Re-emit it deferred (so every
	# UI above has connected) to restore the docked state properly.
	if GameState.current_port != &"":
		EventBus.port_entered.emit.call_deferred(GameState.current_port)

func _on_city_enter_requested(city_id: StringName) -> void:
	var city: CityScene = _cities.get(city_id)
	if city:
		city.enter_street_mode()  # CityPlayer's camera takes over
		_fade_ambience(-60.0)     # the sea falls quiet in the streets

func _on_city_left(_city_id: StringName) -> void:
	# Hand the view back to the ship's chase camera (market UI reopens itself).
	if _ship:
		var cam := _ship.get_node_or_null(^"Camera") as Camera3D
		if cam:
			cam.make_current()
	_fade_ambience(-6.0)

## Snapshot ship position into flags, then save everything. Called on docking
## and from the pause menu's "Save & Main Menu".
func autosave() -> void:
	if _ship:
		var p := _ship.global_position
		GameState.flags["ship_pos"] = [p.x, p.y, p.z]
	GameState.save_game()

func _make_audio() -> void:
	# Ocean ambience. Loops (loop mode set in the .wav import options).
	# Keeps playing through pause menus (PROCESS_MODE_ALWAYS) — the sea never stops.
	var stream := load("res://assets/ocean_loop.wav") as AudioStream
	if stream == null:
		push_warning("ocean_loop.wav failed to load")
		return
	var player := AudioStreamPlayer.new()
	player.name = "OceanAmbience"
	player.stream = stream
	player.volume_db = -6.0
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	player.play()
	_ambience = player

## Fade the ocean loop (e.g. out when walking the city, back when returning).
func _fade_ambience(to_db: float, duration := 0.8) -> void:
	if _ambience == null:
		return
	create_tween().tween_property(_ambience, "volume_db", to_db, duration)

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
	# Far ocean: a big low-density mesh that samples the SAME FFT wave maps (global
	# shader uniforms) via the same material, so it extends the sea to ~2048 units
	# without a second wave simulation. Sits slightly below so the high-detail clipmap
	# wins where they overlap (inner 256).
	var far := MeshInstance3D.new()
	far.name = "FarOcean"
	far.mesh = load("res://assets/water/clipmap_low.obj")
	far.material_override = load("res://assets/water/mat_water.tres")
	far.scale = Vector3(8.0, 1.0, 8.0)   # clipmap is +/-256 -> +/-2048
	far.position.y = -0.2
	far.extra_cull_margin = 4096.0       # huge AABB after scaling; avoid wrongly culling it
	add_child(far)
	_far_ocean = far

func _spawn_land() -> void:
	# Greybox landmasses near each city: a solid island (collides + damages) ringed
	# by a shallow-water band (slows + slowly scrapes the hull). Positioned clear of
	# each port's dock circle and the approach lane between the two cities.
	# Real terrain from the GEBCO heightmap crop (Iberia / Madeira). Sea level = y 0.
	var terrain := HeightmapTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	# Tell the ocean shader where land is, so waves are not drawn over the terrain.
	var wm := load("res://assets/water/mat_water.tres") as ShaderMaterial
	if wm:
		wm.set_shader_parameter("terrain_landmask", load("res://assets/terrain/region_landmask.png"))
		wm.set_shader_parameter("terrain_rect", Vector4(0.0, 0.0, terrain.world_size.x, terrain.world_size.y))

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
	# Ports are a scene now (scenes/port/port.tscn): PortArea + marker + name
	# label. One instance per PortDef; the def drives position and label.
	var dir := DirAccess.open("res://data/ports")
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var def := load("res://data/ports/" + file) as PortDef
		var port: PortArea = PORT_SCENE.instantiate()
		port.def = def
		add_child(port)
		# If this port has a city scene, instance it at the port (sea-view mode:
		# skyline visible from the water, StreetLevel disabled until docking
		# flow calls enter_street_mode() — future work).
		var city_path := "res://scenes/city/city_%s.tscn" % String(def.id)
		if ResourceLoader.exists(city_path):
			var city: CityScene = (load(city_path) as PackedScene).instantiate()
			city.position = def.world_position
			add_child(city)
			_cities[def.id] = city

func _spawn_discoveries() -> void:
	for def in DiscoveryDB.all_defs():
		var area := DiscoveryArea.new()
		area.def = def
		add_child(area)

func _spawn_ship(wind: WindSystem) -> ShipController:
	# The ship is now a proper scene (scenes/ship/ship.tscn): body, HullPivot
	# (ShipVisual: hull fitting + swappable sail mounts), collision, camera,
	# buoyancy. Model/scale/keel tunables moved into the scene's inspector.
	# World only injects what exists at runtime: wind, ocean, spawn position.
	var ship: ShipController = SHIP_SCENE.instantiate()
	ship.wind = wind
	# Continue: resume where the last autosave left the ship; else default spawn.
	var saved_pos: Variant = GameState.flags.get("ship_pos")
	if saved_pos is Array and saved_pos.size() == 3:
		ship.position = Vector3(saved_pos[0], saved_pos[1], saved_pos[2])
	else:
		ship.position = DEFAULT_SPAWN
	add_child(ship)
	var buoyancy: ShipBuoyancy = ship.get_node(^"Buoyancy")
	# Wire scene-internal refs in code as well: exported node refs in the
	# hand-authored .tscn proved unreliable, so nothing relies on them.
	buoyancy.hull_pivot = ship.get_node(^"HullPivot")
	buoyancy.ship = ship
	buoyancy.wind = wind
	if _ocean:
		buoyancy.ocean = _ocean
	else:
		buoyancy.enabled = false  # no ocean, nothing to conform to
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
	minimap.map_texture = load("res://assets/terrain/region_preview.png")
	minimap.world_size = Vector2(3236.0, 4000.0)
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
	if _far_ocean and _ship:
		_far_ocean.global_position = Vector3(roundf(_ship.global_position.x), -0.2, roundf(_ship.global_position.z))
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

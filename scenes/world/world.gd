extends Node3D
## Greybox world bootstrap: builds a flat sea, ports, discoveries, ship and HUD
## entirely from code so the project runs before any art exists.
## Replace pieces with real scenes as they're made.

const SHIP_SCENE := preload("res://scenes/ship/ship.tscn")
const PORT_SCENE := preload("res://scenes/port/port.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const NPC_SHIP_SCENE := preload("res://scenes/ship/npc_ship.tscn")

## Terrain backend switch: Terrain3D (new) vs HeightmapTerrain (legacy fallback).
@export var use_terrain3d := true
const DEFAULT_SPAWN := Vector3(818, 1.5, -900)  # open water just off Lisbon

var _hud: HUD
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
	map.map_texture = load("res://assets/terrain/region_preview_hires.png")
	map.register_ship(ship)
	var events := VoyageEventSystem.new()
	events.wind = wind
	add_child(events)
	var event_ui := VoyageEventUI.new()
	event_ui.system = events
	add_child(event_ui)
	_spawn_pirate(ship, wind)
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
	add_child(CharacterSheetUI.new())      # C — skills / inventory / stats
	add_child(DiscoveryJournalUI.new())    # J — journal of discoveries
	GameState.rebuild_sheet()              # apply skill+equipment modifiers
	_make_audio()
	# Autosave every time we dock (current_port is set before this signal fires).
	EventBus.port_entered.connect(func(_p): autosave())
	# Market UI "Enter the city" -> street mode; "Return to ship" -> ship camera.
	EventBus.city_enter_requested.connect(_on_city_enter_requested)
	EventBus.city_left.connect(_on_city_left)
	# Sunk enemies pay out (placeholder until strike-colors/plunder exists).
	EventBus.ship_sunk.connect(_on_ship_sunk)
	_make_hud()
	# If the save was made while docked, current_port is set but no port_entered
	# ever fired this session — the game would be stuck "half-docked" (market
	# closed, dock prompts suppressed everywhere). Re-emit it deferred (so every
	# UI above has connected) to restore the docked state properly.
	if GameState.current_port != &"":
		EventBus.port_entered.emit.call_deferred(GameState.current_port)

func _on_ship_sunk(ship: Node3D) -> void:
	if ship is ShipController and not ship.is_player:
		GameState.gold += 150
		GameState.stats.add_fame(&"battle", 25)
		if _hud:
			_hud.toast("She's going down! Salvaged 150 gold from the wreck.")

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

## Combat step 0: one pirate at anchor west of the spawn lane. Anchored until
## the player closes to aggro range, then raises sails and chases. Real body:
## ships collide instead of ghosting. See npc_ship.gd for the upgrade path.
func _spawn_pirate(player_ship: ShipController, wind: WindSystem) -> void:
	var pirate: NPCShip = NPC_SHIP_SCENE.instantiate()
	pirate.wind = wind      # AI sails the same wind physics now
	pirate.target = player_ship
	pirate.position = Vector3(600, 1.5, -900)  # deep water, ~220 west of spawn
	pirate.rotation.y = -PI / 2.0              # anchored facing east, toward the lane
	add_child(pirate)
	# Same buoyancy wiring as the player ship (node refs in code, per the rules).
	var buoyancy := pirate.get_node_or_null(^"Buoyancy") as ShipBuoyancy
	if buoyancy:
		buoyancy.hull_pivot = pirate.get_node(^"HullPivot")
		buoyancy.ship = pirate
		buoyancy.wind = wind
		if _ocean:
			buoyancy.ocean = _ocean
		else:
			buoyancy.enabled = false

## TEMP DIAGNOSTIC (remove once terrain placement is verified): measures the
## live Terrain3D height at known probe points and prints them against the
## expected values from the source data. If measured != expected, the pattern
## tells us the transform error (offset / flip / scale).
func _t3d_diagnostic(t: Node3D) -> void:
	print("=== Terrain3D diagnostic ===")
	print("vertex_spacing = ", t.call(&"get_vertex_spacing"))
	print("data_directory = ", t.get("data_directory"))
	var data: Object = t.get("data")
	if data == null:
		print("NO DATA OBJECT")
		return
	print("active regions = ", data.call(&"get_regions_active").size())
	var probes := [
		["spawn      ", Vector3(818, 0, -900), -30.85],
		["lisbon     ", Vector3(999, 0, -906), -0.51],
		["funchal    ", Vector3(-1106, 0, 1125), -26.36],
		["origin     ", Vector3(0, 0, 0), -291.67],
		["iberia_mtn ", Vector3(1300, 0, -700), 8.60],
		["dragon_rock", Vector3(-280, 0, 180), -286.47],
	]
	for p in probes:
		var measured: float = data.call(&"get_height", p[1])
		print("%s world(%6.0f,%6.0f)  measured=%8.2f   expected=%8.2f" % [p[0], p[1].x, p[1].z, measured, p[2]])
	print("=== end diagnostic ===")

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
	# Terrain backend A/B (PROJECT_PLAN §4 Layer 2):
	#  - Terrain3D (new): native-res GEBCO import from assets/terrain/t3d_data,
	#    clipmap LOD, in-editor sculpting. vertex_spacing 2.0 — see terrain3d_meta.json.
	#  - HeightmapTerrain (old): kept as fallback until the new path is proven.
	# Toggle `use_terrain3d` on the World root in the inspector.
	# NOTE: Terrain3D has no port flatten-aprons — harbors get hand-sculpted.
	var world_sz := Vector2(3236.0, 4000.0)
	var mask_path := "res://assets/terrain/region_landmask.png"
	var t3d_ok: bool = use_terrain3d and ClassDB.class_exists(&"Terrain3D") \
		and DirAccess.dir_exists_absolute("res://assets/terrain/t3d_data")
	if t3d_ok:
		var t := ClassDB.instantiate(&"Terrain3D") as Node3D
		t.name = "Terrain"
		t.add_to_group("land")
		add_child(t)
		# Configure AFTER add_child and via setter calls — set() before the node
		# entered the tree silently failed once (terrain rendered at half size).
		t.call(&"set_vertex_spacing", 2.0)
		t.set("data_directory", "res://assets/terrain/t3d_data")
		t.set("collision_mode", 3)  # 3 = Full / Game (see Terrain3DCollision enum)
		# Textures: if the team has saved an assets resource from the dock, use it.
		if ResourceLoader.exists("res://assets/terrain/terrain3d_assets.tres"):
			t.set("assets", load("res://assets/terrain/terrain3d_assets.tres"))
		if ResourceLoader.exists("res://assets/terrain/terrain3d_material.tres"):
			t.set("material", load("res://assets/terrain/terrain3d_material.tres"))
		# Guard against silent property failures — the bug class we just had.
		var spacing: float = t.call(&"get_vertex_spacing")
		if not is_equal_approx(spacing, 2.0):
			push_warning("Terrain3D vertex_spacing=%s (expected 2.0) — terrain will be misscaled!" % spacing)
		mask_path = "res://assets/terrain/region_landmask_hires.png"
		_t3d_diagnostic.call_deferred(t)
	else:
		if use_terrain3d:
			push_warning("Terrain3D unavailable (plugin or t3d_data missing) — using HeightmapTerrain")
		var terrain := HeightmapTerrain.new()
		terrain.name = "Terrain"
		add_child(terrain)
		world_sz = terrain.world_size
	# Tell the ocean shader where land is, so waves are not drawn over the terrain.
	var wm := load("res://assets/water/mat_water.tres") as ShaderMaterial
	if wm:
		wm.set_shader_parameter("terrain_landmask", load(mask_path))
		wm.set_shader_parameter("terrain_rect", Vector4(0.0, 0.0, world_sz.x, world_sz.y))

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
	ship.ship_state = GameState.ship  # the player's hull sails the player's state
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
	# The HUD is a scene now (scenes/ui/hud.tscn) — layout lives in the editor,
	# logic in hud.gd. world only instances it and injects runtime refs.
	_hud = HUD_SCENE.instantiate()
	add_child(_hud)
	_hud.setup(_ship, _wind)

func _process(delta: float) -> void:
	# Keep the ocean centred on the ship (snapped to whole units to avoid jitter).
	if _ocean and _ship:
		_ocean.global_position = Vector3(roundf(_ship.global_position.x), 0.0, roundf(_ship.global_position.z))
	if _far_ocean and _ship:
		_far_ocean.global_position = Vector3(roundf(_ship.global_position.x), -0.2, roundf(_ship.global_position.z))
	# (Sail/status readouts moved into hud.gd — the HUD scene owns them now.)

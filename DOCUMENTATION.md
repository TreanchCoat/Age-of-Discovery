# Age of Discovery — Technical Documentation

Companion to `DESIGN.md` (vision/roadmap) and `README.md` (quick start). This file explains every system, every file, and how they connect.

---

## 1. Core architecture

### The Def/State split

Everything in the game follows one rule:

- **Defs** (`GoodDef`, `PortDef`, `ShipDef`, `DiscoveryDef`, `VoyageEventDef`) are *immutable catalog data*, stored as `.tres` files in `data/`. They describe what things *are*. Never modified at runtime.
- **States** (`ShipState`, `CargoHold`, `CharacterStats`) are *mutable save data*. They describe what's *happening*. Every State implements `to_dict()` / `from_dict()`, which doubles as the save format and, later, the co-op network sync format.

Systems operate on States using Defs. Example: `ShipState.effective_speed()` reads its `ShipDef` for base stats and its own crew/morale for modifiers.

### Signal-driven decoupling

Nothing talks to UI directly, and UI never mutates game state directly. Everything routes through:

- **EventBus** — global signals. A system emits `discovery_made`; the HUD, the map, and (later) a quest system all react independently. None of them know about each other.
- **System methods** — UI calls `EconomySim.buy(...)`, never touches `market` or `gold` itself.

This is the co-op insurance policy: when multiplayer arrives, system methods become host-authoritative RPCs and EventBus signals get replicated, while UI code doesn't change at all.

### Data-driven content

Systems auto-load entire folders of `.tres` files at startup (`data/goods/`, `data/ports/`, `data/discoveries/`, `data/events/`, `data/ships/`). Adding content means duplicating a `.tres` file and editing fields — no code. The greybox world scene spawns ports and discovery triggers from this data automatically.

---

## 2. Autoloads (global singletons)

Registered in `project.godot`, alive for the whole game (they survive scene changes — which is why `GameState.new_game()` must reset them explicitly), in load order:

### EventBus — `scripts/autoload/event_bus.gd`
Pure signal declarations, no logic. Current signals: `hour_passed`, `day_passed`, `port_entered/left`, `undock_requested`, `weather_changed`, `discovery_spotted/made`, `trade_executed`, `prices_updated`, `supplies_short`, `voyage_event_fired/resolved`, `fame_changed`, `gold_changed`.

### WorldClock — `scripts/autoload/world_clock.gd`
Converts real seconds to game minutes (`MINUTES_PER_REAL_SECOND`, default 2.0 → one game day per 12 real minutes). Emits `hour_passed`/`day_passed` through EventBus; all simulation hangs off these ticks. `total_minutes` is the single source of truth — events that "cost time" (e.g. riding out a storm) just add to it.

### GameState — `scripts/autoload/game_state.gd`
Owns the player: `gold` (setter clamps and emits `gold_changed`), `stats` (CharacterStats), `ship` (active ShipState), `fleet` (all owned ships), `current_port` (empty StringName = at sea), `flags` (misc dictionary — also stores the fog-of-war bitmap and last ship position). `save_game()`/`load_game()` serialize everything, including the other autoloads, to `user://save.json`. `new_game()` does the full reset for the main menu's New Game (own fields + `WorldClock.reset()` + `DiscoveryDB.reset()` + `EconomySim.reset()`). See §9 for the full save-system contract.

### Settings — `scripts/autoload/settings.gd`
User preferences, persisted separately from saves in `user://settings.cfg` (ConfigFile). Currently `master_volume` (0–1, applied to the Master audio bus on boot and on change). Menus write it via the property setter and call `save_settings()` when a slider drag ends. Add future settings (fullscreen, keybinds) here.

### EconomySim — `scripts/autoload/economy_sim.gd`
Each port's market: `market[port_id][good_id] = {supply, baseline, fluct}`. **Every port trades every good**, so you can always buy or offload anything you carry.

- **Price formula:** `base_price × fluct / supply`, supply clamped 0.2–4.0. Supply 1.0 = base price; a port that *produces* a good starts at supply 1.5 (cheap), one that *demands* it at 0.5 (dear) — this is what makes the same good worth different amounts at port A vs port B.
- **Fluctuation:** `fluct` is a random 0.8–1.2 multiplier, **re-rolled every time you dock** (`port_entered`), so prices feel fresh each visit.
- **Player impact:** buying drains supply (price rises), selling floods it (price falls) — 1% per unit. You can crash a market by dumping cargo. This is intentional: the economy reacts to *you*.
- **Recovery:** every `day_passed`, supply lerps 10% back toward baseline.
- `buy()`/`sell()` validate gold/cargo space and emit `trade_executed`.

### DiscoveryDB — `scripts/autoload/discovery_db.gd`
Catalog of all DiscoveryDefs + record of what's found. The discovery flow:

1. `spot(id)` — ship entered a DiscoveryArea. Emits `discovery_spotted`. Unconfirmed.
2. `confirm(id, roll_bonus)` — skill check: `observation + roll_bonus + d20 >= difficulty`. On success: fame + gold rewards, observation skill grows by 1 (learn-by-doing), emits `discovery_made`. The `roll_bonus` (+10) comes from a clean spyglass minigame hit.

---

## 3. Data classes — `scripts/data/`

| File | Class | Kind | Notes |
|---|---|---|---|
| `good_def.gd` | GoodDef | Def | id, category, base_price, weight, perishable flag (future spoilage) |
| `port_def.gd` | PortDef | Def | world_position, produces[] (cheap), demands[] (dear), culture, size |
| `ship_def.gd` | ShipDef | Def | horizontal_sail_power, vertical_sail_power, turn_rate, cargo_capacity, crew/durability caps (legacy base_speed/vs_wind_penalty kept, unused) |
| `discovery_def.gd` | DiscoveryDef | Def | position, spot_radius, difficulty, fame/gold rewards, lore text |
| `voyage_event_def.gd` | VoyageEventDef | Def | see §5 |
| `character_stats.gd` | CharacterStats | State | 5 skills + 3 fame tracks; `grow()` for learn-by-doing |
| `ship_state.gd` | ShipState | State | refs a ShipDef; durability, crew, supplies, morale, cargo |
| `cargo_hold.gd` | CargoHold | State | weight-limited dict of good_id→qty |

**`ShipState.effective_speed(align, horizontal, vertical)`** is the heart of sailing feel. The two sails each add thrust, scaled by how well their type suits the wind angle:
```
speed = (horizontal × h_eff × horizontal_sail_power
       + vertical   × v_eff × vertical_sail_power) × crew_mult × morale_mult
  align:  +1 wind dead astern … 0 on the beam … −1 dead ahead
  h_eff:  (align+1)/2 + 0.5·max(0,align)   → ahead 0, beam 0.5, astern 1.5   (square sail)
  v_eff:  (1−|align|) + 0.4·max(0,align)   → ahead 0, astern 0.4, beam 1.0   (fore-and-aft sail)
  crew_mult:   crew/max_crew, floor 0.4
  morale_mult: lerp(0.7 → 1.0) by morale
```
ShipController then multiplies the result by `wind.strength` (0.2–2.0) and `pace` (0.5–1.0). Both sails down → 0 thrust → the ship coasts to a stop; dead into the wind both sails give ~0. Every system (supplies, events, crew) feeds back into how the ship *feels*.

---

## 4. World systems — `scripts/systems/`, `scripts/ship/`

### WindSystem — `systems/wind_system.gd`
One global wind: a unit Vector2 on the XZ plane plus `strength` (0.2 calm – 2.0 storm). Every 3 game hours the target heading drifts ±60° and strength shifts ±0.3; actual direction rotates smoothly. `alignment(forward)` returns tail/headwind dot product for ShipController. Strong wind is also a precondition for storm events.

### The ship scene — `scenes/ship/ship.tscn`
The player ship is a proper scene:

```
Ship (CharacterBody3D + ship_controller.gd)
├── HullPivot (Node3D + ship_visual.gd)   ← buoyancy heaves/tilts THIS, never the body
│   └── HullYaw (180° — placeholder model faces astern)
│       ├── Hull (MeshInstance3D — placeholder medieval_boat.obj + wood material)
│       ├── MainSailMount (Node3D, empty)
│       └── ForeSailMount (Node3D, empty)
├── Collision (level box 4×3×12 — stays on the body)
├── Camera (chase cam — inherits neither tilt nor bob)
└── Buoyancy (ship_buoyancy.gd; ocean/wind/hull_pivot refs injected by world.gd)
```

**ShipVisual** (`ship/ship_visual.gd`, on HullPivot) self-wires and fits the hull model at runtime (scale, AABB centring, keel height — inspector exports), falls back to a greybox box if the mesh is missing, and owns the **swappable-sail API** for the future shipyard: `set_sail(&"main", scene)` / `clear_sail()` / `get_sail()` against named mount nodes. The placeholder hull has sails baked in, so mounts are empty markers for now; when real sail-less hulls arrive, reposition mounts to the masts and instance sail scenes there.

**ShipBuoyancy** (`ship/ship_buoyancy.gd`) samples `ocean.get_height()` at bow/stern/port/starboard probes and applies heave/pitch/roll to HullPivot only — the physics body, collision, and camera stay level so thrust and steering are never corrupted.

### ShipController — `ship/ship_controller.gd` (CharacterBody3D)
Player ship. Steering is via a **helm/wheel**: A/D swing a `wheel` value toward a side (`WHEEL_TURN_RATE`), releasing lets it spring back to center (`WHEEL_RETURN_RATE`); the ship rotates at a rate set by wheel position × `turn_rate` × a speed factor × `pace`. Turn authority scales with speed but never below `MIN_STEERAGE` (0.3), so you can't get stuck in irons. **Two sails**, toggled F (horizontal/square) and G (vertical/fore-and-aft); each eases toward its commanded state (`SAIL_CHANGE_RATE`) so furling lets thrust decay rather than cut out. **Pace** (0.5→1.0) builds +5%/s while making way and steering straight, bleeds while turning, and falls back to 50% when stopped or both sails are down; it scales both speed and turn rate. Target speed = `effective_speed(...) × wind.strength × pace`, approached with inertia (`move_toward`); `velocity.y` is zeroed each frame so the flat sea is never left. Mouse wheel zooms the chase camera (`ZOOM_MIN`–`ZOOM_MAX`). On `port_entered` the ship docks (`set_at_sea(false)`: hull hidden, frozen, sails furled); on `undock_requested` it respawns just outside the harbor. `use_fallback_observe` — when SpyglassUI is present, the plain E-to-confirm fallback is disabled.

### DiscoveryArea / PortArea — `systems/discovery_area.gd`, `port_area.gd` (Area3D)
Proximity triggers built from their Def's position/radius at runtime. DiscoveryArea → `DiscoveryDB.spot()`. PortArea: sailing into range shows **"Press E to dock"** — docking is a choice, not automatic (matters once combat/pursuit exists). E → sets `GameState.current_port`, emits `port_entered` (market UI opens, autosave fires); leaving range after undock emits `port_left`. Ports are instanced from **`scenes/port/port.tscn`** (PortArea + greybox marker + billboard `Label3D` that PortArea fills with the port's display name); one instance per `data/ports/*.tres`.

### HeightmapTerrain — `systems/heightmap_terrain.gd` (StaticBody3D)
Real terrain from a GEBCO bathymetry/topography crop (Iberia/Madeira): a 513² float32 height grid (`assets/terrain/region_height.bin`, metres, sea level = 0) built into an ArrayMesh + `HeightMapShape3D` collision, in the `land` group so the ship grounds on it. Land height uses a saturating curve (`land_near_slope`, `land_max_height` exports): ~linear near the coast, compressing toward a ceiling for peaks. Colored by `assets/terrain/terrain.gdshader` (height/slope bands: sand/grass/rock/snow — flat colors, no textures yet). The landmask (`region_landmask.png`) is passed to the water shader so waves aren't drawn over land. **Planned evolution** (post-demo, see `PROJECT_PLAN.md` §4): shader polish + waterline integration first, then migration to the Terrain3D plugin for LOD, splatting, higher coastline resolution, and in-editor sculpt/paint.

### SupplySystem — `systems/supply_system.gd`
Voyage pressure. Each `day_passed` *at sea*, every fleet ship consumes water (0.5/crew) and food (0.3/crew). Shortage: morale −0.25/day, and at zero morale crew starts dying (10%/day, floor 1). Well-supplied crews recover morale +0.1/day. Static helpers `resupply_cost()`/`resupply()` refill to caps (water crew×10, food crew×8) at 2g per missing unit — used by the market UI's Resupply button. Docked ships consume nothing (simplification, revisit later).

---

## 5. Voyage events

### VoyageEventDef — `data/voyage_event_def.gd`
Fully data-driven event template:

- **Trigger conditions:** `tick` (hourly/daily), `base_chance`, `requires_at_sea`, `min_days_at_sea` (scurvy needs long voyages), `requires_low_supplies`, `min_wind_strength` (storms need weather).
- **Default effects:** deltas to durability, morale, crew, gold, water, food.
- **Optional choice:** if `choice_text` is set, the player may take an alternative outcome (its own deltas + `choice_hours_lost`). E.g. heave to in a storm: less damage, lose 6 hours.
- **`mitigating_skill`:** each point above 5 in that skill cuts fire chance ~4% (floor ×0.5); surviving the event grows the skill by 1.

### VoyageEventSystem — `systems/voyage_event_system.gd`
Listens to hour/day ticks, tracks `_days_at_sea` (reset on docking), rolls each matching def, fires at most one event at a time via `voyage_event_fired`. `resolve(accepted_choice)` applies whichever effect set, clamps everything to valid ranges, applies time cost, grows the mitigating skill, emits `voyage_event_resolved`.

### VoyageEventUI — `ui/voyage_event_ui.gd`
Modal popup (`PROCESS_MODE_ALWAYS`, pauses the tree). Shows title + flavor text, an "Endure it" button, and the choice button when the def has one. Calls `system.resolve(...)`.

### Shipped events — `data/events/`
- `storm.tres` — hourly, needs wind ≥1.4; −15 durability or heave to (−4, lose 6h). Navigation mitigates.
- `scurvy.tres` — daily after 10 days at sea; −2 crew, or spend 50g on limes. Leadership mitigates.
- `dolphins.tres` — daily, +0.15 morale. Not everything at sea is trying to kill you.

---

## 6. UI — `scripts/ui/`

All UI is built from code (greybox); replace with designed scenes later without touching systems.

### PortMarketUI — `port_market_ui.gd`
Opens **centered** on `port_entered` with a green "Voyage Successful — Welcome to {Port}" banner. Per good at this port: live price, held quantity, Buy/Sell ×1/×10 (every good trades at every port). Footer: water/food + Resupply button (via SupplySystem), cargo weight. The "Weigh anchor — set sail" button emits `undock_requested` (respawns the ship at sea) and closes the panel. Subscribes to `prices_updated`/`trade_executed`/`gold_changed`.

### WorldMapUI — `world_map_ui.gd`
Toggled with M. Square map (600px) mapping world XZ (±`world_extent`, default 2000) to map UV.

- **Background:** the terrain preview (`assets/terrain/region_preview.png`), assigned by `world.gd`; swap in stylized map art via `map_texture` whenever it exists.
- **Fog of war:** a 512² RGBA image, opaque dark; each game hour a soft-edged circle is punched transparent around the ship. Persisted in `GameState.flags["fog_png"]` as a **base64 string** (the save is JSON, which can't hold raw `PackedByteArray` — see §9), decoded tolerantly on load.
- **Markers:** ports always shown (captains know charts; fog still covers unvisited regions), found discoveries in gold, ship as red triangle with heading.

### SpyglassUI — `spyglass_ui.gd`
Discovery confirmation minigame:

1. On `discovery_spotted`: banner "Something on the horizon… (E)".
2. E in range → pause, spyglass lens overlay: a red mark drifts/bounces with wandering velocity; a gold sweet-spot circle sits center.
3. Press E when the mark is inside the circle → `DiscoveryDB.confirm(id, +10 bonus)`. Sweet spot grows with observation skill; mark speed grows with discovery difficulty. 3 tries, then it "slips away" — re-enter the area to retry.

### VoyageEventUI — see §5.

### HUD — built in `world.gd._make_hud()`
Top-left: status line (time, gold, port/at-sea, flashes discovery lore) plus a sail readout updated every frame — horizontal/vertical sail %, helm position, pace %, wind-angle word, speed.

### MinimapUI — `minimap_ui.gd`
Always-on, top-right. North-up, centered on the player (gold triangle, rotates with heading); cities are blue dots placed relative to you (clamped to the edge beyond `range_units`). A small cyan arrow in the corner shows wind direction.

### CompassUI — `compass_ui.gd`
Fixed N/E/S/W rose with a red needle pointing along the bow. Sits just left of the minimap.

### HelmIndicator — `helm_indicator.gd`
Bottom-center wheel: a circle with a rotating cross showing the helm (`ship.wheel`) position, with a fixed notch at top for reference.

### MainMenu — `main_menu.gd` + `scenes/menu/main_menu.tscn`
The project's **main scene**. New Game (`GameState.new_game()` → world), Continue (disabled when no save; `GameState.load_game()` → world), Settings (master volume slider → `Settings`), Quit. UI built from code like the rest.

### PauseMenu — `pause_menu.gd`
Esc (`ui_cancel`) pauses the tree and shows Resume / Settings (volume slider) / **Save & Main Menu** (calls `world.autosave()` first). Runs `PROCESS_MODE_ALWAYS`; it deliberately ignores Esc while another modal (voyage event, spyglass) has the tree paused, so it never steals their pause.

---

## 6b. Cities — `scripts/city/`, `scenes/city/`

**One scene per city, two modes** (the agreed Layer-3 architecture, greyboxed):

- **CityScene** (`city.gd`, root of `city_lisbon.tscn` / `city_funchal.tscn`): sea-view mode by default — the `Buildings/` children form the skyline visible from the water (world.gd instances each city at its port automatically if `scenes/city/city_<port_id>.tscn` exists). `enter_street_mode()` enables the `StreetLevel/` node (ground, future props/NPCs; colliders and CSG collision are force-disabled at sea) and spawns the player. Running a city scene directly (**F6**) auto-enters street mode with a test sun/sky — that's the dev loop for building out cities. The docking flow doesn't call `enter_street_mode()` yet (future work).
- **CityBuilding** (`city_building.gd`, StaticBody3D): greybox building typed via `building_type` export (market, shipyard, tavern, bank, governor, church, warehouse, house) — builds its own sized/colored box, sign label, collision, and door slab (+Z face; rotate the node to face the street). `interact()` emits `EventBus.city_building_interacted(city_id, type)` — **future facility UIs subscribe to their type there** — and returns toast text ("Bank — not yet open") until they exist.
- **CityPlayer** (`city_player.gd`, CharacterBody3D): the walking captain, a cube for now. WASD (`walk_*` actions, camera-relative), gravity; E (`observe`) interacts with the nearest building door within 4u. Camera matches the ship's scheme exactly: wheel zoom, hold-RMB orbit (cursor captured), middle-click reset.
- **Entering/leaving on foot:** the market UI's **"Enter the city"** button (shown only where a city scene exists) emits `city_enter_requested` → world calls `enter_street_mode()`; the **"Return to ship"** button in the city calls `exit_street_mode()` → `city_left` → world restores the ship camera and the market panel reopens (still docked).
- **Sea-view scale:** `CityScene.sea_view_scale` (default 2.5) scales the `Buildings` node up in sea view so the skyline holds its own next to the ship, and back to 1.0 (human scale) in street mode.

---

## 7. Scene flow & world bootstrap

**Flow:** `main_menu.tscn` (main scene) → `world.tscn` (gameplay) → back via pause menu. The autoloads persist across these changes; scene scripts only build visuals/UI around them.

`world.tscn` is a single Node3D with `world.gd`; `_ready()` builds:

1. Environment (sun + procedural sky), the **FFT ocean** (`_make_sea()` instances `assets/water/ocean.tscn`; `_process()` keeps it centred on the ship and drives cascade wind from WindSystem) + the far-ocean ring to ~2048. **See `OCEAN_INTEGRATION.md`.**
2. `HeightmapTerrain` (GEBCO land, collision, landmask → water shader).
3. WindSystem, SupplySystem.
4. One `port.tscn` instance per `data/ports/*.tres`; DiscoveryArea per DiscoveryDB def.
5. The ship — instances **`ship.tscn`**, injects wind/ocean into it and its Buoyancy node (node refs wired in code, not scene exports), spawns at the last autosaved position (`flags["ship_pos"]`) or the default off Lisbon.
6. PortMarketUI, WorldMapUI (registered to ship), VoyageEventSystem + UI, SpyglassUI (disables the ship's fallback observe), DebugUI, PauseMenu (given `world` for autosave).
7. Ocean ambience audio (`_make_audio()`, loops, keeps playing while paused).
8. HUD: status + sail readout, MinimapUI, CompassUI, HelmIndicator. *(Still code-built — next candidate for scene migration.)*

`world.autosave()` snapshots the ship position into `flags["ship_pos"]` and calls `GameState.save_game()`; it runs on every `port_entered` and from the pause menu.

---

## 8. Conventions & gotchas

- **Tabs** for indentation (Godot standard).
- **StringName** (`&"id"`) for all ids — fast comparisons, and `.tres` files declare them as `&"..."`.
- **Typed arrays in .tres:** `Array[StringName]([&"wine"])` syntax.
- **Adding a signal?** Declare in EventBus only; emit from the owning system.
- **Adding a system?** Node in the world scene if it needs the scene/ticks via EventBus; autoload only if it must survive scene changes or be globally addressable.
- **Pause behavior:** modal UIs (events, spyglass) set `get_tree().paused = true` and run with `PROCESS_MODE_ALWAYS`. WorldClock pauses with the tree, so paused time costs nothing.
- **Input actions** are predefined in `project.godot` (no manual setup): `turn_left` (A), `turn_right` (D), `toggle_horizontal_sail` (F), `toggle_vertical_sail` (G), `observe` (E), `toggle_map` (M). Pause is the built-in `ui_cancel` (Esc). Camera zoom is mouse-wheel, handled directly in ShipController (not an action).
- **Hand-authored `.tscn` files:** open in the editor and save once to canonicalize. Don't rely on exported node references in hand-written scenes — wire node refs in code (see `ship_visual.gd`, `world.gd`).
- **Shader globals:** the FFT ocean's shaders use `global uniform`s registered in `project.godot` `[shader_globals]` (`water_color`, `foam_color`, `num_cascades`, `displacements`, `normals`). If the water shader fails to compile saying a global "does not exist", they're missing.
- **Ocean mesh LODs:** `assets/water/clipmap_*.obj.import` must keep `generate_lods=false`. If a reimport flips it on, the waves flatten into smooth swells (4.7 decimates the clipmap). See `OCEAN_INTEGRATION.md`.
- **Renderer:** Forward+ / Vulkan. The ocean's compute works on it; `d3d12` is a fallback only.

## 9. The save system

**One slot, one JSON file:** `user://save.json` (Windows: `%APPDATA%\Godot\app_userdata\Age of Discovery\`). Human-readable — hand-edit gold for testing, or send it to a teammate to reproduce a bug. Settings are separate (`user://settings.cfg`) and are *not* part of the save.

**When it saves:** automatically on every docking (`port_entered` → `world.autosave()`) and on the pause menu's "Save & Main Menu". Deliberately no save-anywhere-at-sea: reaching port banks your progress, which keeps voyages tense.

**What it saves:** player (name, gold, skills, fame) · fleet (per ship: durability, crew, supplies, morale, cargo) · current port · `flags` (misc world state, incl. fog-of-war as base64 PNG and the ship's position as `[x,y,z]`) · clock · found discoveries · every port's market state.

**The contract:** everything goes through `to_dict()`/`from_dict()` pairs, and everything inside them must be **JSON-representable** — numbers, strings, bools, arrays, string-keyed dicts. Raw bytes must be base64 (`Marshalls.raw_to_base64`); Vector3s must be number arrays. A raw `PackedByteArray` survives in memory but comes back from JSON as a String and crashes typed assignments (this happened with the fog bitmap — hence the base64 rule). Corollary: **new stateful features must add their fields to a `to_dict()`/`from_dict()` pair or they silently reset on load.** `new_game()` must also reset them.

The same `to_dict()` data is the future co-op sync format, so keeping it clean pays twice.

## 10. Where to go next

**Immediate next: M5** — guided objective tracked on the HUD + voyage summary screen, then a Windows export (see `PROJECT_PLAN.md` §3). M3 leftovers in parallel: migrate the HUD to `hud.tscn`, more goods + a 3rd port when ready, spyglass tuning.

**Post-demo:** the land & cities visual roadmap (`PROJECT_PLAN.md` §4 — terrain shader polish → Terrain3D migration → city scenes with sea-visible LOD), then the parking lot: quests/taverns, fame consumption, shipyard (the sail-mount API in `ship_visual.gd` is waiting for it), fleet/crew depth, factions, naval combat, co-op replication of the State layer.

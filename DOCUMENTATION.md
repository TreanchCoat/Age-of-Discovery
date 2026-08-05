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
Pure signal declarations, no logic. Current signals: `hour_passed`, `day_passed` · `port_entered/left`, `undock_requested`, `weather_changed` · `discovery_spotted/lost/made` · `trade_executed`, `prices_updated` · `supplies_short`, `voyage_event_fired/resolved` · `city_building_interacted`, `city_enter_requested`, `city_left` · `objective_updated/completed` · `fame_changed`, `gold_changed`. (`city_*` become `location_*` when the land owner's LandManager lands — see `LAND_PLAN.md`.)

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

1. `spot(id)` — ship entered a DiscoveryArea. Emits `discovery_spotted` (re-emits on re-entry). Sailing out unconfirmed emits `discovery_lost` and the banner drops — the banner is always range-honest.
2. `confirm(id, roll_bonus)` — skill check: `observation + roll_bonus + d20 >= difficulty`. On success: fame + gold rewards, observation skill grows by 1 (learn-by-doing), emits `discovery_made`. The `roll_bonus` (+10) comes from a clean spyglass minigame hit.

Found entries feed the **Journal (J)**; `DiscoveryDef.hidden` keeps quest/myth discoveries out of it until found. Agreed direction: some discoveries random, some quest-tied, some quest-STARTING (finding them opens a quest); historical setting with mythic seasoning — designed properly once the quest framework lands.

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

Most UI is still built from code (greybox); the HUD is a scene (`scenes/ui/hud.tscn`) — migrate others the same way as they stabilize.

### PortMarketUI — `port_market_ui.gd`
Opens **centered** on `port_entered` with a green "Voyage Successful — Welcome to {Port}" banner. Per good at this port: live price, held quantity, Buy/Sell ×1/×10 (every good trades at every port). Footer: water/food + Resupply button (via SupplySystem), cargo weight. **"Enter the city"** (visible only where a city scene exists) hides the panel and emits `city_enter_requested`; the panel reopens on `city_left`. The "Weigh anchor — set sail" button emits `undock_requested` (respawns the ship at sea) and closes the panel. Subscribes to `prices_updated`/`trade_executed`/`gold_changed`.

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

### HUD — `scenes/ui/hud.tscn` + `hud.gd`
The at-sea HUD is a **scene** — widgets are laid out in the editor, `world.gd` just instances it and calls `setup(ship, wind)` (runtime refs injected in code, per the golden rules). `hud.gd` owns the status line (time/gold/port, discovery flash), the per-frame sail readout, and **`toast(text)`** — the transient bottom-center message channel (use it for voyage-event effect feedback). Widget children (Minimap/Compass/Helm) keep their own scripts. Adding a widget: add the node in `hud.tscn`, script it, wire refs in `setup()` if needed.

### DiscoveryJournalUI — `discovery_journal_ui.gd`
Toggled with **J**. Every discovery as a card: found → name, category, day charted, lore; unfound → "???" with a category hint (a to-do list for explorers); `DiscoveryDef.hidden = true` entries are absent until found — the hook for quest-gated/mythic discoveries revealed by rumors or quests.

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
8. HUD: instances `scenes/ui/hud.tscn` (status, sail readout, minimap, compass, helm, toast area) + CharacterSheetUI (C) + DiscoveryJournalUI (J).

`world.autosave()` snapshots the ship position into `flags["ship_pos"]` and calls `GameState.save_game()`; it runs on every `port_entered` and from the pause menu.

---

## 8. Conventions & gotchas

- **Tabs** for indentation (Godot standard).
- **StringName** (`&"id"`) for all ids — fast comparisons, and `.tres` files declare them as `&"..."`.
- **Typed arrays in .tres:** `Array[StringName]([&"wine"])` syntax.
- **Adding a signal?** Declare in EventBus only; emit from the owning system.
- **Adding a system?** Node in the world scene if it needs the scene/ticks via EventBus; autoload only if it must survive scene changes or be globally addressable.
- **Pause behavior:** modal UIs (events, spyglass) set `get_tree().paused = true` and run with `PROCESS_MODE_ALWAYS`. WorldClock pauses with the tree, so paused time costs nothing.
- **Input actions** are predefined in `project.godot` (no manual setup): `turn_left` (A), `turn_right` (D), `toggle_horizontal_sail` (F), `toggle_vertical_sail` (G), `observe` (E), `toggle_map` (M), `toggle_character` (C), `toggle_journal` (J), `walk_*` (WASD on foot). Pause is the built-in `ui_cancel` (Esc). Camera zoom is mouse-wheel, handled directly in ShipController (not an action).
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

---

## 11. The progression exoskeleton (skills, items, NPCs, facilities)

Six empty-but-wired frameworks added so future features are content drops, not engineering. **Nothing ships in them yet by design.** UI: press **C** in game for the Captain's Sheet (skills / inventory / stats). All state saves automatically (`GameState.skills` / `.inventory` in the save JSON) and resets on New Game.

### 11.1 StatSheet — the modifier engine (`scripts/core/stat_sheet.gd`)

Every tunable number can be a stat: `value(stat) = (base + Σ add) × Π mul`. Modifiers are tagged by source (`&"skill:navigation"`, `&"equip:spyglass"`) and removed by source — re-applying is always `remove_source()` + add, so nothing double-stacks. The player's sheet is `GameState.sheet`; it is **derived, never saved** — `GameState.rebuild_sheet()` reconstructs it from skills + equipment after load.

To make an existing system read a stat (the adoption pattern, one line):
```gdscript
var radius := def.spot_radius * (1.0 + GameState.sheet.value(&"spot_radius_pct") / 100.0)
```
**Stat vocabulary** (grow this list as stats get consumed; agree on names here):
`spot_radius_pct` · `ship_speed_pct` · `turn_rate_pct` · `trade_discount_pct` · `supply_use_pct` · `event_chance_pct` · `spyglass_sweet_pct`. Nothing consumes these yet — wire them into ShipController/EconomySim/etc. as skills and gear that grant them appear.

### 11.2 Skills (`SkillDef` + `SkillSet` + `SkillDB`)

Defs in `data/skills/*.tres`, auto-loaded. State (levels/XP) in `GameState.skills`. Learn-by-doing: gameplay calls `SkillDB.grant_player_xp(&"navigation", 5.0)` at the matching moment (a day sailed, a trade closed) — level-ups auto-refresh the sheet. Passive effects are per-level `StatModDef`s; active skills set `ability_id` (hook only for now).

**Add a skill** — save as `data/skills/navigation.tres`:
```
[gd_resource type="Resource" script_class="SkillDef" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/data/skill_def.gd" id="1"]
[ext_resource type="Script" path="res://scripts/data/stat_mod_def.gd" id="2"]

[sub_resource type="Resource" id="mod1"]
script = ExtResource("2")
stat = &"ship_speed_pct"
add_per_level = 0.0
percent_per_level = 1.5

[resource]
script = ExtResource("1")
id = &"navigation"
display_name = "Navigation"
category = "sailing"
description = "Reading wind and water. Grows with every day at sea."
max_level = 10
base_xp = 100.0
xp_growth = 1.5
modifiers = Array[Resource]([SubResource("mod1")])
```
Then hook its XP source, e.g. in a `day_passed` listener: `SkillDB.grant_player_xp(&"navigation", 10.0)`. It appears on the Captain's Sheet immediately.

### 11.3 Items & equipment (`ItemDef` / `EquipmentDef` + `Inventory` + `ItemDB`)

Defs in `data/items/*.tres`. Personal items ≠ trade goods (those stay `GoodDef`/CargoHold). Equipment declares a `slot` (free-form StringName — current vocabulary: `spyglass`, `weapon`, `coat`; ship slots `cannon`, `sail_main`, `sail_fore` reserved for the shipyard). `GameState.inventory.equip(&"brass_spyglass", GameState.sheet)` swaps slots and applies modifiers; granting items is `GameState.inventory.add(&"id")` or a RewardBundle.

**Add an equipment item** — `data/items/brass_spyglass.tres`:
```
[gd_resource type="Resource" script_class="EquipmentDef" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/data/equipment_def.gd" id="1"]
[ext_resource type="Script" path="res://scripts/data/stat_mod_def.gd" id="2"]

[sub_resource type="Resource" id="mod1"]
script = ExtResource("2")
stat = &"spot_radius_pct"
percent_per_level = 20.0

[resource]
script = ExtResource("1")
id = &"brass_spyglass"
display_name = "Brass Spyglass"
category = "equipment"
description = "A merchant officer's glass. Spots sails a league further."
base_price = 800
slot = &"spyglass"
modifiers = Array[Resource]([SubResource("mod1")])
```
(For equipment, `percent_per_level`/`add_per_level` apply once, not per level.)

### 11.4 NPCs (`NPCDef` + `NPCCharacter` / `NPCCaptain` + `NPCDB`)

Defs in `data/npcs/*.tres`; anyone with `home_city = &"lisbon"` spawns in Lisbon's street mode automatically (wanders near the plaza, E to talk — lines cycle from the def; toast UI until the dialogue framework exists). `NPCCaptain` is the sea-side chassis: parent it to any Node3D and it patrols waypoints / approaches / flees — **placeholder motion**; at combat time it switches to feeding real ship inputs, but its API (states, waypoints, target) is what AI work should build against.

**Add an NPC** — `data/npcs/old_mateus.tres`:
```
[gd_resource type="Resource" script_class="NPCDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/data/npc_def.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"old_mateus"
display_name = "Old Mateus"
role = "sailor"
home_city = &"lisbon"
color = Color(0.55, 0.4, 0.3, 1)
lines = Array[String](["Forty years before the mast, boy.", "Mind the shallows past the headland."])
```

### 11.5 Requirements & rewards (`Requirement` / `RewardBundle`)

The two primitives every future system shares. `Requirement` covers gold/skill/fame/flag/discovery/item checks — build an `Array[Requirement]` and call `Requirement.all_met(reqs)`; each also has `describe()` for UI. `RewardBundle.grant()` pays out gold/fame/items/skill-XP/flags in one call. Use these in quests, dialogue choices, facility actions, titles — never hand-roll the checks again.

### 11.6 Facilities (`Facility` + `Facilities` autoload)

City buildings route through the `Facilities` registry: registered type → its screen opens; unregistered → "not yet open" toast. The tavern is registered as the working example.

**Add a facility** (e.g. the bank): create `scripts/ui/facilities/bank_facility.gd`:
```gdscript
class_name BankFacility
extends Facility

func facility_title() -> String:
	return "Bank of %s" % String(city_id).capitalize()

func _build_content(box: VBoxContainer) -> void:
	var l := Label.new()
	l.text = "Deposits, loans, letters of credit."
	box.add_child(l)
	# buttons -> real logic; gate options with Requirement, pay with RewardBundle
```
then one line in `facilities.gd _ready()`:
```gdscript
register(&"bank", preload("res://scripts/ui/facilities/bank_facility.gd"))
```
The frame (dim, panel, title, Leave button, Esc-closes) is inherited.

### 11.7 Integration status & adoption plan

Built but deliberately not yet consuming each other: `CharacterStats`' five hardcoded ints still drive spyglass/events (migrate them to real SkillDefs when the first skills land — then `stats.observation` reads become `skills.level(&"observation")` + sheet stats); ship speed doesn't read the sheet yet; no XP sources are wired. Each adoption is a one-line change at the call site — that's the point of the exoskeleton.

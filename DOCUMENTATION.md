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

Registered in `project.godot`, alive for the whole game, in load order:

### EventBus — `scripts/autoload/event_bus.gd`
Pure signal declarations, no logic. Current signals: `hour_passed`, `day_passed`, `port_entered/left`, `undock_requested`, `weather_changed`, `discovery_spotted/made`, `trade_executed`, `prices_updated`, `supplies_short`, `voyage_event_fired/resolved`, `fame_changed`, `gold_changed`.

### WorldClock — `scripts/autoload/world_clock.gd`
Converts real seconds to game minutes (`MINUTES_PER_REAL_SECOND`, default 2.0 → one game day per 12 real minutes). Emits `hour_passed`/`day_passed` through EventBus; all simulation hangs off these ticks. `total_minutes` is the single source of truth — events that "cost time" (e.g. riding out a storm) just add to it.

### GameState — `scripts/autoload/game_state.gd`
Owns the player: `gold` (setter clamps and emits `gold_changed`), `stats` (CharacterStats), `ship` (active ShipState), `fleet` (all owned ships), `current_port` (empty StringName = at sea), `flags` (misc dictionary — also stores the map fog bitmap). `save_game()`/`load_game()` serialize everything, including the other autoloads, to `user://save.json`.

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

### ShipController — `ship/ship_controller.gd` (CharacterBody3D)
Player ship. Steering is via a **helm/wheel**: A/D swing a `wheel` value toward a side (`WHEEL_TURN_RATE`), releasing lets it spring back to center (`WHEEL_RETURN_RATE`); the ship rotates at a rate set by wheel position × `turn_rate` × a speed factor × `pace`. Turn authority scales with speed but never below `MIN_STEERAGE` (0.3), so you can't get stuck in irons. **Two sails**, toggled F (horizontal/square) and G (vertical/fore-and-aft); each eases toward its commanded state (`SAIL_CHANGE_RATE`) so furling lets thrust decay rather than cut out. **Pace** (0.5→1.0) builds +5%/s while making way and steering straight, bleeds while turning, and falls back to 50% when stopped or both sails are down; it scales both speed and turn rate. Target speed = `effective_speed(...) × wind.strength × pace`, approached with inertia (`move_toward`); `velocity.y` is zeroed each frame so the flat sea is never left. Mouse wheel zooms the chase camera (`ZOOM_MIN`–`ZOOM_MAX`). On `port_entered` the ship docks (`set_at_sea(false)`: hull hidden, frozen, sails furled); on `undock_requested` it respawns just outside the harbor. `use_fallback_observe` — when SpyglassUI is present, the plain E-to-confirm fallback is disabled.

### DiscoveryArea / PortArea — `systems/discovery_area.gd`, `port_area.gd` (Area3D)
Proximity triggers built from their Def's position/radius at runtime. DiscoveryArea → `DiscoveryDB.spot()`. PortArea → sets `GameState.current_port`, emits `port_entered`/`port_left` (which opens/closes the market UI).

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

- **Background:** empty parchment ColorRect for now. When real map art exists, set `map_texture` — everything else already works.
- **Fog of war:** a 512² RGBA image, opaque dark; each game hour a soft-edged circle is punched transparent around the ship. Persisted as PNG bytes in `GameState.flags["fog_png"]`, so it saves/loads automatically.
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

---

## 7. World bootstrap — `scenes/world/world.gd`

`world.tscn` is a single Node3D with this script; everything is generated in `_ready()` so the game runs with zero art:

1. Environment (sun + procedural sky), 4000² sea plane.
2. WindSystem, SupplySystem.
3. PortArea + greybox box marker per `data/ports/*.tres`; DiscoveryArea per DiscoveryDB def.
4. Player ship (greybox box hull + chase camera) just off Lisbon; refs kept in `_ship`/`_wind`.
5. PortMarketUI, WorldMapUI (registered to ship), VoyageEventSystem + its UI, SpyglassUI (disables the ship's fallback observe).
6. HUD: status + sail readout, MinimapUI, CompassUI, HelmIndicator.

Replace any piece with a real scene incrementally — e.g. give ShipDef.scene a real model and swap `_spawn_ship` to instance it.

---

## 8. Conventions & gotchas

- **Tabs** for indentation (Godot standard).
- **StringName** (`&"id"`) for all ids — fast comparisons, and `.tres` files declare them as `&"..."`.
- **Typed arrays in .tres:** `Array[StringName]([&"wine"])` syntax.
- **Adding a signal?** Declare in EventBus only; emit from the owning system.
- **Adding a system?** Node in the world scene if it needs the scene/ticks via EventBus; autoload only if it must survive scene changes or be globally addressable.
- **Pause behavior:** modal UIs (events, spyglass) set `get_tree().paused = true` and run with `PROCESS_MODE_ALWAYS`. WorldClock pauses with the tree, so paused time costs nothing.
- **Input actions** are predefined in `project.godot` (no manual setup): `turn_left` (A), `turn_right` (D), `toggle_horizontal_sail` (F), `toggle_vertical_sail` (G), `observe` (E), `toggle_map` (M). Camera zoom is mouse-wheel, handled directly in ShipController (not an action).
- **Save data** lives at `user://save.json` (on Windows: `%APPDATA%/Godot/app_userdata/Age of Discovery/`).

## 9. Where to go next

In rough order of value: tavern/quest hooks pointing at discoveries (gives players direction), more content (ports/goods/events are pure data now), a real ocean shader + ship model, port supply/demand affected by world events, then naval combat as an instanced scene, then co-op replication of the State layer.

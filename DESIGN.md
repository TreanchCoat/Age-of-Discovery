# Age of Discovery (working title)

Singleplayer/co-op reimagining of Uncharted Waters Online in Godot 4.7, GDScript, 3D low-poly.

> This file is the **vision**. For what's actually built and what's next, see
> `PROJECT_PLAN.md` (current status + roadmap) and `DOCUMENTATION.md` (technical reference).
> The sea is a ported **FFT ocean** — details + the buoyancy plan in `OCEAN_INTEGRATION.md`.

## Vision

Keep: the fantasy of being a captain in the Age of Sail — exploration, discoveries, trade, fleets, port-to-port life.
Fix (common UWO complaints):
- No grind-as-content: skill progression through *doing interesting things*, not repetition counters.
- No timer-gated travel padding: sailing is engaging (wind, currents, hazards, events), and fast travel unlocks on routes you've mastered.
- Offline economy that reacts to *you* (and co-op partners), not thousands of bots.
- Clear information: in-game encyclopedia, no wiki-required design.
- Meaningful discoveries: each one has a story hook, a reward, and a world effect — not just an XP packet.

## Pillars

1. **The sea is the game** — wind, weather, supplies, crew morale make every voyage a decision chain.
2. **Discovery drives everything** — discoveries unlock trade goods, routes, quests, ship upgrades.
3. **One world, persistent simulation** — ports/prices/factions tick on a world clock whether you're there or not.
4. **Co-op ready from day one** — all gameplay state lives in data (Resources/dictionaries), authority abstracted so a host can replicate it later.

## High-level architecture

```
Autoloads (singletons)
  GameState       — save/load, current player profile, global flags
  WorldClock      — game time, tick signals (hour/day), pause
  EventBus        — global signals (discovery_made, port_entered, price_changed...)
  EconomySim      — port markets, price drift, supply/demand ticks
  DiscoveryDB     — discovery catalog, what's found, by whom
  Settings        — user preferences (volume...), separate from saves

Scenes
  MainMenu        — entry point; New Game / Continue / Settings
  World (3D)      — FFT ocean, GEBCO terrain, port + ship scene instances
  Ship            — ship.tscn: hull, swappable-sail mounts, buoyancy, camera
  Port (UI-heavy) — market now; shipyard, tavern, governor later
  Battle (later)  — instanced naval combat

Data (Resources, .tres)
  GoodDef, PortDef, ShipDef, DiscoveryDef, VoyageEventDef,
  CharacterStats, ShipState, CargoHold
```

Rule of thumb: **Defs are immutable catalog data; States are mutable save data.** Systems operate on States using Defs.

## Class hierarchy (scripts/)

```
RefCounted
  CargoHold

Resource
  GoodDef, PortDef, ShipDef, DiscoveryDef
  CharacterStats
  ShipState (refs a ShipDef)
  SaveGame

Node
  EventBus, WorldClock, GameState, EconomySim, DiscoveryDB (autoloads)
  WindSystem

CharacterBody3D
  ShipController (player's ship at sea)
```

## First vertical slice: Exploration

Goal: sail a low-poly sea between 3 ports, with wind affecting speed, fog of war on the world map, and 5 discoverable points of interest (landmark, sea creature, ruin, current, island). Discovering grants fame + unlocks a map note.

Slice checklist — **all done** (and overshot: the "low-poly sea" became a realistic FFT ocean with real terrain):
- [x] Data layer: defs + states
- [x] WorldClock, EventBus, GameState autoloads
- [x] WindSystem + ShipController (wind-relative speed → two-sail model)
- [x] DiscoveryDB + proximity-based DiscoveryArea
- [x] Ocean + port markers (FFT ocean, GEBCO terrain, port scenes)
- [x] World map UI with fog of war (texture-based reveal, saved with the game)
- [x] Spyglass/observation minigame to confirm a discovery

## Roadmap after slice

1. ~~Port life: market UI, buy/sell using EconomySim~~ ✅
2. ~~Supplies & crew: water/food/morale consumption per day, scurvy events~~ ✅
3. Demo framing: guided objective + summary screen + export (current — see PROJECT_PLAN M5)
4. Land & cities visual pass: terrain textures/waterline → Terrain3D (in-editor sculpting) → city scenes visible from the sea with LOD (PROJECT_PLAN §4)
5. Shipyard & ship customization: bought cannons, swappable sails, refits (see "Ship customization")
6. Quests: tavern rumors pointing at discoveries
7. Naval combat — seamless, in-world (see "Naval combat"); prizes feed fleet management (multiple ShipStates, NPC captains)
8. Co-op: host-authoritative replication of States via Godot multiplayer API

## Ship customization (core progression axis)

Customization is a **big part of the game** — the main thing trade profits buy. The ship is a loadout, not a stat block:

- **Hulls** (ShipDef) set the frame: speed potential, cargo, crew, mount slots.
- **Sails** are swappable models/stats on the ship's mount points (`ship_visual.gd` API already exists) — square vs fore-and-aft tradeoffs plug straight into the two-sail sailing model.
- **Cannons are bought equipment** (`CannonDef` .tres: damage, range, reload, weight, price) mounted per broadside. Weight competes with cargo — a trader who guns up carries less.
- Later: figureheads/flags (identity), hull refits (armor vs speed), special fittings (larger water casks, reinforced holds).

Everything lives in `ShipState` (saves/syncs for free) and renders via mount nodes on `ship.tscn` — the ship you sail visibly reflects what you bolted on.

## Naval combat (agreed direction)

**Seamless, in-world, real-time — combat IS sailing.** No instanced arenas (that was an MMO constraint UWO had; we don't). The wind, helm, and sail mechanics are the tactics system: weather gauge, broadside arcs, stern rakes.

- **Encounters are real ships**: events spawn hostiles at distance; the spyglass identifies them; fleeing by wind-craft is a legitimate, skill-based out.
- **NPC ships** are `ship.tscn` driven by AI captains feeding the same inputs a player uses (approach / engage / break off) — they obey the same physics, so they feel like ships.
- **Broadsides**: port/starboard arcs, range bands, slow reloads; you aim by steering. Shot types map to existing stat tracks — round → durability, chain → sail health (speed), grape → crew.
- **Morale ends fights**: ships strike their colors; plunder, press crew, or **capture the prize** (captured ships seed the fleet system). Sinking is the messy exception.
- **Boarding is resolved, not simulated**: crew/morale/skill-driven choice rounds in the event-UI style. No separate melee game — UWO's weakest system stays dead.

Build order: pirate + round shot + surrender/flee AI → shot types + sail damage → boarding/capture → encounter variety (navy, escorts, fleet fights).

## Visual direction: land & cities

The sea sets the bar (FFT waves, foam, spray); land must not feel like a different game. Direction: textured, LOD'd terrain (Terrain3D) with hand-fixable coasts and harbors; cities built once as modular low-poly scenes and **seen honestly from the water** — the skyline you sail toward is the city you dock in, swapped to cheaper LOD tiers with distance, never a painted backdrop.

## Co-op notes (design now, build later)

- Never mutate world state directly from UI/input; route through systems (EconomySim, DiscoveryDB) — these become server-side later.
- All States serializable to Dictionary (see `to_dict()/from_dict()` pattern) — doubles as save format and network sync format.

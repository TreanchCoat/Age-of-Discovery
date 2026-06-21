# Age of Discovery (working title)

Singleplayer/co-op reimagining of Uncharted Waters Online in Godot 4.x, GDScript, 3D low-poly.

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

Scenes
  World (3D)      — ocean, ports as nodes, ship
  Port (UI-heavy) — market, shipyard, tavern, governor
  Battle (later)  — instanced naval combat

Data (Resources, .tres)
  GoodDef, PortDef, ShipDef, DiscoveryDef, CharacterStats, ShipState, CargoHold
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

Slice checklist:
- [x] Data layer: defs + states (this scaffold)
- [x] WorldClock, EventBus, GameState autoloads
- [x] WindSystem + ShipController (wind-relative speed)
- [x] DiscoveryDB + proximity-based DiscoveryArea
- [ ] Greybox ocean + 3 port markers (in-editor work)
- [ ] World map UI with fog of war (texture-based reveal)
- [ ] Spyglass/observation interaction to confirm a discovery

## Roadmap after slice

1. Port life: market UI, buy/sell using EconomySim
2. Supplies & crew: water/food/morale consumption per day, scurvy events
3. Quests: tavern rumors pointing at discoveries
4. Naval combat (instanced)
5. Fleet management (multiple ShipStates, NPC captains)
6. Co-op: host-authoritative replication of States via Godot multiplayer API

## Co-op notes (design now, build later)

- Never mutate world state directly from UI/input; route through systems (EconomySim, DiscoveryDB) — these become server-side later.
- All States serializable to Dictionary (see `to_dict()/from_dict()` pattern) — doubles as save format and network sync format.

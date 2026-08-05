# Land Plan — the land-owner's roadmap

Division of labor: **sea** (world scene, sailing, ocean, naval combat, trade sim) vs **land** (everything after you step off the ship). This file is the land side's map. Architecture diagram: see the project chat / PROJECT_PLAN.

## 0. What land already has (inventory)

- **Terrain:** `HeightmapTerrain` — GEBCO 513² heightmap → mesh + collision, saturating height curve, flat aprons around ports, height/slope color shader (no textures yet). Landmask feeds the water shader. Post-demo plan: shader polish → **Terrain3D** migration (in-editor sculpting) — PROJECT_PLAN §4.
- **Cities:** `city_lisbon.tscn` / `city_funchal.tscn` — currently ONE scene with TWO modes (sea-view skyline scaled 2.5×, `StreetLevel` toggled for walking). **This changes: street level becomes a separate loaded scene (your first job).** Typed greybox buildings (market/shipyard/tavern/bank/governor/church/warehouse/house) with door markers, name labels, interact contract.
- **On-foot player:** `CityPlayer` — WASD camera-relative walk, ship-style orbit/zoom camera, E-interact with nearest building/NPC.
- **NPCs:** `NPCDef` .tres → `NPCDB` → wandering `NPCCharacter`s auto-spawn per city; placeholder dialogue lines cycle on E. `NPCCaptain` exists but is sea-side.
- **Facilities:** registry (`Facilities` autoload) mapping building type → UI screen; tavern registered as example; everything else toasts "not yet open".
- **Shared exoskeletons (use these, don't reinvent):** `StatSheet` (all number-changing effects), `SkillSet`/`SkillDB` (levels/XP), `ItemDef`/`Inventory` (equipment slots incl. `weapon`), `Requirement`/`RewardBundle` (gates and payouts), EventBus signals, JSON save contract (DOCUMENTATION.md §9, §11).

## 1. Architecture decisions (agreed)

- **Land locations are separate scenes**, loaded on entry (dock / land / travel), world scene unloaded. Return re-enters the world at the ship. Loading screen covers the swap.
- **Sea keeps:** the world scene, skyline LOD instances, the dock/land prompts (door handles). **Land owns:** everything loaded after those prompts.
- **All land state that must persist rides the autoloads** (GameState etc.) — they survive scene changes already. Anything new that persists gets a `to_dict()/from_dict()` pair and a line in `save_game()` (JSON-safe only!).
- **Location graph is data:** `LocationDef` .tres (id, type: port_city / inland_city / wilderness, scene path, region/biome, `connections: Array[StringName]` with travel costs). Cities we dock at are just one location type.
- **Land combat is real-time action, in-scene** (enemies exist in the wilderness scene; no arena teleport — the anti-UWO rule). Genre drift toward light action-adventure is accepted and intended.

## 2. The build order (maps 1:1 to Trello cards below)

### Phase A — Foundation (everything depends on this)
**A1. LocationDef + LocationDB.** Resource + autoload registry (copy the SkillDB pattern). Fields: id, display_name, type, scene_path, biome, connections (array of {to, hours}), requirements (Array[Requirement]).
**A2. LandManager scene flow.** Autoload owning `enter_location(id, entry &"harbor")` / `return_to_sea()`: loading screen, `change_scene_to_file`, spawn player at named entry Marker3D, emit `location_entered/left` on EventBus (replaces city_enter/city_left — coordinate the rename with sea side). Autosave on every transition.
**A3. Convert the two cities to standalone scenes.** Street content moves into `location_lisbon.tscn` / `location_funchal.tscn` (own ground, entries: `Harbor`, `LandGate`). World keeps skyline-only instances. Market's "Enter the city" and the return flow now go through LandManager.
**A4. Land player v2.** Promote CityPlayer to `LandPlayer`: sprint, interact prompt UI ("E — Tavern"), footstep-ready animation hooks, HP field (combat needs it), reads `GameState.sheet` for move-speed stats.

### Phase B — World structure: travel & the wild
**B1. Overland travel.** LandGate → travel UI listing connected locations (from LocationDef graph): shows hours, advances WorldClock, rolls travel events (reuse the VoyageEventDef pattern — generalize or clone as `TravelEventDef`), then loads the target scene. Walking the whole distance is explicitly NOT the plan (travel is a menu + events, like a land voyage).
**B2. First inland city.** One new `LocationDef` + scene (e.g. Évora inland from Lisbon): no harbor, same facilities framework, at least one unique trade hook (a good only sold there — coordinates with sea-side economy later).
**B3. Wild landing.** Sea side exposes a "Land here (E)" prompt near shallow coasts (they own the prompt; you own what it loads): LandManager picks/generates the wilderness location for that coast's biome.
**B4. Wilderness scenes.** One scene per biome to start (forest, jungle): greybox terrain patch, MultiMesh tree/rock scatter, named entry, exit zone back to ship. Points of interest placed from data: land discoveries (reuse DiscoveryDef — add a `terrain` flag), gathering nodes (RewardBundle on interact), a ruin shell.

### Phase C — Dynamic land combat (the genre-drift centerpiece)
**C1. Combat design one-pager FIRST.** Agree on feel before code: lock-on or free? dodge roll or block? stamina? How lethal? Write it into this file. (Recommendation: start Zelda-ish light action — attack combo, dodge, no stamina, generous i-frames; tune from there.)
**C2. EnemyDef + enemy framework.** .tres catalog (hp, damage, speed, aggro/leash radius, attack pattern id, loot RewardBundle) + `EnemyCharacter` (CharacterBody3D + state machine: idle → aggro → attack → recover → flee/death). Spawner node for wilderness scenes.
**C3. Combat prototype arena.** `combat_sandbox.tscn` (F6-run like the cities): LandPlayer with melee attack (weapon from `Inventory` slot `&"weapon"`, damage via `StatSheet`), one enemy type, hit reactions, death + loot drop. Iterate here until it feels good — THEN it graduates to wilderness scenes.
**C4. Integrate combat into wilderness.** Spawners in biome scenes, loot flows to Inventory, XP to combat skills (learn-by-doing), player death consequence (respawn at ship, lose ?— design in C1).
**C5. Crew as land party (later, flagged).** Bring N crew ashore as AI followers who fight; ties to ship crew count. Park until C1–C4 proven.

### Phase D — Integration & polish
**D1. World map shows locations** (inland cities, known landing sites) + current location badge.
**D2. Save/load audit** for all land state (position-in-location on save? or always re-enter at entry point — simpler, recommended).
**D3. Docs:** every new system gets its DOCUMENTATION.md section + how-to-add recipe (follow §11's format).

## 3. Contracts with the sea side (don't break these)

- Signals: `location_entered(id)` / `location_left(id)` replace `city_*` — one PR, both sides updated together.
- The world scene, ship, ocean, PortArea/dock prompts stay sea-side; land never edits `world.gd` beyond the agreed handoff calls.
- Shared exoskeletons are shared: additions welcome, breaking changes need a shout in chat first.
- Save format rules: DOCUMENTATION.md §9. JSON-safe, `to_dict()` pairs, reset in `new_game()`.

## 4. Trello cards (copy-paste)

List "Land — Foundation": A1 LocationDef+DB · A2 LandManager scene flow + loading screen · A3 Cities → standalone scenes · A4 LandPlayer v2
List "Land — Travel & Wild": B1 Overland travel UI + events · B2 First inland city · B3 Wild landing handoff · B4 Biome wilderness scenes + POIs
List "Land — Combat": C1 Combat one-pager · C2 EnemyDef + AI framework · C3 Combat sandbox prototype · C4 Wilderness integration · C5 Crew land party (parked)
List "Land — Integration": D1 Map locations · D2 Save audit · D3 Docs

Order: A strictly first (everything sits on it), B and C can interleave after A3 — but do C1 (design) early, it's free and prevents rework.

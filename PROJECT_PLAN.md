# Project Plan — Age of Discovery (UWO remake)

A learning-Godot-with-friends project. The point is twofold: **learn the engine** and **get to a playable demo fast**. This plan turns the scaffold (see `DESIGN.md` and `DOCUMENTATION.md`) into something you can hand to a friend and say "play this."

- **Team:** 2–3 of you, casual weekend pace.
- **Optimize for:** a fun, shareable vertical slice. Depth (combat, fleets, factions, co-op) is explicitly parked until after the demo.
- **Engine:** Godot 4.7, GDScript. Project lives at `S:\Godot Projects\UWO\uwo`.

---

## 1. What "the demo" actually is

One tight loop a stranger can finish in ~10 minutes and enjoy:

> Start a new game from a menu → sail out of Lisbon → navigate past a coastline (don't run aground) → reach Funchal → buy low / sell high to make a target amount of gold → survive one voyage event → spot and confirm one discovery with the spyglass → see it on your map → hit a "voyage complete" summary screen.

**Demo is done when:** a friend can download one `.exe`, reach the summary screen without you sitting next to them, and say it felt like sailing.

---

## Current status (kept up to date)

Engine is **Godot 4.7**. Nearly everything except the M5 finish line is built:

- **Sailing:** two-sail model (horizontal/square + vertical/fore-aft), steering-wheel helm with momentum + minimum steerage, pace (50→100%) affecting speed & turning, gradual sail furl. Drifting wind (direction + strength) drives ship *and* waves.
- **World:** the **FFT ocean** (realistic *GodotOceanWaves* port — see `OCEAN_INTEGRATION.md`): follows the ship, wind-driven, far-ocean ring to ~2048. **Real GEBCO terrain** (Iberia/Madeira heightmap, saturating height curve, coastline collision + hull damage, shallow-water zones). Ship **buoyancy** on the waves (visual hull pivot, level physics).
- **Scenes (not code-built):** `scenes/ship/ship.tscn` (hull + swappable-sail mount points + camera + buoyancy), `scenes/port/port.tscn` (PortArea + marker + name label), `scenes/menu/main_menu.tscn`.
- **Loop:** dock/undock with "Voyage Successful" + centred market (3 goods, per-visit price variation), supplies/morale, voyage events (storm/scurvy/dolphins), discovery + spyglass minigame.
- **Game framing (M4 ✅):** main menu (New Game / Continue / Settings / Quit — project main scene), Esc pause menu (Resume / Settings / Save & Main Menu), persisted master volume (`Settings` autoload → `user://settings.cfg`), ocean ambience audio, **autosave on docking** (snapshots ship position; Continue resumes there; fog-of-war stored base64/JSON-safe).
- **Instruments/UI:** HUD readout, minimap with map background (+ wind arrow), compass, helm dial, world map (fog of war), debug panel (backtick) with live ocean tuning.
- **Cities (bare bones, §4 Layer 3 seeded):** `city_lisbon.tscn` / `city_funchal.tscn` — one scene, two modes: greybox skylines (typed buildings: market, shipyard, tavern, bank, governor, church, warehouse, houses) visible from the sea at their ports; disabled `StreetLevel` + walkable cube captain (WASD/E, `city_player.gd`) for street mode. F6 a city scene to walk it today; hooking street mode into docking is future work. Building interactions emit `city_building_interacted` — future facility UIs (shipyard, bank, tavern) hang off that signal.
- **Ship health:** hull durability + collision damage.

**Immediate next: M5** — guided objective + voyage summary screen, then export a Windows build.

**Still not done:** HUD/market/map UIs are code-built, not scenes; real map art; wind audio + UI sounds; objective + summary; export. After the demo: the land & cities visual roadmap (§4).

---

## 2. How to work together (read this once)

You're 2–3 people in one Godot project. The single biggest source of pain will be **merge conflicts in scene files**, so a little discipline up front saves weekends later.

- **Git:** one repo, branch per feature (`feat/coastlines`, `ui/hud`), small frequent merges. Don't sit on a giant branch for three weeks.
- **The `world.tscn` rule:** Godot scenes are text but still merge badly. **Avoid two people editing the same `.tscn` at once.** Prefer building features as *their own scene* (ship, port, and main menu already are; HUD should follow) that gets instanced, rather than everyone adding nodes to `world.tscn`. When you must touch a shared scene, call it out in chat first.
- **Hand-authored `.tscn` gotcha:** if a scene file was written by hand/AI, open it in the editor and **save it once** — the editor rewrites it in canonical form (uids, node ids). Exported node references in hand-written scenes are unreliable; wire node refs in code instead (see `ship_visual.gd` / `world.gd` for the pattern).
- **`.gitignore`:** `.godot/` (import cache) stays ignored — never commit it. Commit `.tres`, `.tscn`, `.gd`, `project.godot`.
- **Content is conflict-free:** new ports/goods/ships/events/discoveries are just new `.tres` files in `data/`. Anyone can add these anytime without stepping on code.
- **Save-format rule:** anything persistent must be JSON-representable in a `to_dict()` — numbers/strings/bools/arrays/dicts only. Raw bytes → base64 (`Marshalls`), Vector3 → `[x, y, z]`.
- **Lanes, not silos:** ownership below is a default so work doesn't collide — help each other across lanes freely.

### Suggested roles (2–3 people)

| Lane | Owns | Good fit for someone who likes… |
|---|---|---|
| 🌊 **Captain** — sea & world | sailing feel, terrain/coastlines, ship model, ocean/sky, camera | 3D, movement, "game feel" |
| ⚓ **Quartermaster** — systems & UI | economy/trade, supplies, HUD, world map, spyglass polish | UI, numbers, systems |
| 🧭 **Bosun** — content & framing | `.tres` content, events, menus, audio, build/export | writing, glue, shipping |

If you're **two people:** Captain takes sea + world + build/export; Quartermaster takes systems + UI + content; split menus/audio between you.

### Pace & sizing

No dates — casual weekends. 1 session ≈ a 3–4 hour weekend sit-down.
🟢 **S** = part of a session · 🟡 **M** = ~1 session · 🔴 **L** = 2–3 sessions (or split across people)

---

## 3. The milestones

### M0 — Everyone sailing ✅ (solo bootstrap done; repeat the checklist when teammates join)

- [x] Install Godot, open the project (input actions ship in `project.godot` now — no manual setup).
- [x] Sail Lisbon → Funchal, market, map.
- [ ] 🟢 Teammates — clone, run, tweak one constant, merge one trivial PR (git-flow warm-up).

### M1 — Read the map of the code ✅ / ongoing for new teammates

- [x] `DOCUMENTATION.md` exists and is current; trace one flow end-to-end when onboarding.
- [ ] 🟢 Each new teammate — pick a lane, skim its files, add one `.tres` to prove content grows without code.

### M2 — Make it a world, not a void ✅

- [x] Coastlines + collision (real GEBCO terrain, hull damage, shallows).
- [x] A real ship (placeholder model in `ship.tscn`; buoyancy on the waves).
- [x] Water + sky (FFT ocean + far ring; procedural sky).
- [x] Camera pass (chase cam, wheel zoom, orbit).

### M3 — Make the loop feel good ⚓ (mostly done)

- [x] HUD readouts (status, sails, minimap, compass, helm).
- [x] Market UI with per-visit price variation; resupply.
- [x] Map background texture (terrain preview) in world map + minimap.
- [ ] 🟡 Quartermaster — migrate HUD into `hud.tscn` (it's still code-built in `world.gd`; do this before it grows more).
- [ ] 🟢 Bosun — expand to ~5–6 goods and a 3rd port so buy-low/sell-high has real choice. *(Deliberately deferred for now.)*
- [ ] 🟢 Quartermaster — spyglass tuning pass (banner timing, sweet-spot visibility).

### M4 — Wrap it in a game ✅

- [x] Main menu (New Game / Continue / Settings / Quit) — project main scene.
- [x] Pause menu on Esc (Resume / Settings / Save & Main Menu).
- [x] Minimal settings: persisted master volume. *(Windowed/fullscreen toggle still open.)*
- [x] Autosave on docking (+ ship position; Continue resumes there).
- [x] Ocean ambience audio. *(Still open: wind loop tied to wind strength, UI click sounds — 🟢 Bosun.)*

### M5 — One objective, then ship it 🏁 ← **YOU ARE HERE**

- [x] **A guided goal** — "Dock at Funchal · Amass 1500 gold · Confirm a discovery" checklist (bottom-left HUD, `ObjectiveSystem` + `ObjectiveUI`, progress saved in flags); completing all three triggers the **Voyage Complete summary** (days at sea, gold earned, discoveries, events survived) with Keep Sailing / Save & Main Menu.
- [ ] 🟡 All — **Playtest pass:** each person plays the full loop, lists what confused or broke. Fix the top 5.
- [ ] 🟡 Captain/Bosun — **Export** a Windows `.exe` (export templates, configure, build). Hand it to someone outside the team.

**Done when:** the demo definition in §1 is true and you have a shareable build.

---

## 4. After the demo: land & cities visual roadmap

The ocean now looks far better than the land. Post-M5, close that gap in three layers (agreed direction, not yet started — build in this order):

### Layer 1 — shader polish on current terrain 🟡–🔴
- Texture splatting (tileable sand/grass/rock albedo+normal) instead of flat height-band colors; triplanar on steep slopes.
- World-space noise octaves to break up the height banding.
- **Waterline integration** (the highest-value seam): wet-sand darkening band on terrain near y=0; shoreline foam + shallow-water tint in the water shader (it already receives `terrain_rect` + landmask — add the heightmap for depth-based effects).
- Distance fog/haze so far coasts fade atmospherically.

### Layer 2 — migrate terrain to **Terrain3D** (TokisanGames plugin) 🔴
The structural fix. Clipmap LOD (same trick as the ocean — dense near, sparse far, finally *consistent*), texture splatting built in, and **in-editor sculpt/paint brushes** — which is the "fix mistakes / build harbors by hand in the editor" requirement, solved without custom tooling.
- Source data: our GEBCO crop is 2880×2880 but we currently sample it at 513² — 5×+ coastline fidelity is already in the data. Convert `region_height.bin` → EXR/RAW for the Terrain3D importer; bake the saturating height curve into the import.
- Low migration risk: gameplay only needs "in `land` group + collision"; buoyancy/ship code never touches terrain internals; landmask→water pipeline unchanged.
- Terrain3D is a GDExtension (binary install from the Asset Library).
- **Don't** hand-roll a sculptor on the current ArrayMesh — that's rebuilding a worse Terrain3D.

### Layer 3 — cities you can see from the sea 🔴
Cities are real scenes (`city_lisbon.tscn`) anchored at their PortDef position, assembled from a modular low-poly building kit, **the same city up close and from the water**:
- LOD via `GeometryInstance3D.visibility_range_begin/end`: full buildings within ~150u → merged low-poly mass + landmark silhouettes to ~1500u → nothing (port marker only). Godot's automatic mesh LOD covers the mid-range.
- Repeated houses as MultiMesh; a few hundred buildings is cheap.
- Author cities in **local space**, place via PortDef — never bake into terrain, so terrain edits and city edits stay independent.
- Eventually "entering" a city is a camera transition, not a scene swap.
- Vegetation scatter near coasts (Terrain3D instancer / MultiMesh) sells the land from the sea.

---

## 5. Combat & customization direction (agreed — post-demo)

Full rationale in `DESIGN.md` ("Ship customization" + "Naval combat"). The commitments:

- **Seamless in-world combat, no instanced battles.** Combat reuses the sailing model; tactics = wind + positioning. NPC ships are `ship.tscn` driven by AI captains feeding normal ship inputs.
- **Cannons are bought equipment** (`CannonDef` .tres — damage/range/reload/weight/price), mounted per broadside; weight competes with cargo. Ship customization (hulls, swappable sails on the existing mounts, cannons, later refits/fittings) is the **main gold sink and a core progression axis** — the shipyard becomes a major screen.
- **Shot types** map to existing stats: round → durability, chain → sail health, grape → crew. **Morale breaks end fights** (strike colors → plunder / press crew / capture; prizes seed the fleet). **Boarding is resolved** in choice rounds (event-UI style), never a melee minigame.

Build order (each step playable): 🔴 pirate + round shot + surrender/flee AI → 🟡 shot types + sail damage → 🟡 boarding resolver + capture → 🔴 encounter variety (navy patrols, escorts, fleet fights). Prereq: shipyard UI (buy cannons) — a natural extension of the market screen.

---

## 6. Parking lot (explicitly NOT in the demo)

Pull from here only after M5 (and ideally after §4 Layers 1–2): fleets / multiple ships · crew hiring & officers · quests & tavern contracts · NPC dialogue · factions & nation politics · weather/fog/day-night visuals · currents · landing parties / inland exploration · encyclopedia · save slots UI · walkable city districts (see §4 Layer 3) · **co-op networking** (architecture is prepped; multiplayer is a whole project — v2).

If an idea is exciting mid-demo, write it here instead of building it.

---

## 7. Quick reference

- **Definition of done (demo):** §1, one paragraph. Re-read it when scope creeps.
- **Sizing:** 🟢 part-session · 🟡 ~1 session · 🔴 2–3 sessions.
- **Golden rules:** don't two-people-edit `world.tscn` · editor-save hand-written scenes once · wire node refs in code · JSON-safe save data only.
- **Free assets:** Kenney.nl, Quaternius, Poly Pizza (3D); freesound.org, Kenney audio (sound) — CC0.
- **Suggested order:** M3 leftovers ‖ M5 → export → §4 Layer 1 → Layer 2 (Terrain3D) → shipyard + §5 combat step 1 ‖ Layer 3 (cities) → parking lot.

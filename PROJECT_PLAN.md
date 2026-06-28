# Project Plan — Age of Discovery (UWO remake)

A learning-Godot-with-friends project. The point is twofold: **learn the engine** and **get to a playable demo fast**. This plan turns the existing greybox scaffold (see `DESIGN.md` and `DOCUMENTATION.md`) into something you can hand to a friend and say "play this."

- **Team:** 2–3 of you, casual weekend pace.
- **Optimize for:** a fun, shareable vertical slice. Depth (combat, fleets, factions, co-op) is explicitly parked until after the demo.
- **Engine:** Godot 4.3+, GDScript. Project lives at `S:\Godot Projects\UWO\uwo` (this plan file should be copied there alongside `DESIGN.md`).

---

## 1. What "the demo" actually is

One tight loop a stranger can finish in ~10 minutes and enjoy:

> Start a new game from a menu → sail out of Lisbon → navigate past a coastline (don't run aground) → reach Funchal → buy low / sell high to make a target amount of gold → survive one voyage event → spot and confirm one discovery with the spyglass → see it on your map → hit a "voyage complete" summary screen.

Almost every *system* for this already exists in greybox. The demo is mostly about making it **feel like a world** (land, a real ship, water, sound, menus) and **feel good** (HUD, polish, one clear objective). That's the fast path — you're dressing and tightening what's built, not inventing new systems.

**Demo is done when:** a friend can download one `.exe`, reach the summary screen without you sitting next to them, and say it felt like sailing.

---

## Current status (kept up to date)

Engine is now **Godot 4.7**. Much of the "feel like a world" work is done. Built since this plan was written:

- **Sailing:** two-sail model (horizontal/square + vertical/fore-aft), steering-wheel helm with momentum + minimum steerage, pace (50→100%) affecting speed & turning, gradual sail furl. Drifting wind (direction + strength).
- **World:** the **FFT ocean** is integrated (realistic *GodotOceanWaves* port — see `OCEAN_INTEGRATION.md`): follows the ship, wind-driven. Landmasses + coastline collision (slide + hull damage); shallow-water zones (slow + scrape).
- **Loop:** dock/undock with "Voyage Successful" + centred market (3 goods, per-visit price variation), supplies/morale, voyage events (storm/scurvy/dolphins), discovery + spyglass minigame.
- **Instruments/UI:** HUD readout, minimap (+ wind arrow), compass, helm dial, world map (fog of war), and a **debug panel** (backtick) — wind, teleport, ship/gold, time/events, and **live ocean wave tuning**.
- **Ship health:** hull durability + collision damage.

**Immediate next:** ship **buoyancy** — bob/tilt on the FFT waves (plan in `OCEAN_INTEGRATION.md`).

**Still greybox / not done:** ship/ports/UI are built in code, not real `.tscn` scenes or art (the M2 "real ship model" + scene-migration work); menus, audio, save-slots, and the guided objective + summary screen (M4/M5). The milestones below remain the roadmap.

---

## 2. How to work together (read this once)

You're 2–3 people in one Godot project. The single biggest source of pain will be **merge conflicts in scene files**, so a little discipline up front saves weekends later.

- **Git:** one repo, branch per feature (`feat/coastlines`, `ui/hud`), small frequent merges. Don't sit on a giant branch for three weeks.
- **The `world.tscn` rule:** Godot scenes are text but still merge badly. **Avoid two people editing the same `.tscn` at once.** Prefer building features as *their own scene* (e.g. `hud.tscn`, `main_menu.tscn`) that gets instanced into the world, rather than everyone adding nodes to `world.tscn`. When you must touch a shared scene, call it out in chat first.
- **`.gitignore`:** make sure `.godot/` (the import cache) is ignored — never commit it. Commit `.tres`, `.tscn`, `.gd`, and the `project.godot`.
- **Content is conflict-free:** new ports/goods/ships/events/discoveries are just new `.tres` files in `data/`. Anyone can add these anytime without stepping on code. Great "first contribution" work.
- **Lanes, not silos:** ownership below is a default so work doesn't collide — help each other across lanes freely.

### Suggested roles (2–3 people)

| Lane | Owns | Good fit for someone who likes… |
|---|---|---|
| 🌊 **Captain** — sea & world | sailing feel, coastlines/collision, ship model, ocean/sky, camera | 3D, movement, "game feel" |
| ⚓ **Quartermaster** — systems & UI | economy/trade, supplies, HUD, world map, spyglass polish | UI, numbers, systems |
| 🧭 **Bosun** — content & framing | `.tres` content, events, menus, audio, build/export | writing, glue, shipping |

If you're **two people:** Captain takes sea + world + build/export; Quartermaster takes systems + UI + content; split menus/audio between you.

### Pace & sizing

No dates — casual weekends. Tasks are sized in **sessions**, where 1 session ≈ a 3–4 hour weekend sit-down.

- 🟢 **S** = part of a session
- 🟡 **M** = ~1 session
- 🔴 **L** = 2–3 sessions (or split across people)

The whole demo below is roughly **8–12 sessions of focused work**, parallelized across 2–3 people. At one good weekend each, that's a comfortable summer.

---

## 3. The milestones

Each milestone lists its goal, the tasks (with owner + size), and the **Godot skills you'll pick up** — because learning is half the point. Do them roughly in order; M2 and M3 can run in parallel across lanes.

### M0 — Everyone sailing (½ session each) 🟢

Before anyone writes code, everyone gets the existing build running.

- [ ] 🟢 All — Install Godot 4.3+, clone the repo, open the project.
- [ ] 🟢 All — Add the input actions listed in `README.md` (Project Settings → Input Map): the steering/sail keys, `toggle_map` (M), and the spyglass `E`.
- [ ] 🟢 All — Press F5, sail Lisbon → Funchal, open the market, toggle the map.
- [ ] 🟢 All — Each person tweaks **one** constant (`SPEED_SCALE`, `MINUTES_PER_REAL_SECOND`, camera distance) and commits it on a throwaway branch — your first PR, just to learn the git flow.

**You'll learn:** the Godot editor, the scene tree, nodes, the Input Map, what an autoload is, your team git workflow.
**Done when:** every person has it running and has merged one trivial commit.

### M1 — Read the map of the code (½ session each) 🟢

- [ ] 🟢 All — Read `DOCUMENTATION.md`. Each person traces **one** flow end to end (e.g. "what happens when I press buy?" → `port_market_ui` → `EconomySim` → `CargoHold`/`GameState` → `EventBus`).
- [ ] 🟢 Each — Pick your lane (table above) and skim those files.
- [ ] 🟢 Bosun — Add **one new `.tres`** (a third good, or a new port) and confirm it auto-loads. Proves content can grow without code.

**You'll learn:** GDScript basics, Resources & `.tres` files, signals and the EventBus pattern, the Def-vs-State split.
**Done when:** each person can explain their lane's main files in a sentence.

### M2 — Make it a world, not a void 🌊 (the demo's biggest visual gap)

Right now you sail a box on an infinite flat plane. This milestone is what makes the demo *read* as a game.

- [ ] 🔴 Captain — **Coastlines + collision.** Add 2–3 landmasses (low-poly meshes or even extruded shapes) as `StaticBody3D` so the ship can run aground. Lisbon and Funchal sit on/next to land. This creates actual navigation.
- [ ] 🟡 Captain — **A real ship.** Replace the box with a free low-poly sailing-ship model (Kenney, Quaternius, or itch.io CC0 packs). Learn the import pipeline.
- [ ] 🟡 Captain — **Water + sky.** A simple ocean (Godot has water shader tutorials, or start with a tinted plane + slight UV scroll) and a skybox/`WorldEnvironment`. Even basic sky + colored water transforms the feel.
- [ ] 🟢 Captain — Camera pass: follow distance, slight height, smoothing so it isn't nauseating.

**You'll learn:** importing 3D assets, MeshInstance3D, StaticBody3D / CollisionShape3D, materials, intro to shaders, `WorldEnvironment` and lighting.
**Done when:** you can sail from Lisbon toward Funchal, see land and water and sky, and crash into a coast.

### M3 — Make the loop feel good ⚓ (parallel with M2)

The systems work; the player can't *see* them clearly. Fix the readouts.

- [ ] 🟡 Quartermaster — **HUD scene** (`hud.tscn`, instanced into world): heading, speed, day/time, gold, crew/morale/supplies bars. This is what makes voyages legible.
- [ ] 🟡 Quartermaster — **Market UI polish:** clearer buy/sell, show profit-per-good if you remember last price, cargo weight vs capacity bar.
- [ ] 🟡 Quartermaster — **Map polish:** drop a placeholder parchment/map texture into the `map_texture` slot, add zoom/pan, make discovered markers obvious.
- [ ] 🟢 Bosun — **More trade content:** expand to ~5–6 goods and a 3rd port so "buy low / sell high" has a real choice. Pure `.tres` work.
- [ ] 🟢 Quartermaster — **Spyglass feel:** quick tuning pass so the minigame reads clearly (banner timing, sweet-spot visibility).

**You'll learn:** Control nodes & anchors, UI layout/containers, theming, instancing scenes, signals driving UI updates.
**Done when:** a new player understands their gold, position, and ship status without you explaining.

### M4 — Wrap it in a game 🧭

Menus and sound are what separate "a Godot project" from "a demo."

- [ ] 🟡 Bosun — **Main menu** scene: New Game / Continue / Quit. New Game loads the world; the save/load already exists in `GameState`.
- [ ] 🟢 Bosun — **Pause menu** (resume / settings / quit to menu).
- [ ] 🟢 Bosun — **Minimal settings:** master volume + windowed/fullscreen. (Enough to feel real.)
- [ ] 🟡 Bosun — **Audio:** a looping sea ambience, light music, a couple UI click sounds. Free CC0 audio is plentiful.
- [ ] 🟢 Quartermaster — **Save slot or two** + an autosave on entering port (small extension of existing save system).

**You'll learn:** changing scenes / `get_tree().change_scene`, persisting settings, `AudioStreamPlayer`, structuring an app beyond one scene.
**Done when:** you launch to a menu, start a game, pause, adjust volume, and quit cleanly.

### M5 — One objective, then ship it 🏁

Give the demo a point and a finish line, then package it.

- [ ] 🟡 Bosun/Quartermaster — **A guided goal:** e.g. "Reach Funchal, earn 500 gold, confirm 2 discoveries." Track it and trigger a **summary/victory screen** (gold earned, discoveries made, days at sea).
- [ ] 🟡 All — **Playtest pass:** each person plays the full loop, lists what confused or broke. Fix the top 5.
- [ ] 🟡 Captain/Bosun — **Export** to a Windows `.exe` (install export templates, configure, build). Hand it to someone outside the team.

**You'll learn:** simple game-state/objective tracking, export templates & packaging, the value of playtesting.
**Done when:** the demo definition in §1 is true and you have a shareable build.

---

## 4. Parking lot (explicitly NOT in the demo)

These are great later goals — keep them out of scope so the demo actually ships. Pull from here only after M5.

Naval combat & pirates · fleets / multiple ships · crew hiring & officers · shipyard & ship customization · quests & tavern contracts · NPC dialogue · factions & nation politics · weather/fog/day-night visuals · currents · landing parties / inland exploration · encyclopedia · **co-op networking** (the architecture is prepped, but multiplayer is a whole project — save it for v2).

If an idea is exciting mid-demo, write it here instead of building it.

---

## 5. Quick reference

- **Definition of done (demo):** §1, one paragraph. Re-read it when scope creeps.
- **Sizing:** 🟢 part-session · 🟡 ~1 session · 🔴 2–3 sessions.
- **Golden rule:** don't two-people-edit `world.tscn`; build features as their own scenes.
- **Free assets to lean on:** Kenney.nl, Quaternius, Poly Pizza (3D); freesound.org, Kenney audio (sound) — all CC0.
- **Suggested order:** M0 → M1 → (M2 ‖ M3) → M4 → M5.

When the demo is done, come back and the system map in `DOCUMENTATION.md` / the parking lot above becomes your v2 roadmap.

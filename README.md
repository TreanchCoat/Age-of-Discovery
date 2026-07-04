# Age of Discovery — getting started

1. Open this folder in **Godot 4.7** (Project Manager → Import). The first open reimports the ocean assets (clipmap meshes, shaders) — let it finish.
2. Input actions are already defined in `project.godot` — no manual setup needed.
3. Press F5. You boot to the **main menu** — New Game / Continue / Settings / Quit. In game: the **FFT ocean** (ship bobs on it), real GEBCO terrain around the two ports (Lisbon, Funchal), wind, and one discovery (Dragon Rock at roughly halfway, offset south). The game **autosaves every time you dock**; Continue resumes where you left off.

Controls:
- **A / D** — steer (turns better once you have speed)
- **F** — raise/lower the **horizontal sail** (square sail; pulls best with the wind astern)
- **G** — raise/lower the **vertical sail** (fore-and-aft sail; pulls best on the beam, some astern)
- **Mouse wheel** — zoom the camera in/out
- **E** — observe a spotted discovery
- **M** — toggle the world map
- **Esc** — pause menu (Resume / Settings with volume / Save & Main Menu)
- **` (backtick)** — debug panel (wind, teleport, ship/gold, time/events, live ocean wave tuning)

Both sails start down, so you begin dead in the water — raise at least one to get moving. Sail into a port's circle to auto-dock: you'll see **Voyage Successful** and the market opens.

## Layout

- `DESIGN.md` — vision, architecture, roadmap. Read this first.
- `scripts/autoload/` — global singletons (EventBus, WorldClock, GameState, EconomySim, DiscoveryDB, Settings)
- `scripts/data/` — Def (catalog) and State (save) resources
- `scripts/systems/` — WindSystem, DiscoveryArea, PortArea, SupplySystem, HeightmapTerrain, VoyageEventSystem
- `scripts/ship/` — ShipController, ShipVisual (hull fitting + swappable-sail mounts), ShipBuoyancy
- `scripts/ui/` — market, world map, spyglass, event popup, HUD widgets, pause menu, main menu
- `data/` — content as `.tres` files; add goods/ports/ships/discoveries/events here, systems auto-load whole folders
- `scenes/` — `menu/main_menu.tscn` (main scene) · `world/world.tscn` · `ship/ship.tscn` · `port/port.tscn`
- `assets/` — the **FFT ocean** (water scripts, shaders, `ocean.tscn`), GEBCO terrain, ship model, audio loops

Docs: `DOCUMENTATION.md` (file-by-file reference) · `LEARNING_GODOT.md` (Godot taught through this project) · `PROJECT_PLAN.md` (roadmap + current status) · `OCEAN_INTEGRATION.md` (ocean architecture + buoyancy plan).

## Adding content (no code needed)

Duplicate any `.tres` in `data/`, change the fields. New ports/discoveries appear in-world automatically on next run.

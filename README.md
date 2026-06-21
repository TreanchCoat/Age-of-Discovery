# Age of Discovery — getting started

1. Open this folder in **Godot 4.3+** (Project Manager → Import).
2. Input actions are already defined in `project.godot` — no manual setup needed.
3. Press F5. You get a greybox sea, two port markers (Lisbon, Funchal), wind, and one discovery (Dragon Rock at roughly halfway, offset south).

Controls:
- **A / D** — steer (turns better once you have speed)
- **F** — raise/lower the **horizontal sail** (square sail; pulls best with the wind astern)
- **G** — raise/lower the **vertical sail** (fore-and-aft sail; pulls best on the beam, some astern)
- **Mouse wheel** — zoom the camera in/out
- **E** — observe a spotted discovery
- **M** — toggle the world map

Both sails start down, so you begin dead in the water — raise at least one to get moving. Sail into a port's circle to auto-dock: you'll see **Voyage Successful** and the market opens.

## Layout

- `DESIGN.md` — vision, architecture, roadmap. Read this first.
- `scripts/autoload/` — global singletons (EventBus, WorldClock, GameState, EconomySim, DiscoveryDB)
- `scripts/data/` — Def (catalog) and State (save) resources
- `scripts/systems/` — WindSystem, DiscoveryArea, PortArea
- `scripts/ship/` — ShipController
- `data/` — content as `.tres` files; add goods/ports/ships/discoveries here, systems auto-load whole folders
- `scenes/world/` — bootstrap world scene (all greybox-from-code; replace with real scenes incrementally)

## Adding content (no code needed)

Duplicate any `.tres` in `data/`, change the fields. New ports/discoveries appear in-world automatically on next run.

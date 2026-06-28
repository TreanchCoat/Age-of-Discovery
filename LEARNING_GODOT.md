# Learning Godot through Age of Discovery

A guide to the Godot 4 concepts this project uses, explained with our own code. It
assumes you can program but are new to Godot. Read top to bottom once; after that it's a
reference. Companion docs: `DOCUMENTATION.md` (what each file does) and `DESIGN.md` (why).

---

## 1. The core mental model: nodes, scenes, the tree

Godot has one fundamental building block: the **Node**. A game is a **tree** of nodes
that the engine walks every frame. Each node *type* is really just "a node with extra
abilities":

| Node type | What it adds | Where we use it |
|---|---|---|
| `Node` | nothing — pure logic/organization | EventBus, WorldClock, SupplySystem |
| `Node3D` | a 3D transform (position/rotation/scale) | the World root, WindSystem |
| `CharacterBody3D` | a 3D body you move yourself + collision | `ShipController` (the ship) |
| `Area3D` | detects when bodies enter/exit (no physics) | `PortArea`, `DiscoveryArea`, `ShallowArea` |
| `StaticBody3D` | an immovable solid you collide with | the landmasses |
| `MeshInstance3D` | draws a 3D mesh | the sea, hull, port markers |
| `Camera3D` | the viewpoint | the chase camera |
| `Control` | a 2D UI element with anchoring | every panel, the compass/minimap |
| `CanvasLayer` | a screen-space overlay above the 3D world | the HUD, market, map |

A **scene** is just a saved subtree of nodes (a `.tscn` file). You can instance a scene
inside another scene — that's how big games are built from small reusable pieces.

Our project is deliberately unusual: **`world.tscn` is almost empty** — a single `Node3D`
with `world.gd` attached — and we build the entire tree *in code* in `_ready()`:

```gdscript
func _ready() -> void:
	_make_environment()       # sun + sky
	_make_sea()               # the ocean plane
	_spawn_land()             # islands + shallows
	var wind := WindSystem.new()
	add_child(wind)           # <-- attaching a node to the tree
	...
	var ship := _spawn_ship(wind)
	...
	_make_hud()
```

`add_child()` is the key call: it puts a node into the tree, at which point the engine
starts calling its lifecycle methods. We do it in code so the game runs with zero hand-built
scenes ("greybox") — later you replace pieces with real `.tscn` scenes and art.

You reach nodes with `$Name` or `get_node("Name")` (relative to the current node), e.g.
`main.gd` uses `$Water` and `$OceanAudioPlayer`.

---

## 2. Scripts and the game loop

A script `extends` a node type and adds behavior. The engine calls specific methods at
specific times — you override the ones you care about:

- **`_ready()`** — once, right after the node enters the tree. Setup goes here.
- **`_process(delta)`** — every rendered frame. `delta` = seconds since last frame.
- **`_physics_process(delta)`** — every *physics* step (fixed 60 Hz by default).
  Movement/collision go here so they're frame-rate independent.
- **`_unhandled_input(event)`** — input not already consumed by UI.
- **`_draw()`** — custom 2D drawing (used by our compass/minimap/helm).

**`delta` is how you stay frame-rate independent.** Notice every movement value is
multiplied by it, so the ship moves the same distance whether you run at 30 or 144 fps:

```gdscript
# ship_controller.gd
current_speed = move_toward(current_speed, target_speed, delta * 2.0)
velocity = -global_transform.basis.z * current_speed
move_and_slide()
```

`_process` vs `_physics_process`: visuals/HUD go in `_process` (runs as fast as the
display); anything physical goes in `_physics_process` (runs at a steady rate). Our HUD
text updates in `world.gd`'s `_process`; the ship moves in `_physics_process`.

---

## 3. GDScript essentials — and the gotchas that bit us

GDScript is Python-flavored but **typed**. Types are optional but the engine is strict
about them in ways that caused real bugs in this project — worth understanding:

**Type inference with `:=`.** `var x := 5` infers `int`. But `:=` only works when Godot
can *know* the type. Pulling a value out of a `Dictionary` returns an untyped `Variant`,
and **Godot 4.4+ refuses to infer a type from a Variant** — that was our "ship won't load"
crash:

```gdscript
# BROKE in 4.7 — supplies[...] is a Variant, can't infer:
var water_short := water_need - ship.supplies[&"water"]
# FIX — state the type explicitly:
var water_short: int = water_need - ship.supplies[&"water"]
```
Rule of thumb: when a value comes out of a dictionary, an untyped array, or `load()`
without a cast, **annotate the type** instead of using `:=`.

**Dictionaries use brackets, not dots.** `dict["key"]`, never `dict.key`. Dot access on a
typed dictionary is a parse error (another early crash here):

```gdscript
# economy_sim.gd
var supply: float = clampf(entry["supply"], 0.2, 4.0)   # right
# entry.supply would not compile
```

**`StringName` and `&"..."`.** IDs are written `&"wine"`, not `"wine"`. A `StringName` is
an interned string — comparisons are pointer-fast, which matters when you compare ids
constantly (every good, port, signal). `.tres` files store ids this way too.

**Annotations** (the `@` prefixes):
- `@export var base_speed: float = 8.0` — shows the variable in the **Inspector** and
  saves it into `.tres`/`.tscn`. This is how `ShipDef` exposes tunable stats.
- `@onready var water := $Water` — defers the assignment until `_ready()`, so the node
  exists when you grab it.
- `@tool` — makes the script also run *in the editor* (the ocean uses this so it previews).

**Casting and type checks.** `as` casts (null if it fails), `is` tests type. We needed an
explicit cast because a signal hands you the base `Node3D`, which doesn't know about our
methods:

```gdscript
# shallow_area.gd
func _on_entered(body: Node3D) -> void:
	if body is ShipController:
		(body as ShipController).enter_shallows()   # cast so the method is visible
```

**Lambdas (inline functions)** are fine on one line; multi-line lambdas inside a function
call are fragile and broke our 4.7 parse — we replaced them with named methods. Prefer a
real `func` for anything more than a one-liner.

---

## 4. Signals — the decoupling backbone

A **signal** is an event a node can emit; other nodes **connect** a function to it. The
emitter doesn't know or care who's listening. This is Godot's main decoupling tool.

```gdscript
signal gold_changed(new_value: int)   # declare
EventBus.gold_changed.emit(gold)      # emit
EventBus.gold_changed.connect(_on_gold)  # connect a handler
```

We take this further with **`EventBus`** — an autoload that is *nothing but* signal
declarations. Systems emit there; UI and other systems listen there; **nobody references
anyone directly.** When you buy something, `EconomySim` emits `trade_executed`; the market
UI and the HUD both react, neither knowing the other exists. This is also our multiplayer
insurance: later, those signals can be replicated across the network without touching the
listeners.

Connecting: you can connect a **method** (`connect(_on_gold)`), a **one-line lambda**
(`connect(func(_g): _refresh())`), or a method **with a bound argument**
(`connect(_set_wind.bind(direction))` in the debug panel). The handler must accept the
same number of arguments the signal emits.

---

## 5. Autoloads (singletons)

An **autoload** is a node Godot creates once at startup and keeps alive for the whole game,
reachable by name from anywhere. You register them in `project.godot`:

```
[autoload]
EventBus="*res://scripts/autoload/event_bus.gd"
WorldClock="*res://scripts/autoload/world_clock.gd"
GameState="*res://scripts/autoload/game_state.gd"
...
```

The `*` means "make it a globally-accessible singleton." Order matters — `EventBus` is
first because everything else emits through it. Our five:

- **EventBus** — global signals (no logic).
- **WorldClock** — turns real seconds into game time, emits `hour_passed`/`day_passed`.
- **GameState** — the player's data (gold, ship, fleet) + save/load.
- **EconomySim** — port prices.
- **DiscoveryDB** — what's been discovered.

Anywhere in the code, `GameState.gold += 500` or `EventBus.port_entered.emit(id)` just
works, because they're globals.

---

## 6. Resources (`.tres`) — data as files

Where Nodes are things in the tree, a **Resource** is a reusable data object. A custom
Resource is a class that `extends Resource` with `@export` fields:

```gdscript
# ship_def.gd
class_name ShipDef
extends Resource
@export var display_name: String
@export var horizontal_sail_power: float = 8.0
@export var turn_rate: float = 1.2
@export var max_crew: int = 20
```

`class_name ShipDef` registers it as a **global type** — now you can make `.tres` files of
it and Godot shows the fields in the Inspector. `data/ships/balsa.tres` is just a text file
listing those values. Adding a new ship = a new `.tres`, **no code**.

This drives the project's central idea, the **Def/State split**:

- **Defs** are immutable catalog data (`GoodDef`, `PortDef`, `ShipDef`, `DiscoveryDef`,
  `VoyageEventDef`). They describe what things *are*. Never changed at runtime.
- **States** are the mutable, save-able data (`ShipState`, `CargoHold`, `CharacterStats`).
  They describe what's *happening*.

`ShipState` *references* a `ShipDef` and adds the changing bits (durability, crew, cargo):
its `effective_speed()` reads the Def's sail powers but applies the State's crew/morale. To
load a resource from disk you use `load("res://data/ships/balsa.tres")` (or `preload`,
which loads at compile time).

---

## 7. The 3D world: transforms, movement, collision

**Coordinates:** Y is up, and a node's **forward is −Z**. That's why the ship moves along
`-global_transform.basis.z` (its own forward axis). `basis` is the rotation part of the
transform; `rotate_y(angle)` spins it around the vertical axis (steering).

**Moving a body:** `ShipController` is a `CharacterBody3D` — you set its `velocity` and call
`move_and_slide()`, and Godot moves it *and* slides it along anything it hits. That sliding
is why bumping the coast deflects you along it instead of dead-stopping. We pin
`velocity.y = 0` so the flat sea is never left.

**Detecting vs colliding** — two different things:
- An **`Area3D`** only *detects* overlaps (it emits `body_entered`/`body_exited`). Ports,
  discoveries, and shallow water are Areas: entering one fires an event, but it doesn't
  physically stop you.
- A **`StaticBody3D`** is *solid* — `move_and_slide` collides with it. The islands are
  StaticBodies; that's what makes them block the ship.

We tag the islands with `add_to_group("land")` and, after `move_and_slide()`, check the
collisions to apply hull damage:

```gdscript
for i in get_slide_collision_count():
	var hit := get_slide_collision(i).get_collider() as Node
	if hit and hit.is_in_group("land"):
		... # damage + nudge along the coast
```

---

## 8. Input

Named **input actions** live in `project.godot` (we predefined them so there's no manual
setup). You read them two ways:

```gdscript
var turn := Input.get_axis("turn_right", "turn_left")  # returns -1..+1
if event.is_action_pressed("toggle_horizontal_sail"):  # one-shot, in _unhandled_input
```

`Input.get_axis(neg, pos)` is great for steering/throttle (continuous). `is_action_pressed`
on an `InputEvent` is for discrete presses (toggling a sail). Raw events (like the mouse
wheel for zoom) come through `_unhandled_input(event)` and you check the event type.

---

## 9. Cameras & UI

The **chase camera** is a `Camera3D` added as a *child* of the ship, so it follows
automatically. Zoom just scales its offset from the ship (`_cam_base * _zoom`).

**UI** uses `Control` nodes inside a `CanvasLayer` (which floats above the 3D view).
Positioning uses **anchors** (which screen edge a control sticks to) plus **offsets**. The
minimap is anchored to the top-right corner, the helm to bottom-center, etc.

For the compass/minimap/helm we use **custom drawing**: a `Control` overrides `_draw()` and
calls `draw_circle`, `draw_line`, `draw_colored_polygon`. `_draw` only runs when needed, so
we call `queue_redraw()` each frame to keep them live:

```gdscript
# compass_ui.gd
func _process(_delta): queue_redraw()
func _draw():
	draw_arc(center, radius, 0, TAU, 48, color, 2.0, true)   # the ring
	draw_line(center, center + heading * radius, red, 3.0)    # the needle
```

---

## 10. Materials & shaders

A **material** decides how a surface looks. `StandardMaterial3D` is the no-code PBR
material; a **`ShaderMaterial`** runs a shader *you* write.

A **spatial shader** has two stages (our now-retired `shaders/ocean.gdshader` is a clean example — the game's actual sea is the FFT ocean described below, but this shows the basics):
- **`vertex()`** runs per vertex — we displace `VERTEX.y` by summed sine waves to make the
  surface roll, and compute a `NORMAL` for lighting.
- **`fragment()`** runs per pixel — colors troughs/crests, adds foam and a fresnel sheen.

Shaders take **uniforms** (parameters) you set from GDScript. We feed wind into the waves
every frame:

```gdscript
_sea_mat.set_shader_parameter("wave_strength", _wind.strength)
_sea_mat.set_shader_parameter("wind_dir", _wind.direction)
```

**Compute shaders & `RenderingDevice` (the FFT ocean — now the game's sea).** Regular
shaders draw things; **compute shaders** do general math on the GPU. The realistic FFT
ocean (now integrated — see `OCEAN_INTEGRATION.md`) runs a whole pipeline of compute
shaders (via the low-level `RenderingDevice` API) to simulate ocean physics into textures
each frame. That power is also why it was finicky to port — the
errors you hit were all `RenderingDevice` rules that got stricter in 4.7:
- *push-constant size* must match the shader exactly (no padding),
- a storage image's *read/write qualifier* must match how it's bound,
- *reading a texture back to the CPU* must happen on the render thread.
Those are normal porting friction for GPU code, not something wrong with your setup.

---

## 11. Saving, pausing, and time

**Save/load** uses a simple convention: every State implements `to_dict()` / `from_dict()`,
`GameState` collects them into one dictionary, and writes JSON to `user://save.json`
(`user://` is a per-app folder Godot manages). The same dict format is the future
multiplayer sync format.

**Pausing:** `get_tree().paused = true` freezes the whole tree. Modal UIs (voyage events,
the spyglass) set `process_mode = PROCESS_MODE_ALWAYS` so they keep running while everything
else is frozen. Because `WorldClock` pauses with the tree, paused time costs nothing.

**Game time:** `WorldClock` advances `total_minutes` in `_process` and emits
`hour_passed`/`day_passed` when they roll over. *All* simulation (economy drift, supply
consumption, voyage events) hangs off those signals rather than real time — so it all
scales together and pauses cleanly.

---

## 12. Putting it together: what happens when you raise a sail

A concrete trace that ties the pieces together:

1. You press **F**. The OS sends an `InputEvent`; Godot routes it to
   `ShipController._unhandled_input`, which flips `horizontal_sail_target`.
2. Every physics step, `_physics_process` eases `horizontal_sail` toward that target, asks
   `GameState.ship.effective_speed(...)` for thrust (which reads the **Def's** sail power
   and the **State's** crew/morale), scales by wind and pace, and `move_and_slide()`s the body.
3. `move_and_slide` collides with any **StaticBody** land and slides you along it; we read
   the collisions to apply hull damage.
4. `world.gd._process` reads the ship's values every frame and updates the HUD text; the
   minimap/compass/helm `Control`s redraw from the same data.
5. Sail into a port's **Area3D** → it emits `port_entered` on **EventBus** → `EconomySim`
   re-rolls prices, `ShipController` docks (hides + freezes), and `PortMarketUI` opens —
   none of them knowing about each other, all via the one signal.

That loop — input → physics → systems mutate State → signals fan out → UI reflects it — is
the whole engine in miniature.

---

## 13. Debugging tips & the gotcha checklist

- The **Output** and **Errors** panels (bottom of the editor) are your first stop; a red
  line names the file and line.
- `print(...)` is fine for quick checks; `print_debug` includes a stack trace.
- Recurring GDScript gotchas in this project:
  - Don't `:=` from a dictionary/Variant — annotate the type.
  - Dictionaries use `["key"]`, never `.key`.
  - A signal handler must take the args the signal emits (or use `.bind`).
  - Cast `as` after an `is` check to call subtype methods.
  - Keep multi-line lambdas out of call arguments — use a named `func`.
- When opening the project in a newer Godot, let it convert, then watch for `RenderingDevice`
  / shader strictness changes (as the FFT ocean showed).

---

### Where to go next in the docs
- `DOCUMENTATION.md` — file-by-file reference of every system.
- `DESIGN.md` — the vision and the design rules.
- `PROJECT_PLAN.md` — the build roadmap.
- Official docs: the Godot "Step by step" and "GDScript reference" pages are excellent and
  match everything above.

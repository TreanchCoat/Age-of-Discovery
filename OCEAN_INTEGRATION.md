# Ocean — status, architecture & plans

**Status: DONE / integrated.** The game's sea is the realistic **FFT ocean** (2Retr0's
*GodotOceanWaves* lineage, ported to Godot 4.7). It replaced the earlier code-built sea
plane (sum-of-sines, then Gerstner — both now retired; `shaders/ocean.gdshader` is unused).

Two locations:
- **Standalone (reference / tuning):** `S:\Godot Projects\GodotOceanWaves` — the ported
  demo, runs on 4.7, param sliders on **P**. Port details in its `OCEAN_PORT_NOTES.md`.
- **In-game:** `S:\Godot Projects\UWO\uwo` — copied assets + `ocean.tscn` + `world.gd`
  wiring + `project.godot` shader globals + debug panel.

---

## What's in the game

- **`assets/`** (copied from the standalone): the whole ocean.
  - `assets/water/water.gd` — the **Water** node script (a `MeshInstance3D`).
  - `assets/water/wave_generator.gd` — the GPU compute pipeline (spectrum → FFT → maps).
  - `assets/water/wave_cascade_parameters.gd` — per-cascade params resource.
  - `assets/render_context.gd` — `RenderingDevice` wrapper.
  - `assets/shaders/compute/*.glsl` — the 6 FFT compute shaders.
  - `assets/shaders/spatial/water.gdshader` (+ `sea_spray*.gdshader`) — surface + spray.
  - `assets/water/mat_water.tres`, `mat_spray.tres`, `clipmap_*.obj` (+ `.import`), `sea_spray.png`.
- **`assets/water/ocean.tscn`** — self-contained scene the game instances: a `Water`
  (`water.gd`, `clipmap_high` mesh, `mat_water`, **3 tuned cascades**) + a
  `WaterSprayEmitter` (`GPUParticles3D`) child.
- **`project.godot` → `[shader_globals]`** — `water_color`, `foam_color` (colors),
  `num_cascades` (uint), `displacements`, `normals` (sampler2DArray). **Required** — the
  shaders declare these `global uniform`s; `water.gd` feeds them at runtime, but they must
  be *registered* here or the surface shader won't compile.
- **`world.gd`** — `_make_sea()` `load()`s `ocean.tscn`, instances it, caches the cascades.
  `_process()` (a) keeps the ocean centred on the ship (snaps its position each frame so
  the dense clipmap is always under you; waves are world-space so they don't slide) and
  (b) drives the cascades' wind from `WindSystem`, **throttled to 0.5 s** (changing wind
  regenerates the spectra). The `ocean_wind_auto` flag gates this; the debug panel toggles it.
- **Debug panel** (`scripts/ui/debug_ui.gd`, backtick `` ` ``) → **"Ocean waves"** section:
  cascade selector, sliders (`wind_speed/wind_direction/fetch_length/swell/spread/detail/
  whitecap/foam_amount/displacement_scale`), resolution + mesh_quality dropdowns, sea-spray
  toggle, and a **"Wind drives waves"** checkbox (uncheck to tune wind by hand).

---

## The 4.7 port fixes (so they don't bite again)

1. **Push-constant sizes** — `render_context.gd` `create_push_constant()` supplies the
   *exact* byte size; 4.4+ rejects the old 16-byte padding.
2. **Uniform image writability** — `spectrum_modulate.glsl`: removed `readonly` on the
   spectrum image so it matches how it's bound.
3. **CPU readback** — `texture_get_data` is render-thread-only in 4.7, so `water.gd`'s
   `update_textures = false` and the initial `_setup_cpu_displacement_textures()` is gated.
   **This is why buoyancy is currently off** (see plan below).
4. **Shader globals** — registered in `project.godot` (the 4.3→4.7 conversion dropped them).
5. **Mesh LODs** — `clipmap_*.obj.import`: `generate_lods=false` + `generate_shadow_mesh=false`.
   ⚠️ **If you reimport and the waves go round/smooth, check these.** With LODs on, 4.7
   decimates the clipmap and the sharp Gerstner-style crests average out into soft swells.
6. **Renderer** — game stays on **Forward+ / Vulkan**; the compute fixes were API-agnostic.
   Fallback if it ever misrenders in-game: force `rendering_device/driver.windows="d3d12"`.

---

## Buoyancy (scaffolded — needs tuning)

The ship now bobs on the FFT waves. Mechanism is in place; amplitude/feel still want a
hands-on tuning pass.

**Done:**

1. **Readback re-enabled on the render thread.** `water.gd`'s `texture_get_data` now runs
   inside `RenderingServer.call_on_render_thread(_readback_displacements_render_thread)`,
   throttled to ~25 Hz, publishing each displacing cascade's layer to a CPU `Image` behind a
   mutex. `update_textures` is back to `true`. `get_height(world_pos)` reads that snapshot
   (one frame of latency). Two bugs fixed while there: `get_pixelv` now gets a wrapped
   `Vector2i`, and the dead `cam_distance`/`get_camera_3d()` line (null-crash risk) is gone.
2. **Kinematic conform, not physics floats.** `scripts/ship/ship_buoyancy.gd`
   (`ShipBuoyancy`) samples `get_height` at four hull probes (bow/stern/port/starboard),
   sets heave + pitch + roll **on a `HullPivot` Node3D that wraps the hull mesh** — never on
   the `CharacterBody3D`. The body, its collision shape and the chase camera stay level, so
   thrust (`-basis.z`) and steering are untouched and the camera doesn't pitch. Tilt is
   clamped (`max_tilt_deg`) and scaled by `WindSystem.strength` (flat in a calm). Wired in
   `world.gd._spawn_ship`; `set_at_sea()` now hides nested hull meshes and buoyancy pauses
   while docked.

**Still to do:**

3. **Tune the feel.** Play with `ShipBuoyancy` exports — `draft`, `max_tilt_deg`,
   `heave_smooth`, `tilt_smooth`, `calm_strength` — until the bob reads well without nausea.
4. **Camera (optional).** The chase cam is fully decoupled (no bob/tilt) by design; if it
   feels too static, add a small *damped* fraction of heave to the camera — never 1:1.
5. **Verify first.** Drop a debug node using `assets/player/waveheight_script.gd`
   (`global_position.y = water.get_height(global_position)`) and confirm it tracks the
   crests before trusting the ship bob.

The ocean is GPU-computed, so the readback is the only way to get wave height on the CPU
(the retired Gerstner shader could be evaluated with a formula; the FFT one can't).

---

## Other ocean ideas (just plans)

- Import the demo's HDRI skybox + environment (panorama sky, fog, tonemap) for the exact
  moody reflections; the game currently uses its own procedural sky.
- Shoreline foam where the ocean meets land/shallows; a wake/trail behind the moving ship.
- Strip the `[ocean] valid=…` diagnostic prints from `wave_generator.gd` once stable.
- A graphics-quality setting (map_size / mesh_quality) for weaker GPUs.

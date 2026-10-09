# Daughter Of The Wind: notes for Claude

A Godot 4.7 flying game for the Scareathon arcade, after the flying scenes in Nausicaä.
README.md covers the controls and how it flies.

## Layout

The whole world is built in code. `scenes/main.tscn` is just `scripts/main.gd`.

- `main.gd`: builds the sky, sun, clouds, glider, input, camera and HUD, plus what the level adds: `"clouds"` (cloud sea + fleet) or `"coast"` (`coast.gd`). Whites the view out inside cloud; restart, weather keys, `next_level()` (reloads the scene; the pick is the static `chosen`).
  - Exported switches for tests: `level`, `rider`, `use_fleet`, `use_pads`, `show_hud`. `next_rider()` swaps glider and witch the same way as `next_level()`.
- `glider.gd`: the flight model (Node3D, forward is -Z, integrated in `_physics_process`). Lift and drag from airspeed and angle of attack; the stick asks for a bank angle and an angle of attack. All tuning is the constants at the top.
  - Its air is the sum of `wind_at()` over the nodes in `air`; the nodes in `solids` push it out through `hit()` (signal `bumped`). `control` is the smoothed stick.
  - Upside down with the stick held (`looping`), the roll control keeps the wings level instead of rolling upright, so loops go round.
- `glider_model.gd`: the cream eggshell panel-wing glider (after the user's reference still): a cut-off teardrop tube for a body, low hoops, fins on the tip seams, a few electronics housings. Only the flaps move. It poses the pilot each frame (stand / crouch / hang on, from `glider.climb` and the stick). Each wingtip `trail.gd` ribbon gets its strength from the lift that tip is making.
- `girl.gd` + `models/girl.glb`: the pilot, a single skinned mesh built by `art/build_girl.py` (Blender 4.3: `blender -b --factory-startup --python art/build_girl.py`, then `godot --headless --import`). No animation clips: `pose()` places the hips and solves each arm and leg with two-bone IK to hand and foot targets, in the glider's space. Materials are repainted by their Blender names (`COLOURS`). `art/` has a `.gdignore`; the `.blend` is there to edit by hand.
- `witch_model.gd`: the other rider, a witch on a broomstick (`glider.rider = "witch"`). Same flight, different model; one spark trail from the broom's tail.
- `flight_input.gd`: keys, gamepad and touch into `stick` / `boost` / `brake`. `stick.y` positive pulls the nose up. Tests set `manual = true` and write the values.
- `chase_cam.gd`: follows the glider's interpolated transform in `_process`; keeps the horizon mostly flat when level and goes over with the glider in a loop.
- `coast.gd`: the coast level: sea to the west (-X), endless terraced cliffs running along Z, one valley down to a beach with the castle in it. `height_at(x, z)` is the land (`shore_x`, `inland`, `valley`); ground chunks stream around `focus` (fine near, coarse far, skirts hide the seams, none over open sea) and each grows its own hamlets, windmills, trees and spires from a seed. Also `hit()` and `wind_at()` (ridge lift from `SEA_WIND`). Spires, towers, windmills and giant trees collide as tapered columns; rock arches as runs of capsules. The valley has a stream (`river_z`, repeated in `shaders/terrain`), flower meadows and wobbly fields (all in the terrain shader, driven by vertex colours: red farm, green sand, blue stream).
  - `shaders/ocean.gdshader` repeats `shore_x()`, the valley and the sea bed slope so the water knows where the shore is. Change them together.
- `cloud_manager.gd`: the cloud system. Grid cells per layer (`LAYERS`: cumulus, towers, wisps) stream in around `focus`; each cell is one MultiMesh of puffs, grown from a seed, so a place always has the same clouds. Also the sea of clouds sheet.
  - Air queries in world space: `density_at(p)`, `wind_at(p)` (thermals under clouds, gusts inside them, lift over the cloud sea).
  - `set_weather(0..2)`, `prewarm()`, `stats()`, `all_clouds()`.
  - The node itself drifts on the wind; cloud positions are in its space, so subtract `drift` from world points.
- `airship.gd`: one ship built from a length and a seed (`build()`), cruising straight; `hit()` is its collision. Turrets (`_work_guns`) fire at the glider when she is in range, otherwise at the nearest of `foes`, through `flak.gd`, which owns the shells and the Wind Waker-style puff explosions (`shaders/burst`). A hit calls `glider.take_hit()` (5 health, mends; `downed` restarts).
- `diorama.gd` (`scenes/diorama.tscn`): a separate small scene for judging the look: the rider held still in a wind, plain test shapes, a few drifting clouds, a full orbit camera (drag, wheel, pinch) and a movable sun. It is the third entry in `main.LEVELS`; `next_level()` changes scene to it and its Back button returns. Run it directly with `godot --path . res://scenes/diorama.tscn`.
- `battle.gd`: the war. Two `fleet.gd` (one per side, sailing the same circle a broadside apart), one shared `flak.gd`, and `squadron.gd` (the H-shaped fighters: steered, not flown with the flight model; they chase the glider or each other and are shot down and relaunched). `battle.armed = false` holds all fire; `battle.place()` moves the whole thing. `main.fleet` is `battle.fleets[0]`.
- `toon.gd` + `shaders/toon.gdshader` + `shaders/toon.gdshaderinc`: the look. Every solid material is cel shaded after Breath of the Wild (custom `light()`: two flat tones, a rim on the lit side, an optional hard highlight; no outlines, **no textures**: the user had a watercolour wash removed on 2026-10-08 as "splotchy"). Use `Toon.paint()` / `tinted()` / `glowing()` / `eggshell()` / `shiny()`, never StandardMaterial3D, for anything lit.
- `hair.gd`: a small verlet cloth in world space pinned to an anchor node. The girl has two (short hair on her head, a scarf at her neck); the witch has long hair.
- `sun_glare.gd` + `shaders/sun_glare`: the lens glare, a full-screen additive canvas shader under the HUD.
- `mesh_kit.gd`: `loft`, `wing`, `slab`, `body`, `rod`. UVs are in metres.
- `shaders/`: `cloud_puff` (MultiMesh puffs; per-puff data in INSTANCE_CUSTOM and COLOR), `cloud_sea`, `sky`, `hull` (plates, rivets, belly paint, portholes), `terrain` (grass, fields from vertex colour red, cliff rock by slope), `ocean`.

## Commands

Godot (Steam):

    "C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"

Run from this folder with `--headless --fixed-fps 60 --path . -s res://tests/<name>.gd`:

| Test | What a pass looks like |
| --- | --- |
| `flight_test` | 11 PASS (includes a full loop and the witch) |
| `cloud_test` | 10 PASS |
| `fleet_test` | 12 PASS |
| `coast_test` | 13 PASS |
| `diorama_test` | 5 PASS |
| `hair_test` | 3 PASS (run without `--fixed-fps`) |

`tests/shots.gd` needs a window (no `--headless`) and takes `-- <out dir>`; it saves 13 views (glider close-ups, a turn, the fleet, the cloud sea), or with `-- <out dir> coast [witch]` the coast views (cliffs, valley, castle, flak, explosions). Run tests under `timeout`: a script error at startup hangs the run.

## Conventions

- The renderer is Compatibility on desktop too, so what you see matches the web build. No volumetric fog; the clouds are solid puffs with dithered fades.
- The cloud and sea shaders are `unshaded` with `fog_disabled` and do their own haze; the palette is handed down from `main.gd` (`HAZE`, `HAZE_DISTANCE`) and `cloud_manager.gd` (`lit_color`, `shade_color`).
- Nodes moved in `_process` (camera, cloud manager, trails) have physics interpolation turned off. Call `reset_physics_interpolation()` after teleporting anything else.
- Type GDScript vars explicitly wherever inference fails (values from Dictionaries or untyped arrays).
- Comments are plain-English `##` docs at the top of each script plus short inline notes.
- No Python on this machine. For multi-line edits, write a `.cjs` script to `$CLAUDE_JOB_DIR/tmp` and run it with node.
- Only commit or push when the user asks.

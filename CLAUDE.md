# Daughter Of The Wind: notes for Claude

A Godot 4.7 flying game for the Scareathon arcade, after the flying scenes in Nausicaä.
README.md covers the controls and how it flies.

## Layout

The whole world is built in code. `scenes/main.tscn` is just `scripts/main.gd`.

- `main.gd`: builds the sky, sun, clouds, glider, input, camera, fleet and HUD; whites the view out inside cloud; restart and weather keys.
  - Exported switches for tests: `use_fleet`, `use_pads`, `show_hud`.
- `glider.gd`: the flight model (Node3D, forward is -Z, integrated in `_physics_process`). Lift and drag from airspeed and angle of attack; the stick asks for a bank angle and an angle of attack. All tuning is the constants at the top.
  - Reads the air from `clouds.wind_at()`, and is pushed out of ships by `fleet.hit()` (signal `bumped`).
- `glider_model.gd`: the white gull-wing glider, the pilot, the jet flame and the two wingtip `trail.gd` ribbons.
- `flight_input.gd`: keys, gamepad and touch into `stick` / `boost` / `brake`. `stick.y` positive pulls the nose up. Tests set `manual = true` and write the values.
- `chase_cam.gd`: follows the glider's interpolated transform in `_process`.
- `cloud_manager.gd`: the cloud system. Grid cells per layer (`LAYERS`: cumulus, towers, wisps) stream in around `focus`; each cell is one MultiMesh of puffs, grown from a seed, so a place always has the same clouds. Also the sea of clouds sheet.
  - Air queries in world space: `density_at(p)`, `wind_at(p)` (thermals under clouds, gusts inside them, lift over the cloud sea).
  - `set_weather(0..2)`, `prewarm()`, `stats()`, `all_clouds()`.
  - The node itself drifts on the wind; cloud positions are in its space, so subtract `drift` from world points.
- `airship.gd`: one ship built from a length and a seed (`build()`), cruising straight; `hit()` is its collision. `fleet.gd` holds the convoy formation and brings it back round when the glider loses it.
- `mesh_kit.gd`: `loft`, `wing`, `body`, `rod`. UVs are in metres.
- `shaders/`: `cloud_puff` (MultiMesh puffs; per-puff data in INSTANCE_CUSTOM and COLOR), `cloud_sea`, `sky`, `hull` (plates, rivets, belly paint, portholes).

## Commands

Godot (Steam):

    "C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"

Run from this folder with `--headless --fixed-fps 60 --path . -s res://tests/<name>.gd`:

| Test | What a pass looks like |
| --- | --- |
| `flight_test` | 8 PASS |
| `cloud_test` | 10 PASS |
| `fleet_test` | 5 PASS |

`tests/shots.gd` needs a window (no `--headless`) and takes `-- <out dir>`; it saves 13 views (glider close-ups, a turn, the fleet, the cloud sea).

## Conventions

- The renderer is Compatibility on desktop too, so what you see matches the web build. No volumetric fog; the clouds are solid puffs with dithered fades.
- The cloud and sea shaders are `unshaded` with `fog_disabled` and do their own haze; the palette is handed down from `main.gd` (`HAZE`, `HAZE_DISTANCE`) and `cloud_manager.gd` (`lit_color`, `shade_color`).
- Nodes moved in `_process` (camera, cloud manager, trails) have physics interpolation turned off. Call `reset_physics_interpolation()` after teleporting anything else.
- Type GDScript vars explicitly wherever inference fails (values from Dictionaries or untyped arrays).
- Comments are plain-English `##` docs at the top of each script plus short inline notes.
- No Python on this machine. For multi-line edits, write a `.cjs` script to `$CLAUDE_JOB_DIR/tmp` and run it with node.
- Only commit or push when the user asks.

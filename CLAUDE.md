# Apollo 13: Crew Health Simulation

Internal Show & Tell demo with a 5-day build window. A 3D simulation of Apollo 13 from the oxygen tank explosion (GET 55:54) to splashdown (GET 142:54), built in Godot 4.

How it plays: the presenter runs the game on a shared screen. At 5 decision points, the audience votes in the meeting chat, and the presenter enters the winning option with the A or B key. Every path gets the crew home. The ending scorecard compares the crew's condition with what actually happened in 1970.

**SPEC.md is the source of truth** for events, poll options, the vitals model, effects, the scorecard and assets. Read the relevant section before starting any feature.

## Stack

- Godot 4, latest stable release, the standard (non-.NET) version
- GDScript only, with static typing throughout
- Renderer: start with Forward+. If the Windows laptop struggles, switch to the Mobile renderer.
- Development happens on macOS. The final build is exported to Windows.

## Commands

On the Mac, add this alias to `~/.zshrc` first:
`alias godot="/Applications/Godot.app/Contents/MacOS/Godot"`

- `godot --path .`: run the game
- `godot -e --path .`: open the editor, which also imports any new assets
- `godot --headless --path . --quit`: quick check that loads the project and reports script errors
- `godot --headless --path . --script res://tests/run_tests.gd`: run the simulation tests (exit code 0 means pass)
- `godot --headless --path . --export-release "Windows Desktop" build/windows/Apollo13.exe`: Windows export (see the Windows build section)

## Project structure

```
project.godot
data/events.json            events, captions, poll text, option effects
sim/tuning.gd               all model constants
sim/history.gd              1970 benchmark values for the scorecard
sim/sim_state.gd            state (RefCounted) and initial values
sim/sim_model.gd            static, pure: step(state, dt_hours) -> state
sim/metrics.gd              running min/max/totals for the scorecard
game/game.gd                autoload: current state and flags, emits state_changed
game/director.gd            autoload: flow state machine, presenter keys
scenes/main.tscn            root scene
scenes/cabin/               LM cabin scene, camera presets, lighting
scenes/ui/                  hud, poll, cutscene, scorecard, debug_panel
fx/screen_fx.gdshader       vignette, blur, cold tint, blackout
fx/effects.gd               maps state to shader params, camera shake, breath fog, condensation, blinks
audio/bio_audio.gd          heartbeat, breathing, master alarm
assets/audio  assets/images  assets/fonts
tests/run_tests.gd          extends SceneTree, no addons
```

## Godot rules

- **Use Godot 4 syntax only.** Common Godot 3 mistakes to avoid:
  - `await`, not `yield`
  - `instantiate()`, not `instance()`
  - `Node3D`, not `Spatial`
  - `@onready` and `@export`, not `onready var` and `export var`
  - `my_signal.connect(callable)`, not `connect("signal", self, "method")`
  - `randf_range`, not `rand_range`
  - `FileAccess`, not `File`
  - `create_tween()`, not a Tween node
- Keep hand-edits of `.tscn` files minimal and valid. Never invent `uid://` values or resource ids; load resources in code with `load("res://...")` when that's simpler. Build UI and simple nodes in code or in small scenes.
- Never edit anything in `.godot/` or any `*.import` file. Keep `.godot/` and `build/` in `.gitignore`.
- The `sim/` folder has no Node dependencies: only RefCounted classes and static functions, with no autoloads, so tests can run headless. Tests load scripts with `preload("res://...")` rather than relying on `class_name` globals.
- Every tunable number lives in `sim/tuning.gd` or `data/events.json`. No magic numbers in scene, UI or effects code.
- Use a seeded `RandomNumberGenerator` for vitals noise so every rehearsal plays identically.
- Window setup: base size 1920×1080, stretch mode `canvas_items`, aspect `expand`, so the HUD scales correctly on both laptops.
- Effects implementation:
  - One full-screen shader on a CanvasLayer for the vignette, blur, tint and blackout
  - Camera3D offset for shaking
  - CPUParticles3D for breath fog (works on every renderer)
  - OmniLight3D energy for the cabin light level
- Define presenter keys as Input Map actions and handle them in `director.gd` via `_unhandled_input`, so they work in every state.
- Missing assets must never crash the game. Check `ResourceLoader.exists()` and show a placeholder or caption instead.
- Physiology accuracy matters, because the audience works in space health:
  - SpO2 stays between 95 and 99 for the whole game. The LM had plenty of oxygen; the danger was CO2. CO2 raises breathing rate and heart rate, not SpO2.
  - Cabin pressure stays essentially flat (about 4.8 psi). Don't invent pressure drama.
- Never flash faster than 3 times per second (photosensitivity). Micro-blinks are slow fades.
- Target 60 fps on both the MacBook and the Windows laptop. Keep the cabin low-poly.
- On-screen text: sentence case and plain words, readable over screen share. Use at least font size 20 for body text and 32 for poll options at 1080p.
- Historical captions must be accurate. If unsure about a fact or time, leave a `TODO(fact-check)` comment and ask rather than inventing it.

## Workflow

- Work in small steps, one feature per task. After each step, run the tests and the quick check, then run the game so it can be checked visually, then commit with git.
- Build the debug panel early (jump to any event, scrub mission time, override any state value) and keep it working. It's how we test without playing through every time.
- Export to Windows and test on the Windows laptop by the end of Day 2.
- Don't refactor working code during the final two days unless asked.

## Windows build

1. Install export templates once, from the editor: Editor > Manage Export Templates > Download.
2. In Project > Export, add a "Windows Desktop" preset and enable "Embed PCK" so the result is a single `.exe`.
3. The `.exe` is unsigned, so Windows SmartScreen may warn about it. Click "More info", then "Run anyway".
4. On the Windows laptop, plug into power. If it has two graphics chips, set the game to use the high-performance one in Windows graphics settings.

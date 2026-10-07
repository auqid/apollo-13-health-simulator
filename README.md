# Apollo 13: Crew Health Simulation

A 3D simulation of Apollo 13, from the oxygen tank explosion (GET 55:54) to splashdown, built in
Godot 4. The presenter runs it on a shared screen, the room votes A or B in the meeting chat at five
decision points, and a scorecard compares the crew's condition with what really happened in 1970.
`SPEC.md` describes the game in full; `assets/SOURCES.md` lists where every photo and recording
comes from.

## What you need

- **Godot 4.7.2**, the standard version (not .NET). Older versions are on Godot's download archive,
  https://godotengine.org/download/archive/
- **Windows export templates**, only on the machine that builds the `.exe`. Install them once from
  the editor: Editor > Manage Export Templates > Download and Install.

## macOS

Godot lives at `/Applications/Godot.app`. Add this alias to `~/.zshrc` once, then open a new
terminal:

```sh
alias godot="/Applications/Godot.app/Contents/MacOS/Godot"
```

Run these from the repository folder:

```sh
godot --path .                                    # play the game
godot -e --path .                                 # open the editor
godot --headless --import --path .                # import new images or audio after a pull
godot --headless --path . --quit                  # quick check: loads the project, reports script errors
godot --headless --path . --script res://tests/run_tests.gd   # run the tests
echo $?                                           # 0 means every test passed
```

Build the Windows `.exe` (needs the export templates):

```sh
mkdir -p build/windows
godot --headless --path . --export-release "Windows Desktop" build/windows/Apollo13.exe
```

## Windows

Download the Windows zip for 4.7.2 and unzip it to `C:\Godot`. It holds two programs:
`Godot_v4.7.2-stable_win64.exe` opens windows, and `Godot_v4.7.2-stable_win64_console.exe` also
prints output to the terminal, so use the console one for commands.

Use **Command Prompt** (cmd). PowerShell can swallow the `--` that comes before the game's own
options; if you use PowerShell anyway, write `++` instead of `--`.

Set a shortcut for the session, then run these from the repository folder:

```bat
set GODOT=C:\Godot\Godot_v4.7.2-stable_win64_console.exe

rem Play the game
%GODOT% --path .

rem Open the editor
%GODOT% -e --path .

rem Import new images or audio after a pull
%GODOT% --headless --import --path .

rem Quick check: loads the project, reports script errors
%GODOT% --headless --path . --quit

rem Run the tests; 0 means every test passed
%GODOT% --headless --path . --script res://tests/run_tests.gd
echo %ERRORLEVEL%
```

Build the `.exe` on Windows (needs the export templates there too):

```bat
mkdir build\windows
%GODOT% --headless --path . --export-release "Windows Desktop" build\windows\Apollo13.exe
```

### Running the built game on the Windows laptop

The export embeds everything in one file, `build\windows\Apollo13.exe`; copy it over and
double-click it. Godot isn't needed on that laptop.

- The `.exe` is unsigned, so Windows SmartScreen may warn. Click **More info**, then **Run anyway**.
- Plug the laptop into power. If it has two graphics chips, set `Apollo13.exe` to **High
  performance** in Settings > System > Display > Graphics.
- The options below work on the built game too, after `--`:

```bat
Apollo13.exe -- --autoplay
```

## Presenter keys

| Key | What it does |
|---|---|
| A / B | Enter the room's vote |
| P | Pause or resume everything, to explain something |
| Space or → | Next, or skip a scene; during a fast-forward it pauses, and while paused it carries on |
| Enter | Show every scorecard row at once |
| 1 / 2 / 3 | Focus Lovell / Swigert / Haise |
| M | Mute or unmute |
| S | Silence the alarm |
| H | Hide or show the sensor panel |
| F | Fullscreen |
| R | Restart (asks to confirm) |
| ` | Debug panel: jump to any moment, scrub the clock, change any value |

## Options for testing and rehearsal

Add these after `--`, on either platform, for example `godot --path . -- --jump=e3_poll`.

| Option | What it does |
|---|---|
| `--autoplay` | Plays itself with the 1970 calls and reveals the scorecard, for rehearsing or screen-recording a backup video |
| `--autoplay=abaab` | The same, with your own picks, one letter per vote |
| `--jump=e3_poll` | Start at a moment: `intro`, `e1_cutscene`, `e1_poll`, `e1_timeskip`, and so on to `e5_poll`, then `reentry`, `scorecard` |
| `--preview=explosion` | Loop one outside shot: `exterior`, `explosion`, `lifeboat`, `burn`, `sm_jettison`, `lm_jettison`, `plasma`, `parachute`, `splash`, `map` |
| `--debug` | Open the debug panel at start |
| `--no-hud` | Hide the sensor panel |
| `--camera=co2_panel` | Cabin camera: `front_windows`, `co2_panel`, `overhead` |
| `--outside=moon` | What the windows show: `earth`, `moon` |
| `--fx=cold` | Show one effect on its own: `live`, `co2`, `cold`, `fatigue`, `power`, `explosion` |
| `--fx-strength=0.8` | How strong that effect is, from 0 to 1 |

## Project layout

| Folder | What's in it |
|---|---|
| `data/events.json` | Events, captions, subtitles, poll text and option effects |
| `sim/` | The crew health model and every tunable number (`sim/tuning.gd`); no scene code |
| `game/` | The game state and the flow of the session, including the presenter keys |
| `scenes/` | The cabin, the spacecraft and the outside shots, and the on-screen panels |
| `fx/`, `audio/` | Screen effects, and the heartbeat, breathing and alarm sounds |
| `assets/` | NASA photos, mission audio and fonts |
| `tests/run_tests.gd` | The tests |

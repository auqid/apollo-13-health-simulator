# Apollo 13: Crew Health Simulation, game spec

Times are Ground Elapsed Time (GET) in hours since launch. The explosion is at GET 55.9 and the historical splashdown at GET 142.9, 87 hours later.

All model numbers below are **game approximations** tuned to point in the right direction and land near the 1970 benchmarks. Only the values in the Scorecard section's history column are historical.

---

## 1. Session flow (about 10 minutes)

```
Intro card -> E1 Explosion -> poll -> timeskip -> E2 Return burn -> poll -> timeskip
-> E3 CO2 crisis -> poll -> timeskip -> E4 Cold coast -> poll -> timeskip
-> E5 Wake up Odyssey -> poll -> reentry sequence -> splashdown -> scorecard
```

Each event follows the same pattern:

1. **Cutscene** (20–45 s): NASA photos with a slow pan and zoom, real mission audio, and short captions. The 3D cabin is visible behind or between photos.
2. **Poll card**: a full-screen question with options A and B, each with a one-line consequence hint. The presenter runs the chat poll and presses A or B.
3. **Timeskip**: the mission clock fast-forwards at about 2 GET hours per real second while the vitals and effects change live. Timed captions appear during the skip.

### Intro card (10 s)
"April 13, 1970. Apollo 13 is about 330,000 km from Earth, two days into a smooth flight to the Moon." The mission clock starts at GET 55:52 with calm vitals.

---

## 2. Events and options

Each option carries an `effects` object in `events.json`. The option marked historical is what the 1970 crew and Mission Control did.

### E1: Explosion and lifeboat (GET 55:54)
- **Cutscene:** a bang, the master alarm, then the real "Houston, we've had a problem" exchange. Captions: oxygen is venting, *Odyssey* is dying, and the crew moves into *Aquarius*. Stress spike: +25 bpm, decaying over 2 hours.
- **Poll:** "*Aquarius* was built to keep two people alive for two days. Now it has to keep three alive for four. What do we do with the heat?"
  - **A. Shut everything down** (historical). Cabin temperature heads toward 3 °C. Power margin is unchanged.
  - **B. Keep one heater running.** Cabin temperature bottoms out around 10 °C, and the fatigue rate drops 25% (better sleep). Power margin −30.
- **Timeskip to GET 79.0.** Captions:
  - About GET 61.5: a short engine burn puts them back on a path that loops around the Moon and home.
  - About GET 77: behind the Moon, radio contact is lost. Play 4 seconds of silence. They are now farther from Earth than any humans before them.

### E2: The return burn (GET 79.0)
- **Cutscene:** the far side of the Moon, then the burn. Use real audio from around the PC+2 burn.
- **Poll:** "We're behind the Moon. How fast do we go home?"
  - **A. Standard speed-up burn** (historical). Splashdown at GET 142.9.
  - **B. Drop the Service Module and burn harder.** Splashdown about 24 hours earlier (GET 119). This option was considered in 1970 and rejected, because the Service Module protected the heat shield from the cold of space. Set `heatShieldRisk = true`: reentry stress +20 bpm on top of the normal spike, and the scorecard shows the heat shield exposure. The Service Module photo reveal moves to this point.
- **Timeskip to GET 88.0.** Caption: "CO2 is climbing. The LM's scrubbers were sized for two people."

### E3: The CO2 crisis (GET 88.0, CO2 at about 8 mmHg, alarm on)
- **Cutscene:** the CO2 caution light, CAPCOM reading up the adapter procedure (real audio from about GET 90), and the NASA photo of the finished adapter.
- **Poll:** "The ground team's adapter isn't fully tested yet. Do we build now or wait?"
  - **A. Wait for the tested procedure** (historical). CO2 peaks at about 15 mmHg around GET 91.5, then falls to about 1.5 within 2 hours.
  - **B. Build our own version now.** CO2 peaks at about 10 mmHg around GET 89.5, then settles at about 2.5 because the improvised seal leaks a little. Crew fatigue +0.15.
- **Optional mini-game** (only if ahead of schedule): the player drags 5 items (canister, bag, cardboard cover, hose, tape) onto the adapter in order. CO2 keeps rising while they work.
- **Timeskip to GET 96.0.** Caption: Haise reports that their do-it-yourself canister change is complete.

### E4: The cold coast (GET 96.0)
- **Cutscene:** a dark cabin with breath fog and condensation. Caption: water isn't just for drinking; the LM needs it to cool its electronics.
- **Poll:** "How much water do the crew drink?"
  - **A. Strict ration** (historical). About 0.18 L (6 oz) per person per day. Hydration falls, and Haise develops a fever from about GET 115. Ending water about 9%.
  - **B. Moderate ration.** About 0.5 L per person per day. No fever. Ending water about 7%.
- **Timeskip to splashdown −5 h** (GET 137.9 historical, or 114 with E2-B). Captions:
  - About GET 105: a manual course correction, steered by keeping Earth's day/night line steady in the window.
  - Day 5: *Aquarius* starts recharging *Odyssey*'s reentry batteries.

### E5: Wake up *Odyssey* (splashdown −5 h)
- **Cutscene:** if the Service Module is still attached, jettison it now. Show the NASA photo of the damaged Service Module with the crew's real audio describing the missing panel.
- **Poll:** "*Odyssey* is frozen and wet inside. When do we power it up?"
  - **A. As late as possible** (historical). The cabin stays cold, and the condensation overlay is on. Power margin is unchanged.
  - **B. Early, to warm and dry the cabin.** Cabin temperature +5 °C for the final hours and less condensation. Power margin −20.
- **Automatic reentry sequence** (no more polls):
  1. LM jettison at splashdown −1.4 h. Real "farewell, *Aquarius*" audio.
  2. Reentry: stress +15 bpm (+35 with `heatShieldRisk`).
  3. Blackout: the screen goes nearly black, leaving only the heartbeat audio and the mission clock, compressed to about 20 s. Caption: "Radio blackout. Usually about four minutes; this one lasted about six."
  4. Contact restored, parachutes, then splashdown audio.
- **Scorecard.**

---

## 3. Simulation model

### State
Shown as a schema. Implement in typed GDScript with snake_case names.
```
env:   { cabinTempC, co2mmHg, pressurePsi, waterPct, powerMargin }
crew:  { lovell, swigert, haise } each { hr, spo2, rr, bodyTempC, hydration, fatigue }
flags: { heating: 'off'|'one', returnMode: 'standard'|'fast', adapter: 'wait'|'now',
         ration: 'strict'|'moderate', powerUp: 'late'|'early', heatShieldRisk, smJettisoned }
time:  { get, splashdownGet }
stress: number  // event-driven, decays
```

### Initial values (GET 55.9)
cabinTempC 21, co2mmHg 1.0, pressurePsi 4.8, waterPct 100, powerMargin 100. Crew: hydration 1.0, fatigue 0.25 (it's late evening), bodyTempC 36.8.

### Environment rules
- **Cabin temperature:** `T = floor + (21 - floor) * exp(-(get - 56) / 22)`. floor = 3 (E1-A) or 10 (E1-B). During the final 5 hours with E5-B, add +5.
- **CO2:**
  - GET 56–80: rises linearly from 1.0 to 2.0.
  - GET 80–88: rises from 2.0 to 8.0. The alarm turns on above 7.6.
  - After E3, follow the chosen option's curve: rise to the peak, then fall exponentially (time constant 0.6 h) to the settle value. Values: wait → peak 15 at 91.5, settle 1.5. Now → peak 10 at 89.5, settle 2.5.
- **Pressure:** 4.8 ± 0.03 noise. Flat on purpose.
- **Water:** declines linearly from 100% at the explosion to the ending value at splashdown. Strict ends at 9% and moderate at 7%. With E2-B, compute the consumption rate from the standard duration so the shorter trip ends higher.
- **Power margin:** a game index where history = 100. Apply option deltas; E2-B adds +15 (shorter trip). Clamp to 40 at minimum so every path still gets home.

### Crew rules (per tick, per astronaut)
```
hr = base + 0.6*max(0, 18 - T) + 1.2*max(0, co2 - 5) + 12*max(0, bodyTemp - 37)
        + 8*fatigue + stress + noise(±2)            clamp 50..140
rr = 14 + 0.8*max(0, co2 - 4) + 3*max(0, bodyTemp - 37) + noise(±1)
spo2 = 97 + noise(±1)                               clamp 95..99, always
bodyTemp = 36.8, or 36.6 when T < 8
fatigue += 0.008/h (+0.004/h when T < 8), x0.75 rate with heater; clamp 0..1
hydration declines linearly to 0.55 (strict) or 0.80 (moderate) by splashdown
```
Base heart rates: Lovell 68, Swigert 72, Haise 70.

**Haise's infection:** if hydration < 0.7 at GET 115, his body temperature ramps from 37.0 to 38.3 between GET 115 and 125 and stays there. A short caption appears the first time it crosses 38.0: "Haise is running a fever."

**Stress events:** explosion +25 (2 h decay), each burn +10 for the burn's duration, reentry +15 (+20 more with heatShieldRisk).

**Weight loss (crew total, for the scorecard):** 0.164 kg/h with strict rationing and 0.109 kg/h with moderate rationing, multiplied by the hours from explosion to splashdown.

---

## 4. Effects (state → what the audience sees and hears)

| Driver | Effect | Mapping |
|---|---|---|
| CO2 | Dark vignette | opacity = clamp((co2 − 5) / 10, 0, 0.7) |
| CO2 | Blur on the 3D view | blur px = clamp((co2 − 8) × 0.4, 0, 3) |
| CO2 > 10 | HUD text wobble | 1–2 px slow drift |
| CO2 > 7.6 | Caution light + alarm tone | alarm silenced by the presenter, light stays on |
| Cold | Camera shake (shivering) | amplitude = clamp((10 − T) / 7, 0, 1) × 0.015 rad |
| Cold < 12 °C | Breath fog sprites near camera | density scales with coldness |
| Cold | Blue tint | stronger as T falls |
| Cold < 8 °C after GET 120, or E5-A | Condensation droplets overlay | full-screen texture or shader overlay |
| Power | Cabin light level | 0.35 + 0.65 × (powerMargin / 100), plus a big dim at the explosion |
| Fatigue > 0.6 | Micro-blink | 250 ms fade to black, at most once every 8–12 s |
| Focused crew HR | Heartbeat audio | tempo = HR, volume rises above 80 bpm |
| Focused crew RR | Breathing audio loop | rate = RR |

---

## 5. HUD

Keep the 3D view as the main thing on screen. The HUD is a compact side panel.

- **Top left:** mission clock (GET hhh:mm:ss) and time since the explosion.
- **Right panel:** three crew rows (name, HR, SpO2, breathing rate, body temperature). The focused crew member is highlighted, and the heartbeat follows them.
- **Bottom of panel:** cabin temperature, CO2 (a bar with the 7.6 mmHg safe-limit marker), cabin pressure, water %, power margin.
- **Panel label:** "Modern sensors on a 1970 crew." SpO2 monitoring didn't exist on Apollo, so this nods to what our team builds.

---

## 6. Scorecard

Title: "Every path brings them home. How much margin did you leave them?"

| Metric | You | Apollo 13, 1970 |
|---|---|---|
| Explosion to splashdown | computed | 87 h |
| Coldest cabin temperature | computed | about 3 °C (38 °F) |
| Peak CO2 | computed | about 15 mmHg (safe limit 7.6) |
| Drinking water per person | from option | about 0.18 L (6 oz) a day, a fifth of normal |
| Water left at splashdown | computed | about 9% |
| Crew weight loss (combined) | computed | 14.3 kg (31.5 lb) |
| Haise's infection | computed | yes, a urinary tract infection with fever |
| Power margin | computed | 100 (game index) |
| Heat shield exposed | yes/no | no, the Service Module stayed attached until near the end |

Mark each row as better, worse or same. End on a single line: "The real crew made it home with almost nothing to spare."

Benchmark sources:
- Lovell's account, *Apollo Expeditions to the Moon* (SP-350), ch. 13: https://history.nasa.gov/SP-350/ch-13-3.html
- Apollo 13 Flight Journal: https://www.nasa.gov/history/afj/ap13fj/
- *Biomedical Results of Apollo* (SP-368), for the 7.6 torr CO2 limit

---

## 7. Presenter controls

| Key | Action |
|---|---|
| Space or → | Advance or skip the current cutscene |
| A / B | Choose a poll option |
| 1 / 2 / 3 | Focus Lovell / Swigert / Haise |
| M | Mute or unmute |
| S | Silence the alarm |
| H | Hide or show the HUD |
| F | Fullscreen |
| R | Restart (asks for confirmation) |
| ` | Debug panel |

---

## 8. Visual direction

The cabin is 1970 hardware; the HUD is today's sensors looking at it. The contrast is the design idea.

- **Cabin:** matte grey-green panels, black instrument faces, white placard lettering, amber caution and red warning lamps. Dim, warm-white light. Two angled triangular front windows showing Earth or the Moon.
- **HUD:** cool, quiet and precise. Thin lines, tabular figures, generous spacing. No sci-fi neon.
- **Palette:** panel grey `#5E6560`, instrument black `#1A1D1C`, placard white `#ECE9E1`, caution amber `#E2A33B`, warning red `#C4372C`, sensor teal `#8CCFC1` (HUD only), cold tint `#9DB8D9`.
- **Type:** Barlow Condensed for title cards, captions and in-cabin placards. Barlow with tabular numbers for the HUD. Download both from Google Fonts (open license) into `assets/fonts/`.

### Cabin build notes
- Use low-poly geometry: boxes and extrusions for the front panel, side panels and overhead.
- Draw panel details as simple textures (gauge faces, rows of toggle switches) instead of modelling them.
- Place a textured sphere outside the windows for Earth or the Moon.
- Use a fixed first-person camera with a gentle zero-g idle drift. Set 2–3 camera presets per event (front windows, the CO2 panel, the overhead).
- Add a few slowly tumbling loose objects (a checklist, a bag, a hose) to sell weightlessness cheaply.

---

## 9. Assets checklist

All NASA mission audio, transcripts and photos are public domain. Do not use audio, music or clips from the 1995 film. Files go under `assets/`; Godot imports .ogg, .mp3 and .wav.

Sources:
- Apollo 13 in Real Time (full mission audio, searchable by GET): https://apolloinrealtime.org/13/
- Apollo 13 Flight Journal (transcripts with GET): https://www.nasa.gov/history/afj/ap13fj/
- NASA Image and Video Library: https://images.nasa.gov

| File | Content |
|---|---|
| `audio/e1_problem.mp3` | The "we've had a problem" exchange, plus a few seconds of reports about venting |
| `audio/e2_burn.mp3` | Around the PC+2 burn |
| `audio/e3_procedure.mp3` | CAPCOM reading up the adapter procedure (about GET 90) |
| `audio/e3_complete.mp3` | Crew reporting the adapter done |
| `audio/e5_sm.mp3` | Crew describing the Service Module damage after jettison |
| `audio/e5_farewell.mp3` | LM jettison farewell |
| `audio/e5_splash.mp3` | Contact after blackout, parachutes, splashdown |
| `images/` | Earth from the LM, the Moon's far side, the CO2 adapter, the dark cabin, the damaged Service Module, parachutes, recovery |

Trim clips to 10–30 s and normalize the volume (Audacity is fine).

---

## 10. Build order (5 days)

**Day 1, model and HUD.** Create the Godot project and folder structure from CLAUDE.md. Create `events.json`, `tuning.gd` and `history.gd` from this spec. Implement `sim/sim_model.gd` with tests in `tests/run_tests.gd` (CO2 peaks, Haise's fever logic, SpO2 always 95–99, every option combination reaching splashdown). Build the HUD and the debug panel with timeskip working on a blank background. *A second person collects and trims the assets.*

**Day 2, cabin, effects and a Windows test.** Build the cabin scene, windows, lighting tied to the power margin, and camera presets. Implement the screen effects shader, camera shake, breath fog and the heartbeat, breathing and alarm audio. **Before the day ends, export to Windows and run it on the Windows laptop** so any graphics or performance problems show up early.

**Day 3, flow.** Build the director state machine, cutscenes (photo pans, audio, captions), poll cards, timeskip captions, presenter keys, and the reentry sequence.

**Day 4, ending and polish.** Build the scorecard. Fill in the real assets and captions. Fact-check every caption. Add the optional CO2 mini-game only if everything else is done.

**Day 5, rehearse.** Export the final Windows build and do at least 3 full run-throughs on the presenting laptop with someone playing the audience. Tune the timings. Test it over screen share with **shared computer audio** turned on. Record a backup video of a full playthrough.

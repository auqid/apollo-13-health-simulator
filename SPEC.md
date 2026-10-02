# Apollo 13: Crew Health Simulation, game spec

Times are Ground Elapsed Time (GET) in hours since launch. The explosion is at GET 55:54 (55.9 h in the model) and splashdown at GET 142:54:41 (142.9 h in the model), 87 hours later.

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
- **Poll:** "The lifeboat is short on power. Do we keep the crew warm?" The card does not say which option is historical.
  - **A. Save power** (historical). Good: more battery for the trip home. Cost: the cabin gets close to freezing. Cabin temperature heads toward 3 °C. Power margin is unchanged.
  - **B. Keep a heater on.** Good: a warmer crew that sleeps better. Cost: less battery for the trip home. Cabin temperature bottoms out around 10 °C, and the fatigue rate drops 25%. Power margin −30.
- **Timeskip to GET 79.0.** Captions:
  - At 61:29:43.5: a 34-second burn puts them back on a path that loops around the Moon and home.
  - At about 77:08: behind the Moon, radio contact is lost for about 25 minutes. Play 4 seconds of silence.
  - On the far-side pass, with no GET in the caption: they are farther from Earth than any humans before them. A distance record that stood until Artemis II in 2026.
  - Contact returns at about 77:33. That line is in the E2 cutscene, where there is time to read it.

### E2: The return burn (GET 79.0)
- **Cutscene:** in this order: the far side pass, radio contact restored at about 77:33, then the PC+2 burn at GET 079:27:39.0 (263.8 s). Use real audio from around the PC+2 burn.
- **Poll:** "We've come around the Moon. How fast do we go home?"
  - **A. Normal speed** (historical). Good: the heat shield stays protected. Cost: a longer trip in the cold lifeboat. Splashdown at GET 142.9.
  - **B. Fastest way home.** Good: home about a day sooner. Cost: we drop the damaged back half of the ship, leaving the heat shield exposed. Splashdown about 24 hours earlier (GET 119). This option was considered in 1970 and rejected, because the Service Module protected the heat shield from the cold of space. Set `heatShieldRisk = true`: reentry stress +20 bpm on top of the normal spike, and the scorecard shows the heat shield exposure. The Service Module photo reveal moves to this point.
- **Timeskip to GET 88.0.** Caption: "CO2 is climbing. The LM's scrubbers were sized for two people."

### E3: The CO2 crisis (GET 88.0, CO2 at about 8 mmHg, alarm on)
- **Cutscene:** the CO2 caution light, Joe Kerwin reading up the adapter procedure from about 90:22, and the NASA photo of the finished adapter. Parts: two lithium hydroxide canisters, gray tape, bags from two cooling garments, an LM cue card, suit hoses and a sock.
- **Poll:** "CO2 is building up. Houston's fix isn't fully tested yet."
  - **A. Wait for Houston** (historical). Good: a tested design that seals well. Cost: CO2 climbs higher while we wait. CO2 peaks at about 15 mmHg, then falls to about 1.5 within 2 hours. Do not show a GET for the CO2 peak on screen.
  - **B. Build it now.** Good: CO2 stops rising sooner. Cost: a tired crew and a leaky seal. CO2 peaks at about 10 mmHg, then settles at about 2.5 because the improvised seal leaks a little. Crew fatigue +0.15. Do not show a GET for the CO2 peak on screen.
- **Optional mini-game** (only if ahead of schedule): the player drags the real parts onto the adapter (two lithium hydroxide canisters, gray tape, bags from two cooling garments, an LM cue card, suit hoses and a sock). CO2 keeps rising while they work.
- **Timeskip to GET 96.0.** At about 91:30, Haise: "Our do-it-yourself lithium hydroxide canister change is complete." Do not show a GET for the CO2 peak.

### E4: The cold coast (GET 96.0)
- **Cutscene:** a dark cabin with breath fog and condensation. Caption: water isn't just for drinking; the LM needs it to cool its electronics.
- **Poll:** "Water also cools the electronics. How much should the crew drink?"
  - **A. Very little** (historical). Good: more water to cool the electronics. Cost: dehydration and risk of infection. About 0.18 L (6 oz) per person per day. Hydration falls, and Haise develops a fever from about GET 115. Ending water about 9%.
  - **B. A bit more.** Good: a healthier crew. Cost: less spare water. About 0.5 L per person per day. No fever. Ending water about 7%.
- **Timeskip to splashdown −5 h** (GET 137.9 historical, or 114 with E2-B). Captions:
  - At 105:18:28: a 14-second manual course correction, steered by keeping Earth's day/night line steady in the window.
  - At about 112:12: *Aquarius* starts recharging *Odyssey*'s reentry batteries. Charging takes about 15 hours.

### E5: Wake up *Odyssey* (splashdown −5 h)
- **Cutscene:** if the Service Module is still attached, jettison it now (about 138:02). Show the NASA photo of the damaged Service Module with the crew's audio. Lovell: "And there's one whole side of that spacecraft missing." Then: "Right by the high gain antenna, the whole panel is blown out, almost from the base to the engine." Optional, at 138:09:09, Haise: "Man, that's unbelievable!"
- **Poll:** "The landing capsule is frozen and wet inside. When do we switch it on?"
  - **A. As late as possible** (historical). Good: more battery for landing. Cost: freezing, dripping final hours. The cabin stays cold, and the condensation overlay is on. Power margin is unchanged.
  - **B. Early, to warm up.** Good: a warmer, drier crew. Cost: less battery for landing. Cabin temperature +5 °C for the final hours and less condensation. Power margin −20.
- **Automatic reentry sequence** (no more polls):
  1. LM jettison at 141:30:05. CAPCOM Joe Kerwin: "Farewell, Aquarius, and we thank you."
  2. Blackout from 142:39 to 142:45. The screen goes nearly black, leaving only the heartbeat audio and the mission clock, compressed to about 20 s. Caption: "Radio blackout lasted about six minutes, roughly a minute and a half longer than expected."
  3. Entry interface at 142:40:46. Stress +15 bpm (+35 with `heatShieldRisk`).
  4. Contact restored at 142:45, parachutes, then splashdown at 142:54:41.
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
  - After E3, follow the chosen option's curve: rise to the peak, then fall exponentially (time constant 0.6 h) to the settle value. Values: wait → peak 15 at 91.5, settle 1.5. Now → peak 10 at 89.5, settle 2.5. Those peak times stay in the model. Do not show a GET for the CO2 peak on screen.
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

**Stress events:** explosion +25 (2 h decay), each burn +10 for the burn's duration, reentry +15 (+20 more with heatShieldRisk). Reentry stress starts at entry interface, 142:40:46.

Burns, ignition GET and duration:

| Burn | Ignition | Duration |
|---|---|---|
| Free-return | 61:29:43.5 | 34 s |
| PC+2 | 79:27:39.0 | 263.8 s |
| Manual course correction | 105:18:28 | 14 s |
| Final correction | 137:39:51.5 | 21.5 s |

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
- Apollo 13 Flight Journal: https://www.apollojournals.org/afj/ap13fj/
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
- Apollo 13 Flight Journal (transcripts with GET): https://www.apollojournals.org/afj/ap13fj/
- NASA Image and Video Library: https://images.nasa.gov

| File | Content |
|---|---|
| `audio/e1_problem.mp3` | The "we've had a problem" exchange, plus a few seconds of reports about venting |
| `audio/e2_burn.mp3` | Around the PC+2 burn |
| `audio/e3_procedure.mp3` | Joe Kerwin reading up the adapter procedure (from about 90:22) |
| `audio/e3_complete.mp3` | Haise at about 91:30, reporting the canister change complete |
| `audio/e5_sm.mp3` | Lovell and Haise describing the Service Module damage (about 138:02) |
| `audio/e5_farewell.mp3` | Joe Kerwin at 141:30:05: "Farewell, Aquarius, and we thank you." |
| `audio/e5_splash.mp3` | Contact after blackout, parachutes, splashdown |
| `images/` | Earth from the LM, the Moon's far side, the CO2 adapter, the dark cabin, the damaged Service Module, parachutes, recovery |

Trim clips to 10–30 s and normalize the volume (Audacity is fine).

---

## 10. Build order (5 days)

**Day 1, model and HUD.** Create the Godot project and folder structure from CLAUDE.md. Create `events.json`, `tuning.gd` and `history.gd` from this spec. Implement `sim/sim_model.gd` with tests in `tests/run_tests.gd` (CO2 peaks, Haise's fever logic, SpO2 always 95–99, every option combination reaching splashdown). Build the HUD and the debug panel with timeskip working on a blank background. *A second person collects and trims the assets.*

**Day 2, cabin, effects and a Windows test.** Build the cabin scene, windows, lighting tied to the power margin, and camera presets. Implement the screen effects shader, camera shake, breath fog and the heartbeat, breathing and alarm audio. **Before the day ends, export to Windows and run it on the Windows laptop** so any graphics or performance problems show up early.

**Day 3, flow.** Build the director state machine, cutscenes (photo pans, audio, captions), poll cards, timeskip captions, presenter keys, and the reentry sequence. The director slows the clock to near real time for the PC+2 burn and the reentry, so burn stress is visible.

**Day 4, ending and polish.** Build the scorecard. Fill in the real assets and captions. Fact-check every caption. Add the optional CO2 mini-game only if everything else is done.

**Day 5, rehearse.** Export the final Windows build and do at least 3 full run-throughs on the presenting laptop with someone playing the audience. Tune the timings. Test it over screen share with **shared computer audio** turned on. Record a backup video of a full playthrough.

extends RefCounted
## Every model and flow constant (SPEC.md section 3). These are game approximations,
## tuned to land near the 1970 benchmarks in sim/history.gd.
## Units: *_GET is mission time in hours since launch, *_H is a duration in hours.

# --- Mission timeline ---
const EXPLOSION_GET: float = 55.9
const STANDARD_SPLASHDOWN_GET: float = 142.9
const FAST_SPLASHDOWN_GET: float = 119.0
const SPLASHDOWN_GET_BY_RETURN: Dictionary = {
	"standard": STANDARD_SPLASHDOWN_GET,
	"fast": FAST_SPLASHDOWN_GET,
}
## Water and hydration use the standard trip length on every path, so a shorter trip ends with more left.
const STANDARD_TRIP_H: float = STANDARD_SPLASHDOWN_GET - EXPLOSION_GET

## Allowed values for each flag. The first value is the default and the historical choice.
const FLAG_VALUES: Dictionary = {
	"heating": ["off", "one"],
	"return_mode": ["standard", "fast"],
	"adapter": ["wait", "now"],
	"ration": ["strict", "moderate"],
	"power_up": ["late", "early"],
	"heat_shield_risk": [false, true],
	"sm_jettisoned": [false, true],
}

# --- Cabin temperature: T = floor + (start - floor) * exp(-(get - cooling start) / tau) ---
const CABIN_START_C: float = 21.0
const COOLING_START_GET: float = 56.0
const COOLING_TAU_H: float = 22.0
const CABIN_FLOOR_C_BY_HEATING: Dictionary = {"off": 3.0, "one": 10.0}
## E5-B: powering Odyssey up early warms the cabin for the final hours before splashdown.
const POWER_UP_WARMING_C: float = 5.0
const POWER_UP_WINDOW_H: float = 5.0
const POWER_UP_RAMP_H: float = 1.0

# --- CO2 ---
const CO2_START_MMHG: float = 1.0
const CO2_SLOW_RISE_START_GET: float = 56.0
const CO2_SLOW_RISE_END_GET: float = 80.0
const CO2_SLOW_RISE_END_MMHG: float = 2.0
const CO2_FAST_RISE_END_GET: float = 88.0
const CO2_FAST_RISE_END_MMHG: float = 8.0
## Caution light and alarm: the 7.6 mmHg (torr) limit from Biomedical Results of Apollo (SP-368).
const CO2_ALARM_MMHG: float = 7.6
## After E3, CO2 rises in a straight line to the peak, then falls exponentially to the settle value.
const CO2_FALL_TAU_H: float = 0.6
const CO2_CURVE_BY_ADAPTER: Dictionary = {
	"wait": {"peak_mmhg": 15.0, "peak_get": 91.5, "settle_mmhg": 1.5},
	"now": {"peak_mmhg": 10.0, "peak_get": 89.5, "settle_mmhg": 2.5},
}

# --- Cabin pressure: flat on purpose ---
const PRESSURE_PSI: float = 4.8
const PRESSURE_NOISE_PSI: float = 0.03

# --- Consumables ---
const WATER_START_PCT: float = 100.0
const WATER_END_PCT_BY_RATION: Dictionary = {"strict": 9.0, "moderate": 7.0}
## A game index where the historical path is 100. Options add deltas; the clamp keeps every path flyable.
const POWER_MARGIN_START: float = 100.0
const POWER_MARGIN_MIN: float = 40.0
## Scorecard: drinking water per person per day.
const DRINK_L_PER_DAY_BY_RATION: Dictionary = {"strict": 0.18, "moderate": 0.5}
## Scorecard: combined crew weight loss per hour from explosion to splashdown.
const WEIGHT_LOSS_KG_PER_H_BY_RATION: Dictionary = {"strict": 0.164, "moderate": 0.109}

# --- Heart rate: base + cold + CO2 + fever + fatigue + stress + noise ---
const BASE_HR_BPM_BY_CREW: Dictionary = {"lovell": 68.0, "swigert": 72.0, "haise": 70.0}
const HR_COLD_BELOW_C: float = 18.0
const HR_PER_COLD_C: float = 0.6
const HR_CO2_ABOVE_MMHG: float = 5.0
const HR_PER_CO2_MMHG: float = 1.2
const HR_FEVER_ABOVE_C: float = 37.0
const HR_PER_FEVER_C: float = 12.0
const HR_PER_FATIGUE: float = 8.0
const HR_NOISE_BPM: float = 2.0
const HR_MIN_BPM: float = 50.0
const HR_MAX_BPM: float = 140.0

# --- Breathing rate: base + CO2 + fever + noise (CO2 drives breathing, not SpO2) ---
const RR_BASE_PER_MIN: float = 14.0
const RR_CO2_ABOVE_MMHG: float = 4.0
const RR_PER_CO2_MMHG: float = 0.8
const RR_FEVER_ABOVE_C: float = 37.0
const RR_PER_FEVER_C: float = 3.0
const RR_NOISE_PER_MIN: float = 1.0

# --- SpO2: the LM had plenty of oxygen, so SpO2 stays 95-99 on every path ---
const SPO2_BASE_PCT: float = 97.0
const SPO2_NOISE_PCT: float = 1.0
const SPO2_MIN_PCT: float = 95.0
const SPO2_MAX_PCT: float = 99.0

# --- Body temperature ---
const BODY_TEMP_C: float = 36.8
const BODY_TEMP_COLD_C: float = 36.6
const BODY_COLD_BELOW_CABIN_C: float = 8.0

# --- Fatigue (0 to 1) ---
const FATIGUE_START: float = 0.25
const FATIGUE_PER_H: float = 0.008
const FATIGUE_COLD_EXTRA_PER_H: float = 0.004
const FATIGUE_COLD_BELOW_CABIN_C: float = 8.0
const FATIGUE_HEATER_RATE_MULT: float = 0.75

# --- Hydration (0 to 1): straight line from the explosion to the ration's value at standard splashdown ---
const HYDRATION_START: float = 1.0
const HYDRATION_END_BY_RATION: Dictionary = {"strict": 0.55, "moderate": 0.80}

# --- Haise's infection: decided once at the check time, then a temperature ramp ---
const FEVER_CREW_ID: String = "haise"
const FEVER_CHECK_GET: float = 115.0
const FEVER_HYDRATION_BELOW: float = 0.7
const FEVER_START_C: float = 37.0
const FEVER_PEAK_C: float = 38.3
const FEVER_PEAK_GET: float = 125.0
## The "Haise is running a fever" caption shows the first time his temperature reaches this.
const FEVER_CAPTION_C: float = 38.0

# --- Stress: bpm added to every crew member's heart rate ---
const EXPLOSION_STRESS_BPM: float = 25.0
## The explosion stress fades in a straight line to zero over this many hours.
const EXPLOSION_STRESS_FADE_H: float = 2.0
const BURN_STRESS_BPM: float = 10.0
## Engine burns between the explosion and splashdown: ignition GET (h + min/60 + s/3600) and duration.
## PC+2 at 079:27:40 is confirmed. TODO(fact-check): the other ignition times and all durations.
const BURNS: Array = [
	{"name": "Free-return burn", "get": 61.0 + 29.0 / 60.0 + 43.0 / 3600.0, "duration_h": 34.0 / 3600.0},
	{"name": "PC+2 burn", "get": 79.0 + 27.0 / 60.0 + 40.0 / 3600.0, "duration_h": 264.0 / 3600.0},
	{"name": "Course correction 5", "get": 105.0 + 18.0 / 60.0 + 28.0 / 3600.0, "duration_h": 14.0 / 3600.0},
	{"name": "Course correction 7", "get": 137.0 + 39.0 / 60.0 + 52.0 / 3600.0, "duration_h": 22.0 / 3600.0},
]
const REENTRY_STRESS_BPM: float = 15.0
const HEAT_SHIELD_EXTRA_STRESS_BPM: float = 20.0
## Entry interface (about GET 142:40:46) to splashdown (GET 142:54:41). TODO(fact-check)
const REENTRY_BEFORE_SPLASHDOWN_H: float = 0.23

# --- Vitals noise: each channel drifts smoothly toward a new random target, one step per sim tick ---
const NOISE_SEED: int = 19700413
const NOISE_SEGMENT_TICKS_MIN: int = 40
const NOISE_SEGMENT_TICKS_MAX: int = 90

# --- Flow ---
## Mission clock speed during a timeskip, in GET hours per real second.
const TIMESKIP_H_PER_S: float = 2.0
## Largest sim step when seeking or rebuilding the state, in GET hours.
const SEEK_STEP_H: float = 0.05
## Seconds the presenter has to press restart again to confirm.
const RESTART_CONFIRM_S: float = 3.0
## Seconds a caption or notice stays on screen.
const CAPTION_HOLD_S: float = 4.0
## Clock speeds offered in the debug panel, in GET hours per real second.
const DEBUG_RATES_H_PER_S: Array = [0.1, 0.5, 1.0, 2.0, 4.0, 8.0]

# --- Display scales ---
const HUD_CO2_BAR_MAX_MMHG: float = 20.0

# --- Cabin light level (SPEC.md section 4): floor + span x (power margin / 100) ---
const LIGHT_LEVEL_FLOOR: float = 0.35
const LIGHT_LEVEL_SPAN: float = 0.65

# --- Effects (SPEC.md section 4). Nothing may flash faster than 3 times a second. ---
## CO2 vignette opacity = clamp((co2 - start) / span, 0, max)
const FX_VIGNETTE_CO2_START: float = 5.0
const FX_VIGNETTE_CO2_SPAN: float = 10.0
const FX_VIGNETTE_MAX: float = 0.7
## The vignette darkens from this far out (0 centre, 1 corner), so the middle of the view stays clear.
const FX_VIGNETTE_INNER: float = 0.42
const FX_VIGNETTE_OUTER: float = 1.05
## CO2 blur on the 3D view, in 1080p pixels = clamp((co2 - start) x per mmHg, 0, max)
const FX_BLUR_CO2_START: float = 8.0
const FX_BLUR_PX_PER_MMHG: float = 0.4
const FX_BLUR_MAX_PX: float = 3.0
## Above 10 mmHg the HUD drifts slowly, reaching 2 px at 15 mmHg.
const FX_WOBBLE_CO2_START: float = 10.0
const FX_WOBBLE_CO2_SPAN: float = 5.0
const FX_WOBBLE_MAX_PX: float = 2.0
const FX_WOBBLE_PERIODS_S: Vector2 = Vector2(3.7, 5.3)
## Shivering: camera shake amplitude = clamp((below - T) / span, 0, 1) x max
const FX_SHAKE_BELOW_C: float = 10.0
const FX_SHAKE_SPAN_C: float = 7.0
const FX_SHAKE_MAX_RAD: float = 0.015
## The shake wanders at about this rate. Kept at 3 Hz so the picture never strobes.
const FX_SHAKE_HZ: float = 3.0
const FX_SHAKE_SEED: int = 1971
## Breath fog: none at 12 °C, full at 3 °C. Alpha of a puff at full density.
const FX_FOG_BELOW_C: float = 12.0
const FX_FOG_FULL_C: float = 3.0
const FX_FOG_MAX_ALPHA: float = 0.2
const FX_FOG_PARTICLES: int = 14
const FX_FOG_LIFETIME_S: float = 1.8
const FX_FOG_SPEED_MIN: float = 0.02
const FX_FOG_SPEED_MAX: float = 0.05
const FX_FOG_PUFF_M: float = 0.022
## Cold tint: grows from 18 °C down to 3 °C, up to this strength.
const FX_TINT_BELOW_C: float = 18.0
const FX_TINT_FULL_C: float = 3.0
const FX_TINT_MAX: float = 0.5
## Condensation: on below 8 °C after GET 120, or once E5 is reached with Odyssey powered up late.
## Powering up early (E5-B) leaves this much.
const FX_CONDENSATION_BELOW_C: float = 8.0
const FX_CONDENSATION_AFTER_GET: float = 120.0
const FX_CONDENSATION_EARLY_POWER_UP: float = 0.35
## Droplet grid cells across the screen height, and how much of the full density reaches the centre.
const FX_DROPLET_CELLS: float = 12.0
## Droplets stay off the middle of the view. 0 is none at the centre.
const FX_DROPLET_CENTRE_SHARE: float = 0.0
## Micro-blinks above 0.6 fatigue: a 250 ms fade, at most once every 8 to 12 s.
const FX_BLINK_FATIGUE_ABOVE: float = 0.6
const FX_BLINK_S: float = 0.25
const FX_BLINK_INTERVAL_S_MIN: float = 8.0
const FX_BLINK_INTERVAL_S_MAX: float = 12.0
const FX_BLINK_DEPTH_MIN: float = 0.55
const FX_BLINK_DEPTH_MAX: float = 0.9
const FX_BLINK_SEED: int = 1104
## The big dim at the explosion, in real seconds: drop, hold, then recover. Depth is the share of light lost.
const FX_EXPLOSION_DIM_DEPTH: float = 0.85
const FX_EXPLOSION_DIM_DROP_S: float = 0.08
const FX_EXPLOSION_DIM_HOLD_S: float = 0.6
const FX_EXPLOSION_DIM_RECOVER_S: float = 2.5
## Effects ease toward their targets over about this long, so jumps and seeks never pop.
const FX_SMOOTH_S: float = 0.5
## Caution and master alarm lamps fade on and off over about this long.
const FX_LAMP_FADE_S: float = 0.25
## In the debug panel's single-effect modes, the first blink comes this soon.
const FX_FORCED_FIRST_BLINK_S: float = 1.5
## Debug panel jump for the cold coast: shivering, breath fog, tint, condensation, blinks and the fever all at once.
const DEBUG_COLD_COAST_GET: float = 125.0

# --- Cabin camera, real seconds ---
const CAMERA_MOVE_S: float = 2.0
## Zero-g idle drift: position and rotation wander on slow sine waves, one period per channel.
const CAMERA_DRIFT_M: float = 0.02
const CAMERA_DRIFT_DEG: float = 0.6
const CAMERA_DRIFT_PERIODS_S: Array = [9.7, 13.3, 17.9, 11.1, 15.7, 21.3]

# --- Loose objects floating in the cabin, real seconds ---
const FLOAT_DRIFT_M_MIN: float = 0.03
const FLOAT_DRIFT_M_MAX: float = 0.07
const FLOAT_DRIFT_PERIOD_S_MIN: float = 18.0
const FLOAT_DRIFT_PERIOD_S_MAX: float = 34.0
const FLOAT_SPIN_DEG_PER_S_MIN: float = 4.0
const FLOAT_SPIN_DEG_PER_S_MAX: float = 11.0
const FLOAT_SEED: int = 1970

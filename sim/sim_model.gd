extends RefCounted
## The crew health model (SPEC.md section 3). Static and pure: step() and apply_effects() return
## a new state and never change their input. Every number comes from sim/tuning.gd.

const SimState := preload("res://sim/sim_state.gd")
const Tuning := preload("res://sim/tuning.gd")

const EFFECT_KEYS: Array[String] = ["flags", "power_margin", "fatigue"]

const _DRIFT_FROM: int = 0
const _DRIFT_TO: int = 1
const _DRIFT_TICK: int = 2
const _DRIFT_LENGTH: int = 3
const _DRIFT_SIZE: int = 4


## A new state at start_get with the initial values and the vitals they imply.
static func initial_state(start_get: float = Tuning.EXPLOSION_GET) -> SimState:
	var state := SimState.new()
	state.time.current_get = start_get
	state.time.splashdown_get = Tuning.SPLASHDOWN_GET_BY_RETURN[state.flags.return_mode]
	var rng := RandomNumberGenerator.new()
	rng.seed = Tuning.NOISE_SEED
	_update(state, start_get, rng)
	state.rng_state = rng.state
	return state


## Advances mission time by dt_hours and returns the new state. Each call is also one tick of the
## vitals noise, so call it at a fixed rate, with dt_hours = 0 while the clock is stopped.
static func step(state: SimState, dt_hours: float) -> SimState:
	var next := state.copy()
	var from_get := next.time.current_get
	next.time.current_get = from_get + maxf(dt_hours, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.state = next.rng_state
	_update(next, from_get, rng)
	next.rng_state = rng.state
	return next


## Applies an "effects" object from events.json: flag values, a power margin delta and a fatigue delta.
static func apply_effects(state: SimState, effects: Dictionary) -> SimState:
	var next := state.copy()
	for key: String in effects:
		if key not in EFFECT_KEYS:
			push_warning("Unknown effect '%s' in events.json" % key)
	var flags: Dictionary = effects.get("flags", {})
	for flag: String in flags:
		if Tuning.FLAG_VALUES.has(flag) and flags[flag] in Tuning.FLAG_VALUES[flag]:
			next.flags.set(flag, flags[flag])
		else:
			push_warning("Unknown flag value %s = %s in events.json" % [flag, flags[flag]])
	next.time.splashdown_get = Tuning.SPLASHDOWN_GET_BY_RETURN[next.flags.return_mode]
	var margin: float = next.env.power_margin + float(effects.get("power_margin", 0.0))
	next.env.power_margin = maxf(margin, Tuning.POWER_MARGIN_MIN)
	var fatigue_delta: float = effects.get("fatigue", 0.0)
	for crew_id in SimState.CREW_IDS:
		var member: SimState.CrewMember = next.crew[crew_id]
		member.fatigue = clampf(member.fatigue + fatigue_delta, 0.0, 1.0)
	return next


static func co2_alarm(state: SimState) -> bool:
	return state.env.co2_mmhg > Tuning.CO2_ALARM_MMHG


# --- Environment ---

static func cabin_temp_at(flags: SimState.Flags, at_get: float, splashdown_get: float) -> float:
	var floor_c: float = Tuning.CABIN_FLOOR_C_BY_HEATING[flags.heating]
	var cooling_h: float = maxf(at_get - Tuning.COOLING_START_GET, 0.0)
	var temp_c: float = floor_c + (Tuning.CABIN_START_C - floor_c) * exp(-cooling_h / Tuning.COOLING_TAU_H)
	if flags.power_up == "early":
		var powered_h: float = at_get - (splashdown_get - Tuning.POWER_UP_WINDOW_H)
		temp_c += Tuning.POWER_UP_WARMING_C * clampf(powered_h / Tuning.POWER_UP_RAMP_H, 0.0, 1.0)
	return temp_c


static func co2_at(flags: SimState.Flags, at_get: float) -> float:
	if at_get <= Tuning.CO2_SLOW_RISE_END_GET:
		var slow: float = clampf(inverse_lerp(Tuning.CO2_SLOW_RISE_START_GET, Tuning.CO2_SLOW_RISE_END_GET, at_get), 0.0, 1.0)
		return lerpf(Tuning.CO2_START_MMHG, Tuning.CO2_SLOW_RISE_END_MMHG, slow)
	if at_get <= Tuning.CO2_FAST_RISE_END_GET:
		var fast: float = inverse_lerp(Tuning.CO2_SLOW_RISE_END_GET, Tuning.CO2_FAST_RISE_END_GET, at_get)
		return lerpf(Tuning.CO2_SLOW_RISE_END_MMHG, Tuning.CO2_FAST_RISE_END_MMHG, fast)
	var curve: Dictionary = Tuning.CO2_CURVE_BY_ADAPTER[flags.adapter]
	var peak_get: float = curve["peak_get"]
	var peak_mmhg: float = curve["peak_mmhg"]
	if at_get <= peak_get:
		var rise: float = inverse_lerp(Tuning.CO2_FAST_RISE_END_GET, peak_get, at_get)
		return lerpf(Tuning.CO2_FAST_RISE_END_MMHG, peak_mmhg, rise)
	var settle_mmhg: float = curve["settle_mmhg"]
	return settle_mmhg + (peak_mmhg - settle_mmhg) * exp(-(at_get - peak_get) / Tuning.CO2_FALL_TAU_H)


## Bpm from the explosion (fading), engine burns and reentry.
static func stress_at(flags: SimState.Flags, at_get: float, splashdown_get: float) -> float:
	var bpm: float = 0.0
	var since_explosion_h: float = at_get - Tuning.EXPLOSION_GET
	if since_explosion_h >= 0.0:
		bpm += Tuning.EXPLOSION_STRESS_BPM * maxf(1.0 - since_explosion_h / Tuning.EXPLOSION_STRESS_FADE_H, 0.0)
	for burn: Dictionary in Tuning.BURNS:
		var start_get: float = burn["get"]
		if at_get >= start_get and at_get < start_get + float(burn["duration_h"]):
			bpm += Tuning.BURN_STRESS_BPM
	if at_get >= splashdown_get - Tuning.REENTRY_BEFORE_SPLASHDOWN_H:
		bpm += Tuning.REENTRY_STRESS_BPM
		if flags.heat_shield_risk:
			bpm += Tuning.HEAT_SHIELD_EXTRA_STRESS_BPM
	return bpm


# --- Crew ---

static func fatigue_rate_per_h(flags: SimState.Flags, cabin_temp_c: float) -> float:
	var rate: float = Tuning.FATIGUE_PER_H
	if cabin_temp_c < Tuning.FATIGUE_COLD_BELOW_CABIN_C:
		rate += Tuning.FATIGUE_COLD_EXTRA_PER_H
	if flags.heating == "one":
		rate *= Tuning.FATIGUE_HEATER_RATE_MULT
	return rate


static func body_temp_at(crew_id: String, fever: bool, at_get: float, cabin_temp_c: float) -> float:
	if fever and crew_id == Tuning.FEVER_CREW_ID and at_get >= Tuning.FEVER_CHECK_GET:
		var ramp: float = clampf(inverse_lerp(Tuning.FEVER_CHECK_GET, Tuning.FEVER_PEAK_GET, at_get), 0.0, 1.0)
		return lerpf(Tuning.FEVER_START_C, Tuning.FEVER_PEAK_C, ramp)
	if cabin_temp_c < Tuning.BODY_COLD_BELOW_CABIN_C:
		return Tuning.BODY_TEMP_COLD_C
	return Tuning.BODY_TEMP_C


## noise is in [-1, 1].
static func heart_rate(crew_id: String, cabin_temp_c: float, co2_mmhg: float, body_temp_c: float,
		fatigue: float, stress_bpm: float, noise: float) -> float:
	var hr: float = Tuning.BASE_HR_BPM_BY_CREW[crew_id]
	hr += Tuning.HR_PER_COLD_C * maxf(Tuning.HR_COLD_BELOW_C - cabin_temp_c, 0.0)
	hr += Tuning.HR_PER_CO2_MMHG * maxf(co2_mmhg - Tuning.HR_CO2_ABOVE_MMHG, 0.0)
	hr += Tuning.HR_PER_FEVER_C * maxf(body_temp_c - Tuning.HR_FEVER_ABOVE_C, 0.0)
	hr += Tuning.HR_PER_FATIGUE * fatigue + stress_bpm + Tuning.HR_NOISE_BPM * noise
	return clampf(hr, Tuning.HR_MIN_BPM, Tuning.HR_MAX_BPM)


## noise is in [-1, 1].
static func breathing_rate(co2_mmhg: float, body_temp_c: float, noise: float) -> float:
	var rr: float = Tuning.RR_BASE_PER_MIN
	rr += Tuning.RR_PER_CO2_MMHG * maxf(co2_mmhg - Tuning.RR_CO2_ABOVE_MMHG, 0.0)
	rr += Tuning.RR_PER_FEVER_C * maxf(body_temp_c - Tuning.RR_FEVER_ABOVE_C, 0.0)
	return rr + Tuning.RR_NOISE_PER_MIN * noise


## noise is in [-1, 1]. Always 95-99: the danger on Apollo 13 was CO2, not oxygen.
static func spo2(noise: float) -> float:
	return clampf(Tuning.SPO2_BASE_PCT + Tuning.SPO2_NOISE_PCT * noise, Tuning.SPO2_MIN_PCT, Tuning.SPO2_MAX_PCT)


# --- Internals ---

static func _update(state: SimState, from_get: float, rng: RandomNumberGenerator) -> void:
	var at_get: float = state.time.current_get
	var dt_h: float = at_get - from_get
	var env: SimState.Env = state.env
	var flags: SimState.Flags = state.flags

	env.cabin_temp_c = _held(state, SimState.env_path("cabin_temp_c"),
		cabin_temp_at(flags, at_get, state.time.splashdown_get))
	env.co2_mmhg = _held(state, SimState.env_path("co2_mmhg"), co2_at(flags, at_get))
	var pressure_noise: float = _noise(state, rng, "pressure")
	env.pressure_psi = _held(state, SimState.env_path("pressure_psi"),
		Tuning.PRESSURE_PSI + Tuning.PRESSURE_NOISE_PSI * pressure_noise)
	env.water_pct = _held(state, SimState.env_path("water_pct"),
		_toward_end(env.water_pct, Tuning.WATER_END_PCT_BY_RATION[flags.ration], from_get, at_get))
	env.power_margin = _held(state, SimState.env_path("power_margin"),
		maxf(env.power_margin, Tuning.POWER_MARGIN_MIN))
	state.stress = _held(state, SimState.STRESS_PATH, stress_at(flags, at_get, state.time.splashdown_get))

	var hydration_end: float = Tuning.HYDRATION_END_BY_RATION[flags.ration]
	for crew_id in SimState.CREW_IDS:
		var member: SimState.CrewMember = state.crew[crew_id]
		var fatigue: float = member.fatigue + fatigue_rate_per_h(flags, env.cabin_temp_c) * dt_h
		member.fatigue = _held(state, SimState.crew_path(crew_id, "fatigue"), clampf(fatigue, 0.0, 1.0))
		var hydration_before: float = member.hydration
		member.hydration = _held(state, SimState.crew_path(crew_id, "hydration"),
			_toward_end(member.hydration, hydration_end, from_get, at_get))
		if crew_id == Tuning.FEVER_CREW_ID and from_get < Tuning.FEVER_CHECK_GET and at_get >= Tuning.FEVER_CHECK_GET:
			var at_check: float = lerpf(hydration_before, member.hydration, (Tuning.FEVER_CHECK_GET - from_get) / dt_h)
			state.fever = at_check < Tuning.FEVER_HYDRATION_BELOW
		member.body_temp_c = _held(state, SimState.crew_path(crew_id, "body_temp_c"),
			body_temp_at(crew_id, state.fever, at_get, env.cabin_temp_c))
		var hr_noise: float = _noise(state, rng, crew_id + ".hr")
		member.hr = _held(state, SimState.crew_path(crew_id, "hr"), heart_rate(crew_id, env.cabin_temp_c,
			env.co2_mmhg, member.body_temp_c, member.fatigue, state.stress, hr_noise))
		var rr_noise: float = _noise(state, rng, crew_id + ".rr")
		member.rr = _held(state, SimState.crew_path(crew_id, "rr"),
			breathing_rate(env.co2_mmhg, member.body_temp_c, rr_noise))
		var spo2_noise: float = _noise(state, rng, crew_id + ".spo2")
		member.spo2 = clampf(_held(state, SimState.crew_path(crew_id, "spo2"), spo2(spo2_noise)),
			Tuning.SPO2_MIN_PCT, Tuning.SPO2_MAX_PCT)


## A debug hold replaces the model's value while it's set.
static func _held(state: SimState, path: String, value: float) -> float:
	return state.overrides.get(path, value)


## Moves value in a straight line so it reaches end_value at the standard splashdown.
## Nothing is used up before the explosion.
static func _toward_end(value: float, end_value: float, from_get: float, to_get: float) -> float:
	var start_get: float = maxf(from_get, Tuning.EXPLOSION_GET)
	if to_get <= start_get:
		return value
	var remaining_h: float = Tuning.STANDARD_SPLASHDOWN_GET - start_get
	if remaining_h <= 0.0:
		return end_value
	return lerpf(value, end_value, minf((to_get - start_get) / remaining_h, 1.0))


## Smooth drift in [-1, 1]: each channel eases between random targets over a random number of
## ticks, so displayed vitals wander slowly instead of jittering every frame.
static func _noise(state: SimState, rng: RandomNumberGenerator, channel: String) -> float:
	var drift: PackedFloat64Array = state.noise.get(channel, PackedFloat64Array())
	if drift.size() != _DRIFT_SIZE:
		drift = PackedFloat64Array([rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), 0.0, _segment_ticks(rng)])
	drift[_DRIFT_TICK] += 1.0
	if drift[_DRIFT_TICK] >= drift[_DRIFT_LENGTH]:
		drift[_DRIFT_FROM] = drift[_DRIFT_TO]
		drift[_DRIFT_TO] = rng.randf_range(-1.0, 1.0)
		drift[_DRIFT_TICK] = 0.0
		drift[_DRIFT_LENGTH] = _segment_ticks(rng)
	state.noise[channel] = drift
	return lerpf(drift[_DRIFT_FROM], drift[_DRIFT_TO], smoothstep(0.0, 1.0, drift[_DRIFT_TICK] / drift[_DRIFT_LENGTH]))


static func _segment_ticks(rng: RandomNumberGenerator) -> float:
	return float(rng.randi_range(Tuning.NOISE_SEGMENT_TICKS_MIN, Tuning.NOISE_SEGMENT_TICKS_MAX))

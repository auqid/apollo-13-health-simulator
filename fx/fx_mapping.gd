extends RefCounted
## Pure mappings from simulation values to effect strengths (SPEC.md section 4). No nodes, so the
## tests can check them.

const Tuning := preload("res://sim/tuning.gd")


## Cabin light level: 0.35 + 0.65 x (power margin / 100), where 100 is the historical margin.
static func light_level(power_margin: float) -> float:
	return Tuning.LIGHT_LEVEL_FLOOR + Tuning.LIGHT_LEVEL_SPAN * power_margin / Tuning.POWER_MARGIN_START


## CO2 vignette opacity: clamp((co2 - 5) / 10, 0, 0.7).
static func vignette(co2_mmhg: float) -> float:
	return clampf((co2_mmhg - Tuning.FX_VIGNETTE_CO2_START) / Tuning.FX_VIGNETTE_CO2_SPAN, 0.0, Tuning.FX_VIGNETTE_MAX)


## Blur on the 3D view in 1080p pixels: clamp((co2 - 8) x 0.4, 0, 3).
static func blur_px(co2_mmhg: float) -> float:
	return clampf((co2_mmhg - Tuning.FX_BLUR_CO2_START) * Tuning.FX_BLUR_PX_PER_MMHG, 0.0, Tuning.FX_BLUR_MAX_PX)


## HUD drift in pixels: none up to 10 mmHg, 2 px at 15 mmHg.
static func wobble_px(co2_mmhg: float) -> float:
	return Tuning.FX_WOBBLE_MAX_PX * clampf((co2_mmhg - Tuning.FX_WOBBLE_CO2_START) / Tuning.FX_WOBBLE_CO2_SPAN, 0.0, 1.0)


## Shivering amplitude in radians: clamp((10 - T) / 7, 0, 1) x 0.015.
static func shake_rad(cabin_temp_c: float) -> float:
	return clampf((Tuning.FX_SHAKE_BELOW_C - cabin_temp_c) / Tuning.FX_SHAKE_SPAN_C, 0.0, 1.0) * Tuning.FX_SHAKE_MAX_RAD


## Breath fog density: none from 12 °C up, full at 3 °C.
static func fog(cabin_temp_c: float) -> float:
	return clampf(inverse_lerp(Tuning.FX_FOG_BELOW_C, Tuning.FX_FOG_FULL_C, cabin_temp_c), 0.0, 1.0)


## Cold tint strength, growing as the cabin cools from 18 °C to 3 °C.
static func tint(cabin_temp_c: float) -> float:
	return Tuning.FX_TINT_MAX * clampf(inverse_lerp(Tuning.FX_TINT_BELOW_C, Tuning.FX_TINT_FULL_C, cabin_temp_c), 0.0, 1.0)


## Condensation overlay: on below 8 °C after GET 120, or once E5 is reached with Odyssey powered up
## late (E5-A). Powering up early (E5-B) leaves less.
static func condensation(cabin_temp_c: float, at_get: float, power_up: String, e5_reached: bool) -> float:
	if e5_reached:
		return 1.0 if power_up == "late" else Tuning.FX_CONDENSATION_EARLY_POWER_UP
	if cabin_temp_c < Tuning.FX_CONDENSATION_BELOW_C and at_get >= Tuning.FX_CONDENSATION_AFTER_GET:
		return 1.0
	return 0.0


## How dark a micro-blink gets: no blinks at or below 0.6 fatigue, deeper as fatigue rises.
static func blink_depth(fatigue: float) -> float:
	if fatigue <= Tuning.FX_BLINK_FATIGUE_ABOVE:
		return 0.0
	var tiredness: float = clampf(inverse_lerp(Tuning.FX_BLINK_FATIGUE_ABOVE, 1.0, fatigue), 0.0, 1.0)
	return lerpf(Tuning.FX_BLINK_DEPTH_MIN, Tuning.FX_BLINK_DEPTH_MAX, tiredness)


## Blink shape over its 250 ms: eases to dark by the middle and back to clear by the end.
static func blink_profile(t_s: float) -> float:
	var half: float = Tuning.FX_BLINK_S * 0.5
	if t_s <= 0.0 or t_s >= Tuning.FX_BLINK_S:
		return 0.0
	if t_s < half:
		return smoothstep(0.0, half, t_s)
	return 1.0 - smoothstep(half, Tuning.FX_BLINK_S, t_s)


## Share of the cabin light lost t_s seconds after the explosion: a fast drop, a hold, a slow recovery.
static func explosion_dim(t_s: float) -> float:
	var drop: float = Tuning.FX_EXPLOSION_DIM_DROP_S
	var hold_end: float = drop + Tuning.FX_EXPLOSION_DIM_HOLD_S
	var recover_end: float = hold_end + Tuning.FX_EXPLOSION_DIM_RECOVER_S
	if t_s < 0.0 or t_s >= recover_end:
		return 0.0
	if t_s < drop:
		return Tuning.FX_EXPLOSION_DIM_DEPTH * t_s / drop
	if t_s < hold_end:
		return Tuning.FX_EXPLOSION_DIM_DEPTH
	return Tuning.FX_EXPLOSION_DIM_DEPTH * (1.0 - smoothstep(hold_end, recover_end, t_s))

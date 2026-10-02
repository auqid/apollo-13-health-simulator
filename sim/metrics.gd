extends RefCounted
## Running minimums, maximums and totals for the scorecard. Call observe() after every step.

const SimState := preload("res://sim/sim_state.gd")
const Tuning := preload("res://sim/tuning.gd")

var coldest_cabin_c: float = INF
var peak_co2_mmhg: float = -INF
var peak_hr_bpm: Dictionary[String, float] = {}
var peak_body_temp_c: Dictionary[String, float] = {}
## GET when Haise's temperature first reached the fever caption threshold, or -1 if it never did.
var fever_caption_get: float = -1.0


func observe(state: SimState) -> void:
	coldest_cabin_c = minf(coldest_cabin_c, state.env.cabin_temp_c)
	peak_co2_mmhg = maxf(peak_co2_mmhg, state.env.co2_mmhg)
	for crew_id in SimState.CREW_IDS:
		var member: SimState.CrewMember = state.crew[crew_id]
		peak_hr_bpm[crew_id] = maxf(peak_hr_bpm.get(crew_id, -INF), member.hr)
		peak_body_temp_c[crew_id] = maxf(peak_body_temp_c.get(crew_id, -INF), member.body_temp_c)
	if fever_caption_get < 0.0 and state.crew[Tuning.FEVER_CREW_ID].body_temp_c >= Tuning.FEVER_CAPTION_C:
		fever_caption_get = state.time.current_get


## The "You" column of the scorecard, keyed like the rows in events.json and sim/history.gd.
func scorecard(state: SimState) -> Dictionary:
	var ration: String = state.flags.ration
	var duration_h: float = state.time.splashdown_get - Tuning.EXPLOSION_GET
	return {
		"duration_h": duration_h,
		"coldest_cabin_c": coldest_cabin_c,
		"peak_co2_mmhg": peak_co2_mmhg,
		"drink_l_per_day": Tuning.DRINK_L_PER_DAY_BY_RATION[ration],
		"water_left_pct": state.env.water_pct,
		"weight_loss_kg": Tuning.WEIGHT_LOSS_KG_PER_H_BY_RATION[ration] * duration_h,
		"haise_infection": state.fever,
		"power_margin": state.env.power_margin,
		"heat_shield_exposed": state.flags.heat_shield_risk,
	}

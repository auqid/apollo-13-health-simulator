extends RefCounted
## 1970 benchmarks for the scorecard (SPEC.md section 6), keyed like the scorecard rows in
## data/events.json. "better" says which direction beats what actually happened.
## Sources:
## - Lovell's account, Apollo Expeditions to the Moon (SP-350), ch. 13: https://history.nasa.gov/SP-350/ch-13-3.html
## - Apollo 13 Flight Journal: https://www.apollojournals.org/afj/ap13fj/
## - Biomedical Results of Apollo (SP-368), for the 7.6 torr CO2 limit

const BENCHMARKS: Dictionary = {
	"duration_h": {"value": 87.0, "better": "lower"},
	"coldest_cabin_c": {"value": 3.0, "better": "higher"},
	"peak_co2_mmhg": {"value": 15.0, "better": "lower"},
	"drink_l_per_day": {"value": 0.18, "better": "higher"},
	"water_left_pct": {"value": 9.0, "better": "higher"},
	"weight_loss_kg": {"value": 14.3, "better": "lower"},
	"haise_infection": {"value": true, "better": "lower"},
	"power_margin": {"value": 100.0, "better": "higher"},
	"heat_shield_exposed": {"value": false, "better": "lower"},
}

const CO2_SAFE_LIMIT_MMHG: float = 7.6

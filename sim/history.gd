extends RefCounted
## 1970 benchmarks for the scorecard (SPEC.md section 6), keyed like the scorecard rows in
## data/events.json. "better" says which direction beats what actually happened.
## Sources:
## - Lovell's account, Apollo Expeditions to the Moon (SP-350), ch. 13: https://history.nasa.gov/SP-350/ch-13-3.html
## - Apollo 13 Flight Journal: https://www.apollojournals.org/afj/ap13fj/
## - Biomedical Results of Apollo (SP-368), for the 7.6 torr CO2 limit

## same_within keeps a near miss on an "about" benchmark from reading as better or worse.
const BENCHMARKS: Dictionary = {
	"duration_h": {"value": 87.0, "better": "lower", "same_within": 0.05},
	"coldest_cabin_c": {"value": 3.0, "better": "higher", "same_within": 0.5},
	"peak_co2_mmhg": {"value": 15.0, "better": "lower", "same_within": 0.25},
	"drink_l_per_day": {"value": 0.18, "better": "higher", "same_within": 0.001},
	"water_left_pct": {"value": 9.0, "better": "higher", "same_within": 0.15},
	"weight_loss_kg": {"value": 14.3, "better": "lower", "same_within": 0.15},
	"haise_infection": {"value": true, "better": "lower"},
	"power_margin": {"value": 100.0, "better": "higher", "same_within": 0.5},
	"heat_shield_exposed": {"value": false, "better": "lower"},
}

const CO2_SAFE_LIMIT_MMHG: float = 7.6


## "better", "worse" or "same". For a yes/no row, "lower" means no is the better outcome.
static func verdict(you_value: Variant, key: String) -> String:
	var bench: Dictionary = BENCHMARKS[key]
	var history_value: Variant = bench["value"]
	var higher_is_better: bool = bench["better"] == "higher"
	if history_value is bool:
		if bool(you_value) == history_value:
			return "same"
		var you_yes: bool = bool(you_value)
		if you_yes == higher_is_better:
			return "better"
		return "worse"
	var delta: float = float(you_value) - float(history_value)
	if absf(delta) <= float(bench.get("same_within", 0.0)):
		return "same"
	var you_is_higher: bool = delta > 0.0
	if you_is_higher == higher_is_better:
		return "better"
	return "worse"


## Short text for the You column. The 1970 column keeps the wording in events.json.
static func format_you(key: String, you_value: Variant) -> String:
	match key:
		"duration_h":
			return _hours(float(you_value))
		"coldest_cabin_c":
			return "%.1f °C" % float(you_value)
		"peak_co2_mmhg":
			return "%.0f mmHg" % float(you_value)
		"drink_l_per_day":
			return "%.2f L" % float(you_value)
		"water_left_pct":
			return "%d%%" % roundi(float(you_value))
		"weight_loss_kg":
			return "%.1f kg" % float(you_value)
		"haise_infection", "heat_shield_exposed":
			return "Yes" if bool(you_value) else "No"
		"power_margin":
			return "%d" % roundi(float(you_value))
	return str(you_value)


static func _hours(hours: float) -> String:
	if absf(hours - roundf(hours)) < 0.05:
		return "%d h" % roundi(hours)
	return "%.1f h" % hours

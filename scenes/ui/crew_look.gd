extends RefCounted
## How each crew member looks and feels on screen, worked out from the simulation: the short status
## under their name, and how strongly their photo shows cold, fever and tiredness.
## Pure, so the tests can check it.

const SimState := preload("res://sim/sim_state.gd")
const Tuning := preload("res://sim/tuning.gd")
const FxMapping := preload("res://fx/fx_mapping.gd")


## Up to CREW_STATUS_WORDS plain words on how they are, most serious first: "Fever, shivering".
## The numbers are in the vitals columns beside it, so the words stay short.
static func status(member: SimState.CrewMember, env: SimState.Env) -> String:
	var words: PackedStringArray = []
	if member.body_temp_c >= Tuning.FEVER_CAPTION_C:
		words.append("fever")
	if env.co2_mmhg > Tuning.CO2_ALARM_MMHG:
		words.append("breathing hard")
	if env.cabin_temp_c < Tuning.FX_SHAKE_BELOW_C:
		words.append("shivering")
	elif env.cabin_temp_c < Tuning.CREW_COLD_BELOW_C:
		words.append("cold")
	if member.fatigue >= Tuning.CREW_EXHAUSTED_FATIGUE:
		words.append("exhausted")
	elif member.fatigue >= Tuning.CREW_TIRED_FATIGUE:
		words.append("tired")
	if member.hydration < Tuning.CREW_THIRSTY_HYDRATION:
		words.append("thirsty")
	if words.is_empty():
		words.append("heart racing" if member.hr >= Tuning.CREW_HEART_RACING_BPM else "steady")
	var line: String = ", ".join(words.slice(0, Tuning.CREW_STATUS_WORDS))
	return line.left(1).to_upper() + line.substr(1)


## Whether the status is something to worry about, so it can be shown in the caution colour.
static func is_warning(member: SimState.CrewMember, env: SimState.Env) -> bool:
	return member.body_temp_c >= Tuning.FEVER_CAPTION_C or env.co2_mmhg > Tuning.CO2_ALARM_MMHG


## 0 to 1: how cold the photo looks, following the cabin's cold tint.
static func cold(env: SimState.Env) -> float:
	return clampf(FxMapping.tint(env.cabin_temp_c) / Tuning.FX_TINT_MAX, 0.0, 1.0)


## 0 to 1: the fever flush, from a slight rise to the peak of Haise's fever.
static func flush(member: SimState.CrewMember) -> float:
	return clampf(inverse_lerp(Tuning.CREW_FLUSH_FROM_C, Tuning.FEVER_PEAK_C, member.body_temp_c), 0.0, 1.0)


## 0 to 1: how worn out the photo looks.
static func tired(member: SimState.CrewMember) -> float:
	return clampf(inverse_lerp(Tuning.CREW_TIRED_FROM, 1.0, member.fatigue), 0.0, 1.0)

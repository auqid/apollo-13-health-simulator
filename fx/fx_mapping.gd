extends RefCounted
## Pure mappings from simulation values to effect strengths (SPEC.md section 4). No nodes, so the
## tests can check them.

const Tuning := preload("res://sim/tuning.gd")


## Cabin light level: 0.35 + 0.65 x (power margin / 100), where 100 is the historical margin.
static func light_level(power_margin: float) -> float:
	return Tuning.LIGHT_LEVEL_FLOOR + Tuning.LIGHT_LEVEL_SPAN * power_margin / Tuning.POWER_MARGIN_START

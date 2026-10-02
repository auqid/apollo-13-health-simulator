extends Node
## Maps the simulation state to what the audience sees (SPEC.md section 4). So far: the cabin
## light level from the power margin.

const SimState := preload("res://sim/sim_state.gd")
const FxMapping := preload("res://fx/fx_mapping.gd")
const Cabin := preload("res://scenes/cabin/cabin.gd")

var cabin: Cabin


func _ready() -> void:
	Game.state_changed.connect(_on_state_changed)
	_on_state_changed(Game.state)


func _on_state_changed(state: SimState) -> void:
	if cabin == null:
		return
	var level: float = FxMapping.light_level(state.env.power_margin)
	if not is_equal_approx(level, cabin.light_level):
		cabin.set_light_level(level)

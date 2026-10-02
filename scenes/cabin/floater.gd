extends Node3D
## A loose object in zero g: drifts on slow sine waves around where it was placed and tumbles
## slowly about a fixed axis. Seeded, so every run moves the same way.

const Tuning := preload("res://sim/tuning.gd")

var _home := Vector3.ZERO
var _amplitude := Vector3.ZERO
var _periods_s := Vector3.ONE
var _phases := Vector3.ZERO
var _spin_axis := Vector3.UP
var _spin_rad_per_s: float = 0.0
var _time_s: float = 0.0


func setup(rng: RandomNumberGenerator) -> void:
	_home = position
	for i in 3:
		_amplitude[i] = rng.randf_range(Tuning.FLOAT_DRIFT_M_MIN, Tuning.FLOAT_DRIFT_M_MAX)
		_periods_s[i] = rng.randf_range(Tuning.FLOAT_DRIFT_PERIOD_S_MIN, Tuning.FLOAT_DRIFT_PERIOD_S_MAX)
		_phases[i] = rng.randf_range(0.0, TAU)
	_spin_axis = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
	_spin_rad_per_s = deg_to_rad(rng.randf_range(Tuning.FLOAT_SPIN_DEG_PER_S_MIN, Tuning.FLOAT_SPIN_DEG_PER_S_MAX))


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time_s += delta
	var offset := Vector3.ZERO
	for i in 3:
		offset[i] = _amplitude[i] * sin(TAU * _time_s / _periods_s[i] + _phases[i])
	position = _home + offset
	rotate(_spin_axis, _spin_rad_per_s * delta)

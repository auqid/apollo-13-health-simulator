extends Camera3D
## First-person cabin camera: eases between named presets and adds a gentle zero-g drift.
## The effects add shivering on top through shake_rotation.

const Tuning := preload("res://sim/tuning.gd")

## Extra rotation in radians (pitch, yaw, roll), set by the effects every frame.
var shake_rotation := Vector3.ZERO
## How far the camera has eased forward from its preset, for a slow push-in during cutscenes.
var dolly_m: float = 0.0
var preset: String = ""
## Preset name -> Transform3D
var _presets: Dictionary = {}
var _from := Transform3D.IDENTITY
var _to := Transform3D.IDENTITY
var _blend: float = 1.0
var _time_s: float = 0.0


func setup(presets: Dictionary, start: String) -> void:
	_presets = presets
	go_to(start, true)


func preset_names() -> PackedStringArray:
	return PackedStringArray(_presets.keys())


## Moves to a preset over Tuning.CAMERA_MOVE_S, or at once.
func go_to(preset_name: String, instant: bool = false) -> void:
	if not _presets.has(preset_name):
		push_warning("No camera preset '%s'" % preset_name)
		return
	preset = preset_name
	_from = _base()
	_to = _presets[preset_name]
	_blend = 0.0
	if instant:
		_from = _to
		_blend = 1.0
	_apply()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time_s += delta
	_blend = minf(_blend + delta / Tuning.CAMERA_MOVE_S, 1.0)
	_apply()


func _base() -> Transform3D:
	return _from.interpolate_with(_to, smoothstep(0.0, 1.0, _blend))


func _apply() -> void:
	var drift_position := Vector3(_wave(0), _wave(1), _wave(2)) * Tuning.CAMERA_DRIFT_M
	var drift_rotation := Vector3(_wave(3), _wave(4), _wave(5)) * deg_to_rad(Tuning.CAMERA_DRIFT_DEG)
	var push := Vector3(0.0, 0.0, -dolly_m)
	transform = _base() * Transform3D(Basis.from_euler(drift_rotation + shake_rotation), drift_position + push)


## One slow sine per drift channel, each with its own period and phase.
func _wave(channel: int) -> float:
	var period_s: float = Tuning.CAMERA_DRIFT_PERIODS_S[channel]
	return sin(TAU * _time_s / period_s + channel)

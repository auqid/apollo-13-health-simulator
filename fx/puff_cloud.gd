extends Node3D
## A cloud of soft sprites for gas, steam, plasma and spray, driven by one number, t, that runs
## from 0 to 1 across a shot. The same t always draws the same frame, so rehearsals match and a
## shot can be scrubbed. Each puff is born at its own moment, flies out along its own direction,
## slows as it spreads, grows and fades. Set the fields, call build(), then set_time() each frame.

const PUFF_SHADER := "res://fx/soft_puff.gdshader"
const GLOW_SHADER := "res://fx/soft_glow.gdshader"

var count: int = 24
var seed_value: int = 1
## Where puffs start, in this node's space, and how far from it they may start along each axis.
var origin := Vector3.ZERO
var origin_jitter := Vector3.ZERO
## Main direction of travel, and how far from it a puff may stray (180 is every direction).
var axis := Vector3.UP
var spread_deg: float = 30.0
## Distance travelled per unit of t, before drag, as a range.
var speed := Vector2(2.0, 4.0)
## How quickly puffs slow down. 0 keeps a constant speed.
var drag: float = 3.0
## Added to every puff's position per unit of t after birth, such as a wake trailing behind.
var drift := Vector3.ZERO
## When puffs are born and how long each lives, both in t.
var birth := Vector2(0.0, 0.5)
var life := Vector2(0.3, 0.6)
## Size in metres at birth and at the end of life.
var size := Vector2(0.4, 2.0)
var color := Color.WHITE
var opacity: float = 0.4
## Glowing clouds add light to what is behind them; others blend over it.
var glow: bool = false
var wisp: float = 0.35

var _puffs: Array[MeshInstance3D] = []
var _dir: PackedVector3Array = []
var _start: PackedVector3Array = []
var _speed: PackedFloat32Array = []
var _birth: PackedFloat32Array = []
var _life: PackedFloat32Array = []
var _grow: PackedFloat32Array = []


func build() -> void:
	if not _puffs.is_empty():
		return
	var material := ShaderMaterial.new()
	var shader_path: String = GLOW_SHADER if glow else PUFF_SHADER
	if ResourceLoader.exists(shader_path):
		material.shader = load(shader_path)
	material.set_shader_parameter("wisp", wisp)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		var puff := MeshInstance3D.new()
		puff.mesh = quad
		puff.material_override = material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.visible = false
		puff.set_instance_shader_parameter("puff_seed", rng.randf())
		add_child(puff)
		_puffs.append(puff)
		_dir.append(_random_direction(rng))
		_start.append(origin + _random_offset(rng) * origin_jitter)
		_speed.append(rng.randf_range(speed.x, speed.y))
		var slot: float = (float(i) + rng.randf()) / float(maxi(count, 1))
		_birth.append(lerpf(birth.x, birth.y, slot))
		_life.append(rng.randf_range(life.x, life.y))
		_grow.append(rng.randf_range(0.7, 1.3))


## strength scales every puff's opacity, so a whole cloud can fade.
func set_time(t: float, strength: float = 1.0) -> void:
	for i in _puffs.size():
		var puff: MeshInstance3D = _puffs[i]
		var since: float = t - _birth[i]
		var age: float = since / maxf(_life[i], 0.001)
		if age <= 0.0 or age >= 1.0 or strength <= 0.001:
			puff.visible = false
			continue
		var reach: float = _speed[i] * since
		if drag > 0.0:
			reach = _speed[i] * (1.0 - exp(-drag * since)) / drag
		puff.position = _start[i] + _dir[i] * reach + drift * since
		var grown: float = lerpf(size.x, size.y, 1.0 - pow(1.0 - age, 2.0)) * _grow[i]
		puff.scale = Vector3.ONE * grown
		var fade: float = smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.4, 1.0, age))
		var tint: Color = color
		tint.a = opacity * fade * strength
		puff.set_instance_shader_parameter("puff_color", tint)
		puff.visible = true


func hide_all() -> void:
	for puff: MeshInstance3D in _puffs:
		puff.visible = false


func _random_direction(rng: RandomNumberGenerator) -> Vector3:
	var main: Vector3 = axis.normalized() if axis.length_squared() > 0.0001 else Vector3.UP
	var up: Vector3 = Vector3.UP if absf(main.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var frame := Basis.looking_at(main, up)
	var z: float = rng.randf_range(cos(deg_to_rad(clampf(spread_deg, 0.0, 180.0))), 1.0)
	var around: float = rng.randf_range(0.0, TAU)
	var ring: float = sqrt(maxf(1.0 - z * z, 0.0))
	return frame * Vector3(ring * cos(around), ring * sin(around), -z)


func _random_offset(rng: RandomNumberGenerator) -> Vector3:
	return Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))

extends RefCounted
## Schematic free-return path for the mission map. Not an ephemeris: Earth, the lunar
## far side at GET 77:08, then home. The outbound leg is the same on every return speed.
## After the far side, a faster splashdown simply shortens the trip back.

const EARTH := Vector2(-10.0, 0.0)
const MOON := Vector2(8.0, 1.0)
const FAR_SIDE := Vector2(12.6, 2.2)
## Loss of signal behind the Moon, about 77:08.
const FAR_SIDE_GET := 77.133333

static var _outbound: PackedVector2Array = PackedVector2Array([
	EARTH,
	Vector2(-2.0, 0.35),
	Vector2(5.5, 0.7),
	Vector2(9.2, 1.5),
	FAR_SIDE,
])
static var _return: PackedVector2Array = PackedVector2Array([
	FAR_SIDE,
	Vector2(10.5, -1.6),
	Vector2(5.0, -1.1),
	Vector2(-2.0, -0.35),
	EARTH,
])


## Points added between each pair of control points, so the loop draws as a smooth curve.
const SMOOTH_STEPS := 12

## The two legs as smooth curves through the control points, built once.
static var _smooth_out := PackedVector2Array()
static var _smooth_return := PackedVector2Array()


static func position(get_h: float, splashdown_h: float) -> Vector2:
	_build_legs()
	if get_h <= FAR_SIDE_GET:
		return _along(_smooth_out, clampf(get_h / FAR_SIDE_GET, 0.0, 1.0))
	var span: float = maxf(splashdown_h - FAR_SIDE_GET, 0.1)
	return _along(_smooth_return, clampf((get_h - FAR_SIDE_GET) / span, 0.0, 1.0))


## Points of the whole loop, for drawing. The return leg is sampled at the given splashdown.
static func polyline(splashdown_h: float, steps: int = 48) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in steps + 1:
		var get_h: float = splashdown_h * float(i) / float(steps)
		points.append(position(get_h, splashdown_h))
	return points


## One curve through both legs, so the turn behind the Moon is rounded, then split at the far side.
static func _build_legs() -> void:
	if not _smooth_out.is_empty():
		return
	var loop := PackedVector2Array(_outbound)
	loop.append_array(_return.slice(1))
	var curve := PackedVector2Array()
	for i in loop.size() - 1:
		var before: Vector2 = loop[maxi(i - 1, 0)]
		var after: Vector2 = loop[mini(i + 2, loop.size() - 1)]
		for step in SMOOTH_STEPS:
			curve.append(loop[i].cubic_interpolate(loop[i + 1], before, after, float(step) / SMOOTH_STEPS))
	curve.append(loop[loop.size() - 1])
	var far_side: int = (_outbound.size() - 1) * SMOOTH_STEPS
	_smooth_out = curve.slice(0, far_side + 1)
	_smooth_return = curve.slice(far_side)


static func _along(points: PackedVector2Array, u: float) -> Vector2:
	if points.size() == 1:
		return points[0]
	var lengths: Array[float] = []
	var total: float = 0.0
	for i in points.size() - 1:
		var length: float = points[i].distance_to(points[i + 1])
		lengths.append(length)
		total += length
	var target: float = clampf(u, 0.0, 1.0) * total
	var walked: float = 0.0
	for i in lengths.size():
		var length: float = lengths[i]
		if walked + length >= target or i == lengths.size() - 1:
			var t: float = 0.0 if length <= 0.001 else clampf((target - walked) / length, 0.0, 1.0)
			return points[i].lerp(points[i + 1], t)
		walked += length
	return points[points.size() - 1]

extends RefCounted
## Low-poly mesh builders for the cabin: extruded convex outlines and a bent tube. Faces are wound
## to match the normal they're given, so callers don't have to think about winding.


## Extrudes a convex polygon in the XY plane (either winding) from z = 0 back to z = -depth.
static func prism(polygon: PackedVector2Array, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = polygon.size()
	var front: PackedVector3Array = []
	var back: PackedVector3Array = []
	var center := Vector3.ZERO
	for point in polygon:
		front.append(Vector3(point.x, point.y, 0.0))
		back.append(Vector3(point.x, point.y, -depth))
		center += Vector3(point.x, point.y, -depth * 0.5)
	center /= count
	for i in range(1, count - 1):
		_triangle(st, front[0], front[i], front[i + 1], Vector3.BACK)
		_triangle(st, back[0], back[i], back[i + 1], Vector3.FORWARD)
	for i in count:
		var j: int = (i + 1) % count
		var edge: Vector3 = front[j] - front[i]
		var normal := Vector3(edge.y, -edge.x, 0.0).normalized()
		var middle: Vector3 = (front[i] + front[j] + back[i] + back[j]) * 0.25
		if normal.dot(middle - center) < 0.0:
			normal = -normal
		_triangle(st, front[i], front[j], back[j], normal)
		_triangle(st, front[i], back[j], back[i], normal)
	return st.commit()


## A smooth tube of the given radius along a quadratic Bezier curve from p0 to p2 (control p1).
static func tube(p0: Vector3, p1: Vector3, p2: Vector3, radius: float, segments: int, sides: int) -> ArrayMesh:
	var rings: Array[PackedVector3Array] = []
	var ring_normals: Array[PackedVector3Array] = []
	for s in segments + 1:
		var t: float = float(s) / segments
		var center: Vector3 = p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
		var tangent: Vector3 = ((p1 - p0) * (1.0 - t) + (p2 - p1) * t).normalized()
		var across: Vector3 = tangent.cross(Vector3.UP)
		if across.length() < 0.01:
			across = tangent.cross(Vector3.RIGHT)
		across = across.normalized()
		var around: Vector3 = across.cross(tangent).normalized()
		var ring: PackedVector3Array = []
		var normals: PackedVector3Array = []
		for k in sides:
			var angle: float = TAU * k / sides
			var normal: Vector3 = across * cos(angle) + around * sin(angle)
			ring.append(center + normal * radius)
			normals.append(normal)
		rings.append(ring)
		ring_normals.append(normals)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in segments:
		for k in sides:
			var k2: int = (k + 1) % sides
			var a: Vector3 = rings[s][k]
			var b: Vector3 = rings[s][k2]
			var c: Vector3 = rings[s + 1][k2]
			var d: Vector3 = rings[s + 1][k]
			var outward: Vector3 = ring_normals[s][k] + ring_normals[s][k2]
			_smooth_triangle(st, [a, b, c], [ring_normals[s][k], ring_normals[s][k2], ring_normals[s + 1][k2]], outward)
			_smooth_triangle(st, [a, c, d], [ring_normals[s][k], ring_normals[s + 1][k2], ring_normals[s + 1][k]], outward)
	return st.commit()


## Adds a flat triangle that faces along normal (Godot treats clockwise as the front).
static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	_smooth_triangle(st, [a, b, c], [normal, normal, normal], normal)


static func _smooth_triangle(st: SurfaceTool, points: Array[Vector3], normals: Array[Vector3], facing: Vector3) -> void:
	var order: Array[int] = [0, 1, 2]
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(facing) > 0.0:
		order = [0, 2, 1]
	for i in order:
		st.set_normal(normals[i])
		st.add_vertex(points[i])

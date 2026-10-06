extends RefCounted
## Mesh builders for the exterior shots: lathes for the capsule, engine bells, tanks and parachute
## canopies, plus small helpers that add shapes to a parent. Faces are wound to match their
## normals (Godot treats clockwise as the front), so callers never think about winding.


## Revolves a profile of (radius, z) points around the local Z axis, from angle_from to angle_to
## (radians, from +X toward +Y). List the profile from low z to high z along the outside of the
## shape so the normals face out. u runs around the axis and v along the profile.
static func lathe(profile: PackedVector2Array, sides: int, angle_from: float = 0.0, angle_to: float = TAU,
		smooth: bool = true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = profile.size()
	var segment_normals: PackedVector2Array = []
	var along: PackedFloat32Array = [0.0]
	for i in count - 1:
		var step: Vector2 = profile[i + 1] - profile[i]
		segment_normals.append(Vector2(step.y, -step.x).normalized())
		along.append(along[i] + step.length())
	var total: float = maxf(along[count - 1], 0.0001)
	for k in sides:
		var a0: float = lerpf(angle_from, angle_to, float(k) / sides)
		var a1: float = lerpf(angle_from, angle_to, float(k + 1) / sides)
		var u0: float = float(k) / sides
		var u1: float = float(k + 1) / sides
		for i in count - 1:
			var n0: Vector2 = segment_normals[i]
			var n1: Vector2 = segment_normals[i]
			if smooth and i > 0:
				n0 = (segment_normals[i - 1] + segment_normals[i]).normalized()
			if smooth and i < count - 2:
				n1 = (segment_normals[i] + segment_normals[i + 1]).normalized()
			var v0: float = along[i] / total
			var v1: float = along[i + 1] / total
			var corners: Array[Vector3] = [_around(profile[i], a0), _around(profile[i], a1),
				_around(profile[i + 1], a1), _around(profile[i + 1], a0)]
			var normals: Array[Vector3] = [_turn(n0, a0), _turn(n0, a1), _turn(n1, a1), _turn(n1, a0)]
			var uvs: Array[Vector2] = [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
			var facing: Vector3 = normals[0] + normals[1] + normals[2] + normals[3]
			_triangle(st, [corners[0], corners[1], corners[2]], [normals[0], normals[1], normals[2]], [uvs[0], uvs[1], uvs[2]], facing)
			_triangle(st, [corners[0], corners[2], corners[3]], [normals[0], normals[2], normals[3]], [uvs[0], uvs[2], uvs[3]], facing)
	return st.commit()


## A flat polygon (convex, either winding) in the local XY plane, facing +Z.
static func plate(polygon: PackedVector2Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normal := Vector3.BACK
	for i in range(1, polygon.size() - 1):
		var points: Array[Vector3] = [Vector3(polygon[0].x, polygon[0].y, 0.0),
			Vector3(polygon[i].x, polygon[i].y, 0.0), Vector3(polygon[i + 1].x, polygon[i + 1].y, 0.0)]
		var uvs: Array[Vector2] = [polygon[0], polygon[i], polygon[i + 1]]
		_triangle(st, points, [normal, normal, normal], uvs, normal)
	return st.commit()


static func add_mesh(parent: Node3D, mesh: Mesh, material: Material, where: Transform3D = Transform3D.IDENTITY) -> MeshInstance3D:
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = material
	body.transform = where
	parent.add_child(body)
	return body


static func add_box(parent: Node3D, size: Vector3, where: Vector3, material: Material, turn: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return add_mesh(parent, mesh, material, Transform3D(Basis.from_euler(turn), where))


## A cylinder between two points.
static func add_rod(parent: Node3D, from: Vector3, to: Vector3, radius: float, material: Material, sides: int = 8,
		end_radius: float = -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if end_radius < 0.0 else end_radius
	mesh.height = maxf(from.distance_to(to), 0.001)
	mesh.radial_segments = sides
	mesh.rings = 1
	return add_mesh(parent, mesh, material, Transform3D(along_y(to - from), (from + to) * 0.5))


static func add_sphere(parent: Node3D, radius: float, where: Vector3, material: Material, segments: int = 16) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = maxi(segments / 2, 4)
	return add_mesh(parent, mesh, material, Transform3D(Basis.IDENTITY, where))


## A basis whose +Y points along direction.
static func along_y(direction: Vector3) -> Basis:
	var y: Vector3 = direction.normalized() if direction.length_squared() > 0.000001 else Vector3.UP
	var helper: Vector3 = Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x: Vector3 = y.cross(helper).normalized()
	return Basis(x, y, x.cross(y).normalized())


static func _around(point: Vector2, angle: float) -> Vector3:
	return Vector3(point.x * cos(angle), point.x * sin(angle), point.y)


static func _turn(normal: Vector2, angle: float) -> Vector3:
	return Vector3(normal.x * cos(angle), normal.x * sin(angle), normal.y)


static func _triangle(st: SurfaceTool, points: Array[Vector3], normals: Array[Vector3], uvs: Array[Vector2], facing: Vector3) -> void:
	var order: Array[int] = [0, 1, 2]
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(facing) > 0.0:
		order = [0, 2, 1]
	for i in order:
		st.set_normal(normals[i])
		st.set_uv(uvs[i])
		st.add_vertex(points[i])

extends Node3D
## The Apollo stack in space, and the Earth-Moon mission map. The cabin hides while this
## camera is current. Later cutscenes animate the same stack; this scene only frames it.

const Bodies := preload("res://scenes/space/bodies.gd")
const MapPath := preload("res://scenes/space/map_path.gd")

const GROUP := "exterior"
const MOVES: Array[String] = ["orbit", "push_in", "pan"]

# Stack axis: -Z is the Service Module engine, +Z is the Lunar Module.
const FOCUS := Vector3(0.0, 0.6, 3.2)
const CSM_WHITE := Color(0.86, 0.87, 0.88)
const FOIL := Color(0.72, 0.52, 0.28)
const NOZZLE := Color(0.22, 0.21, 0.2)
const WINDOW := Color(0.05, 0.06, 0.07)
const MARKER := Color(0.55, 0.81, 0.76)

var _camera: Camera3D
var _world: WorldEnvironment
var _environment: Environment
var _stack: Node3D
var _scenic_earth: Node3D
var _scenic_moon: Node3D
var _map: Node3D
var _marker: MeshInstance3D
var _move: String = "orbit"
var _showing: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	build()
	hide_view()


func build() -> void:
	if _camera != null:
		return
	_build_environment()
	_build_scenery()
	_build_stack()
	_build_map()
	_camera = Camera3D.new()
	_camera.fov = 48.0
	_camera.near = 0.08
	_camera.far = 800.0
	add_child(_camera)


func show_exterior(move: String, body: String) -> void:
	build()
	_showing = true
	visible = true
	_stack.visible = true
	_map.visible = false
	_scenic_earth.visible = true
	_scenic_moon.visible = true
	_place_scenery(body)
	_move = move if move in MOVES else "orbit"
	_world.environment = _environment
	_camera.current = true
	set_progress(0.0)


func show_map(get_h: float, splashdown_h: float) -> void:
	build()
	_showing = true
	visible = true
	_stack.visible = false
	_scenic_earth.visible = false
	_scenic_moon.visible = false
	_map.visible = true
	_rebuild_path(splashdown_h)
	_marker.position = _map_point(MapPath.position(get_h, splashdown_h))
	_camera.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3(0, 0, -1)), Vector3(0, 28, 0.5))
	_world.environment = _environment
	_camera.current = true


func set_progress(t: float) -> void:
	if _camera == null:
		return
	_camera.global_transform = camera_transform(_move, clampf(t, 0.0, 1.0))


func hide_view() -> void:
	_showing = false
	visible = false
	if _camera != null:
		_camera.current = false
	if _world != null:
		_world.environment = null


func is_showing() -> bool:
	return _showing


## Camera framing for a move. t goes from 0 to 1 over the shot.
static func camera_transform(move: String, t: float) -> Transform3D:
	var amount: float = clampf(t, 0.0, 1.0)
	var from: Vector3
	match move:
		"push_in":
			from = Vector3(7.0, 3.2, 16.0).lerp(Vector3(2.4, 1.4, 7.5), smoothstep(0.0, 1.0, amount))
		"pan":
			from = Vector3(lerpf(-9.0, 9.0, amount), 2.2, 13.0)
		_:
			var angle: float = lerpf(-0.8, 1.05, amount)
			from = FOCUS + Vector3(sin(angle) * 16.0, 4.2, cos(angle) * 16.0)
	return Transform3D(Basis.looking_at(FOCUS - from, Vector3.UP), from)


func _place_scenery(body: String) -> void:
	if body == "moon":
		_scenic_moon.position = Vector3(-16.0, 5.0, -28.0)
		_scenic_moon.scale = Vector3.ONE * 9.0
		_scenic_earth.position = Vector3(48.0, -12.0, 40.0)
		_scenic_earth.scale = Vector3.ONE * 6.0
	else:
		_scenic_earth.position = Vector3(22.0, -6.0, -36.0)
		_scenic_earth.scale = Vector3.ONE * 11.0
		_scenic_moon.position = Vector3(-40.0, 8.0, 30.0)
		_scenic_moon.scale = Vector3.ONE * 4.0


func _build_environment() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = Bodies.star_panorama()
	sky_material.energy_multiplier = Bodies.STAR_BRIGHTNESS
	_environment.sky = Sky.new()
	_environment.sky.sky_material = sky_material
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.62, 0.66, 0.72)
	_environment.ambient_light_energy = 0.22
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.glow_enabled = true
	_environment.glow_intensity = 0.35
	_world = WorldEnvironment.new()
	add_child(_world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28.0, 36.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = false
	add_child(sun)


func _build_scenery() -> void:
	_scenic_earth = Node3D.new()
	_scenic_earth.add_child(Bodies.sphere(1.0, Bodies.earth_material(), 40))
	_scenic_earth.add_child(Bodies.sphere(1.012, Bodies.cloud_material(), 40))
	var air := Bodies.atmosphere_material()
	if air.shader != null:
		_scenic_earth.add_child(Bodies.sphere(1.04, air, 40))
	add_child(_scenic_earth)
	_scenic_moon = Node3D.new()
	_scenic_moon.add_child(Bodies.sphere(1.0, Bodies.moon_material(), 40))
	add_child(_scenic_moon)


func _build_stack() -> void:
	_stack = Node3D.new()
	add_child(_stack)
	var white := _paint(CSM_WHITE, 0.55)
	var foil := _paint(FOIL, 0.72)
	var dark := _paint(NOZZLE, 0.4)
	var glass := _paint(WINDOW, 0.25)
	# Service Module and its engine.
	_cylinder(1.95, 1.95, 7.4, 16, Vector3(0, 0, 0), white, _stack)
	_cylinder(1.15, 0.32, 1.7, 16, Vector3(0, 0, -4.55), dark, _stack)
	_cylinder(1.96, 1.96, 0.55, 16, Vector3(0, 0, 2.6), foil, _stack)
	# Command Module: heat shield aft, nose toward the Lunar Module.
	_cylinder(1.95, 0.42, 3.4, 16, Vector3(0, 0, 5.55), white, _stack)
	_cylinder(0.34, 0.34, 0.55, 12, Vector3(0, 0, 7.45), white, _stack)
	_box(Vector3(0.28, 0.22, 0.02), Vector3(0.7, 0.35, 4.7), glass, _stack)
	_box(Vector3(0.28, 0.22, 0.02), Vector3(-0.55, 0.55, 5.3), glass, _stack)
	# Lunar Module: ascent cabin, then the descent stage and four legs.
	_box(Vector3(2.3, 2.5, 2.2), Vector3(0, 0.15, 9.0), foil, _stack)
	_box(Vector3(4.1, 1.7, 4.1), Vector3(0, -0.85, 11.15), foil, _stack)
	_cylinder(0.55, 0.55, 0.35, 12, Vector3(0, 1.5, 9.0), dark, _stack, false)
	_box(Vector3(0.46, 0.46, 0.04), Vector3(0, 0.35, 7.88), glass, _stack)
	for side: int in [-1, 1]:
		for fore: int in [-1, 1]:
			var root := Vector3(side * 1.7, -1.5, 11.15 + fore * 1.5)
			var foot := root + Vector3(side * 1.3, -1.7, fore * 0.8)
			_strut(root, foot, dark, _stack)


func _build_map() -> void:
	_map = Node3D.new()
	_map.visible = false
	add_child(_map)
	var earth := Bodies.sphere(1.35, Bodies.earth_material(), 28)
	earth.position = _map_point(MapPath.EARTH)
	_map.add_child(earth)
	var moon := Bodies.sphere(0.72, Bodies.moon_material(), 24)
	moon.position = _map_point(MapPath.MOON)
	_map.add_child(moon)
	_marker = Bodies.sphere(0.28, _marker_material(), 12)
	_map.add_child(_marker)
	var path := MeshInstance3D.new()
	path.name = "path"
	path.material_override = _paint(Color(0.85, 0.86, 0.84), 1.0)
	_map.add_child(path)


func _rebuild_path(splashdown_h: float) -> void:
	var path: MeshInstance3D = _map.get_node("path")
	var flat: PackedVector2Array = MapPath.polyline(splashdown_h, 64)
	var points := PackedVector3Array()
	for p: Vector2 in flat:
		points.append(_map_point(p))
	path.mesh = _ribbon(points, 0.08)


func _map_point(flat: Vector2) -> Vector3:
	return Vector3(flat.x, 0.0, flat.y)


func _ribbon(points: PackedVector3Array, width: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var dir: Vector3 = b - a
		if dir.length_squared() < 0.0001:
			continue
		var side: Vector3 = dir.normalized().cross(Vector3.UP).normalized() * width
		if side.length_squared() < 0.0001:
			side = Vector3(width, 0, 0)
		tool.set_normal(Vector3.UP)
		tool.add_vertex(a - side)
		tool.add_vertex(a + side)
		tool.add_vertex(b + side)
		tool.add_vertex(a - side)
		tool.add_vertex(b + side)
		tool.add_vertex(b - side)
	return tool.commit()


func _cylinder(bottom: float, top: float, height: float, sides: int, where: Vector3, material: Material, parent: Node3D, along_ship: bool = true) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = sides
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = material
	body.position = where
	if along_ship:
		body.rotation.x = PI / 2.0
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(body)


func _box(size: Vector3, where: Vector3, material: Material, parent: Node3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = material
	body.position = where
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(body)


func _strut(a: Vector3, b: Vector3, material: Material, parent: Node3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, a.distance_to(b), 0.12)
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = material
	var y_axis: Vector3 = (b - a).normalized()
	var x_axis: Vector3 = y_axis.cross(Vector3.FORWARD)
	if x_axis.length_squared() < 0.001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	body.transform = Transform3D(Basis(x_axis, y_axis, x_axis.cross(y_axis).normalized()), (a + b) * 0.5)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(body)


func _paint(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _marker_material() -> StandardMaterial3D:
	var material := _paint(MARKER, 0.4)
	material.emission_enabled = true
	material.emission = MARKER
	material.emission_energy_multiplier = 1.4
	return material

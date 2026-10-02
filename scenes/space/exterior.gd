extends Node3D
## The Apollo stack in space, and the Earth-Moon mission map. The cabin hides while this
## camera is current. Later cutscenes animate the same stack; this scene only frames it.

const Bodies := preload("res://scenes/space/bodies.gd")
const MapPath := preload("res://scenes/space/map_path.gd")

const GROUP := "exterior"
const MOVES: Array[String] = ["orbit", "push_in", "pan", "bay"]
const PANEL_HOME := Vector3(2.05, 0.15, 0.25)
const PANEL_DRIFT := Vector3(5.8, 1.8, -1.4)
const BAY := Vector3(1.72, 0.15, 0.25)

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
var _action: String = ""
var _showing: bool = false
var _panel: MeshInstance3D
var _debris: Array[MeshInstance3D] = []
var _debris_dir: Array[Vector3] = []
var _puffs: Array[MeshInstance3D] = []
var _puff_dir: Array[Vector3] = []
var _cloud_mat: StandardMaterial3D
var _cm_windows: Array[StandardMaterial3D] = []
var _lm_windows: Array[StandardMaterial3D] = []


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


func show_exterior(move: String, body: String, action: String = "") -> void:
	build()
	_showing = true
	visible = true
	_stack.visible = true
	_map.visible = false
	_scenic_earth.visible = true
	_scenic_moon.visible = true
	_place_scenery(body)
	_move = move if move in MOVES else "orbit"
	_action = action
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
	var amount: float = clampf(t, 0.0, 1.0)
	_camera.global_transform = camera_transform(_move, amount, _action)
	_apply_action(amount)


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
## The explosion watches the Service Module bay. The lifeboat push-in aims at the docking tunnel.
static func camera_transform(move: String, t: float, action: String = "") -> Transform3D:
	var amount: float = clampf(t, 0.0, 1.0)
	var eased: float = smoothstep(0.0, 1.0, amount)
	var from: Vector3
	var aim: Vector3 = FOCUS
	if action == "explosion" or move == "bay":
		from = Vector3(8.2, 2.0, 3.2).lerp(Vector3(10.4, 2.6, 0.2), eased)
		aim = Vector3(1.4, 0.2, 0.3)
	elif action == "lifeboat":
		from = Vector3(6.2, 2.2, 13.5).lerp(Vector3(1.7, 0.85, 8.6), eased)
		aim = Vector3(0.0, 0.4, 7.6)
	else:
		match move:
			"push_in":
				from = Vector3(7.0, 3.2, 16.0).lerp(Vector3(2.4, 1.4, 7.5), eased)
			"pan":
				from = Vector3(lerpf(-9.0, 9.0, amount), 2.2, 13.0)
			_:
				var angle: float = lerpf(-0.8, 1.05, amount)
				from = FOCUS + Vector3(sin(angle) * 16.0, 4.2, cos(angle) * 16.0)
	return Transform3D(Basis.looking_at(aim - from, Vector3.UP), from)


## 0 while the panel is on the hull, 1 when it has blown clear.
static func panel_travel(action: String, t: float) -> float:
	if action == "lifeboat":
		return 1.0
	if action == "explosion":
		return smoothstep(0.06, 0.48, clampf(t, 0.0, 1.0))
	return 0.0


## Opacity of the oxygen cloud. The lifeboat shot starts with it already venting, then thinner.
static func cloud_alpha(action: String, t: float) -> float:
	var amount: float = clampf(t, 0.0, 1.0)
	if action == "explosion":
		return lerpf(0.0, 0.5, smoothstep(0.1, 0.8, amount))
	if action == "lifeboat":
		return lerpf(0.4, 0.14, amount)
	return 0.0


## Warm-window glow, x for Odyssey and y for Aquarius.
static func window_glow(action: String, t: float) -> Vector2:
	if action == "explosion":
		return Vector2(1.0, 0.0)
	if action == "lifeboat":
		var swap: float = smoothstep(0.12, 0.88, clampf(t, 0.0, 1.0))
		return Vector2(1.0 - swap, swap)
	return Vector2.ZERO


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
	# Service Module and its engine.
	_cylinder(1.95, 1.95, 7.4, 16, Vector3(0, 0, 0), white, _stack)
	_cylinder(1.15, 0.32, 1.7, 16, Vector3(0, 0, -4.55), dark, _stack)
	_cylinder(1.96, 1.96, 0.55, 16, Vector3(0, 0, 2.6), foil, _stack)
	# Command Module: heat shield aft, nose toward the Lunar Module.
	_cylinder(1.95, 0.42, 3.4, 16, Vector3(0, 0, 5.55), white, _stack)
	_cylinder(0.34, 0.34, 0.55, 12, Vector3(0, 0, 7.45), white, _stack)
	_window(Vector3(0.28, 0.22, 0.02), Vector3(0.7, 0.35, 4.7), false)
	_window(Vector3(0.28, 0.22, 0.02), Vector3(-0.55, 0.55, 5.3), false)
	# Lunar Module: ascent cabin, then the descent stage and four legs.
	_box(Vector3(2.3, 2.5, 2.2), Vector3(0, 0.15, 9.0), foil, _stack)
	_box(Vector3(4.1, 1.7, 4.1), Vector3(0, -0.85, 11.15), foil, _stack)
	_cylinder(0.55, 0.55, 0.35, 12, Vector3(0, 1.5, 9.0), dark, _stack, false)
	_window(Vector3(0.46, 0.5, 0.04), Vector3(0, 0.4, 7.86), true)
	_window(Vector3(0.04, 0.42, 0.55), Vector3(1.16, 0.35, 9.0), true)
	_build_damage(dark)
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


func _build_damage(dark: Material) -> void:
	_box(Vector3(0.4, 1.65, 1.25), BAY, dark, _stack)
	_panel = MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(0.12, 2.15, 1.55)
	_panel.mesh = plate
	_panel.material_override = _paint(CSM_WHITE, 0.5)
	_panel.position = PANEL_HOME
	_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stack.add_child(_panel)
	_cloud_mat = _paint(Color(0.96, 0.97, 1.0, 0.0), 1.0)
	_cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cloud_mat.emission_enabled = true
	_cloud_mat.emission = Color(0.92, 0.95, 1.0)
	_cloud_mat.emission_energy_multiplier = 0.85
	_cloud_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dirs: Array[Vector3] = [
		Vector3(1.0, 0.15, 0.1), Vector3(0.85, 0.45, -0.2), Vector3(0.7, -0.15, 0.45),
		Vector3(0.95, 0.3, -0.4), Vector3(0.6, 0.55, 0.2), Vector3(0.8, -0.35, -0.25),
		Vector3(1.0, 0.05, 0.35),
	]
	for dir: Vector3 in dirs:
		var puff := Bodies.sphere(0.45, _cloud_mat, 10)
		puff.visible = false
		_stack.add_child(puff)
		_puffs.append(puff)
		_puff_dir.append(dir.normalized())
	for i in 5:
		var chip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.28, 0.08, 0.16) if i % 2 == 0 else Vector3(0.14, 0.22, 0.1)
		chip.mesh = box
		chip.material_override = _paint(CSM_WHITE.darkened(0.15 * float(i % 3)), 0.6)
		chip.visible = false
		chip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_stack.add_child(chip)
		_debris.append(chip)
		_debris_dir.append(Vector3(0.7 + 0.15 * float(i), 0.35 - 0.2 * float(i % 3), -0.25 + 0.18 * float(i % 2)).normalized())


func _apply_action(t: float) -> void:
	var travel: float = panel_travel(_action, t)
	var drift: float = smoothstep(0.25, 1.0, t) if _action == "explosion" else travel
	_panel.position = PANEL_HOME + PANEL_DRIFT * travel
	_panel.rotation = Vector3(0.5, 0.25, 1.1) * travel * 3.5
	for i in _debris.size():
		var piece: MeshInstance3D = _debris[i]
		piece.visible = travel > 0.02
		var out: float = travel * (3.2 + float(i) * 0.7) + drift * 1.4
		piece.position = BAY + _debris_dir[i] * out
		piece.rotation = _debris_dir[i] * travel * (2.0 + float(i))
	var alpha: float = cloud_alpha(_action, t)
	var spread: float = 0.0
	if _action == "explosion":
		spread = smoothstep(0.1, 1.0, t)
	elif _action == "lifeboat":
		spread = lerpf(0.85, 1.0, t)
	var cloud_color := Color(0.96, 0.97, 1.0, alpha)
	_cloud_mat.albedo_color = cloud_color
	_cloud_mat.emission_energy_multiplier = alpha * 1.7
	for i in _puffs.size():
		var puff: MeshInstance3D = _puffs[i]
		puff.visible = alpha > 0.02
		var reach: float = spread * (1.6 + float(i) * 0.45)
		puff.position = BAY + _puff_dir[i] * reach
		var size: float = 0.35 + spread * (0.7 + float(i) * 0.18)
		puff.scale = Vector3.ONE * size
	var glow: Vector2 = window_glow(_action, t)
	for mat: StandardMaterial3D in _cm_windows:
		mat.emission_energy_multiplier = glow.x * 1.6
	for mat: StandardMaterial3D in _lm_windows:
		mat.emission_energy_multiplier = glow.y * 1.6


func _window(size: Vector3, where: Vector3, aquarius: bool) -> void:
	var material := _window_material()
	_box(size, where, material, _stack)
	if aquarius:
		_lm_windows.append(material)
	else:
		_cm_windows.append(material)


func _window_material() -> StandardMaterial3D:
	var material := _paint(Color(0.12, 0.1, 0.08), 0.3)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.82, 0.48)
	material.emission_energy_multiplier = 0.0
	return material


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

@tool
extends Node3D
## The LM cabin, Aquarius (SPEC.md section 8): matte grey-green panels with drawn-on instruments,
## two triangular front windows onto Earth or the Moon, dim warm lights scaled by
## set_light_level(), camera presets with a zero-g drift, and a few slowly tumbling loose objects.
## Built in code; as a tool script it also shows when cabin.tscn is opened in the editor.

const CabinMesh := preload("res://scenes/cabin/cabin_mesh.gd")
const PanelArt := preload("res://scenes/cabin/panel_art.gd")
const CabinCamera := preload("res://scenes/cabin/cabin_camera.gd")
const Floater := preload("res://scenes/cabin/floater.gd")
const UiStyle := preload("res://scenes/ui/ui_style.gd")
const Tuning := preload("res://sim/tuning.gd")
const Bodies := preload("res://scenes/space/bodies.gd")

const GROUP := "cabin"
const START_PRESET := "front_windows"
const OUTSIDE_VIEWS: Array[String] = ["earth", "moon"]

# --- Layout in metres: origin on the floor at the cabin centre, -Z forward, +X to the right ---
const HALF_WIDTH := 1.15
const HEIGHT := 2.2
const FRONT_Z := -0.85
const AFT_Z := 0.95
const SHELL := 0.06
const BULKHEAD := 0.08
## The bulkhead above the main console, with the two windows cut out of it as a V.
const BULKHEAD_BOTTOM := 1.26
const WINDOW_TOP := 2.02
const WINDOW_BOTTOM := 1.34
const WINDOW_INNER_X := 0.16
const WINDOW_OUTER_X := 0.9
const GLASS_INSET := 0.06
const GASKET := 0.018
## The trim sits on the cabin side of the wall. It does not share a face with the wall,
## the glass or the instrument panels, so the frame does not flicker as the camera drifts.
const FRAME_DEPTH := 0.008
const FRAME_GAP := 0.014
## The main console leans back from the bulkhead; its bottom edge comes toward the crew.
const CONSOLE_TILT_DEG := 20.0
const SIDE_CONSOLE_TOP := 1.05
const SIDE_CONSOLE_INNER_X := 0.91
const SIDE_CONSOLE_Z := Vector2(-0.6, 0.3)
const BREAKER_PANEL_Y := 1.5
const BREAKER_PANEL_Z := -0.17
const BREAKER_PANEL_YAW_DEG := 12.0
const ECS_PANEL_CENTER := Vector3(1.14, 1.27, 0.61)
const CANISTER_POSITION := Vector3(0.98, 0.62, 0.64)
const CANISTER_SIZE := Vector2(0.08, 0.26)
## The CO2 "mail box" (NASA photo AS13-62-8929): one of Odyssey's square canisters with its
## perforated face, taped into a plastic bag, with a suit hose running down from it. It hangs on
## the right wall below the breakers, in view of the CO2 panel camera, once it is built.
const MAILBOX_CENTER := Vector3(1.01, 1.1, 0.2)
## Depth from the wall, height, width.
const MAILBOX_SIZE := Vector3(0.22, 0.22, 0.24)
const MAILBOX_GRILLE := 3
const MAILBOX_CANISTER := Color("#A9ACA6")
## The face is perforated metal: holes this far apart.
const MAILBOX_GRILLE_METAL := Color("#8A8D88")
const MAILBOX_PERFORATED := Color("#2E312E")
const MAILBOX_HOLE_PITCH_M := 0.008
const MAILBOX_TAPE := Color("#A7A9A3")
const MAILBOX_BAG := Color(0.93, 0.95, 0.96, 0.32)
const MAILBOX_HOSE := Color("#E4E2DA")
const OVERHEAD_WINDOW := Rect2(-0.62, -0.62, 0.3, 0.24)
const HATCH_CENTER := Vector3(0.05, 0.0, 0.25)
const HATCH_DEPTH := 0.04
const SURFACE_OFFSET := 0.004

## Camera presets: where the camera sits and what it looks at.
const PRESETS: Dictionary = {
	"front_windows": {"title": "Front windows", "position": Vector3(0.0, 1.55, 0.48), "target": Vector3(-0.12, 1.62, -0.85)},
	"co2_panel": {"title": "CO2 panel", "position": Vector3(0.3, 1.42, 0.05), "target": Vector3(1.15, 1.22, 0.6)},
	"overhead": {"title": "Overhead", "position": Vector3(0.1, 1.25, 0.8), "target": Vector3(-0.2, 2.2, -0.15)},
}
const CAMERA_FOV_DEG := 70.0
const CAMERA_NEAR := 0.02
const CAMERA_FAR := 400.0

# --- Look ---
const LIGHT_COLOR := Color(1.0, 0.93, 0.82)
## Cabin lights: position, energy at full power, range, and whether it casts shadows.
const LIGHTS: Array = [
	{"position": Vector3(-0.6, 1.9, 0.3), "energy": 0.5, "range": 3.0, "shadow": true},
	{"position": Vector3(0.6, 1.9, 0.3), "energy": 0.42, "range": 3.0, "shadow": false},
	{"position": Vector3(0.0, 1.45, -0.25), "energy": 0.3, "range": 1.6, "shadow": false},
	{"position": Vector3(0.2, 1.5, 0.75), "energy": 0.28, "range": 2.0, "shadow": false},
]
const AMBIENT_COLOR := Color(0.55, 0.56, 0.52)
const AMBIENT_ENERGY := 0.08
const GLOW_INTENSITY := 0.7
const LAMP_ON_ENERGY := 2.5
const PLACARD_FONT_SIZE := 40
const PLACARD_PIXEL_SIZE := 0.00025
const CABIN_LAYER := 1
const OUTSIDE_LAYER := 2
## Direction the sunlight travels for each outside view: Earth mostly lit, the Moon side-lit for relief.
const SUN_DIRECTIONS: Dictionary = {"earth": Vector3(-0.6, -0.2, -0.75), "moon": Vector3(-1.0, -0.15, -0.3)}
const SUN_ENERGY := 1.6
const EARTH_DISTANCE := 80.0
const EARTH_RADIUS := 6.0
const CLOUD_SCALE := 1.012
const ATMOSPHERE_SCALE := 1.04
const MOON_DISTANCE := 95.0
const MOON_RADIUS := 62.0
const CHECKLIST_COVER := Color("#D9D2BF")
const BAG_FABRIC := Color("#B8B2A4")
const HOSE_COLOR := Color("#7F94A3")

var camera: CabinCamera
var light_level: float = 1.0
var outside_view: String = "earth"
var _lights: Array[OmniLight3D] = []
var _base_energy: Dictionary = {}
var _environment: Environment
var _world: WorldEnvironment
## Lamp name -> StandardMaterial3D shared by every lamp with that name
var _lamps: Dictionary = {}
var _bodies: Dictionary = {}
var _sun: DirectionalLight3D
var _wall_material: StandardMaterial3D
var _dark_material: StandardMaterial3D
var _metal_material: StandardMaterial3D
var _mailbox: Node3D


func _ready() -> void:
	add_to_group(GROUP)
	if get_child_count() == 0:
		build()


func build() -> void:
	_make_materials()
	_build_environment()
	_build_shell()
	_build_bulkhead()
	_build_consoles()
	_build_side_panels()
	_build_mailbox()
	_build_overhead()
	_build_outside()
	_build_lights()
	_build_floaters()
	_build_camera()
	set_outside_view(outside_view)
	set_light_level(light_level)


# --- Public ---

func preset_names() -> PackedStringArray:
	return PackedStringArray(PRESETS.keys())


func preset_title(preset_name: String) -> String:
	return PRESETS.get(preset_name, {}).get("title", preset_name)


func camera_go_to(preset_name: String, instant: bool = false) -> void:
	camera.go_to(preset_name, instant)


## Scales every cabin light and the ambient light. 1.0 is full power.
func set_light_level(level: float) -> void:
	light_level = level
	for light in _lights:
		light.light_energy = _base_energy[light] * level
	_environment.ambient_light_energy = AMBIENT_ENERGY * level


## Which body fills the front windows: "earth" or "moon".
func set_outside_view(body: String) -> void:
	if body not in OUTSIDE_VIEWS:
		push_warning("Unknown outside view '%s'" % body)
		return
	outside_view = body
	for body_name: String in _bodies:
		_bodies[body_name].visible = body_name == body
	_sun.basis = Basis.looking_at(SUN_DIRECTIONS[body], Vector3.UP)


func set_lamp(lamp: String, lit: bool) -> void:
	set_lamp_level(lamp, 1.0 if lit else 0.0)


## 0 is dark, 1 is fully lit; values in between let the effects fade a lamp.
## Shows the CO2 adapter once the crew has built it.
func set_mailbox(shown: bool) -> void:
	if _mailbox != null:
		_mailbox.visible = shown


func set_lamp_level(lamp: String, level: float) -> void:
	var material: StandardMaterial3D = _lamps.get(lamp)
	if material != null:
		material.emission_energy_multiplier = LAMP_ON_ENERGY * clampf(level, 0.0, 1.0)


func lamp_names() -> PackedStringArray:
	return PackedStringArray(_lamps.keys())


## Hides the cabin while an exterior or map shot uses the only camera.
func set_presented(shown: bool) -> void:
	visible = shown
	if camera != null:
		camera.current = shown
	if _world != null:
		_world.environment = _environment if shown else null


# --- Building ---

func _make_materials() -> void:
	_wall_material = StandardMaterial3D.new()
	_wall_material.albedo_texture = PanelArt.texture("wall", PanelArt.WALL_TILE_SIZE, PanelArt.WALL_TILE, PanelArt.WALL)
	_wall_material.uv1_triplanar = true
	_wall_material.uv1_world_triplanar = true
	_wall_material.uv1_scale = Vector3.ONE / PanelArt.WALL_TILE_SIZE.x
	_wall_material.roughness = 0.85
	_dark_material = _plain_material(UiStyle.INSTRUMENT_BLACK, 0.6)
	_metal_material = _plain_material(PanelArt.METAL_DARK, 0.5)


func _build_environment() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = Bodies.star_panorama()
	sky_material.energy_multiplier = Bodies.STAR_BRIGHTNESS
	_environment.sky = Sky.new()
	_environment.sky.sky_material = sky_material
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = AMBIENT_COLOR
	_environment.ambient_light_energy = AMBIENT_ENERGY
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.glow_enabled = true
	_environment.glow_intensity = GLOW_INTENSITY
	_world = WorldEnvironment.new()
	_world.environment = _environment
	add_child(_world)


func _build_shell() -> void:
	var depth: float = AFT_Z - FRONT_Z
	var middle_z: float = (AFT_Z + FRONT_Z) * 0.5
	_box(Vector3(HALF_WIDTH * 2.0, SHELL, depth), Vector3(0.0, -SHELL * 0.5, middle_z), _wall_material)
	_box(Vector3(SHELL, HEIGHT, depth), Vector3(-HALF_WIDTH - SHELL * 0.5, HEIGHT * 0.5, middle_z), _wall_material)
	_box(Vector3(SHELL, HEIGHT, depth), Vector3(HALF_WIDTH + SHELL * 0.5, HEIGHT * 0.5, middle_z), _wall_material)
	_box(Vector3(HALF_WIDTH * 2.0, HEIGHT, SHELL), Vector3(0.0, HEIGHT * 0.5, AFT_Z + SHELL * 0.5), _wall_material)
	var lower_height: float = _console_bottom().x
	_box(Vector3(HALF_WIDTH * 2.0, lower_height, SHELL), Vector3(0.0, lower_height * 0.5, FRONT_Z - SHELL * 0.5), _wall_material)
	_panel("front_hatch", PanelArt.FRONT_HATCH_SIZE, PanelArt.FRONT_HATCH,
		_facing(Vector3(0.0, PanelArt.FRONT_HATCH_SIZE.y * 0.5, FRONT_Z + SURFACE_OFFSET), Vector3.BACK), PanelArt.WALL)


## The window bulkhead: four convex pieces around the two triangular openings.
func _build_bulkhead() -> void:
	var pieces: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-HALF_WIDTH, WINDOW_TOP), Vector2(HALF_WIDTH, WINDOW_TOP),
			Vector2(HALF_WIDTH, HEIGHT), Vector2(-HALF_WIDTH, HEIGHT)]),
		PackedVector2Array([Vector2(-WINDOW_INNER_X, BULKHEAD_BOTTOM), Vector2(WINDOW_INNER_X, BULKHEAD_BOTTOM),
			Vector2(WINDOW_INNER_X, WINDOW_TOP), Vector2(-WINDOW_INNER_X, WINDOW_TOP)]),
	]
	for side: float in [-1.0, 1.0]:
		pieces.append(PackedVector2Array([
			Vector2(side * HALF_WIDTH, BULKHEAD_BOTTOM), Vector2(side * WINDOW_INNER_X, BULKHEAD_BOTTOM),
			Vector2(side * WINDOW_INNER_X, WINDOW_BOTTOM), Vector2(side * WINDOW_OUTER_X, WINDOW_TOP),
			Vector2(side * HALF_WIDTH, WINDOW_TOP)]))
	for piece in pieces:
		var wall := MeshInstance3D.new()
		wall.mesh = CabinMesh.prism(piece, BULKHEAD)
		wall.material_override = _wall_material
		wall.position = Vector3(0.0, 0.0, FRONT_Z)
		add_child(wall)
	var pillar_center := Vector3(0.0, (WINDOW_BOTTOM + WINDOW_TOP) * 0.5, FRONT_Z + SURFACE_OFFSET)
	_panel("pillar", PanelArt.PILLAR_SIZE, PanelArt.PILLAR, _facing(pillar_center, Vector3.BACK))
	for side: float in [-1.0, 1.0]:
		_build_window([Vector2(side * WINDOW_OUTER_X, WINDOW_TOP), Vector2(side * WINDOW_INNER_X, WINDOW_TOP),
			Vector2(side * WINDOW_INNER_X, WINDOW_BOTTOM)])


func _build_window(corners: Array[Vector2]) -> void:
	var glass_z: float = FRONT_Z - GLASS_INSET
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for corner in corners:
		st.set_normal(Vector3.BACK)
		st.add_vertex(Vector3(corner.x, corner.y, glass_z))
	var glass := MeshInstance3D.new()
	glass.mesh = st.commit()
	glass.material_override = _glass_material()
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)
	var centroid := Vector2.ZERO
	for corner in corners:
		centroid += corner
	centroid /= corners.size()
	for i in corners.size():
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % corners.size()]
		var edge: Vector2 = b - a
		var mid: Vector2 = (a + b) * 0.5
		var outward: Vector2 = Vector2(edge.y, -edge.x).normalized()
		if outward.dot(mid - centroid) < 0.0:
			outward = -outward
		var place: Vector2 = mid + outward * (GASKET * 0.5)
		var length: float = maxf(edge.length() - 0.004, 0.01)
		var gasket := _box(Vector3(length, GASKET, FRAME_DEPTH),
			Vector3(place.x, place.y, FRONT_Z + FRAME_GAP + FRAME_DEPTH * 0.5), _dark_material)
		gasket.rotation.z = edge.angle()
		gasket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_consoles() -> void:
	var size: Vector2 = PanelArt.CONSOLE_SIZE
	var top := Vector2(BULKHEAD_BOTTOM, FRONT_Z)
	var bottom: Vector2 = _console_bottom()
	var wedge := MeshInstance3D.new()
	wedge.mesh = CabinMesh.prism(PackedVector2Array([Vector2(top.y, top.x), Vector2(bottom.y, bottom.x),
		Vector2(FRONT_Z, bottom.x)]), HALF_WIDTH * 2.0)
	wedge.material_override = _wall_material
	wedge.transform = Transform3D(Basis(Vector3.BACK, Vector3.UP, Vector3.LEFT), Vector3(-HALF_WIDTH, 0.0, 0.0))
	add_child(wedge)
	var tilt: float = deg_to_rad(CONSOLE_TILT_DEG)
	var normal := Vector3(0.0, sin(tilt), cos(tilt))
	var center := Vector3(0.0, (top.x + bottom.x) * 0.5, (top.y + bottom.y) * 0.5) + normal * SURFACE_OFFSET
	_panel("console", size, PanelArt.CONSOLE, _facing(center, normal, Vector3(0.0, cos(tilt), -sin(tilt))))

	var console_size: Vector2 = PanelArt.SIDE_CONSOLE_SIZE
	var length: float = SIDE_CONSOLE_Z.y - SIDE_CONSOLE_Z.x
	for side: float in [-1.0, 1.0]:
		var width: float = HALF_WIDTH - SIDE_CONSOLE_INNER_X
		var middle := Vector3(side * (SIDE_CONSOLE_INNER_X + width * 0.5), SIDE_CONSOLE_TOP * 0.5,
			(SIDE_CONSOLE_Z.x + SIDE_CONSOLE_Z.y) * 0.5)
		_box(Vector3(width, SIDE_CONSOLE_TOP, length), middle, _wall_material)
		var along := Vector3.FORWARD if side < 0.0 else Vector3.BACK
		var basis := Basis(along, Vector3.UP.cross(along), Vector3.UP)
		var top_center := Vector3(middle.x, SIDE_CONSOLE_TOP + SURFACE_OFFSET, middle.z)
		_panel("side_console", console_size, PanelArt.SIDE_CONSOLE, Transform3D(basis, top_center))


func _build_side_panels() -> void:
	var yaw: float = deg_to_rad(BREAKER_PANEL_YAW_DEG)
	var inset: float = PanelArt.BREAKERS_SIZE.x * 0.5 * sin(yaw) + SURFACE_OFFSET
	for side: float in [-1.0, 1.0]:
		var normal := Vector3(-side * cos(yaw), 0.0, sin(yaw))
		var center := Vector3(side * (HALF_WIDTH - inset), BREAKER_PANEL_Y, BREAKER_PANEL_Z)
		_panel("breakers", PanelArt.BREAKERS_SIZE, PanelArt.BREAKERS, _facing(center, normal))
	_panel("ecs", PanelArt.ECS_SIZE, PanelArt.ECS, _facing(ECS_PANEL_CENTER, Vector3.LEFT))
	var canister := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = CANISTER_SIZE.x
	cylinder.bottom_radius = CANISTER_SIZE.x
	cylinder.height = CANISTER_SIZE.y
	canister.mesh = cylinder
	canister.material_override = _metal_material
	canister.position = CANISTER_POSITION
	add_child(canister)


func _build_mailbox() -> void:
	_mailbox = Node3D.new()
	_mailbox.position = MAILBOX_CENTER
	_mailbox.visible = false
	add_child(_mailbox)
	var size: Vector3 = MAILBOX_SIZE
	_mailbox_part(BoxMesh.new(), size, Vector3.ZERO, _plain_material(MAILBOX_CANISTER, 0.5))
	# The perforated face, in squares, toward the cabin (-X).
	var holes := _plain_material(Color.WHITE, 0.6)
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(MAILBOX_GRILLE_METAL)
	image.fill_rect(Rect2i(2, 2, 4, 4), MAILBOX_PERFORATED)
	holes.albedo_texture = ImageTexture.create_from_image(image)
	holes.uv1_triplanar = true
	holes.uv1_scale = Vector3.ONE / MAILBOX_HOLE_PITCH_M
	var cell: float = size.z / float(MAILBOX_GRILLE)
	for row in MAILBOX_GRILLE:
		for column in MAILBOX_GRILLE:
			var at := Vector3(-size.x * 0.5 - 0.002, (float(row) - 1.0) * cell, (float(column) - 1.0) * cell)
			_mailbox_part(BoxMesh.new(), Vector3(0.004, cell * 0.8, cell * 0.8), at, holes)
	# Gray tape across the face, two strips each way, and the bag round the back half.
	var tape := _plain_material(MAILBOX_TAPE, 0.65)
	for offset: float in [-0.045, 0.045]:
		_mailbox_part(BoxMesh.new(), Vector3(0.008, size.y + 0.01, 0.035), Vector3(-size.x * 0.5 - 0.004, 0.0, offset), tape)
		_mailbox_part(BoxMesh.new(), Vector3(0.008, 0.035, size.z + 0.01), Vector3(-size.x * 0.5 - 0.006, offset, 0.0), tape)
	var bag := _plain_material(MAILBOX_BAG, 0.25)
	bag.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bag.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mailbox_part(BoxMesh.new(), Vector3(size.x * 0.6, size.y + 0.04, size.z + 0.04), Vector3(size.x * 0.22, 0.0, 0.0), bag)
	# The suit hose down from the bottom of the bag.
	var hose := MeshInstance3D.new()
	hose.mesh = CabinMesh.tube(Vector3(0.02, -size.y * 0.5, 0.0), Vector3(0.0, -0.4, -0.02), Vector3(-0.22, -0.62, -0.14), 0.026, 14, 10)
	hose.material_override = _plain_material(MAILBOX_HOSE, 0.75)
	_mailbox.add_child(hose)


func _mailbox_part(mesh: BoxMesh, size: Vector3, at: Vector3, material: Material) -> void:
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	_mailbox.add_child(part)


func _build_overhead() -> void:
	var hole: Rect2 = OVERHEAD_WINDOW
	var y: float = HEIGHT + SHELL * 0.5
	var full_x := Vector2(-HALF_WIDTH, HALF_WIDTH)
	var strips: Array[Rect2] = [
		Rect2(full_x.x, FRONT_Z, full_x.y - full_x.x, hole.position.y - FRONT_Z),
		Rect2(full_x.x, hole.end.y, full_x.y - full_x.x, AFT_Z - hole.end.y),
		Rect2(full_x.x, hole.position.y, hole.position.x - full_x.x, hole.size.y),
		Rect2(hole.end.x, hole.position.y, full_x.y - hole.end.x, hole.size.y),
	]
	for strip in strips:
		_box(Vector3(strip.size.x, SHELL, strip.size.y), Vector3(strip.get_center().x, y, strip.get_center().y), _wall_material)
	var glass := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = hole.size
	glass.mesh = quad
	glass.material_override = _glass_material()
	glass.transform = _facing(Vector3(hole.get_center().x, HEIGHT + SHELL * 0.5, hole.get_center().y), Vector3.DOWN, Vector3.FORWARD)
	add_child(glass)
	var hatch_size: Vector2 = PanelArt.HATCH_SIZE
	var disc := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = hatch_size.x * 0.5
	cylinder.bottom_radius = hatch_size.x * 0.5
	cylinder.height = HATCH_DEPTH
	disc.mesh = cylinder
	disc.material_override = _metal_material
	disc.position = Vector3(HATCH_CENTER.x, HEIGHT - HATCH_DEPTH * 0.5, HATCH_CENTER.z)
	add_child(disc)
	var hatch_center := Vector3(HATCH_CENTER.x, HEIGHT - HATCH_DEPTH - SURFACE_OFFSET, HATCH_CENTER.z)
	_panel("hatch", hatch_size, PanelArt.HATCH, _facing(hatch_center, Vector3.DOWN, Vector3.FORWARD), Color(0.0, 0.0, 0.0, 0.0))


func _build_outside() -> void:
	_sun = DirectionalLight3D.new()
	_sun.light_energy = SUN_ENERGY
	_sun.light_cull_mask = OUTSIDE_LAYER
	add_child(_sun)
	var eye: Vector3 = PRESETS[START_PRESET]["position"]
	var left_window := Vector3((-WINDOW_OUTER_X - 2.0 * WINDOW_INNER_X) / 3.0, (2.0 * WINDOW_TOP + WINDOW_BOTTOM) / 3.0, FRONT_Z)
	var between_windows := Vector3(0.0, (WINDOW_TOP + WINDOW_BOTTOM) * 0.5, FRONT_Z)

	var earth := Node3D.new()
	earth.position = eye + (left_window - eye).normalized() * EARTH_DISTANCE
	earth.add_child(_sphere(EARTH_RADIUS, Bodies.earth_material()))
	earth.add_child(_sphere(EARTH_RADIUS * CLOUD_SCALE, Bodies.cloud_material()))
	var atmosphere := Bodies.atmosphere_material()
	if atmosphere.shader != null:
		earth.add_child(_sphere(EARTH_RADIUS * ATMOSPHERE_SCALE, atmosphere))
	add_child(earth)
	_bodies["earth"] = earth

	var moon := Node3D.new()
	moon.position = eye + (between_windows - eye).normalized() * MOON_DISTANCE
	moon.add_child(_sphere(MOON_RADIUS, Bodies.moon_material()))
	add_child(moon)
	_bodies["moon"] = moon


func _build_lights() -> void:
	for spec: Dictionary in LIGHTS:
		var light := OmniLight3D.new()
		light.position = spec["position"]
		light.light_color = LIGHT_COLOR
		light.omni_range = spec["range"]
		light.shadow_enabled = spec["shadow"]
		if spec["shadow"]:
			light.shadow_bias = 0.06
			light.shadow_normal_bias = 2.0
		light.light_cull_mask = CABIN_LAYER
		add_child(light)
		_lights.append(light)
		_base_energy[light] = spec["energy"]


func _build_floaters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Tuning.FLOAT_SEED

	var checklist := _floater(Vector3(-0.72, 1.42, -0.32))
	_box(Vector3(0.16, 0.01, 0.21), Vector3.ZERO, _plain_material(CHECKLIST_COVER, 0.9), checklist)
	_box(Vector3(0.012, 0.016, 0.21), Vector3(-0.08, 0.0, 0.0), _dark_material, checklist)
	checklist.rotation = Vector3(0.6, 0.4, 0.2)

	var bag := _floater(Vector3(0.74, 1.78, -0.5))
	var pouch := SphereMesh.new()
	pouch.radius = 0.1
	pouch.height = 0.2
	pouch.radial_segments = 16
	pouch.rings = 8
	var bag_mesh := MeshInstance3D.new()
	bag_mesh.mesh = pouch
	bag_mesh.material_override = _plain_material(BAG_FABRIC, 1.0)
	bag_mesh.scale = Vector3(1.25, 0.55, 0.9)
	bag.add_child(bag_mesh)
	var flap := _box(Vector3(0.2, 0.012, 0.09), Vector3(0.0, 0.05, 0.03), _plain_material(BAG_FABRIC.darkened(0.15), 1.0), bag)
	flap.rotation.x = -0.25

	var hose := _floater(Vector3(0.58, 1.08, -0.52))
	var tube := MeshInstance3D.new()
	tube.mesh = CabinMesh.tube(Vector3(-0.16, 0.0, 0.0), Vector3(0.0, 0.13, 0.06), Vector3(0.16, -0.03, 0.13), 0.018, 16, 10)
	var hose_material := _plain_material(HOSE_COLOR, 0.7)
	hose_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	tube.material_override = hose_material
	hose.add_child(tube)

	for floater: Floater in [checklist, bag, hose]:
		floater.setup(rng)


func _build_camera() -> void:
	camera = CabinCamera.new()
	camera.fov = CAMERA_FOV_DEG
	camera.near = CAMERA_NEAR
	camera.far = CAMERA_FAR
	camera.current = true
	add_child(camera)
	var transforms: Dictionary = {}
	for preset_name: String in PRESETS:
		var spec: Dictionary = PRESETS[preset_name]
		var from: Vector3 = spec["position"]
		transforms[preset_name] = Transform3D(Basis.looking_at(spec["target"] - from, Vector3.UP), from)
	camera.setup(transforms, START_PRESET)


# --- Pieces ---

## A textured instrument panel quad, plus its lamps and placards from the same layout.
func _panel(key: String, size: Vector2, layout: Array, where: Transform3D, background: Color = PanelArt.FACE) -> MeshInstance3D:
	var panel := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	panel.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_texture = PanelArt.texture(key, size, layout, background)
	material.roughness = 0.8
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if background.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	panel.material_override = material
	panel.transform = where
	add_child(panel)
	for element: Dictionary in layout:
		match str(element["kind"]):
			"lamp":
				_add_lamp(panel, size, element)
			"placard":
				_add_placard(panel, size, element)
	return panel


func _add_lamp(panel: MeshInstance3D, size: Vector2, element: Dictionary) -> void:
	var lamp_name: String = element["name"]
	if not _lamps.has(lamp_name):
		var color: Color = PanelArt.lamp_color(element["color"])
		var lit := StandardMaterial3D.new()
		lit.albedo_color = PanelArt.RED_UNLIT if element["color"] == "red" else PanelArt.AMBER_UNLIT
		lit.emission_enabled = true
		lit.emission = color
		lit.emission_energy_multiplier = 0.0
		_lamps[lamp_name] = lit
	var w: float = element["w"]
	var h: float = element["h"]
	var lamp := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h) * 0.86
	lamp.mesh = quad
	lamp.material_override = _lamps[lamp_name]
	lamp.position = _on_panel(size, float(element["x"]) + w * 0.5, float(element["y"]) + h * 0.5)
	panel.add_child(lamp)


func _add_placard(panel: MeshInstance3D, size: Vector2, element: Dictionary) -> void:
	var placard := Label3D.new()
	placard.text = element["text"]
	placard.font = UiStyle.font(UiStyle.FONT_TITLE)
	placard.font_size = PLACARD_FONT_SIZE
	placard.pixel_size = PLACARD_PIXEL_SIZE
	placard.modulate = UiStyle.PLACARD_WHITE
	placard.outline_size = 0
	placard.shaded = true
	placard.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	placard.position = _on_panel(size, element["x"], element["y"])
	panel.add_child(placard)


## A point on a panel quad, from layout metres (origin top left, y down) to the quad's local space.
func _on_panel(size: Vector2, x: float, y: float) -> Vector3:
	return Vector3(x - size.x * 0.5, size.y * 0.5 - y, SURFACE_OFFSET)


func _floater(where: Vector3) -> Floater:
	var floater := Floater.new()
	floater.position = where
	add_child(floater)
	return floater


func _box(size: Vector3, where: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.material_override = material
	box.position = where
	(parent if parent != null else self).add_child(box)
	return box


func _sphere(radius: float, material: Material) -> MeshInstance3D:
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 64
	mesh.rings = 32
	sphere.mesh = mesh
	sphere.material_override = material
	sphere.layers = OUTSIDE_LAYER
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sphere


## A transform whose +Z faces along normal, with local +Y as close to up as possible.
func _facing(where: Vector3, normal: Vector3, up: Vector3 = Vector3.UP) -> Transform3D:
	return Transform3D(Basis.looking_at(-normal, up), where)


## (y, z) of the main console's bottom edge.
func _console_bottom() -> Vector2:
	var tilt: float = deg_to_rad(CONSOLE_TILT_DEG)
	var length: float = PanelArt.CONSOLE_SIZE.y
	return Vector2(BULKHEAD_BOTTOM - length * cos(tilt), FRONT_Z + length * sin(tilt))


func _plain_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _glass_material() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.5, 0.6, 0.7, 0.03)
	glass.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	return glass


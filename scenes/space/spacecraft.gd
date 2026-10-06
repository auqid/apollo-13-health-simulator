extends RefCounted
## The Apollo 13 spacecraft for the exterior shots, from simple shapes at about real size in
## metres: the Service Module with the Sector 4 panel that blew off and the bay behind it, the
## Command Module Odyssey, and the Lunar Module Aquarius docked roof first to Odyssey's nose.
## Stack axis: -Z is the Service Module engine, +Z is Aquarius's footpads. Sector 4 faces +X.
## Construct with a parent node; the fields below are what the exterior shots animate.

const SpaceMesh := preload("res://scenes/space/space_mesh.gd")
const CabinMesh := preload("res://scenes/cabin/cabin_mesh.gd")

# --- Service Module ---
const SM_RADIUS := 1.96
const SM_AFT_Z := -3.0
const SM_FORE_Z := 2.0
## Sector 4: the panel covers this angle either side of +X, from BAY_AFT_Z to BAY_FORE_Z.
const BAY_HALF_ANGLE := 0.52
const BAY_AFT_Z := -2.7
const BAY_FORE_Z := 1.75
const NOZZLE_EXIT_Z := -6.0
# --- Command Module, built with its base at z = 0 ---
const CM_BASE_Z := 2.1
const CM_TOP := 3.45
# --- Lunar Module, built upright (+Y toward Odyssey, +X its front), tunnel top at the origin ---
const LM_DOCK_Z := 5.6
const LM_ENGINE_EXIT_Y := -5.1
const LM_WINDOW_Y := -1.2

const WHITE := Color(0.86, 0.86, 0.84)
const SILVER := Color(0.6, 0.62, 0.65)
## Odyssey's skin after reentry: the heat browned and streaked it.
const SCORCHED := Color(0.4, 0.36, 0.31)
const RADIATOR := Color(0.62, 0.64, 0.66)
const DARK := Color(0.1, 0.1, 0.11)
const ENGINE := Color(0.26, 0.25, 0.24)
const ENGINE_BELL := Color(0.55, 0.55, 0.56)
const HEAT_SHIELD := Color(0.2, 0.16, 0.13)
const LM_GREY := Color(0.44, 0.44, 0.45)
const LM_BLACK := Color(0.07, 0.07, 0.08)
const FOIL_GOLD := Color(0.86, 0.62, 0.26)
const TANK := Color(0.82, 0.82, 0.8)
const FUEL_CELL := Color(0.6, 0.6, 0.62)
const WINDOW_GLASS := Color(0.05, 0.06, 0.07)
const WINDOW_GLOW := Color(1.0, 0.8, 0.5)

static var _foil_bumps: NoiseTexture2D

var sm: Node3D
var odyssey: Node3D
var aquarius: Node3D
## The Sector 4 panel. Its origin is the middle of the panel, so it can tumble about it.
var panel: Node3D
## What the open bay shows once the panel is gone: tanks, fuel cells and torn insulation.
var bay: Node3D
var cm_windows: Array[StandardMaterial3D] = []
var lm_windows: Array[StandardMaterial3D] = []
var heat_shield: StandardMaterial3D
## Points the shots aim at or emit from, in the stack's space.
var bay_center := Vector3(SM_RADIUS, 0.0, (BAY_AFT_Z + BAY_FORE_Z) * 0.5)
var tunnel_center := Vector3(0.0, 0.0, LM_DOCK_Z)
var lm_engine_exit := Vector3(0.0, 0.0, LM_DOCK_Z - LM_ENGINE_EXIT_Y)
var lm_front := Vector3(1.3, 0.0, LM_DOCK_Z - LM_WINDOW_Y)


func _init(parent: Node3D) -> void:
	sm = Node3D.new()
	odyssey = Node3D.new()
	aquarius = Node3D.new()
	parent.add_child(sm)
	parent.add_child(odyssey)
	parent.add_child(aquarius)
	_build_service_module()
	var cm := Node3D.new()
	cm.position = Vector3(0.0, 0.0, CM_BASE_Z)
	odyssey.add_child(cm)
	heat_shield = build_command_module(cm, cm_windows)
	var lm := Node3D.new()
	# Upright Aquarius: +Y toward Odyssey (stack -Z), +X its front (stack +X).
	lm.transform = Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), Vector3(0.0, 0.0, LM_DOCK_Z))
	aquarius.add_child(lm)
	_build_lunar_module(lm)


## Odyssey alone, apex up (+Y), for the reentry and splashdown. Returns the heat shield material.
static func build_capsule(parent: Node3D, windows: Array[StandardMaterial3D], skin_color: Color = SILVER) -> StandardMaterial3D:
	var cm := Node3D.new()
	cm.transform = Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), Vector3.ZERO)
	parent.add_child(cm)
	return build_command_module(cm, windows, skin_color)


## The Command Module along +Z with its heat shield at z = 0. Returns the heat shield material.
static func build_command_module(cm: Node3D, windows: Array[StandardMaterial3D], skin_color: Color = SILVER) -> StandardMaterial3D:
	var skin := paint(skin_color, 0.42, 0.65)
	var shield := paint(HEAT_SHIELD, 0.9)
	shield.emission_enabled = true
	shield.emission = Color(1.0, 0.45, 0.12)
	shield.emission_energy_multiplier = 0.0
	SpaceMesh.add_mesh(cm, SpaceMesh.lathe(PackedVector2Array([Vector2(1.96, 0.0), Vector2(1.98, 0.12),
		Vector2(0.56, 3.0), Vector2(0.42, 3.2), Vector2(0.0, 3.26)]), 28), skin)
	SpaceMesh.add_mesh(cm, SpaceMesh.lathe(PackedVector2Array([Vector2(0.0, -0.14), Vector2(1.1, -0.09),
		Vector2(1.96, 0.0)]), 28), shield)
	SpaceMesh.add_rod(cm, Vector3(0.0, 0.0, 3.2), Vector3(0.0, 0.0, CM_TOP), 0.42, paint(DARK, 0.6), 16)
	# Two side windows and two rendezvous windows, glowing while Odyssey is powered.
	for spot: Vector2 in [Vector2(0.35, 2.1), Vector2(-0.35, 2.1), Vector2(2.8, 1.25), Vector2(-2.8, 1.25)]:
		var glass := paint(WINDOW_GLASS, 0.15, 0.2)
		glass.emission_enabled = true
		glass.emission = WINDOW_GLOW
		glass.emission_energy_multiplier = 0.0
		windows.append(glass)
		var height: float = spot.y
		var radius: float = lerpf(1.98, 0.56, (height - 0.12) / 2.88) + 0.012
		var outward := Vector3(cos(spot.x) * 2.88, sin(spot.x) * 2.88, 1.42).normalized()
		var where := Vector3(cos(spot.x) * radius, sin(spot.x) * radius, height)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.34, 0.3, 0.02)
		SpaceMesh.add_mesh(cm, mesh, glass, Transform3D(Basis.looking_at(-outward, Vector3.BACK), where))
	return shield


static func paint(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


## Crinkled gold foil, like the blankets on Aquarius's descent stage.
static func foil(color: Color = FOIL_GOLD) -> StandardMaterial3D:
	var material := paint(color, 0.38, 0.75)
	if _foil_bumps == null:
		var noise := FastNoiseLite.new()
		noise.seed = 1304
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.frequency = 0.045
		_foil_bumps = NoiseTexture2D.new()
		_foil_bumps.width = 256
		_foil_bumps.height = 256
		_foil_bumps.seamless = true
		_foil_bumps.noise = noise
		_foil_bumps.as_normal_map = true
		_foil_bumps.bump_strength = 6.0
	material.normal_enabled = true
	material.normal_texture = _foil_bumps
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE * 0.6
	return material


func _build_service_module() -> void:
	var white := paint(WHITE, 0.5, 0.1)
	var radiator := paint(RADIATOR, 0.3, 0.6)
	var dark := paint(DARK, 0.7)
	# Hull: closed rings fore and aft, and the middle open where Sector 4 is.
	SpaceMesh.add_mesh(sm, SpaceMesh.lathe(PackedVector2Array([Vector2(SM_RADIUS, SM_AFT_Z), Vector2(SM_RADIUS, BAY_AFT_Z)]), 36), white)
	SpaceMesh.add_mesh(sm, SpaceMesh.lathe(PackedVector2Array([Vector2(SM_RADIUS, BAY_FORE_Z), Vector2(SM_RADIUS, SM_FORE_Z)]), 36), white)
	SpaceMesh.add_mesh(sm, SpaceMesh.lathe(PackedVector2Array([Vector2(SM_RADIUS, BAY_AFT_Z), Vector2(SM_RADIUS, BAY_FORE_Z)]),
		30, BAY_HALF_ANGLE, TAU - BAY_HALF_ANGLE), white)
	# Radiator panels in two other sectors.
	for middle: float in [2.1, 4.2]:
		SpaceMesh.add_mesh(sm, SpaceMesh.lathe(PackedVector2Array([Vector2(SM_RADIUS + 0.015, -1.6), Vector2(SM_RADIUS + 0.015, 1.4)]),
			6, middle - 0.35, middle + 0.35), radiator)
	# Aft bulkhead, the main engine and its bell.
	var bulkhead := CylinderMesh.new()
	bulkhead.top_radius = SM_RADIUS
	bulkhead.bottom_radius = SM_RADIUS
	bulkhead.height = 0.06
	bulkhead.radial_segments = 36
	SpaceMesh.add_mesh(sm, bulkhead, dark, Transform3D(SpaceMesh.along_y(Vector3.BACK), Vector3(0.0, 0.0, SM_AFT_Z)))
	SpaceMesh.add_mesh(sm, bulkhead, dark, Transform3D(SpaceMesh.along_y(Vector3.BACK), Vector3(0.0, 0.0, SM_FORE_Z)))
	var engine := paint(ENGINE, 0.45, 0.5)
	SpaceMesh.add_mesh(sm, SpaceMesh.lathe(PackedVector2Array([Vector2(0.5, -3.55), Vector2(0.62, -3.25), Vector2(0.62, SM_AFT_Z)]), 20), engine)
	var bell := paint(ENGINE_BELL, 0.35, 0.7)
	bell.cull_mode = BaseMaterial3D.CULL_DISABLED
	SpaceMesh.add_mesh(sm, SpaceMesh.lathe(PackedVector2Array([Vector2(1.22, NOZZLE_EXIT_Z), Vector2(1.0, -5.1),
		Vector2(0.75, -4.3), Vector2(0.5, -3.55)]), 28), bell)
	# Reaction control quads at the four corners, and the high-gain antenna next to Sector 4.
	for corner: float in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		_rcs_quad(sm, Vector3(cos(corner) * SM_RADIUS, sin(corner) * SM_RADIUS, 1.25), Vector3(cos(corner), sin(corner), 0.0), dark, white)
	_high_gain_antenna(radiator, dark)
	_build_panel(white)
	_build_bay(dark)


## Four small thrusters on a housing: two along the ship's axis and two to the sides.
func _rcs_quad(parent: Node3D, base: Vector3, outward: Vector3, dark: Material, housing: Material) -> void:
	var axis: Vector3 = Vector3.BACK if absf(outward.dot(Vector3.BACK)) < 0.9 else Vector3.UP
	var frame := Basis.looking_at(-outward, axis)
	SpaceMesh.add_mesh(parent, _box_mesh(Vector3(0.42, 0.62, 0.22)), housing, Transform3D(frame, base + outward * 0.1))
	var tip: Vector3 = base + outward * 0.22
	var sideways: Vector3 = outward.cross(axis).normalized()
	for direction: Vector3 in [axis, -axis, sideways, -sideways]:
		SpaceMesh.add_rod(parent, tip, tip + direction * 0.22, 0.035, dark, 6, 0.07)


func _high_gain_antenna(dish_material: Material, dark: Material) -> void:
	var angle: float = -0.95
	var root := Vector3(cos(angle) * SM_RADIUS, sin(angle) * SM_RADIUS, SM_AFT_Z + 0.35)
	var outward := Vector3(cos(angle), sin(angle), 0.0)
	var head: Vector3 = root + outward * 1.6 + Vector3(0.0, 0.0, -0.9)
	SpaceMesh.add_rod(sm, root, head, 0.05, dark, 6)
	var dish := SpaceMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.2, 0.03), Vector2(0.4, 0.12)]), 14)
	for offset: Vector3 in [Vector3(0.3, 0.3, 0.0), Vector3(-0.3, 0.3, 0.0), Vector3(0.3, -0.3, 0.0), Vector3(-0.3, -0.3, 0.0)]:
		var facing := Basis.looking_at(outward + Vector3(0.0, 0.0, -0.4), Vector3.BACK)
		SpaceMesh.add_mesh(sm, dish, dish_material, Transform3D(facing, head + facing * offset))


func _build_panel(white: Material) -> void:
	panel = Node3D.new()
	panel.position = bay_center
	sm.add_child(panel)
	var skin := (white as StandardMaterial3D).duplicate() as StandardMaterial3D
	skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shell := SpaceMesh.lathe(PackedVector2Array([Vector2(SM_RADIUS + 0.01, BAY_AFT_Z), Vector2(SM_RADIUS + 0.01, BAY_FORE_Z)]),
		8, -BAY_HALF_ANGLE, BAY_HALF_ANGLE)
	SpaceMesh.add_mesh(panel, shell, skin, Transform3D(Basis.IDENTITY, -bay_center))


func _build_bay(dark: Material) -> void:
	bay = Node3D.new()
	sm.add_child(bay)
	var cavity := paint(Color(0.05, 0.05, 0.05), 0.9)
	cavity.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Back wall and the two radial walls of the sector.
	SpaceMesh.add_mesh(bay, SpaceMesh.lathe(PackedVector2Array([Vector2(0.6, BAY_AFT_Z), Vector2(0.6, BAY_FORE_Z)]),
		6, -BAY_HALF_ANGLE, BAY_HALF_ANGLE), cavity)
	for side: float in [-1.0, 1.0]:
		var wall := Node3D.new()
		wall.rotation.z = side * BAY_HALF_ANGLE
		bay.add_child(wall)
		SpaceMesh.add_box(wall, Vector3(SM_RADIUS - 0.6, 0.03, BAY_FORE_Z - BAY_AFT_Z), Vector3((SM_RADIUS + 0.6) * 0.5, 0.0, (BAY_AFT_Z + BAY_FORE_Z) * 0.5), cavity)
	# Shelves, then three fuel cells on top, two oxygen tanks and two hydrogen tanks below.
	var shelf := paint(Color(0.3, 0.3, 0.3), 0.8)
	shelf.cull_mode = BaseMaterial3D.CULL_DISABLED
	for shelf_z: float in [0.55, -0.85]:
		SpaceMesh.add_mesh(bay, SpaceMesh.lathe(PackedVector2Array([Vector2(0.6, shelf_z), Vector2(SM_RADIUS - 0.05, shelf_z)]),
			6, -BAY_HALF_ANGLE, BAY_HALF_ANGLE, false), shelf)
	var cell := paint(FUEL_CELL, 0.35, 0.6)
	for offset: float in [-0.42, 0.0, 0.42]:
		SpaceMesh.add_rod(bay, Vector3(1.35, offset, 0.62), Vector3(1.35, offset, 1.6), 0.2, cell, 12)
	var tank := paint(TANK, 0.45, 0.2)
	for offset: float in [-0.36, 0.36]:
		SpaceMesh.add_sphere(bay, 0.32, Vector3(1.35, offset, -0.2), tank)
		SpaceMesh.add_sphere(bay, 0.4, Vector3(1.3, offset * 1.1, -1.75), tank)
	# Shreds of insulation along the torn edges.
	var shreds := foil(Color(0.75, 0.6, 0.35))
	shreds.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rng := RandomNumberGenerator.new()
	rng.seed = 1970
	for i in 9:
		var along: float = lerpf(BAY_AFT_Z + 0.3, BAY_FORE_Z - 0.3, float(i) / 8.0)
		var side: float = BAY_HALF_ANGLE * (1.0 if i % 2 == 0 else -1.0)
		var where := Vector3(cos(side) * SM_RADIUS, sin(side) * SM_RADIUS, along)
		SpaceMesh.add_box(bay, Vector3(0.02, rng.randf_range(0.2, 0.45), rng.randf_range(0.15, 0.35)), where, shreds,
			Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6), side + rng.randf_range(-0.4, 0.4)))
	SpaceMesh.add_rod(bay, Vector3(0.6, 0.0, BAY_FORE_Z), Vector3(0.6, 0.0, BAY_AFT_Z), 0.03, dark)


func _build_lunar_module(lm: Node3D) -> void:
	var grey := paint(LM_GREY, 0.55, 0.35)
	var black := paint(LM_BLACK, 0.8)
	var gold := foil()
	var dark := paint(DARK, 0.6, 0.3)
	# Docking tunnel, roof, then the front cabin with its angled upper corners.
	SpaceMesh.add_rod(lm, Vector3.ZERO, Vector3(0.0, -0.75, 0.0), 0.42, dark, 16)
	SpaceMesh.add_box(lm, Vector3(1.9, 0.22, 1.5), Vector3(-0.25, -0.75, 0.0), black)
	var front := PackedVector2Array([Vector2(-1.15, -2.55), Vector2(1.15, -2.55), Vector2(1.15, -1.45),
		Vector2(0.72, -0.82), Vector2(-0.72, -0.82), Vector2(-1.15, -1.45)])
	var cabin_frame := Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT)
	SpaceMesh.add_mesh(lm, CabinMesh.prism(front, 1.3), grey, Transform3D(cabin_frame, Vector3(1.2, 0.0, 0.0)))
	SpaceMesh.add_box(lm, Vector3(1.15, 1.75, 2.0), Vector3(-0.45, -1.65, 0.0), black)
	SpaceMesh.add_box(lm, Vector3(0.95, 1.25, 1.7), Vector3(-1.45, -1.55, 0.0), grey)
	# The two triangular front windows and the hatch.
	for side: float in [-1.0, 1.0]:
		var glass := paint(WINDOW_GLASS, 0.15, 0.2)
		glass.emission_enabled = true
		glass.emission = WINDOW_GLOW
		glass.emission_energy_multiplier = 0.0
		lm_windows.append(glass)
		var triangle := PackedVector2Array([Vector2(side * 0.98, -1.48), Vector2(side * 0.3, -0.92), Vector2(side * 0.3, -1.48)])
		SpaceMesh.add_mesh(lm, SpaceMesh.plate(triangle), glass, Transform3D(cabin_frame, Vector3(1.206, 0.0, 0.0)))
	SpaceMesh.add_box(lm, Vector3(0.02, 0.78, 0.78), Vector3(1.21, -2.0, 0.0), dark)
	# Thruster quads on the four corners, the rendezvous radar and the steerable antenna.
	for corner: Vector2 in [Vector2(0.55, 1.0), Vector2(0.55, -1.0), Vector2(-1.3, 1.0), Vector2(-1.3, -1.0)]:
		var base := Vector3(corner.x, -1.55, corner.y * 1.15)
		_rcs_quad(lm, base, Vector3(0.0, 0.0, corner.y), dark, grey)
	var dish := SpaceMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.25, 0.04), Vector2(0.5, 0.15)]), 16)
	var radar_at := Vector3(0.75, -0.62, 0.55)
	SpaceMesh.add_rod(lm, Vector3(0.75, -0.75, 0.55), radar_at, 0.05, dark)
	SpaceMesh.add_mesh(lm, dish, grey, Transform3D(Basis.looking_at(-Vector3(1.0, 1.0, 0.2), Vector3.UP), radar_at))
	var antenna_at := Vector3(-0.9, -0.3, -1.05)
	SpaceMesh.add_rod(lm, Vector3(-0.9, -0.9, -0.85), antenna_at, 0.04, dark)
	SpaceMesh.add_mesh(lm, dish, grey, Transform3D(Basis.looking_at(-Vector3(-0.3, 1.0, -0.4), Vector3.UP), antenna_at).scaled_local(Vector3.ONE * 0.7))
	# Descent stage: a gold octagon, its black base, the engine bell, and four legs.
	var octagon := CylinderMesh.new()
	octagon.top_radius = 2.25
	octagon.bottom_radius = 2.25
	octagon.height = 1.65
	octagon.radial_segments = 8
	octagon.rings = 1
	SpaceMesh.add_mesh(lm, octagon, gold, Transform3D(Basis(Vector3.UP, PI / 8.0), Vector3(0.0, -3.4, 0.0)))
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 2.0
	base_mesh.bottom_radius = 1.85
	base_mesh.height = 0.2
	base_mesh.radial_segments = 8
	SpaceMesh.add_mesh(lm, base_mesh, black, Transform3D(Basis(Vector3.UP, PI / 8.0), Vector3(0.0, -4.32, 0.0)))
	var nozzle := paint(ENGINE, 0.4, 0.5)
	nozzle.cull_mode = BaseMaterial3D.CULL_DISABLED
	SpaceMesh.add_mesh(lm, SpaceMesh.lathe(PackedVector2Array([Vector2(0.35, 0.0), Vector2(0.55, 0.4), Vector2(0.78, 0.7)]), 18),
		nozzle, Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN), Vector3(0.0, -4.4, 0.0)))
	var strut := paint(Color(0.7, 0.7, 0.72), 0.35, 0.7)
	var pad := CylinderMesh.new()
	pad.top_radius = 0.45
	pad.bottom_radius = 0.42
	pad.height = 0.14
	pad.radial_segments = 14
	for out: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var side: Vector3 = out.cross(Vector3.UP)
		var foot: Vector3 = out * 4.1 + Vector3(0.0, -5.45, 0.0)
		var knee: Vector3 = out * 3.25 + Vector3(0.0, -4.45, 0.0)
		SpaceMesh.add_rod(lm, out * 2.1 + Vector3(0.0, -2.75, 0.0), foot, 0.075, gold)
		for lean: float in [-1.0, 1.0]:
			SpaceMesh.add_rod(lm, out * 1.85 + side * lean * 0.85 + Vector3(0.0, -4.15, 0.0), knee, 0.045, strut)
		SpaceMesh.add_mesh(lm, pad, strut, Transform3D(Basis.IDENTITY, foot + Vector3(0.0, -0.1, 0.0)))


static func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

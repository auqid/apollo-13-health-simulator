extends RefCounted
## The Apollo 13 spacecraft for the exterior shots, from simple shapes at about real size in
## metres: the Service Module with the Sector 4 panel that blew off and the bay behind it, the
## Command Module Odyssey, and the Lunar Module Aquarius docked roof first to Odyssey's nose.
## Stack axis: -Z is the Service Module engine, +Z is Aquarius's footpads. Sector 4 faces +X.
## Construct with a parent node; the fields below are what the exterior shots animate.
## Finishes follow the 1970 photos: a polished aluminium Service Module with white radiator
## bands, Aquarius's ascent stage mostly aluminized with dark panels, and gold foil below it.

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
## The white band of power system radiators round the forward end, and the two environmental
## control radiators lower down, each this wide.
const EPS_BAND_AFT_Z := 0.95
const ECS_PANEL_HALF_ANGLE := 0.35
const ECS_PANEL_ANGLES: Array[float] = [2.1, 4.2]
const RADIATOR_RIBS := 14.0
# --- Command Module, built with its base at z = 0 ---
const CM_BASE_Z := 2.1
const CM_TOP := 3.45
## Where the cone's surface is at a height: radius from 1.98 at the base to 0.56 at 3.0 m.
const CM_CONE_BASE := Vector2(1.98, 0.12)
const CM_CONE_TOP := Vector2(0.56, 3.0)
# --- Lunar Module, built upright (+Y toward Odyssey, +X its front), tunnel top at the origin ---
const LM_DOCK_Z := 5.6
const LM_ENGINE_EXIT_Y := -5.1
const LM_WINDOW_Y := -1.2
## Landing gear: each leg hinges on the descent stage at LEG_HINGE, its footpad is LEG_FOOT
## further out and down when deployed, and stowed it hangs folded by LEG_STOW_RAD. The front
## leg (+X) carries the ladder; the other three trail contact probes once deployed.
const LEG_DIRECTIONS: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
const LEG_HINGE := Vector2(2.1, -2.75)
const LEG_FOOT := Vector2(2.0, -2.7)
const LEG_STOW_RAD := -0.567
const PROBE_LENGTH := 1.6
const LADDER_RUNG_STEP := 0.3

const WHITE := Color(0.86, 0.86, 0.84)
const SILVER := Color(0.6, 0.62, 0.65)
## Odyssey's skin after reentry: the heat browned and streaked it.
const SCORCHED := Color(0.4, 0.36, 0.31)
const SM_HULL := Color(0.74, 0.75, 0.77)
const RADIATOR := Color(0.9, 0.9, 0.88)
const RADIATOR_RIB := Color(0.66, 0.67, 0.69)
const DARK := Color(0.1, 0.1, 0.11)
const ENGINE := Color(0.26, 0.25, 0.24)
const ENGINE_BELL := Color(0.55, 0.55, 0.56)
const THRUSTER := Color(0.3, 0.29, 0.28)
const HEAT_SHIELD := Color(0.2, 0.16, 0.13)
const LM_ALUMINIZED := Color(0.7, 0.7, 0.68)
const LM_GREY := Color(0.44, 0.44, 0.45)
const LM_BLACK := Color(0.07, 0.07, 0.08)
const FOIL_GOLD := Color(0.86, 0.62, 0.26)
const FOIL_SILVER := Color(0.82, 0.82, 0.8)
const STRUT := Color(0.7, 0.7, 0.72)
const TANK := Color(0.82, 0.82, 0.8)
const FUEL_CELL := Color(0.6, 0.6, 0.62)
const WINDOW_GLASS := Color(0.05, 0.06, 0.07)
const WINDOW_GLOW := Color(1.0, 0.8, 0.5)
## Aquarius's cabin was powered down to the minimum, so its windows glow dimmer than Odyssey's.
const LM_WINDOW_GLOW := Color(0.22, 0.17, 0.1)

static var _foil_bumps: NoiseTexture2D
static var _scorch_streaks: NoiseTexture2D
static var _radiator_ribs: GradientTexture2D
static var _bell: ArrayMesh

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
## The four legs (each pivots at its hinge), and the parts that only show stowed or deployed.
var _legs: Array[Node3D] = []
var _gear_deployed: Node3D
var _gear_stowed: Node3D


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
	set_landing_gear(true)


## Aquarius's legs: folded as launched, or down and locked (Haise, GET 061:00:10).
func set_landing_gear(deployed: bool) -> void:
	for i in _legs.size():
		var side: Vector3 = LEG_DIRECTIONS[i].cross(Vector3.UP).normalized()
		_legs[i].basis = Basis.IDENTITY if deployed else Basis(side, LEG_STOW_RAD)
	_gear_deployed.visible = deployed
	_gear_stowed.visible = not deployed


## Odyssey alone, apex up (+Y), for the reentry and splashdown. Returns the heat shield material.
static func build_capsule(parent: Node3D, windows: Array[StandardMaterial3D], skin_color: Color = SILVER) -> StandardMaterial3D:
	var cm := Node3D.new()
	cm.transform = Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), Vector3.ZERO)
	parent.add_child(cm)
	return build_command_module(cm, windows, skin_color)


## The Command Module along +Z with its heat shield at z = 0. Returns the heat shield material.
## A SCORCHED skin is the ablator after reentry, rough and streaked; otherwise it is the
## reflective tape the capsule flew in.
static func build_command_module(cm: Node3D, windows: Array[StandardMaterial3D], skin_color: Color = SILVER) -> StandardMaterial3D:
	var scorched: bool = skin_color == SCORCHED
	var skin := paint(skin_color, 0.85 if scorched else 0.34, 0.1 if scorched else 0.7)
	if scorched:
		skin.albedo_texture = _scorch()
		skin.uv1_scale = Vector3(10.0, 1.0, 1.0)
	var shield := paint(HEAT_SHIELD, 0.9)
	shield.emission_enabled = true
	shield.emission = Color(1.0, 0.45, 0.12)
	shield.emission_energy_multiplier = 0.0
	SpaceMesh.add_mesh(cm, SpaceMesh.lathe(PackedVector2Array([Vector2(1.96, 0.0), CM_CONE_BASE,
		CM_CONE_TOP, Vector2(0.42, 3.2), Vector2(0.0, 3.26)]), 32), skin)
	SpaceMesh.add_mesh(cm, SpaceMesh.lathe(PackedVector2Array([Vector2(0.0, -0.14), Vector2(1.1, -0.09),
		Vector2(1.96, 0.0)]), 32), shield)
	var dark := paint(DARK, 0.6)
	SpaceMesh.add_rod(cm, Vector3(0.0, 0.0, 3.2), Vector3(0.0, 0.0, CM_TOP), 0.42, dark, 16)
	# The crew hatch between the side windows, with its own small window.
	var hatch := paint(skin_color.darkened(0.12), skin.roughness, skin.metallic)
	hatch.albedo_texture = skin.albedo_texture
	hatch.uv1_scale = skin.uv1_scale
	SpaceMesh.add_mesh(cm, _cone_patch(-0.2, 0.2, 1.15, 2.35, 0.012), hatch)
	# Two side windows, two rendezvous windows and the hatch window, glowing while powered.
	for spot: Vector3 in [Vector3(0.35, 2.1, 0.34), Vector3(-0.35, 2.1, 0.34), Vector3(2.8, 1.25, 0.34),
			Vector3(-2.8, 1.25, 0.34), Vector3(0.0, 1.85, 0.2)]:
		var glass := paint(WINDOW_GLASS, 0.15, 0.2)
		glass.emission_enabled = true
		glass.emission = WINDOW_GLOW
		glass.emission_energy_multiplier = 0.0
		windows.append(glass)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(spot.z, spot.z * 0.88, 0.02)
		SpaceMesh.add_mesh(cm, mesh, glass, _on_cone(spot.x, spot.y, 0.024))
		var frame := BoxMesh.new()
		frame.size = Vector3(spot.z + 0.08, spot.z * 0.88 + 0.08, 0.02)
		SpaceMesh.add_mesh(cm, frame, dark, _on_cone(spot.x, spot.y, 0.014))
	# Reaction control ports in pairs round the cone: pitch and yaw near the top, roll lower down.
	for port: Vector2 in [Vector2(PI * 0.5, 2.55), Vector2(-PI * 0.5, 2.55), Vector2(PI, 2.55),
			Vector2(PI * 0.75, 1.55), Vector2(-PI * 0.75, 1.55)]:
		for offset: float in [-0.09, 0.09]:
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.1, 0.07, 0.02)
			SpaceMesh.add_mesh(cm, mesh, dark, _on_cone(port.x + offset / _cone_radius(port.y), port.y, 0.016))
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


## The Service Module's polished aluminium skin.
static func hull() -> StandardMaterial3D:
	return paint(SM_HULL, 0.32, 0.6)


## Streaks running from the heat shield to the apex, light and dark, for the scorched skin.
static func _scorch() -> NoiseTexture2D:
	if _scorch_streaks == null:
		var noise := FastNoiseLite.new()
		noise.seed = 1704
		noise.frequency = 0.02
		noise.fractal_octaves = 3
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.5, 0.46, 0.42))
		ramp.set_color(1, Color(1.0, 0.97, 0.92))
		_scorch_streaks = NoiseTexture2D.new()
		_scorch_streaks.width = 256
		_scorch_streaks.height = 256
		_scorch_streaks.seamless = true
		_scorch_streaks.noise = noise
		_scorch_streaks.color_ramp = ramp
	return _scorch_streaks


## Ribbed radiator panels: white with grey tube lines along the length.
static func _radiator() -> StandardMaterial3D:
	if _radiator_ribs == null:
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.18, 0.32, 1.0])
		ramp.colors = PackedColorArray([RADIATOR_RIB, RADIATOR, RADIATOR, RADIATOR])
		_radiator_ribs = GradientTexture2D.new()
		_radiator_ribs.gradient = ramp
		_radiator_ribs.width = 64
		_radiator_ribs.height = 4
	var material := paint(Color.WHITE, 0.55, 0.05)
	material.albedo_texture = _radiator_ribs
	return material


## A small rocket bell, open end along +Z.
static func _thruster_bell() -> ArrayMesh:
	if _bell == null:
		_bell = SpaceMesh.lathe(PackedVector2Array([Vector2(0.03, 0.0), Vector2(0.042, 0.09), Vector2(0.075, 0.2)]), 10)
	return _bell


static func _cone_radius(height: float) -> float:
	return lerpf(CM_CONE_BASE.x, CM_CONE_TOP.x, (height - CM_CONE_BASE.y) / (CM_CONE_TOP.y - CM_CONE_BASE.y))


## A flat part lying on the cone's surface at an angle round the axis and a height, lifted off it.
static func _on_cone(angle: float, height: float, lift: float) -> Transform3D:
	var slope: Vector2 = CM_CONE_TOP - CM_CONE_BASE
	var outward := Vector3(cos(angle) * slope.y, sin(angle) * slope.y, -slope.x).normalized()
	var radius: float = _cone_radius(height)
	var where := Vector3(cos(angle) * radius, sin(angle) * radius, height) + outward * lift
	return Transform3D(Basis.looking_at(-outward, Vector3.BACK), where)


## A patch of the cone between two angles and two heights, lifted off the surface.
static func _cone_patch(angle_from: float, angle_to: float, from_height: float, to_height: float, lift: float) -> ArrayMesh:
	return SpaceMesh.lathe(PackedVector2Array([Vector2(_cone_radius(from_height) + lift, from_height),
		Vector2(_cone_radius(to_height) + lift, to_height)]), 6, angle_from, angle_to)


func _build_service_module() -> void:
	var skin := hull()
	var radiator := _radiator()
	var dark := paint(DARK, 0.7)
	# Hull: closed rings fore and aft, and the middle open where Sector 4 is.
	SpaceMesh.add_mesh(sm, SpaceMesh.lathe(PackedVector2Array([Vector2(SM_RADIUS, SM_AFT_Z), Vector2(SM_RADIUS, BAY_AFT_Z)]), 36), skin)
	SpaceMesh.add_mesh(sm, SpaceMesh.lathe(PackedVector2Array([Vector2(SM_RADIUS, BAY_FORE_Z), Vector2(SM_RADIUS, SM_FORE_Z)]), 36), skin)
	SpaceMesh.add_mesh(sm, SpaceMesh.lathe(PackedVector2Array([Vector2(SM_RADIUS, BAY_AFT_Z), Vector2(SM_RADIUS, BAY_FORE_Z)]),
		30, BAY_HALF_ANGLE, TAU - BAY_HALF_ANGLE), skin)
	# The radiator band round the forward end (not over Sector 4), and the two lower panels.
	var band := radiator.duplicate() as StandardMaterial3D
	band.uv1_scale = Vector3(RADIATOR_RIBS * 6.0, 1.0, 1.0)
	SpaceMesh.add_mesh(sm, SpaceMesh.lathe(PackedVector2Array([Vector2(SM_RADIUS + 0.012, EPS_BAND_AFT_Z),
		Vector2(SM_RADIUS + 0.012, SM_FORE_Z - 0.06)]), 30, BAY_HALF_ANGLE, TAU - BAY_HALF_ANGLE), band)
	var panels := radiator.duplicate() as StandardMaterial3D
	panels.uv1_scale = Vector3(RADIATOR_RIBS, 1.0, 1.0)
	for middle: float in ECS_PANEL_ANGLES:
		SpaceMesh.add_mesh(sm, SpaceMesh.lathe(PackedVector2Array([Vector2(SM_RADIUS + 0.015, -2.2), Vector2(SM_RADIUS + 0.015, 0.6)]),
			6, middle - ECS_PANEL_HALF_ANGLE, middle + ECS_PANEL_HALF_ANGLE), panels)
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
	# A darker band where the bell's cooled throat ends.
	SpaceMesh.add_mesh(sm, SpaceMesh.lathe(PackedVector2Array([Vector2(0.66, -4.05), Vector2(0.76, -4.3)]), 28), engine)
	# Reaction control quads at the four corners, and the high-gain antenna next to Sector 4.
	var bells := paint(THRUSTER, 0.4, 0.6)
	bells.cull_mode = BaseMaterial3D.CULL_DISABLED
	for corner: float in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		var outward := Vector3(cos(corner), sin(corner), 0.0)
		var sideways := outward.cross(Vector3.BACK).normalized()
		_thruster_quad(sm, outward * SM_RADIUS + Vector3(0.0, 0.0, 1.25), outward, Vector3(0.42, 0.62, 0.22),
			[Vector3.BACK, Vector3.FORWARD, sideways, -sideways], skin, bells)
	_high_gain_antenna(dark)
	_build_panel(skin)
	_build_bay(dark)


## A thruster cluster: a housing standing out from the hull along outward, with a bell pointing
## each way in directions.
func _thruster_quad(parent: Node3D, base: Vector3, outward: Vector3, size: Vector3, directions: Array,
		housing: Material, bells: Material) -> void:
	var up: Vector3 = Vector3.BACK if absf(outward.dot(Vector3.BACK)) < 0.9 else Vector3.UP
	SpaceMesh.add_mesh(parent, _box_mesh(size), housing, Transform3D(Basis.looking_at(-outward, up), base + outward * size.z * 0.5))
	var tip: Vector3 = base + outward * size.z
	for direction: Vector3 in directions:
		var helper: Vector3 = outward if absf(direction.dot(outward)) < 0.9 else up
		SpaceMesh.add_mesh(parent, _thruster_bell(), bells, Transform3D(Basis.looking_at(-direction, helper), tip + direction * 0.06))


## The high-gain antenna on its boom off the aft end: four dishes in a square round a horn.
func _high_gain_antenna(dark: Material) -> void:
	var angle: float = -0.95
	var outward := Vector3(cos(angle), sin(angle), 0.0)
	var root := Vector3(cos(angle) * SM_RADIUS, sin(angle) * SM_RADIUS, SM_AFT_Z + 0.35)
	var elbow: Vector3 = root + outward * 0.9 + Vector3(0.0, 0.0, -0.3)
	var head: Vector3 = elbow + outward * 0.75 + Vector3(0.0, 0.0, -0.55)
	SpaceMesh.add_rod(sm, root, elbow, 0.06, dark, 8)
	SpaceMesh.add_rod(sm, elbow, head, 0.05, dark, 8)
	SpaceMesh.add_box(sm, Vector3(0.22, 0.22, 0.22), elbow, dark)
	var aim: Vector3 = (outward + Vector3(0.0, 0.0, -0.5)).normalized()
	var facing := Basis.looking_at(-aim, Vector3.BACK)
	var dish_material := paint(Color(0.88, 0.88, 0.86), 0.5)
	dish_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dish := SpaceMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.2, 0.03), Vector2(0.38, 0.11)]), 16)
	for offset: Vector2 in [Vector2(0.41, 0.41), Vector2(-0.41, 0.41), Vector2(0.41, -0.41), Vector2(-0.41, -0.41)]:
		var middle: Vector3 = head + facing * Vector3(offset.x, offset.y, 0.0)
		SpaceMesh.add_mesh(sm, dish, dish_material, Transform3D(facing, middle))
		SpaceMesh.add_rod(sm, head, middle, 0.025, dark, 6)
	SpaceMesh.add_rod(sm, head - aim * 0.1, head + aim * 0.35, 0.08, dark, 10, 0.12)


func _build_panel(skin: Material) -> void:
	panel = Node3D.new()
	panel.position = bay_center
	sm.add_child(panel)
	var outer := (skin as StandardMaterial3D).duplicate() as StandardMaterial3D
	outer.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shell := SpaceMesh.lathe(PackedVector2Array([Vector2(SM_RADIUS + 0.01, BAY_AFT_Z), Vector2(SM_RADIUS + 0.01, BAY_FORE_Z)]),
		8, -BAY_HALF_ANGLE, BAY_HALF_ANGLE)
	SpaceMesh.add_mesh(panel, shell, outer, Transform3D(Basis.IDENTITY, -bay_center))


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
	var alu := paint(LM_ALUMINIZED, 0.4, 0.7)
	var grey := paint(LM_GREY, 0.55, 0.35)
	var black := paint(LM_BLACK, 0.8)
	var gold := foil()
	var silver_foil := foil(FOIL_SILVER)
	var dark := paint(DARK, 0.6, 0.3)
	var strut := paint(STRUT, 0.35, 0.7)
	var bells := paint(THRUSTER, 0.4, 0.6)
	bells.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Docking tunnel with the drogue's ring, on the roof.
	SpaceMesh.add_rod(lm, Vector3.ZERO, Vector3(0.0, -0.75, 0.0), 0.42, dark, 20)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.38
	ring.outer_radius = 0.48
	SpaceMesh.add_mesh(lm, ring, strut, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.05, 0.0)))
	SpaceMesh.add_box(lm, Vector3(1.9, 0.22, 1.5), Vector3(-0.25, -0.75, 0.0), alu)
	# The front cabin with its angled upper corners, the midsection and the aft equipment bay.
	var front := PackedVector2Array([Vector2(-1.15, -2.55), Vector2(1.15, -2.55), Vector2(1.15, -1.45),
		Vector2(0.72, -0.82), Vector2(-0.72, -0.82), Vector2(-1.15, -1.45)])
	var cabin_frame := Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT)
	SpaceMesh.add_mesh(lm, CabinMesh.prism(front, 1.3), alu, Transform3D(cabin_frame, Vector3(1.2, 0.0, 0.0)))
	SpaceMesh.add_box(lm, Vector3(1.15, 1.75, 2.0), Vector3(-0.45, -1.65, 0.0), grey)
	# Dark panels on the midsection's upper sides, where the thrusters' plumes would scorch.
	for side: float in [-1.0, 1.0]:
		SpaceMesh.add_box(lm, Vector3(0.9, 0.7, 0.02), Vector3(-0.45, -1.15, side * 1.005), black)
	SpaceMesh.add_box(lm, Vector3(0.95, 1.25, 1.7), Vector3(-1.45, -1.55, 0.0), alu)
	SpaceMesh.add_box(lm, Vector3(0.02, 1.0, 1.4), Vector3(-1.935, -1.55, 0.0), black)
	# The bulges of the ascent fuel and oxidizer tanks, one each side behind the cabin.
	var tank := CapsuleMesh.new()
	tank.radius = 0.5
	tank.height = 1.4
	tank.radial_segments = 16
	tank.rings = 6
	for side: float in [-1.0, 1.0]:
		SpaceMesh.add_mesh(lm, tank, alu, Transform3D(SpaceMesh.along_y(Vector3.RIGHT), Vector3(-0.6, -1.95, side * 0.95)))
	# The two triangular front windows in dark frames, and the hatch with its handle below them.
	for side: float in [-1.0, 1.0]:
		var bezel := PackedVector2Array([Vector2(side * 1.02, -1.52), Vector2(side * 0.26, -0.88), Vector2(side * 0.26, -1.52)])
		SpaceMesh.add_mesh(lm, SpaceMesh.plate(bezel), black, Transform3D(cabin_frame, Vector3(1.204, 0.0, 0.0)))
		var glass := paint(WINDOW_GLASS, 0.15, 0.2)
		glass.emission_enabled = true
		glass.emission = LM_WINDOW_GLOW
		glass.emission_energy_multiplier = 0.0
		lm_windows.append(glass)
		var triangle := PackedVector2Array([Vector2(side * 0.9, -1.47), Vector2(side * 0.33, -0.98), Vector2(side * 0.33, -1.47)])
		SpaceMesh.add_mesh(lm, SpaceMesh.plate(triangle), glass, Transform3D(cabin_frame, Vector3(1.208, 0.0, 0.0)))
	SpaceMesh.add_box(lm, Vector3(0.02, 0.86, 0.86), Vector3(1.206, -2.0, 0.0), grey)
	SpaceMesh.add_box(lm, Vector3(0.02, 0.76, 0.76), Vector3(1.212, -2.0, 0.0), dark)
	SpaceMesh.add_rod(lm, Vector3(1.24, -2.2, -0.2), Vector3(1.24, -2.2, 0.2), 0.02, strut, 6)
	# Thruster quads on outriggers at the four corners: up, down, fore or aft, and outward.
	for corner: Vector2 in [Vector2(0.55, 1.0), Vector2(0.55, -1.0), Vector2(-1.3, 1.0), Vector2(-1.3, -1.0)]:
		var outward := Vector3(0.0, 0.0, corner.y)
		var fore_aft := Vector3(signf(corner.x), 0.0, 0.0)
		var base := Vector3(corner.x, -1.55, corner.y * 1.0)
		SpaceMesh.add_rod(lm, base, base + outward * 0.2, 0.05, dark, 6)
		_thruster_quad(lm, base + outward * 0.2, outward, Vector3(0.26, 0.26, 0.26),
			[Vector3.UP, Vector3.DOWN, fore_aft, outward], black, bells)
	# Rendezvous radar on the front of the roof, the steerable S-band dish, and two VHF antennas.
	var radar_dish := SpaceMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.25, 0.04), Vector2(0.48, 0.15)]), 18)
	var radar_at := Vector3(0.75, -0.5, 0.55)
	SpaceMesh.add_rod(lm, Vector3(0.75, -0.75, 0.55), radar_at, 0.06, dark)
	SpaceMesh.add_box(lm, Vector3(0.22, 0.16, 0.22), radar_at, black)
	var radar_material := silver_foil.duplicate() as StandardMaterial3D
	radar_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	SpaceMesh.add_mesh(lm, radar_dish, radar_material, Transform3D(Basis.looking_at(-Vector3(1.0, 1.0, 0.2), Vector3.UP), radar_at + Vector3(0.1, 0.08, 0.0)))
	var antenna_dish := SpaceMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.18, 0.03), Vector2(0.33, 0.11)]), 16)
	var antenna_at := Vector3(-0.9, -0.2, -1.05)
	SpaceMesh.add_rod(lm, Vector3(-0.9, -0.95, -0.85), antenna_at, 0.04, dark)
	SpaceMesh.add_mesh(lm, antenna_dish, radar_material, Transform3D(Basis.looking_at(-Vector3(-0.3, 1.0, -0.4), Vector3.UP), antenna_at))
	SpaceMesh.add_rod(lm, Vector3(0.95, -0.86, -0.55), Vector3(1.35, -0.1, -0.75), 0.015, strut, 4)
	SpaceMesh.add_rod(lm, Vector3(-1.75, -0.92, 0.55), Vector3(-2.2, -0.2, 0.75), 0.015, strut, 4)
	# Descent stage: a gold octagon, a dark band round its top, its black base, the engine bell.
	var octagon := CylinderMesh.new()
	octagon.top_radius = 2.25
	octagon.bottom_radius = 2.25
	octagon.height = 1.65
	octagon.radial_segments = 8
	octagon.rings = 1
	SpaceMesh.add_mesh(lm, octagon, gold, Transform3D(Basis(Vector3.UP, PI / 8.0), Vector3(0.0, -3.4, 0.0)))
	var band := CylinderMesh.new()
	band.top_radius = 2.27
	band.bottom_radius = 2.27
	band.height = 0.14
	band.radial_segments = 8
	band.rings = 1
	SpaceMesh.add_mesh(lm, band, black, Transform3D(Basis(Vector3.UP, PI / 8.0), Vector3(0.0, -2.64, 0.0)))
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
	# The porch in front of the hatch, with its handrails, where the ladder starts.
	SpaceMesh.add_box(lm, Vector3(0.75, 0.04, 0.85), Vector3(1.6, -2.53, 0.0), strut)
	for side: float in [-1.0, 1.0]:
		SpaceMesh.add_rod(lm, Vector3(1.25, -2.28, side * 0.4), Vector3(1.95, -2.28, side * 0.4), 0.015, strut, 4)
		SpaceMesh.add_rod(lm, Vector3(1.95, -2.53, side * 0.4), Vector3(1.95, -2.28, side * 0.4), 0.015, strut, 4)
	_build_landing_gear(lm, gold, strut, silver_foil)


## Four legs, each a pivot at its hinge holding the primary strut, the footpad and (front leg)
## the ladder or (others) a contact probe. The bracing struts are built twice, deployed and
## stowed, and set_landing_gear shows one set.
func _build_landing_gear(lm: Node3D, gold: Material, strut: Material, pad_material: Material) -> void:
	_gear_deployed = Node3D.new()
	_gear_stowed = Node3D.new()
	lm.add_child(_gear_deployed)
	lm.add_child(_gear_stowed)
	var pad_skin := (pad_material as StandardMaterial3D).duplicate() as StandardMaterial3D
	pad_skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pad := SpaceMesh.lathe(PackedVector2Array([Vector2(0.0, -0.08), Vector2(0.36, -0.06), Vector2(0.46, 0.04),
		Vector2(0.47, 0.1)]), 16)
	var pad_frame := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
	for out: Vector3 in LEG_DIRECTIONS:
		var side: Vector3 = out.cross(Vector3.UP).normalized()
		var hinge: Vector3 = out * LEG_HINGE.x + Vector3(0.0, LEG_HINGE.y, 0.0)
		var leg := Node3D.new()
		leg.position = hinge
		lm.add_child(leg)
		_legs.append(leg)
		var foot: Vector3 = out * LEG_FOOT.x + Vector3(0.0, LEG_FOOT.y, 0.0)
		var along: Vector3 = foot.normalized()
		SpaceMesh.add_rod(leg, Vector3.ZERO, foot, 0.075, gold, 10)
		SpaceMesh.add_mesh(leg, pad, pad_skin, Transform3D(pad_frame, foot + Vector3(0.0, -0.06, 0.0)))
		if out == Vector3.RIGHT:
			# The ladder down the front leg, on the strut's outer face.
			var face: Vector3 = side.cross(along).normalized()
			var rails: Array[Vector3] = [side * 0.2 + face * 0.1, -side * 0.2 + face * 0.1]
			for rail: Vector3 in rails:
				SpaceMesh.add_rod(leg, along * 0.45 + rail, along * 2.9 + rail, 0.018, strut, 4)
			var rung: float = 0.6
			while rung < 2.85:
				SpaceMesh.add_rod(leg, along * rung + rails[0], along * rung + rails[1], 0.014, strut, 4)
				rung += LADDER_RUNG_STEP
		else:
			var probe := SpaceMesh.add_rod(_gear_deployed, hinge + foot + Vector3(0.0, -0.08, 0.0),
				hinge + foot + out * 0.25 + Vector3(0.0, -PROBE_LENGTH, 0.0), 0.012, strut, 4)
			probe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Bracing: two struts from the base of the stage to the primary strut's knee.
		var knee: Vector3 = hinge + along * 1.95
		var stowed_knee: Vector3 = hinge + Basis(side, LEG_STOW_RAD) * (along * 2.3)
		for lean: float in [-1.0, 1.0]:
			var anchor: Vector3 = out * 1.85 + side * lean * 0.85 + Vector3(0.0, -4.15, 0.0)
			SpaceMesh.add_rod(_gear_deployed, anchor, knee, 0.045, strut, 6)
			SpaceMesh.add_rod(_gear_stowed, anchor, stowed_knee, 0.045, strut, 6)


static func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

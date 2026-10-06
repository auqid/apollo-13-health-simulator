extends Node3D
## The exterior shots and the mission map. The cabin hides while this camera is current.
## A shot is a camera move plus an action, both driven by t from 0 to 1 across the shot, so the
## same t always draws the same frame: the explosion, the move into the lifeboat, the PC+2 burn,
## the Service Module and Aquarius jettisons, the plasma of reentry, the parachutes and the splash.

const Bodies := preload("res://scenes/space/bodies.gd")
const MapPath := preload("res://scenes/space/map_path.gd")
const Spacecraft := preload("res://scenes/space/spacecraft.gd")
const SpaceMesh := preload("res://scenes/space/space_mesh.gd")
const PuffCloud := preload("res://fx/puff_cloud.gd")
const UiStyle := preload("res://scenes/ui/ui_style.gd")

const OCEAN_SHADER := "res://scenes/space/ocean.gdshader"
const GLOW_SHADER := "res://fx/soft_glow.gdshader"
const PLUME_SHADER := "res://fx/plume.gdshader"
const PLUME_LENGTH := 11.0
const GROUP := "exterior"
const MOVES: Array[String] = ["orbit", "push_in", "pan", "bay"]
const DESCENT: Array[String] = ["plasma", "parachute", "splash"]
## The middle of the docked stack, which the wide shots circle.
const FOCUS := Vector3(0.0, 0.0, 2.8)
## When the oxygen tank bursts in the explosion shot, as a share of the shot.
const BURST_T := 0.12
## Where the Sector 4 panel ends up, and how far it has turned, by the end of the explosion shot.
const PANEL_FLIGHT := Vector3(15.0, 4.5, -7.0)
const PANEL_TUMBLE := Vector3(1.6, 0.7, 2.6)
const DEBRIS_COUNT := 14
## Parachutes at about real size: three 25 m mains on long lines, two small drogues.
const MAIN_RADIUS := 12.5
const MAIN_LINES := 34.0
const MAIN_SPLAY := 0.3
const DROGUE_RADIUS := 2.4
const DROGUE_LINES := 16.0
const RISER := 8.0
const CAPSULE_TOP := 3.45
## Height of the capsule's heat shield above the sea across the descent, then afloat with its
## base about a metre under the water.
const DESCENT_FROM_M := 140.0
const DESCENT_TO_M := 2.5
const FLOAT_HEIGHT := -0.9
const SPLASH_DIP := -1.7
## When Odyssey meets the water in the splash shot.
const SPLASH_T := 0.12
## The ring of foam spreading from the splash, in metres across.
## After splashdown the crew lets the mains go. They slump downwind over this share of the shot,
## lose their splay, and lie flat on the sea side by side, a little crumpled.
const CHUTE_FALL_T := 0.45
const CHUTE_DOWNWIND := Vector3(-0.95, 0.0, -0.3)
const CHUTE_DRIFT_M := 22.0
const CHUTE_SPREAD_M := 9.0
const CHUTE_SINK_M := 1.9
const CHUTE_SLACK := 0.35
const CHUTE_FLAT := 0.06
const CHUTE_LYING_SCALE := 0.6
const FOAM_START_M := 6.0
const FOAM_END_M := 22.0
## A big sea that fades into haze, with a fine enough grid near the camera for the swell.
const OCEAN_SIZE_M := 4000.0
const OCEAN_GRID := 320
## Reentry: which way Odyssey is moving in the plasma shot (down and across the frame), and the
## size of the Earth beneath it.
const ENTRY_HEADING := Vector3(-0.8, -0.45, 0.4)
const PLASMA_EARTH_RADIUS := 260.0
const MAP_REVEAL_S := 1.6
const MAP_PULSE_HZ := 0.8
const SWAY_RAD := 0.0025
const SWAY_PERIODS_S := Vector3(7.3, 9.1, 11.7)

const MARKER := Color(0.55, 0.81, 0.76)
const PATH_DIM := Color(0.85, 0.86, 0.84, 0.35)
const PATH_DONE := Color(0.92, 0.92, 0.9)
const OXYGEN := Color(0.93, 0.96, 1.0)
const PLASMA := Color(1.0, 0.5, 0.16)
const WAKE := Color(1.0, 0.38, 0.22)
const PLUME := Color(1.0, 0.78, 0.5)
const SPRAY := Color(0.94, 0.97, 1.0)
const SEA_HAZE := Color(0.7, 0.78, 0.87)
const CANOPY_ORANGE := Color(0.93, 0.36, 0.12)
const CANOPY_WHITE := Color(0.95, 0.94, 0.9)

var _camera: Camera3D
var _world: WorldEnvironment
var _space_env: Environment
var _day_env: Environment
var _sun: DirectionalLight3D
var _earthshine: DirectionalLight3D
var _stack: Node3D
var _craft: Spacecraft
var _scenic_earth: Node3D
var _scenic_moon: Node3D
var _earth_basis := Basis.IDENTITY
var _move: String = "orbit"
var _action: String = ""
var _showing: bool = false
var _sway_s: float = 0.0
# Explosion and lifeboat
var _flash: OmniLight3D
var _flash_glow: MeshInstance3D
var _o2_burst: PuffCloud
var _o2_vent: PuffCloud
var _o2_haze: PuffCloud
var _debris: Array[MeshInstance3D] = []
var _debris_dir: PackedVector3Array = []
var _debris_spin: PackedVector3Array = []
var _debris_speed: PackedFloat32Array = []
# Burn and jettisons
var _plume: MeshInstance3D
var _plume_material: ShaderMaterial
var _plume_glow: MeshInstance3D
var _rcs_puffs: PuffCloud
var _tunnel_puff: PuffCloud
# Reentry, parachutes and splash
var _entry: Node3D
var _capsule: Node3D
var _heat_shield: StandardMaterial3D
var _capsule_windows: Array[StandardMaterial3D] = []
var _sheath: PuffCloud
var _wake: PuffCloud
var _bow_glow: MeshInstance3D
var _chutes: Node3D
var _mains: Array[Node3D] = []
var _main_leans: Array[Basis] = []
var _drogues: Array[Node3D] = []
var _riser: MeshInstance3D
var _clouds: PuffCloud
var _ocean: MeshInstance3D
var _spray: PuffCloud
var _foam: MeshInstance3D
var _foam_material: StandardMaterial3D
# Map
var _map: Node3D
var _marker: MeshInstance3D
var _marker_halo: MeshInstance3D
var _path_full: MeshInstance3D
var _path_done: MeshInstance3D
var _path_next: MeshInstance3D
var _next_label: Label3D
var _next_points := PackedVector3Array()
var _map_t: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	build()
	hide_view()


func _process(delta: float) -> void:
	if not _showing:
		return
	_sway_s += delta
	if _map.visible:
		_animate_map(delta)


func build() -> void:
	if _camera != null:
		return
	_build_environments()
	_build_scenery()
	_stack = Node3D.new()
	add_child(_stack)
	_craft = Spacecraft.new(_stack)
	_build_explosion()
	_build_burn_and_jettisons()
	_build_entry()
	_build_map()
	_camera = Camera3D.new()
	_camera.fov = 45.0
	_camera.near = 0.1
	_camera.far = 1200.0
	add_child(_camera)


## gear_down: Aquarius's landing gear deployed, as it was from GET 061:00 on.
func show_exterior(move: String, body: String, action: String = "", gear_down: bool = true) -> void:
	build()
	_craft.set_landing_gear(gear_down)
	_showing = true
	visible = true
	_move = move if move in MOVES else "orbit"
	_action = action
	var day: bool = action == "parachute" or action == "splash"
	_world.environment = _day_env if day else _space_env
	_map.visible = false
	_place_scenery(body, action)
	_light_for(action)
	_camera.fov = 50.0 if day else 45.0
	_camera.current = true
	set_progress(0.0)


## The free-return loop with the ship at get_h. The leg up to next_get_h is drawn in, in teal,
## and next_label marks where it ends.
func show_map(get_h: float, splashdown_h: float, next_get_h: float = -1.0, next_label: String = "") -> void:
	build()
	_showing = true
	visible = true
	_stack.visible = false
	_entry.visible = false
	_ocean.visible = false
	_spray.hide_all()
	_foam.visible = false
	_scenic_earth.visible = false
	_scenic_moon.visible = false
	_map.visible = true
	_world.environment = _space_env
	_light_for("map")
	_camera.fov = 45.0
	_rebuild_path(get_h, splashdown_h, next_get_h if next_get_h > get_h else get_h)
	_marker.position = _map_point(MapPath.position(get_h, splashdown_h))
	_marker_halo.position = _marker.position
	_marker_halo.visible = true
	_next_label.text = next_label
	_next_label.visible = not next_label.is_empty() and next_get_h > get_h
	if _next_label.visible:
		_next_label.position = _map_point(MapPath.position(next_get_h, splashdown_h)) + Vector3(0.0, 0.0, 1.3)
	_map_t = 0.0
	_animate_map(0.0)
	_camera.current = true


func set_progress(t: float) -> void:
	if _camera == null:
		return
	var amount: float = clampf(t, 0.0, 1.0)
	var view: Transform3D = camera_transform(_move, amount, _action)
	_camera.global_transform = view * Transform3D(Basis.from_euler(_shake(amount) + _sway()), Vector3.ZERO)
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
static func camera_transform(move: String, t: float, action: String = "") -> Transform3D:
	var amount: float = clampf(t, 0.0, 1.0)
	var eased: float = smoothstep(0.0, 1.0, amount)
	var from: Vector3
	var aim: Vector3 = FOCUS
	if action == "explosion" or (action.is_empty() and move == "bay"):
		from = Vector3(13.5, 5.2, 12.0).lerp(Vector3(11.5, 3.8, 8.5), eased)
		aim = Vector3(1.4, 0.2, 1.8)
	elif action == "lifeboat":
		from = Vector3(14.0, 4.4, 6.5).lerp(Vector3(6.6, 1.7, 9.6), eased)
		aim = Vector3(2.0, 0.0, 1.8).lerp(Vector3(1.2, 0.1, 6.8), eased)
	elif action == "burn":
		from = Vector3(13.0, 5.5, 13.0).lerp(Vector3(11.0, 3.0, 18.0), eased)
		aim = Vector3(0.0, 0.0, 8.0).lerp(Vector3(0.0, 0.0, 12.0), eased)
	elif action == "sm_jettison":
		from = Vector3(-15.0, 4.5, 7.0).lerp(Vector3(-17.0, 3.2, -1.0), eased)
		aim = Vector3(0.0, 0.0, 1.5).lerp(Vector3(0.0, 0.0, -4.5), eased)
	elif action == "lm_jettison":
		from = Vector3(15.0, 4.0, 5.5).lerp(Vector3(16.5, 3.2, 8.5), eased)
		aim = Vector3(0.0, 0.0, 6.5).lerp(Vector3(0.0, 0.0, 9.5), eased)
	elif action == "plasma":
		from = Vector3(7.0, 2.4, 9.0).lerp(Vector3(5.2, 1.6, 6.8), eased)
		aim = Vector3(0.0, 1.2, 0.0)
	elif action == "parachute":
		# Close on the drogues, then wider as the three mains open above.
		var height: float = descent_height(amount)
		var wide: float = smoothstep(0.3, 0.75, amount)
		from = Vector3(64.0, 0.0, 60.0) * lerpf(0.42, 1.0, wide)
		from.y = maxf(height - lerpf(2.0, 6.0, wide), 6.0)
		aim = Vector3(0.0, height + lerpf(9.0, 24.0, wide), 0.0)
	elif action == "splash":
		from = Vector3(17.0, 5.5, 14.0).lerp(Vector3(12.5, 2.8, 10.5), eased)
		aim = Vector3(0.0, 1.4, 0.0)
	else:
		match move:
			"push_in":
				from = Vector3(9.0, 4.0, 24.0).lerp(Vector3(4.8, 1.9, 12.5), eased)
				aim = Vector3(0.5, 0.0, 6.0)
			"pan":
				from = Vector3(lerpf(-14.0, 14.0, amount), 3.0, 17.0)
				aim = Vector3(lerpf(-2.0, 2.0, amount), 0.0, 3.0)
			_:
				var angle: float = lerpf(-0.8, 1.05, amount)
				from = FOCUS + Vector3(sin(angle) * 24.0, 5.0, cos(angle) * 24.0)
	return Transform3D(Basis.looking_at(aim - from, Vector3.UP), from)


## 0 while the Sector 4 panel is on the hull, 1 once it has blown clear. After the explosion
## shot it is long gone.
static func panel_travel(action: String, t: float) -> float:
	if action != "explosion":
		return 1.0
	var since: float = clampf((t - BURST_T) / (1.0 - BURST_T), 0.0, 1.0)
	return 1.0 - pow(1.0 - since, 2.5)


## How strong the oxygen cloud is: nothing before the burst, then full. On the lifeboat shot it is
## still there, thinning.
static func cloud_alpha(action: String, t: float) -> float:
	var amount: float = clampf(t, 0.0, 1.0)
	if action == "explosion":
		return smoothstep(BURST_T, BURST_T + 0.03, amount)
	if action == "lifeboat":
		return lerpf(1.0, 0.35, amount)
	return 0.0


## Warm-window glow, x for Odyssey and y for Aquarius. Odyssey goes dark after the explosion and
## Aquarius carries the crew until they move back for the reentry.
static func window_glow(action: String, t: float) -> Vector2:
	if action == "explosion":
		return Vector2(1.0, 0.0)
	if action == "lifeboat":
		var swap: float = smoothstep(0.12, 0.88, clampf(t, 0.0, 1.0))
		return Vector2(1.0 - swap, swap)
	if action == "lm_jettison":
		return Vector2(1.0, 0.0)
	return Vector2(0.0, 0.6)


## 0 before the sheath forms, 1 when the heat shield is wrapped in plasma.
static func plasma_strength(t: float) -> float:
	return smoothstep(0.08, 0.82, clampf(t, 0.0, 1.0))


## x is the drogue scale, y the main-canopy scale.
static func parachute_open(t: float) -> Vector2:
	var amount: float = clampf(t, 0.0, 1.0)
	var drogue: float = smoothstep(0.04, 0.24, amount) * (1.0 - smoothstep(0.38, 0.5, amount))
	var mains: float = smoothstep(0.38, 0.72, amount)
	return Vector2(drogue, mains)


## Height of the capsule's heat shield above the sea during the parachute shot.
static func descent_height(t: float) -> float:
	return lerpf(DESCENT_FROM_M, DESCENT_TO_M, clampf(t, 0.0, 1.0))


## 0 as the capsule reaches the water, 1 once it is floating.
static func splash_float(t: float) -> float:
	return smoothstep(0.18, 0.62, clampf(t, 0.0, 1.0))


## How far Odyssey and Aquarius have moved off the Service Module.
static func sm_separation(t: float) -> float:
	return smoothstep(0.08, 0.9, clampf(t, 0.0, 1.0))


## How far Aquarius has drifted off Odyssey. The puff of tunnel air is strongest at the start.
static func lm_separation(t: float) -> float:
	return smoothstep(0.06, 0.88, clampf(t, 0.0, 1.0))


static func lm_puff(t: float) -> float:
	var amount: float = clampf(t, 0.0, 1.0)
	return smoothstep(0.0, 0.12, amount) * (1.0 - smoothstep(0.22, 0.55, amount))


# --- Applying a shot ---

func _apply_action(t: float) -> void:
	var descent: bool = _action in DESCENT
	_stack.visible = not descent
	_entry.visible = descent
	_ocean.visible = _action == "parachute" or _action == "splash"
	if descent:
		_apply_descent(t)
		return
	_spray.hide_all()
	_foam.visible = false
	_restack()
	_apply_damage(t)
	_apply_separation(t)
	_apply_burn(t)
	var glow: Vector2 = window_glow(_action, t)
	for material: StandardMaterial3D in _craft.cm_windows:
		material.emission_energy_multiplier = glow.x * 2.2
	for material: StandardMaterial3D in _craft.lm_windows:
		material.emission_energy_multiplier = glow.y * 2.2


func _restack() -> void:
	for ship: Node3D in [_craft.sm, _craft.odyssey, _craft.aquarius]:
		ship.visible = true
		ship.position = Vector3.ZERO
		ship.rotation = Vector3.ZERO


func _apply_damage(t: float) -> void:
	var exploding: bool = _action == "explosion"
	var travel: float = panel_travel(_action, t)
	var burst: bool = exploding and t >= BURST_T
	_craft.panel.visible = exploding
	_craft.bay.visible = not exploding or burst
	if exploding:
		var since: float = maxf(t - BURST_T, 0.0)
		_craft.panel.position = _craft.bay_center + PANEL_FLIGHT * travel
		_craft.panel.rotation = PANEL_TUMBLE * since
	for i in _debris.size():
		var piece: MeshInstance3D = _debris[i]
		piece.visible = burst
		if not burst:
			continue
		var since: float = t - BURST_T
		piece.position = _craft.bay_center + _debris_dir[i] * _debris_speed[i] * since
		piece.rotation = _debris_spin[i] * since
	var flash: float = 0.0
	if burst:
		flash = 1.0 - smoothstep(0.0, 0.07, t - BURST_T)
	_flash.visible = flash > 0.0
	_flash.light_energy = flash * 9.0
	_flash_glow.visible = flash > 0.0
	_flash_glow.scale = Vector3.ONE * lerpf(2.0, 7.0, 1.0 - flash)
	_flash_glow.set_instance_shader_parameter("puff_color", Color(1.0, 0.96, 0.9, flash * 0.9))
	var strength: float = cloud_alpha(_action, t)
	if exploding:
		_o2_burst.set_time(t, strength)
		_o2_vent.set_time(t, strength)
		_o2_haze.hide_all()
	elif _action == "lifeboat":
		_o2_burst.hide_all()
		_o2_vent.set_time(0.55 + t * 0.45, strength * 0.6)
		_o2_haze.set_time(t, strength)
	else:
		_o2_burst.hide_all()
		_o2_vent.hide_all()
		_o2_haze.hide_all()


func _apply_separation(t: float) -> void:
	_rcs_puffs.hide_all()
	_tunnel_puff.hide_all()
	if _action == "sm_jettison":
		var apart: float = sm_separation(t)
		_craft.odyssey.position = Vector3(0.0, 0.0, 7.0) * apart
		_craft.aquarius.position = _craft.odyssey.position
		# The Service Module drifts back and rolls, turning the open bay toward the camera.
		_craft.sm.position = Vector3(-0.4, 0.3, -5.0) * apart
		_craft.sm.rotation = Vector3(0.18, -0.12, PI) * apart
		_rcs_puffs.set_time(t)
	elif _action == "lm_jettison":
		_craft.sm.visible = false
		var apart: float = lm_separation(t)
		_craft.aquarius.position = Vector3(0.35, 0.15, 6.0) * apart
		_craft.aquarius.rotation = Vector3(0.12, 0.05, 0.3) * apart
		_tunnel_puff.set_time(t)


func _apply_burn(t: float) -> void:
	var burning: bool = _action == "burn"
	_plume.visible = burning
	_plume_glow.visible = burning
	if not burning:
		return
	var strength: float = smoothstep(0.0, 0.08, t)
	_plume_material.set_shader_parameter("strength", 0.3 * strength)
	_plume_glow.set_instance_shader_parameter("puff_color", Color(PLUME, 0.6 * strength))


func _apply_descent(t: float) -> void:
	_heat_shield.emission_energy_multiplier = 0.0
	_sheath.hide_all()
	_wake.hide_all()
	_bow_glow.visible = false
	_chutes.visible = false
	_clouds.hide_all()
	_spray.hide_all()
	_foam.visible = false
	for glass: StandardMaterial3D in _capsule_windows:
		glass.emission_energy_multiplier = 0.0
	match _action:
		"plasma":
			_apply_plasma(t)
		"parachute":
			_apply_parachutes(t)
		"splash":
			_apply_splash(t)


func _apply_plasma(t: float) -> void:
	var strength: float = plasma_strength(t)
	_entry.position = Vector3.ZERO
	# Heat shield first into the air, which streams back past the apex into a glowing wake.
	_capsule.transform = Transform3D(SpaceMesh.along_y(-ENTRY_HEADING), Vector3.ZERO)
	_heat_shield.emission_energy_multiplier = strength * 6.0
	_sheath.set_time(t, strength)
	_wake.set_time(t, strength)
	_bow_glow.visible = strength > 0.01
	_bow_glow.scale = Vector3.ONE * lerpf(3.5, 9.0, strength)
	_bow_glow.set_instance_shader_parameter("puff_color", Color(1.0, 0.72, 0.45, 0.85 * strength))
	# The ground slides by underneath.
	_scenic_earth.basis = _earth_basis * Basis(Vector3.UP, t * 0.04)
	_scenic_earth.scale = Vector3.ONE * PLASMA_EARTH_RADIUS


func _apply_parachutes(t: float) -> void:
	var open: Vector2 = parachute_open(t)
	var height: float = descent_height(t)
	_entry.position = Vector3(0.0, height, 0.0)
	_place_hanging_capsule(t)
	_hang_chutes()
	for rig: Node3D in _drogues:
		rig.visible = open.x > 0.02
		rig.scale = Vector3(maxf(open.x, 0.02), lerpf(0.45, 1.0, open.x), maxf(open.x, 0.02))
	for rig: Node3D in _mains:
		rig.visible = open.y > 0.02
		rig.scale = Vector3(maxf(open.y, 0.02), lerpf(0.35, 1.0, open.y), maxf(open.y, 0.02))
	_clouds.set_time(0.5)
	_clouds.position = Vector3(0.0, -height, 0.0)


func _apply_splash(t: float) -> void:
	var height: float
	if t < SPLASH_T:
		height = lerpf(DESCENT_TO_M, SPLASH_DIP * 0.5, t / SPLASH_T)
	else:
		var settle: float = splash_float(t)
		var since: float = (t - SPLASH_T) / (1.0 - SPLASH_T)
		height = lerpf(SPLASH_DIP, FLOAT_HEIGHT, settle) + sin(since * TAU * 2.2) * 0.14 * settle
	_entry.position = Vector3(0.0, height, 0.0)
	_place_hanging_capsule(t)
	_hang_chutes()
	for rig: Node3D in _drogues:
		rig.visible = false
	# The mains are let go as Odyssey hits the water: they slump downwind and lie on the sea.
	var fall: float = smoothstep(SPLASH_T, SPLASH_T + CHUTE_FALL_T, t)
	var lying: Vector3 = CHUTE_DOWNWIND.normalized() * CHUTE_DRIFT_M - Vector3(0.0, height + CHUTE_SINK_M, 0.0)
	_chutes.position = _chutes.position.lerp(lying, fall)
	_riser.visible = fall <= 0.0
	# Falling, the lines go slack and the canopies crumple; on the water they flatten out.
	var slack: float = smoothstep(0.0, 0.5, fall)
	var flat: float = smoothstep(0.55, 1.0, fall)
	for i in _mains.size():
		var rig: Node3D = _mains[i]
		var around: float = TAU * float(i) / float(_mains.size())
		var spread: float = lerpf(1.0, CHUTE_LYING_SCALE, slack)
		rig.visible = true
		rig.basis = _main_leans[i].slerp(Basis.IDENTITY, flat)
		rig.scale = Vector3(spread, lerpf(lerpf(1.0, CHUTE_SLACK, slack), CHUTE_FLAT, flat), spread)
		rig.position = Vector3(cos(around), 0.0, sin(around)) * CHUTE_SPREAD_M * fall
	_spray.set_time(t)
	var ring: float = smoothstep(SPLASH_T, 0.95, t)
	_foam.visible = t >= SPLASH_T
	_foam.scale = Vector3.ONE * lerpf(FOAM_START_M, FOAM_END_M, ring)
	_foam_material.albedo_color = Color(1.0, 1.0, 1.0, 0.8 * (1.0 - ring))


## The parachutes as they hang above the capsule, splayed, on the riser.
func _hang_chutes() -> void:
	_chutes.visible = true
	_chutes.position = Vector3(0.0, CAPSULE_TOP + RISER, 0.0)
	_riser.visible = true
	for i in _mains.size():
		_mains[i].position = Vector3.ZERO
		_mains[i].basis = _main_leans[i]


## The capsule hangs under its risers, swinging gently; afloat it rocks upright.
func _place_hanging_capsule(t: float) -> void:
	var swing: float = sin(t * TAU * 1.4) * 0.05
	_capsule.position = Vector3.ZERO
	_capsule.rotation = Vector3(swing, 0.4, 0.28 + swing * 0.6)
	if _action == "splash" and t >= SPLASH_T:
		var settle: float = splash_float(t)
		_capsule.rotation = Vector3(swing * (1.0 - settle), 0.4, lerpf(0.28, 0.05, settle) + sin(t * TAU * 2.0) * 0.04)


func _shake(t: float) -> Vector3:
	var amplitude: float = 0.0
	if _action == "explosion" and t > BURST_T:
		amplitude = 0.02 * exp(-(t - BURST_T) / 0.05)
	elif _action == "plasma":
		amplitude = 0.004 * plasma_strength(t)
	if amplitude <= 0.0:
		return Vector3.ZERO
	return Vector3(sin(t * 170.0), sin(t * 230.0 + 1.0), sin(t * 130.0 + 2.0)) * amplitude


## A slow, slight handheld sway so even a still frame breathes.
func _sway() -> Vector3:
	return Vector3(sin(TAU * _sway_s / SWAY_PERIODS_S.x), sin(TAU * _sway_s / SWAY_PERIODS_S.y + 1.0),
		sin(TAU * _sway_s / SWAY_PERIODS_S.z + 2.0)) * SWAY_RAD


## Puts the Earth or the Moon in the background of the shot, behind the ship as the camera sees it
## halfway through. Near the end of the trip the Earth fills the lower frame.
func _place_scenery(body: String, action: String) -> void:
	var view: Transform3D = camera_transform(_move, 0.5, action)
	var forward: Vector3 = -view.basis.z
	var backdrop: Vector3 = view.origin + forward * 150.0 + view.basis.x * 28.0 + view.basis.y * 14.0
	_scenic_earth.visible = true
	_scenic_moon.visible = false
	# Poles to the sides of the frame, so the texture's pinch at a pole never faces the camera.
	_earth_basis = Basis(view.basis.y, view.basis.x, forward)
	_scenic_earth.basis = _earth_basis
	_scenic_moon.basis = _earth_basis
	if action == "parachute" or action == "splash":
		_scenic_earth.visible = false
	elif action == "plasma":
		_scenic_earth.position = view.origin + forward * 200.0 - view.basis.y * (PLASMA_EARTH_RADIUS + 32.0)
		_scenic_earth.scale = Vector3.ONE * PLASMA_EARTH_RADIUS
	elif action == "lm_jettison":
		_scenic_earth.position = view.origin + forward * 170.0 - view.basis.y * 120.0
		_scenic_earth.scale = Vector3.ONE * 110.0
	elif body == "moon":
		_scenic_earth.visible = false
		_scenic_moon.visible = true
		_scenic_moon.position = view.origin + forward * 140.0 - view.basis.x * 30.0 + view.basis.y * 8.0
		_scenic_moon.scale = Vector3.ONE * 38.0
	else:
		_scenic_earth.position = backdrop
		_scenic_earth.scale = Vector3.ONE * 13.0


func _light_for(action: String) -> void:
	_earthshine.visible = true
	_sun.light_color = Color(1.0, 0.97, 0.92)
	_sun.light_energy = 1.7
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 60.0
	match action:
		"parachute", "splash":
			_sun.rotation_degrees = Vector3(-52.0, 30.0, 0.0)
			_sun.light_energy = 1.35
			_sun.directional_shadow_max_distance = 180.0
			_earthshine.visible = false
		"sm_jettison":
			# Sunlight from the camera's side, so the open bay is lit as it turns.
			_sun.rotation_degrees = Vector3(-24.0, -80.0, 0.0)
		"plasma":
			_sun.rotation_degrees = Vector3(-15.0, 110.0, 0.0)
			_sun.light_energy = 0.55
		"map":
			_sun.rotation_degrees = Vector3(-60.0, 40.0, 0.0)
			_sun.shadow_enabled = false
		_:
			_sun.rotation_degrees = Vector3(-26.0, 38.0, 0.0)


# --- Building ---

func _build_environments() -> void:
	_space_env = Environment.new()
	_space_env.background_mode = Environment.BG_SKY
	var stars := PanoramaSkyMaterial.new()
	stars.panorama = Bodies.star_panorama()
	stars.energy_multiplier = Bodies.STAR_BRIGHTNESS
	_space_env.sky = Sky.new()
	_space_env.sky.sky_material = stars
	_space_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_space_env.ambient_light_color = Color(0.6, 0.65, 0.72)
	_space_env.ambient_light_energy = 0.18
	_space_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_space_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_space_env.glow_enabled = true
	_space_env.glow_intensity = 0.45
	_space_env.glow_bloom = 0.05

	_day_env = Environment.new()
	_day_env.background_mode = Environment.BG_SKY
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.18, 0.4, 0.76)
	sky.sky_horizon_color = Color(0.68, 0.78, 0.88)
	# Beyond the edge of the sea mesh the sky's ground shows, so it matches the haze over the sea.
	sky.ground_bottom_color = Color(0.3, 0.43, 0.56)
	sky.ground_horizon_color = SEA_HAZE
	sky.sun_angle_max = 20.0
	_day_env.sky = Sky.new()
	_day_env.sky.sky_material = sky
	_day_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_day_env.ambient_light_energy = 0.7
	_day_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_day_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_day_env.fog_enabled = true
	_day_env.fog_light_color = SEA_HAZE
	_day_env.fog_density = 0.0015
	_day_env.fog_sky_affect = 0.0

	_world = WorldEnvironment.new()
	add_child(_world)
	_sun = DirectionalLight3D.new()
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(_sun)
	# Faint blue light from below, as if from the Earth.
	_earthshine = DirectionalLight3D.new()
	_earthshine.rotation_degrees = Vector3(70.0, -20.0, 0.0)
	_earthshine.light_color = Color(0.55, 0.68, 0.9)
	_earthshine.light_energy = 0.18
	add_child(_earthshine)


func _build_scenery() -> void:
	_scenic_earth = Node3D.new()
	_scenic_earth.add_child(Bodies.sphere(1.0, Bodies.earth_material(), 64))
	_scenic_earth.add_child(Bodies.sphere(1.012, Bodies.cloud_material(), 64))
	var air := Bodies.atmosphere_material()
	if air.shader != null:
		_scenic_earth.add_child(Bodies.sphere(1.035, air, 64))
	add_child(_scenic_earth)
	_scenic_moon = Node3D.new()
	_scenic_moon.add_child(Bodies.sphere(1.0, Bodies.moon_material(), 48))
	add_child(_scenic_moon)


func _build_explosion() -> void:
	var bay: Vector3 = _craft.bay_center
	_flash = OmniLight3D.new()
	_flash.position = bay + Vector3(1.2, 0.0, 0.0)
	_flash.omni_range = 14.0
	_flash.light_color = Color(1.0, 0.95, 0.88)
	_flash.visible = false
	_craft.sm.add_child(_flash)
	_flash_glow = _glow_sprite(_craft.sm, bay + Vector3(0.8, 0.0, 0.0))
	_o2_burst = _cloud(_craft.sm, {"count": 40, "seed": 55, "origin": bay + Vector3(0.3, 0.0, 0.0),
		"axis": Vector3(1.0, 0.1, -0.3), "spread": 65.0, "speed": Vector2(9.0, 16.0), "drag": 2.2,
		"birth": Vector2(BURST_T, BURST_T + 0.04), "life": Vector2(0.5, 0.8), "size": Vector2(0.5, 4.5),
		"color": OXYGEN, "opacity": 0.3})
	_o2_vent = _cloud(_craft.sm, {"count": 70, "seed": 56, "origin": bay + Vector3(0.2, 0.0, 0.0),
		"jitter": Vector3(0.1, 0.5, 1.6), "axis": Vector3(1.0, 0.15, -0.35), "spread": 24.0,
		"speed": Vector2(7.0, 12.0), "drag": 1.0, "birth": Vector2(BURST_T + 0.02, 1.0),
		"life": Vector2(0.28, 0.5), "size": Vector2(0.3, 2.6), "color": OXYGEN, "opacity": 0.2})
	_o2_haze = _cloud(_craft.sm, {"count": 44, "seed": 57, "origin": bay + Vector3(6.0, 0.5, -2.0),
		"jitter": Vector3(5.0, 3.5, 6.0), "axis": Vector3.RIGHT, "spread": 180.0, "speed": Vector2(0.5, 2.0),
		"drag": 0.5, "birth": Vector2(-1.0, 0.0), "life": Vector2(1.6, 2.4), "size": Vector2(2.0, 5.0),
		"color": OXYGEN, "opacity": 0.14})
	var rng := RandomNumberGenerator.new()
	rng.seed = 413
	var white := Spacecraft.hull()
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shred := Spacecraft.foil(Color(0.8, 0.66, 0.42))
	shred.cull_mode = BaseMaterial3D.CULL_DISABLED
	var frame := Basis.looking_at(Vector3.RIGHT, Vector3.UP)
	for i in DEBRIS_COUNT:
		var size := Vector3(rng.randf_range(0.08, 0.55), rng.randf_range(0.015, 0.04), rng.randf_range(0.08, 0.45))
		var chip := SpaceMesh.add_box(_craft.sm, size, bay, white if i % 3 != 0 else shred)
		chip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chip.visible = false
		_debris.append(chip)
		var z: float = rng.randf_range(cos(deg_to_rad(60.0)), 1.0)
		var around: float = rng.randf_range(0.0, TAU)
		var ring: float = sqrt(1.0 - z * z)
		_debris_dir.append(frame * Vector3(ring * cos(around), ring * sin(around), -z))
		_debris_speed.append(rng.randf_range(7.0, 18.0))
		_debris_spin.append(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * rng.randf_range(6.0, 16.0))


func _build_burn_and_jettisons() -> void:
	var exit: Vector3 = _craft.lm_engine_exit
	# A faint cone of exhaust: the descent engine fired for the PC+2 burn.
	var cone := CylinderMesh.new()
	cone.top_radius = 0.7
	cone.bottom_radius = 2.6
	cone.height = PLUME_LENGTH
	cone.radial_segments = 24
	cone.cap_top = false
	cone.cap_bottom = false
	_plume_material = ShaderMaterial.new()
	if ResourceLoader.exists(PLUME_SHADER):
		_plume_material.shader = load(PLUME_SHADER)
	_plume_material.set_shader_parameter("plume_color", PLUME)
	_plume = SpaceMesh.add_mesh(_craft.aquarius, cone, _plume_material,
		Transform3D(SpaceMesh.along_y(Vector3.FORWARD), exit + Vector3(0.0, 0.0, PLUME_LENGTH * 0.5)))
	_plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plume.visible = false
	_plume_glow = _glow_sprite(_craft.aquarius, exit + Vector3(0.0, 0.0, 0.4))
	_plume_glow.scale = Vector3.ONE * 3.5
	# Aquarius's thrusters push the stack clear of the Service Module.
	_rcs_puffs = _cloud(_craft.aquarius, {"count": 28, "seed": 58, "origin": Vector3(-0.4, 0.0, 7.0),
		"jitter": Vector3(1.0, 1.3, 0.1), "axis": Vector3.FORWARD, "spread": 18.0, "speed": Vector2(3.0, 6.0),
		"drag": 2.0, "birth": Vector2(0.04, 0.18), "life": Vector2(0.12, 0.25), "size": Vector2(0.15, 1.1),
		"color": OXYGEN, "opacity": 0.45})
	# The puff of tunnel air as Aquarius lets go of Odyssey.
	_tunnel_puff = _cloud(_stack, {"count": 30, "seed": 59, "origin": _craft.tunnel_center,
		"axis": Vector3.UP, "spread": 180.0, "speed": Vector2(1.5, 4.0), "drag": 3.0,
		"birth": Vector2(0.0, 0.08), "life": Vector2(0.3, 0.55), "size": Vector2(0.2, 1.6),
		"color": OXYGEN, "opacity": 0.5})


func _build_entry() -> void:
	_entry = Node3D.new()
	_entry.visible = false
	add_child(_entry)
	_capsule = Node3D.new()
	_entry.add_child(_capsule)
	_heat_shield = Spacecraft.build_capsule(_capsule, _capsule_windows, Spacecraft.SCORCHED)
	# Plasma sheath around the heat shield, the glowing wake, and the bow glow in front.
	_sheath = _cloud(_capsule, {"count": 120, "seed": 60, "origin": Vector3(0.0, -0.3, 0.0),
		"jitter": Vector3(1.7, 0.1, 1.7), "axis": Vector3.UP, "spread": 40.0, "speed": Vector2(5.0, 9.0),
		"drag": 1.5, "birth": Vector2(0.0, 1.0), "life": Vector2(0.06, 0.12), "size": Vector2(1.0, 3.4),
		"color": PLASMA, "opacity": 0.55, "glow": true})
	_wake = _cloud(_capsule, {"count": 90, "seed": 61, "origin": Vector3(0.0, 3.0, 0.0),
		"jitter": Vector3(0.9, 0.5, 0.9), "axis": Vector3.UP, "spread": 12.0, "speed": Vector2(18.0, 30.0),
		"drag": 0.2, "birth": Vector2(0.0, 1.0), "life": Vector2(0.12, 0.2), "size": Vector2(1.4, 6.0),
		"color": WAKE, "opacity": 0.38, "glow": true})
	_bow_glow = _glow_sprite(_capsule, Vector3(0.0, -0.8, 0.0))
	_build_parachutes()
	_build_sea()


func _build_parachutes() -> void:
	_chutes = Node3D.new()
	_chutes.position = Vector3(0.0, CAPSULE_TOP + RISER, 0.0)
	_entry.add_child(_chutes)
	var riser_material := _line_material(Color(0.78, 0.76, 0.7))
	_riser = MeshInstance3D.new()
	_riser.mesh = _lines(PackedVector3Array([Vector3.ZERO, Vector3(0.0, -RISER, 0.0)]))
	_riser.material_override = riser_material
	_riser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_chutes.add_child(_riser)
	var stripes := _canopy_material()
	for slot in 3:
		var lean := Basis(Vector3.UP, TAU * float(slot) / 3.0) * Basis(Vector3.RIGHT, MAIN_SPLAY)
		_main_leans.append(lean)
		_mains.append(_canopy(MAIN_RADIUS, MAIN_LINES, stripes, riser_material, lean))
	for side: float in [-1.0, 1.0]:
		_drogues.append(_canopy(DROGUE_RADIUS, DROGUE_LINES, stripes, riser_material, Basis(Vector3.FORWARD, side * 0.16)))
	_clouds = _cloud(_entry, {"count": 70, "seed": 62, "origin": Vector3(0.0, 92.0, 0.0),
		"jitter": Vector3(150.0, 8.0, 150.0), "axis": Vector3.UP, "spread": 180.0, "speed": Vector2(0.0, 0.0),
		"drag": 0.0, "birth": Vector2(-3.0, -2.0), "life": Vector2(10.0, 10.0), "size": Vector2(16.0, 16.0),
		"color": Color(1.0, 1.0, 1.0), "opacity": 0.9, "wisp": 0.55})


## A canopy on its suspension lines, its lines meeting at the rig's origin.
func _canopy(radius: float, lines: float, cloth: Material, line_material: Material, lean: Basis) -> Node3D:
	var rig := Node3D.new()
	rig.basis = lean
	rig.visible = false
	_chutes.add_child(rig)
	var dome := SpaceMesh.lathe(PackedVector2Array([Vector2(radius, 0.0), Vector2(radius * 0.96, radius * 0.22),
		Vector2(radius * 0.8, radius * 0.45), Vector2(radius * 0.52, radius * 0.62), Vector2(radius * 0.18, radius * 0.7),
		Vector2(0.0, radius * 0.71)]), 24)
	var canopy := SpaceMesh.add_mesh(rig, dome, cloth, Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), Vector3(0.0, lines, 0.0)))
	canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var points := PackedVector3Array()
	for i in 12:
		var angle: float = TAU * float(i) / 12.0
		points.append(Vector3.ZERO)
		points.append(Vector3(cos(angle) * radius, lines, sin(angle) * radius))
	var cords := MeshInstance3D.new()
	cords.mesh = _lines(points)
	cords.material_override = line_material
	cords.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(cords)
	return rig


func _build_sea() -> void:
	_ocean = MeshInstance3D.new()
	var sea := PlaneMesh.new()
	sea.size = Vector2(OCEAN_SIZE_M, OCEAN_SIZE_M)
	sea.subdivide_width = OCEAN_GRID
	sea.subdivide_depth = OCEAN_GRID
	_ocean.mesh = sea
	_ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if ResourceLoader.exists(OCEAN_SHADER):
		var water := ShaderMaterial.new()
		water.shader = load(OCEAN_SHADER)
		_ocean.material_override = water
	else:
		_ocean.material_override = Spacecraft.paint(Color(0.04, 0.2, 0.28), 0.2)
	_ocean.visible = false
	add_child(_ocean)
	# Spray and the ring of foam stay on the water, not on the bobbing capsule.
	_spray = _cloud(self, {"count": 70, "seed": 63, "origin": Vector3(0.0, 0.4, 0.0),
		"jitter": Vector3(2.0, 0.2, 2.0), "axis": Vector3.UP, "spread": 60.0, "speed": Vector2(10.0, 22.0),
		"drag": 2.4, "drift": Vector3(0.0, -10.0, 0.0), "birth": Vector2(SPLASH_T, SPLASH_T + 0.06),
		"life": Vector2(0.3, 0.6), "size": Vector2(0.5, 3.2), "color": SPRAY, "opacity": 0.8})
	var ring_profile := Gradient.new()
	ring_profile.offsets = PackedFloat32Array([0.0, 0.45, 0.72, 0.86, 1.0])
	ring_profile.colors = PackedColorArray([Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.25), Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.0)])
	var ring_texture := GradientTexture2D.new()
	ring_texture.gradient = ring_profile
	ring_texture.fill = GradientTexture2D.FILL_RADIAL
	ring_texture.fill_from = Vector2(0.5, 0.5)
	ring_texture.fill_to = Vector2(1.0, 0.5)
	ring_texture.width = 256
	ring_texture.height = 256
	_foam_material = StandardMaterial3D.new()
	_foam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_foam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_foam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_foam_material.albedo_texture = ring_texture
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_foam = SpaceMesh.add_mesh(self, quad, _foam_material, Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.0, 0.15, 0.0)))
	_foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_foam.visible = false


func _build_map() -> void:
	_map = Node3D.new()
	_map.visible = false
	add_child(_map)
	var earth := Node3D.new()
	earth.position = _map_point(MapPath.EARTH)
	earth.add_child(Bodies.sphere(1.7, Bodies.earth_material(), 40))
	var air := Bodies.atmosphere_material()
	if air.shader != null:
		earth.add_child(Bodies.sphere(1.78, air, 40))
	_map.add_child(earth)
	var moon := Bodies.sphere(0.9, Bodies.moon_material(), 32)
	moon.position = _map_point(MapPath.MOON)
	_map.add_child(moon)
	_path_full = _map_line(PATH_DIM)
	_path_done = _map_line(PATH_DONE)
	_path_next = _map_line(MARKER)
	_marker = Bodies.sphere(0.32, _glowing(MARKER, 2.0), 16)
	_map.add_child(_marker)
	_marker_halo = _glow_sprite(_map, Vector3.ZERO)
	_map.add_child(_map_label("Earth", _map_point(MapPath.EARTH) + Vector3(0.0, 0.0, 2.7)))
	_map.add_child(_map_label("Moon", _map_point(MapPath.MOON) + Vector3(0.0, 0.0, 1.9)))
	_next_label = _map_label("", Vector3.ZERO)
	_next_label.modulate = MARKER
	_map.add_child(_next_label)


func _rebuild_path(get_h: float, splashdown_h: float, next_get_h: float) -> void:
	_path_full.mesh = _ribbon(_path_points(0.0, splashdown_h, splashdown_h), 0.06)
	_path_done.mesh = _ribbon(_path_points(0.0, get_h, splashdown_h), 0.1)
	_next_points = _path_points(get_h, next_get_h, splashdown_h)
	_path_next.mesh = null


func _path_points(from_h: float, to_h: float, splashdown_h: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	if to_h <= from_h:
		return points
	var steps: int = maxi(ceili((to_h - from_h) / splashdown_h * 96.0), 2)
	for i in steps + 1:
		var get_h: float = lerpf(from_h, to_h, float(i) / steps)
		points.append(_map_point(MapPath.position(get_h, splashdown_h)))
	return points


## Draws the next leg in over MAP_REVEAL_S, pulses the ship marker and drifts the camera.
func _animate_map(delta: float) -> void:
	_map_t += delta
	var reveal: float = smoothstep(0.0, 1.0, _map_t / MAP_REVEAL_S)
	var shown: int = roundi(reveal * float(_next_points.size() - 1)) + 1
	if _next_points.size() >= 2 and shown >= 2:
		_path_next.mesh = _ribbon(_next_points.slice(0, mini(shown, _next_points.size())), 0.13)
	var pulse: float = 0.5 + 0.5 * sin(TAU * MAP_PULSE_HZ * _map_t)
	_marker_halo.scale = Vector3.ONE * lerpf(1.6, 2.4, pulse)
	_marker_halo.set_instance_shader_parameter("puff_color", Color(MARKER, lerpf(0.35, 0.6, pulse)))
	var from := Vector3(1.5 + sin(_map_t * 0.25) * 0.8, 21.0, 15.5)
	var aim := Vector3(1.5, 0.0, 0.8)
	_camera.global_transform = Transform3D(Basis.looking_at(aim - from, Vector3.UP), from)


func _map_point(flat: Vector2) -> Vector3:
	return Vector3(flat.x, 0.0, flat.y)


func _map_line(color: Color) -> MeshInstance3D:
	var line := MeshInstance3D.new()
	var material := _glowing(color, 1.2)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	line.material_override = material
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_map.add_child(line)
	return line


func _map_label(text: String, where: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = UiStyle.font(UiStyle.FONT_TITLE)
	label.font_size = 72
	label.pixel_size = 0.012
	label.outline_size = 12
	label.modulate = UiStyle.PLACARD_WHITE
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = where
	return label


func _ribbon(points: PackedVector3Array, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var dir: Vector3 = b - a
		if dir.length_squared() < 0.0001:
			continue
		var side: Vector3 = dir.normalized().cross(Vector3.UP).normalized() * width
		st.set_normal(Vector3.UP)
		st.add_vertex(a - side)
		st.add_vertex(a + side)
		st.add_vertex(b + side)
		st.add_vertex(a - side)
		st.add_vertex(b + side)
		st.add_vertex(b - side)
	return st.commit()


## A PuffCloud from a spec dictionary, built and added to parent.
func _cloud(parent: Node3D, spec: Dictionary) -> PuffCloud:
	var cloud := PuffCloud.new()
	cloud.count = spec.get("count", 24)
	cloud.seed_value = spec.get("seed", 1)
	cloud.origin = spec.get("origin", Vector3.ZERO)
	cloud.origin_jitter = spec.get("jitter", Vector3.ZERO)
	cloud.axis = spec.get("axis", Vector3.UP)
	cloud.spread_deg = spec.get("spread", 30.0)
	cloud.speed = spec.get("speed", Vector2(2.0, 4.0))
	cloud.drag = spec.get("drag", 3.0)
	cloud.drift = spec.get("drift", Vector3.ZERO)
	cloud.birth = spec.get("birth", Vector2(0.0, 0.5))
	cloud.life = spec.get("life", Vector2(0.3, 0.6))
	cloud.size = spec.get("size", Vector2(0.4, 2.0))
	cloud.color = spec.get("color", Color.WHITE)
	cloud.opacity = spec.get("opacity", 0.4)
	cloud.glow = spec.get("glow", false)
	cloud.wisp = spec.get("wisp", 0.35)
	parent.add_child(cloud)
	cloud.build()
	return cloud


## One soft glowing sprite, for flashes, the engine and the map marker.
func _glow_sprite(parent: Node3D, where: Vector3) -> MeshInstance3D:
	var sprite := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	sprite.mesh = quad
	var material := ShaderMaterial.new()
	if ResourceLoader.exists(GLOW_SHADER):
		material.shader = load(GLOW_SHADER)
	material.set_shader_parameter("wisp", 0.0)
	sprite.material_override = material
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.position = where
	sprite.visible = false
	sprite.set_instance_shader_parameter("puff_color", Color(1.0, 1.0, 1.0, 0.0))
	parent.add_child(sprite)
	return sprite


func _glowing(color: Color, energy: float) -> StandardMaterial3D:
	var material := Spacecraft.paint(color, 0.5)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _line_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


func _lines(points: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for point: Vector3 in points:
		st.add_vertex(point)
	return st.commit()


## Orange and white gores, like Odyssey's main parachutes.
func _canopy_material() -> StandardMaterial3D:
	var gores: int = 24
	var width: int = 8
	var image := Image.create_empty(gores * width, 4, false, Image.FORMAT_RGB8)
	for x in gores * width:
		var color: Color = CANOPY_ORANGE if (x / width) % 2 == 0 else CANOPY_WHITE
		for y in 4:
			image.set_pixel(x, y, color)
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

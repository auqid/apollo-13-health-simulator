extends Node
## Maps the simulation to what the audience sees (SPEC.md section 4). One full-screen shader under
## the HUD (vignette, blur, cold tint, condensation, blinks), camera shake, breath fog, HUD wobble,
## the caution and master alarm lamps, and the cabin light level with the explosion dim.
##
## mode "live" follows the simulation. The other modes show one driver at a time, scaled by strength.

const SimState := preload("res://sim/sim_state.gd")
const SimModel := preload("res://sim/sim_model.gd")
const FxMapping := preload("res://fx/fx_mapping.gd")
const Tuning := preload("res://sim/tuning.gd")
const Cabin := preload("res://scenes/cabin/cabin.gd")
const UiStyle := preload("res://scenes/ui/ui_style.gd")

const GROUP := "effects"
const SHADER_PATH := "res://fx/screen_fx.gdshader"
const MODE_LIVE := "live"
const MODE_CO2 := "co2"
const MODE_COLD := "cold"
const MODE_FATIGUE := "fatigue"
const MODE_POWER := "power"
const MODE_EXPLOSION := "explosion"
const MODES: Array[String] = [MODE_LIVE, MODE_CO2, MODE_COLD, MODE_FATIGUE, MODE_POWER, MODE_EXPLOSION]
const MODE_TITLES: Dictionary = {
	MODE_LIVE: "Live",
	MODE_CO2: "CO2",
	MODE_COLD: "Cold",
	MODE_FATIGUE: "Fatigue",
	MODE_POWER: "Power",
	MODE_EXPLOSION: "Explosion dim",
}

var cabin: Cabin
var mode: String = MODE_LIVE
## 0 to 1. In a forced mode, 1 is the strongest that driver gets on the historical path.
var strength: float = 1.0

var _material: ShaderMaterial
var _hud: CanvasLayer
var _puffs: Array[MeshInstance3D] = []
var _puff_age: Array[float] = []
var _puff_from: Array[Vector3] = []
var _puff_drift: Array[Vector3] = []
var _next_puff: int = 0
var _breath_phase: float = 0.0
var _vignette: float = 0.0
var _blur_px: float = 0.0
var _wobble_px: float = 0.0
var _shake: float = 0.0
var _fog_amount: float = 0.0
var _tint: float = 0.0
var _condensation: float = 0.0
var _light: float = 1.0
var _dim: float = 0.0
var _co2_lamp: float = 0.0
var _master_lamp: float = 0.0
var _fatigue: float = 0.0
var _dim_t: float = -1.0
var _last_get: float = -1.0
var _time_s: float = 0.0
var _blink_age: float = -1.0
var _blink_depth: float = 0.0
var _blink_wait: float = 0.0
var _blink_rng := RandomNumberGenerator.new()
var _shake_rng := RandomNumberGenerator.new()
var _shake_from := Vector3.ZERO
var _shake_to := Vector3.ZERO
var _shake_age: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	_blink_rng.seed = Tuning.FX_BLINK_SEED
	_shake_rng.seed = Tuning.FX_SHAKE_SEED
	_arm_blink(false)
	_build_screen()
	_build_fog()
	var host := get_node("/root/Game")
	host.connect("state_changed", _on_state_changed)
	_on_state_changed(host.get("state"))


func set_mode(mode_name: String) -> void:
	if mode_name not in MODES:
		push_warning("Unknown effect mode '%s'" % mode_name)
		return
	mode = mode_name
	if mode_name == MODE_EXPLOSION:
		play_explosion_dim()
	if mode_name == MODE_FATIGUE:
		_arm_blink(true)


func set_strength(value: float) -> void:
	strength = clampf(value, 0.0, 1.0)


func play_explosion_dim() -> void:
	_dim_t = 0.0


## One line for the debug panel.
## True while the red master alarm lamps are lit, during the explosion dim.
func master_alarm_lit() -> bool:
	return _master_lamp > 0.35


func summary() -> String:
	return "Vignette %.2f   Blur %.1f px   Wobble %.1f px\nShake %.3f°   Fog %.0f%%   Tint %.0f%%   Condensation %.0f%%\nCO2 lamp %.0f%%   Master alarm %.0f%%   Light %.0f%%   Blink %.0f%%" % [
		_vignette, _blur_px, _wobble_px,
		rad_to_deg(_shake), _fog_amount * 100.0, _tint / Tuning.FX_TINT_MAX * 100.0, _condensation * 100.0,
		_co2_lamp * 100.0, _master_lamp * 100.0, _light * (1.0 - _dim) * 100.0, _blink_blackout() * 100.0]


func _process(delta: float) -> void:
	_time_s += delta
	_advance_dim(delta)
	var targets: Dictionary = _targets(get_node("/root/Game").get("state"))
	_fatigue = targets["fatigue"]
	_advance_blink(delta)
	_vignette = _approach(_vignette, targets["vignette"], delta, Tuning.FX_SMOOTH_S)
	_blur_px = _approach(_blur_px, targets["blur_px"], delta, Tuning.FX_SMOOTH_S)
	_wobble_px = _approach(_wobble_px, targets["wobble_px"], delta, Tuning.FX_SMOOTH_S)
	_shake = _approach(_shake, targets["shake"], delta, Tuning.FX_SMOOTH_S)
	_fog_amount = _approach(_fog_amount, targets["fog"], delta, Tuning.FX_SMOOTH_S)
	_tint = _approach(_tint, targets["tint"], delta, Tuning.FX_SMOOTH_S)
	_condensation = _approach(_condensation, targets["condensation"], delta, Tuning.FX_SMOOTH_S)
	_light = _approach(_light, targets["light"], delta, Tuning.FX_SMOOTH_S)
	_dim = targets["dim"]
	_co2_lamp = _approach(_co2_lamp, targets["co2_lamp"], delta, Tuning.FX_LAMP_FADE_S)
	_master_lamp = _approach(_master_lamp, targets["master_lamp"], delta, Tuning.FX_LAMP_FADE_S)
	_apply()


func _on_state_changed(state: SimState) -> void:
	var at_get: float = state.time.current_get
	var crossed: bool = _last_get >= 0.0 and _last_get < Tuning.EXPLOSION_GET and at_get >= Tuning.EXPLOSION_GET
	var jumped_back: bool = _last_get > Tuning.EXPLOSION_GET + 1.0 and at_get <= Tuning.EXPLOSION_GET + 0.05
	if mode == MODE_LIVE and (crossed or jumped_back):
		play_explosion_dim()
	_last_get = at_get


# --- What each mode asks for ---

func _targets(state: SimState) -> Dictionary:
	var co2: float = state.env.co2_mmhg
	var temp: float = state.env.cabin_temp_c
	var margin: float = state.env.power_margin
	var fatigue: float = _crew_fatigue(state)
	var power_up: String = state.flags.power_up
	var e5_reached: bool = "e5" in state.reached_events
	var alarm: bool = SimModel.co2_alarm(state)
	var show_cold: bool = true
	var show_co2: bool = true
	var show_power: bool = true
	match mode:
		MODE_CO2:
			co2 = lerpf(Tuning.FX_VIGNETTE_CO2_START, Tuning.CO2_CURVE_BY_ADAPTER["wait"]["peak_mmhg"], strength)
			show_cold = false
			show_power = false
			alarm = co2 > Tuning.CO2_ALARM_MMHG
			fatigue = 0.0
		MODE_COLD:
			temp = lerpf(Tuning.FX_FOG_BELOW_C, Tuning.FX_FOG_FULL_C, strength)
			show_co2 = false
			show_power = false
			alarm = false
			fatigue = 0.0
			e5_reached = false
			power_up = "late"
		MODE_FATIGUE:
			fatigue = lerpf(Tuning.FX_BLINK_FATIGUE_ABOVE, 1.0, strength)
			show_co2 = false
			show_cold = false
			show_power = false
			alarm = false
		MODE_POWER:
			margin = lerpf(Tuning.POWER_MARGIN_START, Tuning.POWER_MARGIN_MIN, strength)
			show_co2 = false
			show_cold = false
			alarm = false
			fatigue = 0.0
		MODE_EXPLOSION:
			show_co2 = false
			show_cold = false
			alarm = false
			fatigue = 0.0
			margin = Tuning.POWER_MARGIN_START
	var dim: float = FxMapping.explosion_dim(_dim_t) if mode == MODE_LIVE or mode == MODE_EXPLOSION else 0.0
	var light: float = 1.0
	if show_power or mode == MODE_EXPLOSION:
		light = FxMapping.light_level(margin)
	return {
		"vignette": FxMapping.vignette(co2) if show_co2 else 0.0,
		"blur_px": FxMapping.blur_px(co2) if show_co2 else 0.0,
		"wobble_px": FxMapping.wobble_px(co2) if show_co2 else 0.0,
		"shake": FxMapping.shake_rad(temp) if show_cold else 0.0,
		"fog": FxMapping.fog(temp) if show_cold else 0.0,
		"tint": FxMapping.tint(temp) if show_cold else 0.0,
		"condensation": _condensation_target(temp, state.time.current_get, power_up, e5_reached) if show_cold else 0.0,
		"light": light,
		"dim": dim,
		"co2_lamp": 1.0 if alarm else 0.0,
		"master_lamp": 1.0 if dim > 0.05 else 0.0,
		"fatigue": fatigue,
	}


func _condensation_target(temp: float, at_get: float, power_up: String, e5_reached: bool) -> float:
	if mode == MODE_COLD:
		return 1.0 if temp < Tuning.FX_CONDENSATION_BELOW_C else 0.0
	return FxMapping.condensation(temp, at_get, power_up, e5_reached)


func _crew_fatigue(state: SimState) -> float:
	var worst: float = 0.0
	for crew_id in SimState.CREW_IDS:
		worst = maxf(worst, state.crew[crew_id].fatigue)
	return worst


# --- Applying ---

func _apply() -> void:
	_apply_shader()
	_apply_shake()
	_apply_fog()
	_apply_wobble()
	_apply_lamps()
	if cabin != null:
		cabin.set_light_level(_light * (1.0 - _dim))


func _apply_shader() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("vignette", _vignette)
	_material.set_shader_parameter("blur_px", _blur_px)
	_material.set_shader_parameter("tint", _tint)
	_material.set_shader_parameter("condensation", _condensation)
	_material.set_shader_parameter("blackout", _blink_blackout())


func _apply_shake() -> void:
	if cabin == null or cabin.camera == null:
		return
	cabin.camera.shake_rotation = _shake_offset() * _shake


func _shake_offset() -> Vector3:
	var step_s: float = 1.0 / Tuning.FX_SHAKE_HZ
	_shake_age += get_process_delta_time()
	if _shake_age >= step_s:
		_shake_age = fmod(_shake_age, step_s)
		_shake_from = _shake_to
		_shake_to = Vector3(_shake_rng.randf_range(-1.0, 1.0), _shake_rng.randf_range(-1.0, 1.0), _shake_rng.randf_range(-1.0, 1.0))
		if _shake_to.length() < 0.001:
			_shake_to = Vector3.UP
		_shake_to = _shake_to.normalized()
	return _shake_from.lerp(_shake_to, smoothstep(0.0, 1.0, _shake_age / step_s))


func _apply_fog() -> void:
	if _puffs.is_empty():
		return
	var phase: float = 0.0
	var bio := get_tree().get_first_node_in_group("bio_audio")
	if bio != null:
		phase = bio.breath_phase()
	var exhale: float = Tuning.AUDIO_BREATH_INHALE
	if _fog_amount > 0.05 and _breath_phase < exhale and phase >= exhale:
		_start_puff()
	_breath_phase = phase
	var life_s: float = Tuning.FX_FOG_PUFF_S
	var dt_s: float = get_process_delta_time()
	for i in _puffs.size():
		if _puff_age[i] < 0.0:
			_puffs[i].visible = false
			continue
		_puff_age[i] += dt_s
		var t: float = _puff_age[i] / life_s
		if t >= 1.0:
			_puff_age[i] = -1.0
			_puffs[i].visible = false
			continue
		var fade: float = smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.35, 1.0, t))
		_puffs[i].position = _puff_from[i] + _puff_drift[i] * t
		_puffs[i].visible = true
		var material: StandardMaterial3D = _puffs[i].material_override
		var color: Color = material.albedo_color
		color.a = fade * Tuning.FX_FOG_MAX_ALPHA * _fog_amount
		material.albedo_color = color


func _apply_wobble() -> void:
	if _hud == null:
		_hud = get_tree().get_first_node_in_group("hud")
	if _hud == null:
		return
	if _wobble_px < 0.05:
		_hud.offset = Vector2.ZERO
		return
	var periods: Vector2 = Tuning.FX_WOBBLE_PERIODS_S
	_hud.offset = Vector2(sin(TAU * _time_s / periods.x), sin(TAU * _time_s / periods.y + 1.7)) * _wobble_px


func _apply_lamps() -> void:
	if cabin == null:
		return
	cabin.set_lamp_level("co2", _co2_lamp)
	cabin.set_lamp_level("master_alarm", _master_lamp)


func _advance_dim(delta: float) -> void:
	if _dim_t < 0.0:
		return
	_dim_t += delta
	var recover_end: float = Tuning.FX_EXPLOSION_DIM_DROP_S + Tuning.FX_EXPLOSION_DIM_HOLD_S + Tuning.FX_EXPLOSION_DIM_RECOVER_S
	if _dim_t >= recover_end:
		_dim_t = -1.0


func _advance_blink(delta: float) -> void:
	if _blink_age >= 0.0:
		_blink_age += delta
		if _blink_age >= Tuning.FX_BLINK_S:
			_blink_age = -1.0
			_arm_blink(false)
		return
	if FxMapping.blink_depth(_fatigue) <= 0.0:
		return
	_blink_wait -= delta
	if _blink_wait <= 0.0:
		_blink_age = 0.0
		_blink_depth = FxMapping.blink_depth(_fatigue)


func _blink_blackout() -> float:
	if _blink_age < 0.0:
		return 0.0
	return _blink_depth * FxMapping.blink_profile(_blink_age)


func _arm_blink(soon: bool) -> void:
	_blink_age = -1.0
	_blink_wait = Tuning.FX_FORCED_FIRST_BLINK_S if soon else _blink_rng.randf_range(Tuning.FX_BLINK_INTERVAL_S_MIN, Tuning.FX_BLINK_INTERVAL_S_MAX)


func _approach(current: float, target: float, delta: float, seconds: float) -> float:
	if seconds <= 0.0:
		return target
	return lerpf(current, target, 1.0 - exp(-delta / seconds))


# --- Building ---

func _build_screen() -> void:
	if not ResourceLoader.exists(SHADER_PATH):
		push_warning("Missing %s, screen effects are off" % SHADER_PATH)
		return
	var layer := CanvasLayer.new()
	layer.layer = UiStyle.LAYER_SCREEN_FX
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH)
	var tint: Color = UiStyle.COLD_TINT
	_material.set_shader_parameter("tint_color", Vector3(tint.r, tint.g, tint.b))
	_material.set_shader_parameter("vignette_inner", Tuning.FX_VIGNETTE_INNER)
	_material.set_shader_parameter("vignette_outer", Tuning.FX_VIGNETTE_OUTER)
	_material.set_shader_parameter("droplet_cells", Tuning.FX_DROPLET_CELLS)
	_material.set_shader_parameter("droplet_centre_share", Tuning.FX_DROPLET_CENTRE_SHARE)
	rect.material = _material
	layer.add_child(rect)
	add_child(layer)


func _start_puff() -> void:
	var i: int = _next_puff
	_next_puff = (_next_puff + 1) % _puffs.size()
	var side: float = Tuning.FX_FOG_SIDE_M if i == 0 else -Tuning.FX_FOG_SIDE_M
	_puff_from[i] = Vector3(side, -Tuning.FX_FOG_DROP_M, -Tuning.FX_FOG_DISTANCE_M)
	_puff_drift[i] = Vector3(Tuning.FX_FOG_DRIFT_M * (1.0 if i == 0 else -1.0), Tuning.FX_FOG_DRIFT_M * 0.35, 0.0)
	_puff_age[i] = 0.0


func _build_fog() -> void:
	if cabin == null or cabin.camera == null:
		return
	var disc := QuadMesh.new()
	disc.size = Vector2(Tuning.FX_FOG_PUFF_M, Tuning.FX_FOG_PUFF_M)
	var texture := _soft_disc()
	for i in 2:
		var puff := MeshInstance3D.new()
		puff.mesh = disc
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_texture = texture
		material.albedo_color = Color(0.86, 0.91, 0.95, 0.0)
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		puff.material_override = material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.visible = false
		cabin.camera.add_child(puff)
		_puffs.append(puff)
		_puff_age.append(-1.0)
		_puff_from.append(Vector3.ZERO)
		_puff_drift.append(Vector3.ZERO)


func _soft_disc() -> ImageTexture:
	var size: int = 64
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var center: float = size * 0.5
	for y in size:
		for x in size:
			var dist: float = Vector2(x + 0.5 - center, y + 0.5 - center).length() / center
			var alpha: float = clampf(1.0 - dist, 0.0, 1.0)
			alpha *= alpha
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)

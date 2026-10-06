extends CanvasLayer
## Mission clock (top left) and the sensor panel (right): three crew rows, then the cabin
## readings (SPEC.md section 5). Built in code and updated from Game.state_changed.

const SimState := preload("res://sim/sim_state.gd")
const SimModel := preload("res://sim/sim_model.gd")
const Tuning := preload("res://sim/tuning.gd")
const UiStyle := preload("res://scenes/ui/ui_style.gd")
const Co2Bar := preload("res://scenes/ui/co2_bar.gd")
const CrewLook := preload("res://scenes/ui/crew_look.gd")
const HeartIcon := preload("res://scenes/ui/heart_icon.gd")
const FacePhoto := preload("res://scenes/ui/face_photo.gd")

const PANEL_LABEL := "Modern sensors on a 1970 crew."
## Crew vitals columns: state field, header, unit.
const VITAL_COLUMNS: Array[Dictionary] = [
	{"field": "hr", "header": "Heart", "unit": "bpm"},
	{"field": "spo2", "header": "SpO2", "unit": "%"},
	{"field": "rr", "header": "Breaths", "unit": "per min"},
	{"field": "body_temp_c", "header": "Temp", "unit": "°C"},
]
const CO2_LIMIT_TEXT := "Safe limit %.1f mmHg"
## Changes smaller than this, per state update, count as steady.
const TREND_EPSILON := 0.0001

var _left: VBoxContainer
var _clock_box: PanelContainer
var _clock: Label
var _since: Label
var _panel: PanelContainer
var _fade: Tween
var _spot_key: String = ""
var _spot_box: PanelContainer
var _spot_title: Label
var _spot_value: Label
var _spot_trend: Label
var _spot_last: float = NAN
## Spotlight key -> the sensor panel row it lights up.
var _env_rows: Dictionary = {}
## crew id -> {"row", "name", "status", "face", "heart", <vital field>: Label}
var _rows: Dictionary = {}
var _cabin_temp: Label
var _co2: Label
var _pressure: Label
var _water: Label
var _power: Label
var _co2_bar: Co2Bar
var _row_style: StyleBoxFlat
var _focus_style: StyleBoxFlat
## Label -> whether it's currently shown in the caution colour.
var _cautions: Dictionary = {}


func _ready() -> void:
	add_to_group("hud")
	layer = UiStyle.LAYER_HUD
	_row_style = _make_row_style(false)
	_focus_style = _make_row_style(true)
	_build_clock()
	_build_panel()
	Game.state_changed.connect(_on_state_changed)
	Game.focus_changed.connect(_on_focus_changed)
	Director.hud_visibility_changed.connect(_on_hud_visibility_changed)
	_on_focus_changed(Game.focused_crew)
	_on_state_changed(Game.state)


## Fades the clock and the sensor panel out for cutscenes and the reentry, and back in for play.
## The cinematic bars carry the mission clock meanwhile.
func set_cinematic(on: bool) -> void:
	if _fade != null:
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	var alpha: float = 0.0 if on else 1.0
	for part: Control in [_left, _panel]:
		_fade.tween_property(part, "modulate:a", alpha, UiStyle.FADE_S)


## Puts the value a decision changes under the clock, with its trend, and lights up its row in the
## sensor panel. An empty key clears it.
func set_spotlight(key: String) -> void:
	_spot_key = key if UiStyle.SPOTLIGHTS.has(key) else ""
	_spot_last = NAN
	_spot_box.visible = not _spot_key.is_empty()
	for row_key: String in _env_rows:
		_env_rows[row_key].add_theme_stylebox_override("panel", _focus_style if row_key == _spot_key else _row_style)
	if not _spot_key.is_empty():
		_spot_title.text = str(UiStyle.SPOTLIGHTS[_spot_key]["title"])
		_spot_trend.text = ""
		_update_spotlight(Game.state)


func _build_clock() -> void:
	_left = VBoxContainer.new()
	_left.position = Vector2(UiStyle.MARGIN, UiStyle.MARGIN)
	_left.add_theme_constant_override("separation", UiStyle.SECTION_GAP)
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_left)
	var box := PanelContainer.new()
	_clock_box = box
	box.add_theme_stylebox_override("panel", UiStyle.panel_box())
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UiStyle.ROW_PADDING)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(UiStyle.label("GET", UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_CLOCK, UiStyle.TEXT_DIM))
	_clock = UiStyle.label("", UiStyle.FONT_HUD, UiStyle.SIZE_CLOCK, UiStyle.PLACARD_WHITE, true)
	line.add_child(_clock)
	column.add_child(line)
	_since = UiStyle.label("", UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_BODY, UiStyle.TEXT_DIM, true)
	column.add_child(_since)
	box.add_child(column)
	_left.add_child(box)
	_build_spotlight()


func _build_spotlight() -> void:
	_spot_box = PanelContainer.new()
	var style := UiStyle.panel_box()
	style.border_color = UiStyle.SENSOR_TEAL
	style.border_width_left = UiStyle.FOCUS_BAR_WIDTH
	_spot_box.add_theme_stylebox_override("panel", style)
	_spot_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spot_box.visible = false
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spot_title = UiStyle.label("", UiStyle.FONT_HUD, UiStyle.SIZE_NAME, UiStyle.SENSOR_TEAL)
	column.add_child(_spot_title)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UiStyle.SECTION_GAP)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spot_value = UiStyle.label("", UiStyle.FONT_HUD_STRONG, UiStyle.SIZE_SPOTLIGHT, UiStyle.PLACARD_WHITE, true)
	line.add_child(_spot_value)
	_spot_trend = UiStyle.label("", UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_NAME, UiStyle.TEXT_DIM)
	_spot_trend.size_flags_vertical = Control.SIZE_SHRINK_END
	line.add_child(_spot_trend)
	column.add_child(line)
	_spot_box.add_child(column)
	_left.add_child(_spot_box)


func _update_spotlight(state: SimState) -> void:
	if _spot_key.is_empty() or state == null:
		return
	var value: float = 0.0
	match _spot_key:
		"cabin_temp":
			value = state.env.cabin_temp_c
			_spot_value.text = "%.1f °C" % value
		"co2":
			value = state.env.co2_mmhg
			_spot_value.text = "%.1f mmHg" % value
		"water":
			value = state.env.water_pct
			_spot_value.text = "%d%%" % roundi(value)
		"power":
			value = state.env.power_margin
			_spot_value.text = "%d" % roundi(value)
		"splashdown":
			value = maxf(state.time.splashdown_get - state.time.current_get, 0.0)
			_spot_value.text = UiStyle.format_hours(value)
	if not is_nan(_spot_last) and absf(value - _spot_last) > TREND_EPSILON:
		_spot_trend.text = "Rising" if value > _spot_last else "Falling"
	_spot_last = value
	_set_caution(_spot_value, _spot_key == "co2" and SimModel.co2_alarm(state))


func _build_panel() -> void:
	var panel := PanelContainer.new()
	_panel = panel
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -(UiStyle.MARGIN + UiStyle.HUD_PANEL_WIDTH)
	panel.offset_right = -UiStyle.MARGIN
	panel.offset_top = UiStyle.MARGIN
	panel.offset_bottom = UiStyle.MARGIN
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiStyle.ROW_GAP)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(UiStyle.label(PANEL_LABEL, UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_LABEL, UiStyle.SENSOR_TEAL))
	column.add_child(UiStyle.divider())
	column.add_child(_header_row("header", UiStyle.TEXT_DIM))
	column.add_child(_header_row("unit", UiStyle.TEXT_FAINT))
	for crew_id in SimState.CREW_IDS:
		column.add_child(_crew_row(crew_id))
	column.add_child(_gap())
	column.add_child(UiStyle.divider())
	_cabin_temp = _env_row(column, "Cabin temperature", "cabin_temp")
	_co2 = _env_row(column, "CO2", "co2")
	_co2_bar = Co2Bar.new()
	column.add_child(_co2_bar)
	column.add_child(_co2_limit_row())
	_pressure = _env_row(column, "Cabin pressure", "pressure")
	_water = _env_row(column, "Water", "water")
	_power = _env_row(column, "Power margin", "power")
	panel.add_child(column)
	add_child(panel)


func _header_row(key: String, color: Color) -> Control:
	var margin := _row_margin()
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spacer := Control.new()
	spacer.custom_minimum_size.x = UiStyle.FACE_SIZE.x + UiStyle.ROW_PADDING + UiStyle.CREW_NAME_WIDTH
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(spacer)
	for column: Dictionary in VITAL_COLUMNS:
		var cell := UiStyle.label(column[key], UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_LABEL, color)
		cell.custom_minimum_size.x = UiStyle.VITAL_COLUMN_WIDTH
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(cell)
	margin.add_child(line)
	return margin


## One crew member: their photo (reacting to how they are), name and a short status, then vitals.
func _crew_row(crew_id: String) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face := FacePhoto.new(UiStyle.FACE_SIZE)
	face.show_person(Game.events.get("people", {}), SimState.CREW_NAMES[crew_id])
	line.add_child(face)
	var gap := Control.new()
	gap.custom_minimum_size.x = UiStyle.ROW_PADDING
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(gap)
	# Name and vitals on one line, and under them a status that can use the whole width.
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", 0)
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := UiStyle.label(SimState.CREW_NAMES[crew_id], UiStyle.FONT_HUD, UiStyle.SIZE_NAME, UiStyle.TEXT_DIM)
	name_label.custom_minimum_size.x = UiStyle.CREW_NAME_WIDTH
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	top.add_child(name_label)
	who.add_child(top)
	var status := UiStyle.label("", UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_LABEL, UiStyle.TEXT_DIM)
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.add_child(status)
	line.add_child(who)
	var cells: Dictionary = {"row": row, "name": name_label, "status": status, "face": face}
	for column: Dictionary in VITAL_COLUMNS:
		var value := UiStyle.label("", UiStyle.FONT_HUD_STRONG, UiStyle.SIZE_VITAL, UiStyle.PLACARD_WHITE, true)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cells[column["field"]] = value
		if column["field"] != "hr":
			value.custom_minimum_size.x = UiStyle.VITAL_COLUMN_WIDTH
			top.add_child(value)
			continue
		# Heart rate: a heart beating at that rate, then the number.
		var cell := HBoxContainer.new()
		cell.custom_minimum_size.x = UiStyle.VITAL_COLUMN_WIDTH
		cell.alignment = BoxContainer.ALIGNMENT_END
		cell.add_theme_constant_override("separation", UiStyle.HEART_ICON_GAP)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var heart := HeartIcon.new()
		heart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(heart)
		cell.add_child(value)
		top.add_child(cell)
		cells["heart"] = heart
	row.add_child(line)
	_rows[crew_id] = cells
	return row


func _env_row(column: VBoxContainer, text: String, key: String) -> Label:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _row_style)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_env_rows[key] = row
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := UiStyle.label(text, UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_BODY, UiStyle.TEXT_DIM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.size_flags_vertical = Control.SIZE_FILL
	var value := UiStyle.label("", UiStyle.FONT_HUD, UiStyle.SIZE_ENV_VALUE, UiStyle.PLACARD_WHITE, true)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(name_label)
	line.add_child(value)
	row.add_child(line)
	column.add_child(row)
	return value


## "Safe limit 7.6 mmHg", starting under the marker on the CO2 bar.
func _co2_limit_row() -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var before := Control.new()
	before.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	before.size_flags_stretch_ratio = Tuning.CO2_ALARM_MMHG
	before.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := UiStyle.label(CO2_LIMIT_TEXT % Tuning.CO2_ALARM_MMHG, UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_LABEL, UiStyle.TEXT_FAINT)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_stretch_ratio = Tuning.HUD_CO2_BAR_MAX_MMHG - Tuning.CO2_ALARM_MMHG
	line.add_child(before)
	line.add_child(text)
	return line


func _row_margin() -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UiStyle.ROW_PADDING)
	margin.add_theme_constant_override("margin_right", UiStyle.ROW_PADDING)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return margin


func _gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = UiStyle.SECTION_GAP - UiStyle.ROW_GAP
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _make_row_style(focused: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = UiStyle.FOCUS_FILL if focused else Color(UiStyle.FOCUS_FILL, 0.0)
	box.border_color = UiStyle.SENSOR_TEAL
	box.border_width_left = UiStyle.FOCUS_BAR_WIDTH if focused else 0
	box.content_margin_left = UiStyle.ROW_PADDING
	box.content_margin_right = UiStyle.ROW_PADDING
	box.content_margin_top = UiStyle.ROW_PADDING_V
	box.content_margin_bottom = UiStyle.ROW_PADDING_V
	return box


func _on_state_changed(state: SimState) -> void:
	_clock.text = UiStyle.format_get(state.time.current_get)
	var since_h: float = state.time.current_get - Tuning.EXPLOSION_GET
	_since.text = "%s since the explosion" % UiStyle.format_hours(since_h) if since_h >= 0.0 else "Before the explosion"
	for crew_id in SimState.CREW_IDS:
		var member: SimState.CrewMember = state.crew[crew_id]
		var cells: Dictionary = _rows[crew_id]
		cells["hr"].text = "%d" % roundi(member.hr)
		cells["spo2"].text = "%d" % roundi(member.spo2)
		cells["rr"].text = "%d" % roundi(member.rr)
		cells["body_temp_c"].text = "%.1f" % member.body_temp_c
		_set_caution(cells["body_temp_c"], member.body_temp_c >= Tuning.FEVER_CAPTION_C)
		cells["status"].text = CrewLook.status(member, state.env)
		var warning: bool = CrewLook.is_warning(member, state.env)
		cells["status"].add_theme_color_override("font_color", UiStyle.CAUTION_AMBER if warning else UiStyle.TEXT_DIM)
		cells["face"].react(member, state.env)
		cells["heart"].bpm = member.hr
		cells["heart"].color = UiStyle.CAUTION_AMBER if member.hr >= Tuning.CREW_HEART_RACING_BPM else UiStyle.SENSOR_TEAL
	_cabin_temp.text = "%.1f °C" % state.env.cabin_temp_c
	_co2.text = "%.1f mmHg" % state.env.co2_mmhg
	_set_caution(_co2, SimModel.co2_alarm(state))
	_co2_bar.co2_mmhg = state.env.co2_mmhg
	_pressure.text = "%.2f psi" % state.env.pressure_psi
	_water.text = "%d%%" % roundi(state.env.water_pct)
	_power.text = "%d" % roundi(state.env.power_margin)
	_update_spotlight(state)


func _on_focus_changed(crew_id: String) -> void:
	for id: String in _rows:
		var cells: Dictionary = _rows[id]
		var focused: bool = id == crew_id
		cells["row"].add_theme_stylebox_override("panel", _focus_style if focused else _row_style)
		cells["name"].add_theme_color_override("font_color", UiStyle.SENSOR_TEAL if focused else UiStyle.TEXT_DIM)


func _on_hud_visibility_changed(shown: bool) -> void:
	visible = shown


func _set_caution(target: Label, caution: bool) -> void:
	if _cautions.get(target, false) == caution:
		return
	_cautions[target] = caution
	target.add_theme_color_override("font_color", UiStyle.CAUTION_AMBER if caution else UiStyle.PLACARD_WHITE)

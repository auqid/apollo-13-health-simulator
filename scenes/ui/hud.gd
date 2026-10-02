extends CanvasLayer
## Mission clock (top left) and the sensor panel (right): three crew rows, then the cabin
## readings (SPEC.md section 5). Built in code and updated from Game.state_changed.

const SimState := preload("res://sim/sim_state.gd")
const SimModel := preload("res://sim/sim_model.gd")
const Tuning := preload("res://sim/tuning.gd")
const UiStyle := preload("res://scenes/ui/ui_style.gd")
const Co2Bar := preload("res://scenes/ui/co2_bar.gd")

const PANEL_LABEL := "Modern sensors on a 1970 crew."
## Crew vitals columns: state field, header, unit.
const VITAL_COLUMNS: Array[Dictionary] = [
	{"field": "hr", "header": "Heart", "unit": "bpm"},
	{"field": "spo2", "header": "SpO2", "unit": "%"},
	{"field": "rr", "header": "Breaths", "unit": "per min"},
	{"field": "body_temp_c", "header": "Temp", "unit": "°C"},
]
const CO2_LIMIT_TEXT := "Safe limit %.1f mmHg"

var _clock: Label
var _since: Label
## crew id -> {"row": PanelContainer, "name": Label, <vital field>: Label}
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


func _build_clock() -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiStyle.panel_box())
	box.position = Vector2(UiStyle.MARGIN, UiStyle.MARGIN)
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
	add_child(box)


func _build_panel() -> void:
	var panel := PanelContainer.new()
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
	_cabin_temp = _env_row(column, "Cabin temperature")
	_co2 = _env_row(column, "CO2")
	_co2_bar = Co2Bar.new()
	column.add_child(_co2_bar)
	column.add_child(_co2_limit_row())
	_pressure = _env_row(column, "Cabin pressure")
	_water = _env_row(column, "Water")
	_power = _env_row(column, "Power margin")
	panel.add_child(column)
	add_child(panel)


func _header_row(key: String, color: Color) -> Control:
	var margin := _row_margin()
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spacer := Control.new()
	spacer.custom_minimum_size.x = UiStyle.NAME_COLUMN_WIDTH
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


func _crew_row(crew_id: String) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := UiStyle.label(SimState.CREW_NAMES[crew_id], UiStyle.FONT_HUD, UiStyle.SIZE_NAME, UiStyle.TEXT_DIM)
	name_label.custom_minimum_size.x = UiStyle.NAME_COLUMN_WIDTH
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.size_flags_vertical = Control.SIZE_FILL
	line.add_child(name_label)
	var cells: Dictionary = {"row": row, "name": name_label}
	for column: Dictionary in VITAL_COLUMNS:
		var value := UiStyle.label("", UiStyle.FONT_HUD_STRONG, UiStyle.SIZE_VITAL, UiStyle.PLACARD_WHITE, true)
		value.custom_minimum_size.x = UiStyle.VITAL_COLUMN_WIDTH
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)
		cells[column["field"]] = value
	row.add_child(line)
	_rows[crew_id] = cells
	return row


func _env_row(column: VBoxContainer, text: String) -> Label:
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
	column.add_child(line)
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
	_cabin_temp.text = "%.1f °C" % state.env.cabin_temp_c
	_co2.text = "%.1f mmHg" % state.env.co2_mmhg
	_set_caution(_co2, SimModel.co2_alarm(state))
	_co2_bar.co2_mmhg = state.env.co2_mmhg
	_pressure.text = "%.2f psi" % state.env.pressure_psi
	_water.text = "%d%%" % roundi(state.env.water_pct)
	_power.text = "%d" % roundi(state.env.power_margin)


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

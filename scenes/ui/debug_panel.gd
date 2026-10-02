extends CanvasLayer
## Debug panel, toggled with `: clock controls, scrubbing, jumping to any event, forcing one
## effect at a time, the poll choice for each event, holding any state value, and a readout.

const SimState := preload("res://sim/sim_state.gd")
const SimModel := preload("res://sim/sim_model.gd")
const Timeline := preload("res://sim/timeline.gd")
const Tuning := preload("res://sim/tuning.gd")
const UiStyle := preload("res://scenes/ui/ui_style.gd")
const Cabin := preload("res://scenes/cabin/cabin.gd")
const Effects := preload("res://fx/effects.gd")
const BioAudio := preload("res://audio/bio_audio.gd")
const AudioMix := preload("res://audio/audio_mix.gd")

## Values the panel can hold, with the range each number box offers.
const ENV_FIELDS: Array[Dictionary] = [
	{"path": "env.cabin_temp_c", "label": "Cabin temperature (°C)", "min": -10.0, "max": 30.0, "step": 0.1},
	{"path": "env.co2_mmhg", "label": "CO2 (mmHg)", "min": 0.0, "max": 25.0, "step": 0.1},
	{"path": "env.pressure_psi", "label": "Cabin pressure (psi)", "min": 4.0, "max": 5.5, "step": 0.01},
	{"path": "env.water_pct", "label": "Water (%)", "min": 0.0, "max": 100.0, "step": 1.0},
	{"path": "env.power_margin", "label": "Power margin", "min": 0.0, "max": 150.0, "step": 1.0},
	{"path": "stress", "label": "Stress (bpm)", "min": 0.0, "max": 60.0, "step": 1.0},
]
const CREW_FIELDS: Array[Dictionary] = [
	{"field": "hr", "label": "Heart rate (bpm)", "min": 40.0, "max": 160.0, "step": 1.0},
	{"field": "spo2", "label": "SpO2 (%)", "min": 95.0, "max": 99.0, "step": 1.0},
	{"field": "rr", "label": "Breaths per min", "min": 8.0, "max": 40.0, "step": 1.0},
	{"field": "body_temp_c", "label": "Body temperature (°C)", "min": 35.0, "max": 40.0, "step": 0.1},
	{"field": "hydration", "label": "Hydration (0 to 1)", "min": 0.0, "max": 1.0, "step": 0.01},
	{"field": "fatigue", "label": "Fatigue (0 to 1)", "min": 0.0, "max": 1.0, "step": 0.01},
]
const SCRUB_STEP_H := 0.01

var _clock_label: Label
var _play_button: Button
var _rate_option: OptionButton
var _scrub: HSlider
var _dragging: bool = false
var _jump_box: HFlowContainer
## event id -> Label showing whether its choice has been applied yet
var _choice_status: Dictionary = {}
## {"path": String, "field": String, "spin": SpinBox, "hold": CheckBox}
var _hold_rows: Array[Dictionary] = []
var _crew_heading: Label
var _readout: Label
var _effect_buttons: Dictionary = {}
var _effect_strength: HSlider
var _effect_summary: Label
var _sound_summary: Label
var _fps_label: Label


func _ready() -> void:
	layer = UiStyle.LAYER_DEBUG
	_build()
	Director.debug_visibility_changed.connect(_on_visibility_changed)
	Game.state_changed.connect(_on_state_changed)
	Game.clock_changed.connect(_on_clock_changed)
	Game.focus_changed.connect(_on_focus_changed)
	_on_focus_changed(Game.focused_crew)
	_on_clock_changed(Game.running, Game.rate_h_per_s)
	_on_visibility_changed(Director.debug_visible)


## Typing in a number box keeps the keyboard, but ` and Space still reach the presenter keys.
func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.is_pressed():
		return
	if event.is_action_pressed("toggle_debug") or event.is_action_pressed("advance"):
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused != null and is_ancestor_of(focused):
			focused.release_focus()


# --- Building ---

func _build() -> void:
	var panel := PanelContainer.new()
	panel.theme = _make_theme()
	var box: StyleBoxFlat = UiStyle.panel_box()
	box.bg_color = UiStyle.DEBUG_FILL
	box.border_color = UiStyle.DEBUG_LINE
	panel.add_theme_stylebox_override("panel", box)
	panel.offset_left = UiStyle.MARGIN
	panel.offset_right = UiStyle.MARGIN + UiStyle.DEBUG_PANEL_WIDTH
	panel.offset_top = UiStyle.DEBUG_PANEL_TOP
	panel.anchor_bottom = 1.0
	panel.offset_bottom = -UiStyle.MARGIN

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", UiStyle.DEBUG_SCROLL_GUTTER)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", UiStyle.ROW_GAP)
	gutter.add_child(column)
	scroll.add_child(gutter)
	panel.add_child(scroll)
	add_child(panel)

	var title_line := HBoxContainer.new()
	var title := _heading("Debug panel. Press ` to close.")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_line.add_child(title)
	_fps_label = _text("0 fps")
	title_line.add_child(_fps_label)
	column.add_child(title_line)
	_build_clock(column)
	_build_view(column)
	_build_effects(column)
	_build_sound(column)
	_build_jumps(column)
	_build_choices(column)
	_build_holds(column)
	column.add_child(_heading("Internals"))
	_readout = _text("")
	_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_readout)


func _build_clock(column: VBoxContainer) -> void:
	var line := HBoxContainer.new()
	_play_button = _button("Play", Game.toggle_play)
	line.add_child(_play_button)
	line.add_child(_button("Restart", Director.restart_now))
	line.add_child(_text("Speed"))
	_rate_option = OptionButton.new()
	_rate_option.focus_mode = Control.FOCUS_NONE
	for rate: float in Tuning.DEBUG_RATES_H_PER_S:
		_rate_option.add_item("%.1f h/s" % rate)
	_rate_option.item_selected.connect(_on_rate_selected)
	line.add_child(_rate_option)
	column.add_child(line)
	_clock_label = _text("")
	column.add_child(_clock_label)
	_scrub = HSlider.new()
	_scrub.focus_mode = Control.FOCUS_NONE
	_scrub.min_value = Tuning.EXPLOSION_GET
	_scrub.step = SCRUB_STEP_H
	_scrub.drag_started.connect(_on_scrub_drag_started)
	_scrub.drag_ended.connect(_on_scrub_drag_ended)
	_scrub.value_changed.connect(_on_scrub_value_changed)
	column.add_child(_scrub)


func _build_view(column: VBoxContainer) -> void:
	var cabin: Cabin = get_tree().get_first_node_in_group(Cabin.GROUP)
	if cabin == null:
		return
	column.add_child(_heading("Camera and view"))
	var line := HFlowContainer.new()
	for preset_name: String in cabin.preset_names():
		line.add_child(_button(cabin.preset_title(preset_name), cabin.camera_go_to.bind(preset_name, false)))
	for body: String in Cabin.OUTSIDE_VIEWS:
		line.add_child(_button("%s outside" % body.capitalize(), cabin.set_outside_view.bind(body)))
	column.add_child(line)


func _build_effects(column: VBoxContainer) -> void:
	column.add_child(_heading("Effects, one at a time"))
	var modes := HFlowContainer.new()
	for mode_name: String in Effects.MODES:
		var button := _button(Effects.MODE_TITLES[mode_name], _on_effect_mode.bind(mode_name))
		modes.add_child(button)
		_effect_buttons[mode_name] = button
	column.add_child(modes)
	var strength_line := HBoxContainer.new()
	strength_line.add_child(_text("Strength"))
	_effect_strength = HSlider.new()
	_effect_strength.min_value = 0.0
	_effect_strength.max_value = 1.0
	_effect_strength.step = 0.05
	_effect_strength.value = 1.0
	_effect_strength.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effect_strength.focus_mode = Control.FOCUS_NONE
	_effect_strength.value_changed.connect(_on_effect_strength)
	strength_line.add_child(_effect_strength)
	column.add_child(strength_line)
	_effect_summary = _text("")
	_effect_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_effect_summary)
	_mark_effect_mode(Effects.MODE_LIVE)


func _build_sound(column: VBoxContainer) -> void:
	column.add_child(_heading("Sound"))
	for bus_name in AudioMix.BUSES:
		var line := HBoxContainer.new()
		var name_label := _text(bus_name)
		name_label.custom_minimum_size.x = 72
		line.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = 1.0
		slider.value = 100.0
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.focus_mode = Control.FOCUS_NONE
		slider.value_changed.connect(_on_bus_volume.bind(bus_name))
		line.add_child(slider)
		column.add_child(line)
	var buttons := HBoxContainer.new()
	buttons.add_child(_button("Play test voice", _on_test_voice))
	column.add_child(buttons)
	_sound_summary = _text("")
	_sound_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_sound_summary)


func _process(_delta: float) -> void:
	if _fps_label != null:
		_fps_label.text = "%d fps" % roundi(Engine.get_frames_per_second())
	if not visible or _effect_summary == null:
		return
	var effects: Effects = _effects()
	if effects != null:
		_effect_summary.text = effects.summary()
	var bio: BioAudio = _bio()
	if bio != null and _sound_summary != null:
		_sound_summary.text = bio.summary()


func _effects() -> Effects:
	return get_tree().get_first_node_in_group(Effects.GROUP)


func _bio() -> BioAudio:
	return get_tree().get_first_node_in_group(BioAudio.GROUP)


func _on_bus_volume(percent: float, bus_name: String) -> void:
	var bio: BioAudio = _bio()
	if bio != null:
		bio.set_bus_linear(bus_name, percent / 100.0)


func _on_test_voice() -> void:
	var bio: BioAudio = _bio()
	if bio != null:
		bio.play_test_voice()


func _on_effect_mode(mode_name: String) -> void:
	var effects: Effects = _effects()
	if effects == null:
		return
	effects.set_strength(_effect_strength.value)
	effects.set_mode(mode_name)
	_mark_effect_mode(mode_name)


func _on_effect_strength(value: float) -> void:
	var effects: Effects = _effects()
	if effects != null:
		effects.set_strength(value)


func _mark_effect_mode(mode_name: String) -> void:
	for mode: String in _effect_buttons:
		var button: Button = _effect_buttons[mode]
		var title: String = Effects.MODE_TITLES[mode]
		button.text = ("• " + title) if mode == mode_name else title


func _build_jumps(column: VBoxContainer) -> void:
	column.add_child(_heading("Jump to (replays the mission from the explosion)"))
	_jump_box = HFlowContainer.new()
	column.add_child(_jump_box)


func _build_choices(column: VBoxContainer) -> void:
	column.add_child(_heading("Poll choices, applied when the clock reaches each event"))
	for event: Dictionary in Timeline.event_list(Game.events):
		var event_id: String = event["id"]
		var line := HBoxContainer.new()
		var id_label := _text(event_id.to_upper())
		id_label.custom_minimum_size.x = UiStyle.DEBUG_ID_WIDTH
		line.add_child(id_label)
		var option := OptionButton.new()
		option.focus_mode = Control.FOCUS_NONE
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.clip_text = true
		var keys: Array[String] = []
		for choice: Dictionary in event["poll"]["options"]:
			var marker: String = " (historical)" if choice.get("historical", false) else ""
			option.add_item("%s. %s%s" % [str(choice["key"]).to_upper(), choice["label"], marker])
			keys.append(choice["key"])
		option.select(maxi(keys.find(str(Game.plan.get(event_id, ""))), 0))
		option.item_selected.connect(_on_choice_selected.bind(event_id, keys))
		line.add_child(option)
		var status := _text("")
		status.custom_minimum_size.x = UiStyle.DEBUG_STATUS_WIDTH
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(status)
		_choice_status[event_id] = status
		column.add_child(line)


func _build_holds(column: VBoxContainer) -> void:
	column.add_child(_heading("Hold values: change a number to hold it, untick Hold to release"))
	for field: Dictionary in ENV_FIELDS:
		column.add_child(_hold_row(field["path"], "", field))
	_crew_heading = _heading("")
	column.add_child(_crew_heading)
	for field: Dictionary in CREW_FIELDS:
		column.add_child(_hold_row("", field["field"], field))
	column.add_child(_button("Release all holds", Game.release_all))


func _hold_row(path: String, crew_field: String, field: Dictionary) -> Control:
	var line := HBoxContainer.new()
	var name_label := _text(field["label"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	var spin := SpinBox.new()
	spin.min_value = field["min"]
	spin.max_value = field["max"]
	spin.step = field["step"]
	spin.custom_minimum_size.x = UiStyle.DEBUG_SPIN_WIDTH
	spin.select_all_on_focus = true
	line.add_child(spin)
	var hold := CheckBox.new()
	hold.text = "Hold"
	hold.focus_mode = Control.FOCUS_NONE
	line.add_child(hold)
	var row: Dictionary = {"path": path, "field": crew_field, "spin": spin, "hold": hold}
	spin.value_changed.connect(_on_hold_value_changed.bind(row))
	spin.get_line_edit().text_submitted.connect(_on_spin_submitted.bind(spin))
	hold.toggled.connect(_on_hold_toggled.bind(row))
	_hold_rows.append(row)
	return line


func _rebuild_jumps() -> void:
	for child in _jump_box.get_children():
		child.queue_free()
	var planned: SimState = _planned_state()
	var start_mark: Dictionary = {"get": Tuning.EXPLOSION_GET}
	var co2_peak: float = Tuning.CO2_CURVE_BY_ADAPTER["wait"]["peak_get"]
	_jump_box.add_child(_button("CO2 peak %s" % UiStyle.format_get_short(co2_peak), Game.jump_to.bind({"get": co2_peak})))
	_jump_box.add_child(_button("Cold coast %s" % UiStyle.format_get_short(Tuning.DEBUG_COLD_COAST_GET),
		Game.jump_to.bind({"get": Tuning.DEBUG_COLD_COAST_GET})))
	_jump_box.add_child(_button("Start %s" % UiStyle.format_get_short(Tuning.EXPLOSION_GET), Game.jump_to.bind(start_mark)))
	for event: Dictionary in Timeline.event_list(Game.events):
		var event_get: float = Timeline.event_get(event, planned)
		var text: String = "%s %s" % [str(event["id"]).to_upper(), UiStyle.format_get_short(event_get)]
		_jump_box.add_child(_button(text, Game.jump_to.bind(event)))
	for step: Dictionary in Game.events.get("reentry", {}).get("steps", []):
		var step_get: float = Timeline.event_get(step, planned)
		var text: String = "%s %s" % [step.get("title", step["id"]), UiStyle.format_get_short(step_get)]
		_jump_box.add_child(_button(text, Game.jump_to.bind(step)))
	_scrub.max_value = planned.time.splashdown_get


## The flags every planned choice leads to, used to show where E5 and splashdown will fall.
func _planned_state() -> SimState:
	var planned: SimState = SimModel.initial_state()
	for event_id: String in Game.plan:
		planned = Timeline.choose(planned, Game.events, event_id, Game.plan[event_id])
	return planned


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = UiStyle.font(UiStyle.FONT_HUD_LIGHT, true)
	theme.default_font_size = UiStyle.SIZE_LABEL
	var looks: Dictionary = {
		"normal": UiStyle.DEBUG_BUTTON_FILL,
		"hover": UiStyle.DEBUG_BUTTON_HOVER,
		"pressed": UiStyle.DEBUG_BUTTON_PRESSED,
		"hover_pressed": UiStyle.DEBUG_BUTTON_PRESSED,
		"disabled": UiStyle.DEBUG_BUTTON_FILL,
		"focus": Color(UiStyle.DEBUG_BUTTON_FILL, 0.0),
	}
	for look: String in looks:
		var box := StyleBoxFlat.new()
		box.bg_color = looks[look]
		box.set_corner_radius_all(UiStyle.PANEL_RADIUS)
		box.content_margin_left = UiStyle.DEBUG_BUTTON_PADDING_H
		box.content_margin_right = UiStyle.DEBUG_BUTTON_PADDING_H
		box.content_margin_top = UiStyle.DEBUG_BUTTON_PADDING_V
		box.content_margin_bottom = UiStyle.DEBUG_BUTTON_PADDING_V
		theme.set_stylebox(look, "Button", box)
	return theme


func _heading(text: String) -> Label:
	var l := UiStyle.label(text, UiStyle.FONT_HUD_STRONG, UiStyle.SIZE_LABEL, UiStyle.SENSOR_TEAL)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _text(text: String) -> Label:
	var l := UiStyle.label(text, UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_LABEL, UiStyle.PLACARD_WHITE, true)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button


# --- Updates ---

func _on_visibility_changed(shown: bool) -> void:
	visible = shown
	if shown:
		_rebuild_jumps()
		_on_state_changed(Game.state)
		var effects: Effects = _effects()
		if effects != null and _effect_strength != null:
			_mark_effect_mode(effects.mode)
			_effect_strength.set_value_no_signal(effects.strength)


func _on_state_changed(state: SimState) -> void:
	if not visible:
		return
	var clock: String = "Running" if Game.running else "Paused"
	_clock_label.text = "GET %s  (%s)   %s" % [UiStyle.format_get(state.time.current_get), clock,
		"at splashdown" if Timeline.at_splashdown(state) else ""]
	if not _dragging:
		_scrub.set_value_no_signal(state.time.current_get)
	for event_id: String in _choice_status:
		var status: Label = _choice_status[event_id]
		if state.decisions.has(event_id):
			status.text = "applied %s" % state.decisions[event_id].to_upper()
		elif event_id in state.reached_events:
			status.text = "waiting"
		else:
			status.text = "later"
	for row: Dictionary in _hold_rows:
		var spin: SpinBox = row["spin"]
		var hold: CheckBox = row["hold"]
		hold.set_pressed_no_signal(state.overrides.has(row["path"]))
		if not spin.get_line_edit().has_focus():
			spin.set_value_no_signal(state.read_path(row["path"]))
	_readout.text = _readout_text(state)


func _readout_text(state: SimState) -> String:
	var f: SimState.Flags = state.flags
	var lines: PackedStringArray = []
	lines.append("Splashdown GET %s. CO2 alarm %s. Haise's infection %s." % [
		UiStyle.format_get_short(state.time.splashdown_get), _on_off(SimModel.co2_alarm(state)), _yes_no(state.fever)])
	lines.append("Heating %s, return %s, adapter %s, ration %s, power-up %s." % [
		f.heating, f.return_mode, f.adapter, f.ration, f.power_up])
	lines.append("Heat shield risk %s. Service Module %s." % [
		_yes_no(f.heat_shield_risk), "jettisoned" if f.sm_jettisoned else "attached"])
	lines.append("Stress %.1f bpm. Reached: %s." % [state.stress, ", ".join(state.reached_events) if not state.reached_events.is_empty() else "none"])
	var hydration: PackedStringArray = []
	var fatigue: PackedStringArray = []
	for crew_id in SimState.CREW_IDS:
		var member: SimState.CrewMember = state.crew[crew_id]
		hydration.append("%s %.2f" % [SimState.CREW_NAMES[crew_id], member.hydration])
		fatigue.append("%s %.2f" % [SimState.CREW_NAMES[crew_id], member.fatigue])
	lines.append("Hydration: " + ", ".join(hydration))
	lines.append("Fatigue: " + ", ".join(fatigue))
	var caption_get: float = Game.metrics.fever_caption_get
	lines.append("Coldest cabin %.1f °C. Peak CO2 %.1f mmHg. Fever caption %s." % [
		Game.metrics.coldest_cabin_c, Game.metrics.peak_co2_mmhg,
		"at GET " + UiStyle.format_get_short(caption_get) if caption_get >= 0.0 else "not yet"])
	var holds: PackedStringArray = []
	for path: String in state.overrides:
		holds.append("%s = %s" % [path, String.num(state.overrides[path], 2)])
	lines.append("Holds: " + (", ".join(holds) if not holds.is_empty() else "none"))
	return "\n".join(lines)


func _on_clock_changed(running: bool, rate_h_per_s: float) -> void:
	_play_button.text = "Pause" if running else "Play"
	var index: int = Tuning.DEBUG_RATES_H_PER_S.find(rate_h_per_s)
	if index >= 0:
		_rate_option.select(index)


func _on_focus_changed(crew_id: String) -> void:
	_crew_heading.text = "Crew: %s (press 1, 2 or 3 to switch)" % SimState.CREW_NAMES[crew_id]
	for row: Dictionary in _hold_rows:
		if not str(row["field"]).is_empty():
			row["path"] = SimState.crew_path(crew_id, row["field"])
	_on_state_changed(Game.state)


func _on_rate_selected(index: int) -> void:
	Game.set_rate(Tuning.DEBUG_RATES_H_PER_S[index])


func _on_scrub_drag_started() -> void:
	_dragging = true


func _on_scrub_drag_ended(_value_changed: bool) -> void:
	_dragging = false
	Game.seek(_scrub.value)


func _on_scrub_value_changed(value: float) -> void:
	if not _dragging:
		Game.seek(value)


func _on_choice_selected(index: int, event_id: String, keys: Array[String]) -> void:
	Game.set_choice(event_id, keys[index])
	_rebuild_jumps()


func _on_hold_value_changed(value: float, row: Dictionary) -> void:
	Game.hold(row["path"], value)


func _on_hold_toggled(pressed: bool, row: Dictionary) -> void:
	if pressed:
		var spin: SpinBox = row["spin"]
		Game.hold(row["path"], spin.value)
	else:
		Game.release(row["path"])


func _on_spin_submitted(_text_value: String, spin: SpinBox) -> void:
	spin.get_line_edit().release_focus()


static func _yes_no(value: bool) -> String:
	return "yes" if value else "no"


static func _on_off(value: bool) -> String:
	return "on" if value else "off"

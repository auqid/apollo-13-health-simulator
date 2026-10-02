extends CanvasLayer
## Full-screen cards for the session: intro, the poll, and the scorecard. The cabin stays
## visible through the dimmed edges.

const UiStyle := preload("res://scenes/ui/ui_style.gd")

const GROUP := "stage_card"
const CONTINUE_HINT := "Press Space to continue"
const POLL_HINT := "Vote A or B in the chat"
const SCORE_HINT := "Space for the next row. Enter shows the rest"
const POLL_COLUMN_WIDTH := 1500
const SCORE_COLUMN_WIDTH := 1640
const SCORE_YOU_WIDTH := 180
const SCORE_VERDICT_WIDTH := 110
const SCORE_HISTORY_WIDTH := 460

var _dim: ColorRect
var _column: VBoxContainer
var _title: Label
var _body: Label
var _options: HBoxContainer
var _hint: Label
var _option_rows: Dictionary = {}
var _score: VBoxContainer
var _score_rows: Array[Control] = []
var _score_header: Control
var _score_closing: Label
var _score_shown: int = 0


func _ready() -> void:
	add_to_group(GROUP)
	layer = UiStyle.LAYER_CARD
	_build()
	visible = false


func show_intro(text: String) -> void:
	_show_text("Apollo 13", text, CONTINUE_HINT)
	visible = true


func show_cutscene(title: String, get_text: String) -> void:
	_show_text(title, "GET %s\nPlaceholder" % get_text, CONTINUE_HINT)
	visible = true


func show_poll(question: String, options: Array) -> void:
	_clear_options()
	_clear_score()
	_set_column_width(POLL_COLUMN_WIDTH)
	_title.add_theme_font_size_override("font_size", UiStyle.SIZE_QUESTION)
	_title.text = question
	_body.visible = false
	_options.visible = true
	for option: Dictionary in options:
		_options.add_child(_option_row(option))
	_hint.text = POLL_HINT
	_dim.visible = true
	visible = true


func highlight(option_key: String) -> void:
	for key: String in _option_rows:
		var selected: bool = key == option_key
		var row: PanelContainer = _option_rows[key]
		row.add_theme_stylebox_override("panel", _option_style(selected))
		row.modulate.a = 1.0 if selected else 0.45
	_hint.text = ""


func show_reentry(steps: PackedStringArray) -> void:
	var body: String = "Placeholder. The clock runs through to splashdown.\n\n" + "\n".join(steps)
	_show_text("Reentry", body, CONTINUE_HINT)
	visible = true


## choices: {poll, choice, historical}. rows: {label, you, history, verdict}.
## Comparison rows stay hidden until reveal_next or reveal_all.
func show_scorecard(title: String, choices: Array, rows: Array, closing: String) -> void:
	_clear_options()
	_clear_score()
	_set_column_width(SCORE_COLUMN_WIDTH)
	_options.visible = false
	_body.visible = false
	_title.add_theme_font_size_override("font_size", UiStyle.SIZE_POLL)
	_title.text = title
	_score.visible = true
	_score.add_child(_score_heading("Your choices"))
	for choice: Dictionary in choices:
		_score.add_child(_choice_line(choice))
	_score_header = _table_header()
	_score_header.visible = false
	_score.add_child(_score_header)
	for row: Dictionary in rows:
		var line := _metric_row(row)
		line.visible = false
		_score_rows.append(line)
		_score.add_child(line)
	_score_closing = UiStyle.label(closing, UiStyle.FONT_CAPTION, UiStyle.SIZE_BODY)
	_score_closing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_score_closing.visible = false
	_score.add_child(_score_closing)
	_score_shown = 0
	_hint.text = SCORE_HINT
	_dim.visible = true
	visible = true


func reveal_next() -> void:
	if _score_shown >= _score_rows.size():
		return
	if _score_header != null:
		_score_header.visible = true
	_score_rows[_score_shown].visible = true
	_score_shown += 1
	if _score_shown >= _score_rows.size():
		_finish_scorecard()


func reveal_all() -> void:
	if _score_header != null:
		_score_header.visible = true
	for row: Control in _score_rows:
		row.visible = true
	_score_shown = _score_rows.size()
	_finish_scorecard()


func hide_card() -> void:
	visible = false


func _show_text(title: String, body: String, hint: String) -> void:
	_clear_options()
	_clear_score()
	_set_column_width(UiStyle.CARD_COLUMN_WIDTH)
	_options.visible = false
	_title.add_theme_font_size_override("font_size", UiStyle.SIZE_CARD_TITLE)
	_title.text = title
	_body.text = body
	_body.visible = true
	_hint.text = hint
	_dim.visible = true


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(UiStyle.BACKDROP, 0.84)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", UiStyle.SECTION_GAP)
	_column.custom_minimum_size.x = UiStyle.CARD_COLUMN_WIDTH
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = UiStyle.label("", UiStyle.FONT_TITLE, UiStyle.SIZE_CARD_TITLE)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = UiStyle.CARD_COLUMN_WIDTH
	_column.add_child(_title)
	_body = UiStyle.label("", UiStyle.FONT_CAPTION, UiStyle.SIZE_QUESTION)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = UiStyle.CARD_COLUMN_WIDTH
	_column.add_child(_body)
	_options = HBoxContainer.new()
	_options.add_theme_constant_override("separation", UiStyle.SECTION_GAP)
	_options.visible = false
	_column.add_child(_options)
	_score = VBoxContainer.new()
	_score.add_theme_constant_override("separation", UiStyle.ROW_GAP)
	_score.visible = false
	_column.add_child(_score)
	_hint = UiStyle.label("", UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_BODY, UiStyle.TEXT_DIM)
	_column.add_child(_hint)
	var panel := PanelContainer.new()
	var box := UiStyle.panel_box()
	box.bg_color = Color(UiStyle.INSTRUMENT_BLACK, 0.94)
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_column)
	center.add_child(panel)
	add_child(center)


func _option_row(option: Dictionary) -> Control:
	var key: String = option["key"]
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _option_style(false))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", UiStyle.ROW_GAP)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(UiStyle.label(key.to_upper(), UiStyle.FONT_TITLE, UiStyle.SIZE_POLL_LETTER, UiStyle.SENSOR_TEAL))
	var title := UiStyle.label(option["label"], UiStyle.FONT_HUD, UiStyle.SIZE_POLL)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(title)
	text.add_child(_tradeoff("Good: " + str(option["good"]), UiStyle.SENSOR_TEAL))
	text.add_child(_tradeoff("Cost: " + str(option["cost"]), UiStyle.CAUTION_AMBER))
	row.add_child(text)
	_option_rows[key] = row
	return row


func _tradeoff(line: String, color: Color) -> Label:
	var label := UiStyle.label(line, UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_BODY, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _set_column_width(width: int) -> void:
	_column.custom_minimum_size.x = width
	_title.custom_minimum_size.x = width


func _option_style(selected: bool) -> StyleBoxFlat:
	var box := UiStyle.panel_box()
	box.bg_color = UiStyle.FOCUS_FILL if selected else Color(UiStyle.INSTRUMENT_BLACK, 0.92)
	if selected:
		box.border_color = UiStyle.SENSOR_TEAL
		box.set_border_width_all(UiStyle.FOCUS_BAR_WIDTH)
	return box


func _finish_scorecard() -> void:
	if _score_closing != null:
		_score_closing.visible = true
	_hint.text = ""


func _score_heading(text: String) -> Label:
	return UiStyle.label(text, UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_BODY, UiStyle.SENSOR_TEAL)


func _choice_line(choice: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UiStyle.ROW_PADDING)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var poll := UiStyle.label(choice["poll"], UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_BODY, UiStyle.TEXT_DIM)
	poll.custom_minimum_size.x = 520
	line.add_child(poll)
	var picked := UiStyle.label(choice["choice"], UiStyle.FONT_HUD, UiStyle.SIZE_NAME)
	picked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(picked)
	var mark := UiStyle.label("1970" if choice.get("historical", false) else "", UiStyle.FONT_HUD, UiStyle.SIZE_BODY, UiStyle.SENSOR_TEAL)
	mark.custom_minimum_size.x = 80
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(mark)
	return line


func _table_header() -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UiStyle.ROW_PADDING)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var metric := UiStyle.label("", UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_LABEL, UiStyle.TEXT_DIM)
	metric.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(metric)
	line.add_child(_fixed_label("You", SCORE_YOU_WIDTH, UiStyle.TEXT_DIM, UiStyle.SIZE_LABEL, false))
	line.add_child(_fixed_label("", SCORE_VERDICT_WIDTH, UiStyle.TEXT_DIM, UiStyle.SIZE_LABEL, false))
	line.add_child(_fixed_label("Apollo 13, 1970", SCORE_HISTORY_WIDTH, UiStyle.TEXT_DIM, UiStyle.SIZE_LABEL, false))
	return line


func _metric_row(row: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UiStyle.ROW_PADDING)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var metric := UiStyle.label(row["label"], UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_BODY)
	metric.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metric.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(metric)
	var you := _fixed_label(row["you"], SCORE_YOU_WIDTH, UiStyle.PLACARD_WHITE, UiStyle.SIZE_VITAL, true)
	you.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(you)
	var verdict: String = str(row["verdict"])
	var word := verdict.capitalize()
	var mark := _fixed_label(word, SCORE_VERDICT_WIDTH, _verdict_color(verdict), UiStyle.SIZE_BODY, false)
	line.add_child(mark)
	var history := _fixed_label(row["history"], SCORE_HISTORY_WIDTH, UiStyle.TEXT_DIM, UiStyle.SIZE_LABEL, false)
	history.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	history.max_lines_visible = 2
	line.add_child(history)
	return line


func _fixed_label(text: String, width: int, color: Color, size: int, tabular: bool) -> Label:
	var label := UiStyle.label(text, UiStyle.FONT_HUD, size, color, tabular)
	label.custom_minimum_size.x = width
	return label


func _verdict_color(verdict: String) -> Color:
	if verdict == "better":
		return UiStyle.SENSOR_TEAL
	if verdict == "worse":
		return UiStyle.CAUTION_AMBER
	return UiStyle.TEXT_DIM


func _clear_score() -> void:
	if _score == null:
		return
	for child in _score.get_children():
		_score.remove_child(child)
		child.free()
	_score_rows.clear()
	_score_header = null
	_score_closing = null
	_score_shown = 0
	_score.visible = false


func _clear_options() -> void:
	for child in _options.get_children():
		_options.remove_child(child)
		child.free()
	_option_rows.clear()

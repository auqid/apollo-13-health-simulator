extends CanvasLayer
## Full-screen cards for the session: intro, placeholder cutscenes, the poll, and the
## placeholder reentry and scorecard. The cabin stays visible through the dimmed edges.

const UiStyle := preload("res://scenes/ui/ui_style.gd")

const GROUP := "stage_card"
const CONTINUE_HINT := "Press Space to continue"
const POLL_HINT := "Press A or B"

var _dim: ColorRect
var _column: VBoxContainer
var _title: Label
var _body: Label
var _options: VBoxContainer
var _hint: Label
var _option_rows: Dictionary = {}


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


func show_scorecard(title: String, splashdown_text: String, closing: String) -> void:
	_show_text(title, "%s\n\nPlaceholder. The comparison with 1970 comes next.\n\n%s" % [splashdown_text, closing], "")
	visible = true


func hide_card() -> void:
	visible = false


func _show_text(title: String, body: String, hint: String) -> void:
	_clear_options()
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
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", UiStyle.SECTION_GAP)
	_options.visible = false
	_column.add_child(_options)
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
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", UiStyle.ROW_GAP)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := UiStyle.label("%s.  %s" % [key.to_upper(), option["label"]], UiStyle.FONT_HUD, UiStyle.SIZE_POLL)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var hint := UiStyle.label(option["hint"], UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_BODY, UiStyle.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(line)
	text.add_child(hint)
	row.add_child(text)
	_option_rows[key] = row
	return row


func _option_style(selected: bool) -> StyleBoxFlat:
	var box := UiStyle.panel_box()
	box.bg_color = UiStyle.FOCUS_FILL if selected else Color(UiStyle.INSTRUMENT_BLACK, 0.92)
	if selected:
		box.border_color = UiStyle.SENSOR_TEAL
		box.set_border_width_all(UiStyle.FOCUS_BAR_WIDTH)
	return box


func _clear_options() -> void:
	for child in _options.get_children():
		_options.remove_child(child)
		child.free()
	_option_rows.clear()

extends CanvasLayer
## Full-screen cards for the session: intro, the poll, and the scorecard. The cabin stays
## visible through the dimmed edges.

const UiStyle := preload("res://scenes/ui/ui_style.gd")

const GROUP := "stage_card"
const CONTINUE_HINT := "Press Space to continue"
const POLL_HINT := "Vote A or B in the chat"
const POLL_TIME := "Vote A or B in the chat: %d s left"
const POLL_CLOSED := "Voting is closed. Presenter, press A or B"
const HISTORY_BADGE := "1970"
const SCORE_HINT := "Space for the next row. Enter shows the rest"
const POLL_COLUMN_WIDTH := 1500
const SCORE_COLUMN_WIDTH := 1640
const SCORE_YOU_WIDTH := 180
const SCORE_VERDICT_WIDTH := 110
const SCORE_HISTORY_WIDTH := 460

var _root: Control
var _fade: Tween
var _dim: ColorRect
var _column: VBoxContainer
var _title: Label
var _body: Label
var _intro_row: HBoxContainer
var _intro_photo_box: VBoxContainer
var _intro_photo: TextureRect
var _intro_photo_caption: Label
var _intro_text: Label
var _intro_how: Label
var _options: HBoxContainer
var _hint: Label
var _option_rows: Dictionary = {}
## Option key -> the "1970" badge shown on the historical option after the vote.
var _badges: Dictionary = {}
## Option key -> its labels, which fade when the other option is chosen. The badge does not.
var _option_words: Dictionary = {}
var _kicker: Label
var _countdown: HBoxContainer
var _count_fill: ColorRect
var _count_rest: ColorRect
## Seconds left to vote, or below 0 when no countdown is running.
var _poll_left_s: float = -1.0
var _poll_total_s: float = 0.0
var _reveal: VBoxContainer
var _reveal_line: Label
var _reveal_note: Label
var _reveal_watch: Label
var _score_summary: Label
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


## The opening card: the date and setting, how the audience plays, and the crew photo if there is one.
func show_intro(text: String, how_to: String = "", photo: Texture2D = null, photo_caption: String = "") -> void:
	_show_text("Apollo 13", "", CONTINUE_HINT)
	_body.visible = false
	_intro_row.visible = true
	_intro_text.text = text
	_intro_how.text = how_to
	_intro_how.visible = not how_to.is_empty()
	_intro_photo.texture = photo
	_intro_photo_box.visible = photo != null
	_intro_photo_caption.text = photo_caption
	_appear()


## A decision: the question, two options with what each is good for and costs, and a countdown
## for the chat vote. kicker is the line above the question, like "Decision 2 of 5". The countdown
## never picks; at zero it asks the presenter to press A or B.
func show_poll(question: String, options: Array, kicker: String = "", countdown_s: float = 0.0) -> void:
	_clear_options()
	_clear_score()
	_intro_row.visible = false
	_set_column_width(POLL_COLUMN_WIDTH)
	_kicker.text = kicker
	_kicker.visible = not kicker.is_empty()
	_title.add_theme_font_size_override("font_size", UiStyle.SIZE_QUESTION)
	_title.text = question
	_body.visible = false
	_options.visible = true
	for option: Dictionary in options:
		_options.add_child(_option_row(option))
	_reveal.visible = false
	_poll_total_s = maxf(countdown_s, 0.0)
	_poll_left_s = _poll_total_s if _poll_total_s > 0.0 else -1.0
	_countdown.visible = _poll_total_s > 0.0
	_hint.text = POLL_HINT
	_update_countdown()
	_dim.visible = true
	_appear()


func highlight(option_key: String) -> void:
	for key: String in _option_rows:
		var selected: bool = key == option_key
		var row: PanelContainer = _option_rows[key]
		row.add_theme_stylebox_override("panel", _option_style(selected))
		for word: Label in _option_words.get(key, []):
			word.modulate.a = 1.0 if selected else UiStyle.UNCHOSEN_ALPHA
	_poll_left_s = -1.0
	_countdown.visible = false
	_hint.text = ""


## After the vote: whether it matches what was done in 1970, any note on the choice, and what to
## watch next. The option chosen in 1970 gets a badge.
func show_reveal(line: String, note: String, watch: String, historical_key: String) -> void:
	_reveal_line.text = line
	_reveal_note.text = note
	_reveal_note.visible = not note.is_empty()
	_reveal_watch.text = watch
	_reveal_watch.visible = not watch.is_empty()
	_reveal.visible = true
	for key: String in _badges:
		_badges[key].visible = key == historical_key


func _process(delta: float) -> void:
	if _poll_left_s > 0.0:
		_poll_left_s = maxf(_poll_left_s - delta, 0.0)
		_update_countdown()


func _update_countdown() -> void:
	if _poll_total_s <= 0.0 or _count_fill == null:
		return
	var share: float = clampf(_poll_left_s / _poll_total_s, 0.0, 1.0)
	_count_fill.size_flags_stretch_ratio = maxf(share, 0.0001)
	_count_rest.size_flags_stretch_ratio = maxf(1.0 - share, 0.0001)
	if _poll_left_s < 0.0:
		return
	_hint.text = POLL_TIME % ceili(_poll_left_s) if _poll_left_s > 0.0 else POLL_CLOSED


## choices: {poll, choice, historical}. rows: {label, you, history, verdict}.
## Comparison rows stay hidden until reveal_next or reveal_all.
func show_scorecard(title: String, choices: Array, rows: Array, closing: String, summary: String = "") -> void:
	_clear_options()
	_clear_score()
	_reset_poll_parts()
	_intro_row.visible = false
	_set_column_width(SCORE_COLUMN_WIDTH)
	_options.visible = false
	_body.visible = false
	_title.add_theme_font_size_override("font_size", UiStyle.SIZE_POLL)
	_title.text = title
	_score.visible = true
	_score.add_child(_score_heading("Your choices"))
	for choice: Dictionary in choices:
		_score.add_child(_choice_line(choice))
	if not summary.is_empty():
		_score_summary = UiStyle.label(summary, UiStyle.FONT_CAPTION, UiStyle.SIZE_NAME, UiStyle.SENSOR_TEAL)
		_score.add_child(_score_summary)
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
	_appear()


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


## Fades the card out. Showing another card while it fades brings it straight back.
func hide_card() -> void:
	if not visible:
		return
	if _fade != null:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_root, "modulate:a", 0.0, UiStyle.FADE_S)
	_fade.tween_callback(hide)


## Shows the card again as it was, after a debug preview hid it.
func restore() -> void:
	_appear()


func _appear() -> void:
	if _fade != null:
		_fade.kill()
	if not visible:
		_root.modulate.a = 0.0
		visible = true
	_fade = create_tween()
	_fade.tween_property(_root, "modulate:a", 1.0, UiStyle.FADE_S)


func _show_text(title: String, body: String, hint: String) -> void:
	_clear_options()
	_clear_score()
	_reset_poll_parts()
	_set_column_width(UiStyle.CARD_COLUMN_WIDTH)
	_options.visible = false
	_intro_row.visible = false
	_title.add_theme_font_size_override("font_size", UiStyle.SIZE_CARD_TITLE)
	_title.text = title
	_body.text = body
	_body.visible = true
	_hint.text = hint
	_dim.visible = true


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_dim = ColorRect.new()
	_dim.color = Color(UiStyle.BACKDROP, 0.84)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", UiStyle.SECTION_GAP)
	_column.custom_minimum_size.x = UiStyle.CARD_COLUMN_WIDTH
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kicker = UiStyle.label("", UiStyle.FONT_TITLE, UiStyle.SIZE_CHAPTER, UiStyle.SENSOR_TEAL)
	_kicker.visible = false
	_column.add_child(_kicker)
	_title = UiStyle.label("", UiStyle.FONT_TITLE, UiStyle.SIZE_CARD_TITLE)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = UiStyle.CARD_COLUMN_WIDTH
	_column.add_child(_title)
	_body = UiStyle.label("", UiStyle.FONT_CAPTION, UiStyle.SIZE_QUESTION)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = UiStyle.CARD_COLUMN_WIDTH
	_column.add_child(_body)
	_build_intro_row()
	_options = HBoxContainer.new()
	_options.add_theme_constant_override("separation", UiStyle.SECTION_GAP)
	_options.visible = false
	_column.add_child(_options)
	_build_reveal()
	_build_countdown()
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
	_root.add_child(center)


func _build_reveal() -> void:
	_reveal = VBoxContainer.new()
	_reveal.add_theme_constant_override("separation", UiStyle.ROW_GAP)
	_reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal.visible = false
	_reveal_line = UiStyle.label("", UiStyle.FONT_CAPTION, UiStyle.SIZE_QUESTION)
	_reveal_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reveal.add_child(_reveal_line)
	_reveal_note = UiStyle.label("", UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_TRADEOFF, UiStyle.TEXT_DIM)
	_reveal_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reveal.add_child(_reveal_note)
	_reveal_watch = UiStyle.label("", UiStyle.FONT_HUD, UiStyle.SIZE_TRADEOFF, UiStyle.SENSOR_TEAL)
	_reveal.add_child(_reveal_watch)
	_column.add_child(_reveal)


## A thin bar that drains while the chat votes.
func _build_countdown() -> void:
	_countdown = HBoxContainer.new()
	_countdown.add_theme_constant_override("separation", 0)
	_countdown.custom_minimum_size.y = UiStyle.COUNTDOWN_HEIGHT
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown.visible = false
	_count_fill = ColorRect.new()
	_count_fill.color = UiStyle.SENSOR_TEAL
	_count_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_rest = ColorRect.new()
	_count_rest.color = UiStyle.BAR_TRACK
	_count_rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_rest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown.add_child(_count_fill)
	_countdown.add_child(_count_rest)
	_column.add_child(_countdown)


func _reset_poll_parts() -> void:
	_kicker.visible = false
	_reveal.visible = false
	_countdown.visible = false
	_poll_left_s = -1.0
	_poll_total_s = 0.0


## The crew photo with their names, beside the intro text and how to play.
func _build_intro_row() -> void:
	_intro_row = HBoxContainer.new()
	_intro_row.add_theme_constant_override("separation", UiStyle.SECTION_GAP * 2)
	_intro_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_row.visible = false
	_intro_photo_box = VBoxContainer.new()
	_intro_photo_box.add_theme_constant_override("separation", UiStyle.ROW_GAP)
	_intro_photo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_photo = TextureRect.new()
	_intro_photo.custom_minimum_size = UiStyle.INTRO_PHOTO_SIZE
	_intro_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_intro_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_intro_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_photo_box.add_child(_intro_photo)
	_intro_photo_caption = UiStyle.label("", UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_LABEL, UiStyle.TEXT_DIM)
	_intro_photo_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro_photo_caption.custom_minimum_size.x = UiStyle.INTRO_PHOTO_SIZE.x
	_intro_photo_box.add_child(_intro_photo_caption)
	_intro_row.add_child(_intro_photo_box)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", UiStyle.SECTION_GAP * 2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_text = UiStyle.label("", UiStyle.FONT_CAPTION, UiStyle.SIZE_QUESTION)
	_intro_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro_text.custom_minimum_size.x = UiStyle.INTRO_TEXT_WIDTH
	words.add_child(_intro_text)
	_intro_how = UiStyle.label("", UiStyle.FONT_CAPTION, UiStyle.SIZE_POLL, UiStyle.SENSOR_TEAL)
	_intro_how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro_how.custom_minimum_size.x = UiStyle.INTRO_TEXT_WIDTH
	words.add_child(_intro_how)
	_intro_row.add_child(words)
	_column.add_child(_intro_row)


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
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var letter := UiStyle.label(key.to_upper(), UiStyle.FONT_TITLE, UiStyle.SIZE_POLL_LETTER, UiStyle.SENSOR_TEAL)
	letter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(letter)
	var badge := UiStyle.label(HISTORY_BADGE, UiStyle.FONT_TITLE, UiStyle.SIZE_CHAPTER, UiStyle.INSTRUMENT_BLACK)
	var badge_box := StyleBoxFlat.new()
	badge_box.bg_color = UiStyle.PLACARD_WHITE
	badge_box.set_corner_radius_all(UiStyle.PANEL_RADIUS)
	badge_box.content_margin_left = UiStyle.ROW_PADDING
	badge_box.content_margin_right = UiStyle.ROW_PADDING
	badge.add_theme_stylebox_override("normal", badge_box)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.visible = false
	top.add_child(badge)
	_badges[key] = badge
	text.add_child(top)
	var title := UiStyle.label(option["label"], UiStyle.FONT_HUD, UiStyle.SIZE_OPTION)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(title)
	var good := _tradeoff("Good: " + str(option["good"]), UiStyle.SENSOR_TEAL)
	var cost := _tradeoff("Cost: " + str(option["cost"]), UiStyle.CAUTION_AMBER)
	text.add_child(good)
	text.add_child(cost)
	_option_words[key] = [letter, title, good, cost]
	row.add_child(text)
	_option_rows[key] = row
	return row


func _tradeoff(line: String, color: Color) -> Label:
	var label := UiStyle.label(line, UiStyle.FONT_HUD_LIGHT, UiStyle.SIZE_TRADEOFF, color)
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
	_score_summary = null
	_score_shown = 0
	_score.visible = false


func _clear_options() -> void:
	for child in _options.get_children():
		_options.remove_child(child)
		child.free()
	_option_rows.clear()
	_badges.clear()
	_option_words.clear()

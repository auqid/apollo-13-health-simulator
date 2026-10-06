extends CanvasLayer
## How cutscenes look (SPEC.md section 1): a photo with a slow pan and zoom, cinematic bars that
## carry the chapter and the mission clock, a dip to black between shots, and the caption.
## Every story caption, in a cutscene or a timeskip, goes through show_caption, so two captions
## never stack: a new one replaces the last. Hiding the photo leaves the 3D view visible.

const UiStyle := preload("res://scenes/ui/ui_style.gd")
const Tuning := preload("res://sim/tuning.gd")
const SimState := preload("res://sim/sim_state.gd")
const FacePhoto := preload("res://scenes/ui/face_photo.gd")

const GROUP := "cutscene_view"
## "Name: words" at the start of a subtitle line, like "Lovell:" or "Photographic helicopter:".
## The name is drawn dimmer than the words, and their photo, if "people" has one, sits beside it.
const SPEAKER_PATTERN := "^([A-Z][A-Za-z]+(?: [a-z]+)*): "

var _clip: Control
var _backdrop: TextureRect
var _photo: TextureRect
var _curtain: ColorRect
var _top_bar: ColorRect
var _bottom_bar: ColorRect
var _chapter: Label
var _clock: Label
var _caption_area: MarginContainer
var _caption_box: PanelContainer
var _caption: RichTextLabel
## Photos beside a subtitle: the first speaker on the left, a second one on the right.
var _speaker_faces: Array[FacePhoto] = []
var _caption_text: String = ""
## Seconds until the caption fades by itself; 0 keeps it until it is replaced or cleared.
var _caption_left_s: float = 0.0
var _bars: float = 0.0
var _heart_rate_shown: bool = false
var _bars_tween: Tween
var _curtain_tween: Tween
var _caption_tween: Tween
var _from := Vector2.ZERO
var _to := Vector2.ZERO
## Where the photo sits before the pan, so its focus point is on screen.
var _photo_home := Vector2.ZERO
var _speaker := RegEx.create_from_string(SPEAKER_PATTERN)


func _ready() -> void:
	add_to_group(GROUP)
	layer = UiStyle.LAYER_HUD + 2
	_build()
	_set_bars(0.0)


func _process(delta: float) -> void:
	if _caption_left_s > 0.0:
		_caption_left_s -= delta
		if _caption_left_s <= 0.0:
			_caption_left_s = 0.0
			show_caption("")
	if _bars > 0.0:
		_update_clock()


## Shows a photo with a slow pan. Covering the screen crops it, keeping focus (0 to 1 across and
## down the photo) in view; contain shows all of it, over a dimmed copy that fills the screen.
func show_photo(texture: Texture2D, flip: bool, contain: bool = false, focus := Vector2(0.5, 0.5)) -> void:
	_photo.texture = texture
	_photo.visible = texture != null
	_backdrop.texture = texture if contain else null
	_backdrop.visible = contain and texture != null
	if texture == null:
		return
	var area: Vector2 = _clip.size
	var aspect: float = float(texture.get_width()) / maxf(float(texture.get_height()), 1.0)
	var fitted := Vector2(area.x, area.x / aspect)
	var wider: bool = fitted.y < area.y
	if wider != contain:
		fitted = Vector2(area.y * aspect, area.y)
	if contain:
		fitted *= UiStyle.PHOTO_CONTAIN_SCALE
		_photo_home = (area - fitted) * 0.5
	else:
		fitted *= UiStyle.PHOTO_COVER_SCALE
		_photo_home = -(fitted - area) * focus.clamp(Vector2.ZERO, Vector2.ONE)
	_photo.size = fitted
	_photo.pivot_offset = fitted * 0.5
	var travel: float = UiStyle.PHOTO_PAN_PX if flip else -UiStyle.PHOTO_PAN_PX
	_from = Vector2(-travel, -UiStyle.PHOTO_PAN_PX * 0.5)
	_to = Vector2(travel, UiStyle.PHOTO_PAN_PX * 0.35)
	set_pan(0.0)


func hide_photo() -> void:
	_photo.visible = false
	_photo.texture = null
	_backdrop.visible = false
	_backdrop.texture = null


func set_pan(t: float) -> void:
	var zoom: float = lerpf(1.0, Tuning.CUTSCENE_PHOTO_ZOOM, smoothstep(0.0, 1.0, t))
	_photo.scale = Vector2(zoom, zoom)
	_photo.position = _photo_home + _from.lerp(_to, smoothstep(0.0, 1.0, t))


## Replaces the caption. hold_s > 0 fades it out after that long; empty text fades it out now.
## Asking again for the caption already shown changes nothing, so it can be called every frame.
func show_caption(text: String, hold_s: float = 0.0) -> void:
	_caption_left_s = hold_s
	if text == _caption_text:
		return
	_caption_text = text
	if _caption_tween != null:
		_caption_tween.kill()
	_caption_tween = create_tween()
	if text.is_empty():
		_caption_tween.tween_property(_caption_box, "modulate:a", 0.0, UiStyle.CAPTION_FADE_S)
		return
	if _caption_box.modulate.a > 0.01:
		_caption_tween.tween_property(_caption_box, "modulate:a", 0.0, UiStyle.CAPTION_FADE_S * 0.5)
	_caption_tween.tween_callback(_set_caption_text.bind(text))
	_caption_tween.tween_property(_caption_box, "modulate:a", 1.0, UiStyle.CAPTION_FADE_S)


func clear_caption() -> void:
	show_caption("")


func caption_text() -> String:
	return _caption_text


## Cinematic bars slide in for cutscenes and slide away for play. The caption moves into the bar.
func set_letterbox(on: bool) -> void:
	if _bars_tween != null:
		_bars_tween.kill()
	_bars_tween = create_tween()
	_bars_tween.tween_method(_set_bars, _bars, 1.0 if on else 0.0, UiStyle.LETTERBOX_SLIDE_S) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## The chapter shown in the top bar, such as "1 of 5 · Explosion and lifeboat".
func set_chapter(text: String) -> void:
	_chapter.text = text


## During the reentry the top bar also shows the focused crew member's heart rate.
func show_heart_rate(shown: bool) -> void:
	_heart_rate_shown = shown
	_update_clock()


## Fades the picture to black over seconds. Captions and bars stay on top.
func close_curtain(seconds: float) -> void:
	_tween_curtain(1.0, seconds)


func open_curtain(seconds: float) -> void:
	_tween_curtain(0.0, seconds)


func set_curtain(amount: float) -> void:
	if _curtain_tween != null:
		_curtain_tween.kill()
	_curtain.modulate.a = clampf(amount, 0.0, 1.0)


## Back to play: no photo, no bars, no curtain, no caption.
func hide_view() -> void:
	hide_photo()
	set_curtain(0.0)
	clear_caption()


func _tween_curtain(alpha: float, seconds: float) -> void:
	if _curtain_tween != null:
		_curtain_tween.kill()
	if seconds <= 0.0:
		_curtain.modulate.a = alpha
		return
	_curtain_tween = create_tween()
	_curtain_tween.tween_property(_curtain, "modulate:a", alpha, seconds).set_trans(Tween.TRANS_SINE)


func _set_bars(amount: float) -> void:
	_bars = amount
	var height: float = UiStyle.LETTERBOX_HEIGHT * amount
	_top_bar.offset_bottom = height
	_bottom_bar.offset_top = -height
	_chapter.modulate.a = amount
	_clock.modulate.a = amount
	var bottom: float = lerpf(UiStyle.CAPTION_BOTTOM_LOWER_THIRD, UiStyle.CAPTION_BOTTOM_IN_BAR, amount)
	_caption_area.add_theme_constant_override("margin_bottom", roundi(bottom))
	_update_clock()


func _update_clock() -> void:
	var host := get_node_or_null("/root/Game")
	if host == null or host.get("state") == null:
		return
	var state: SimState = host.get("state")
	var line: String = "GET %s" % UiStyle.format_get(state.time.current_get)
	if _heart_rate_shown:
		var crew_id: String = str(host.get("focused_crew"))
		var member: SimState.CrewMember = state.crew[crew_id]
		line = "%s %d bpm    %s" % [SimState.CREW_NAMES[crew_id], roundi(member.hr), line]
	_clock.text = line


func _set_caption_text(text: String) -> void:
	var font: Font = UiStyle.font(UiStyle.FONT_CAPTION)
	var measured: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER,
		UiStyle.CAPTION_MAX_WIDTH, UiStyle.SIZE_SUBTITLE)
	_caption.custom_minimum_size.x = minf(ceilf(measured.x) + UiStyle.CAPTION_WRAP_SLACK, UiStyle.CAPTION_MAX_WIDTH)
	_caption.text = "[center]%s[/center]" % _bbcode(text)
	_show_speaker_faces(text)


## The people speaking in a caption, in order and each once: "Lovell: …\nBrand: …" gives both.
static func speakers(text: String) -> PackedStringArray:
	var pattern := RegEx.create_from_string(SPEAKER_PATTERN)
	var names: PackedStringArray = []
	for line: String in text.split("\n"):
		var found: RegExMatch = pattern.search(line)
		if found != null and found.get_string(1) not in names:
			names.append(found.get_string(1))
	return names


## Which speaker photos are showing, left to right, for the tests.
func speaker_faces_shown() -> int:
	return _speaker_faces.filter(func(face: FacePhoto) -> bool: return face.visible).size()


## A crew member's photo shows how they are right now; Mission Control's stay as they are.
func _show_speaker_faces(text: String) -> void:
	var host := get_node_or_null("/root/Game")
	var people: Dictionary = {}
	var state: SimState = null
	if host != null:
		people = host.get("events").get("people", {}) if host.get("events") is Dictionary else {}
		state = host.get("state")
	var names: PackedStringArray = speakers(text)
	for i in _speaker_faces.size():
		var face: FacePhoto = _speaker_faces[i]
		face.visible = i < names.size() and face.show_person(people, names[i])
		if not face.visible:
			continue
		var crew_id: Variant = SimState.CREW_NAMES.find_key(names[i])
		if crew_id != null and state != null:
			face.react(state.crew[crew_id], state.env)
		else:
			face.calm()


## Escapes the text and colours the speaker's name at the start of each line.
func _bbcode(text: String) -> String:
	var lines: PackedStringArray = []
	for line: String in text.replace("[", "[lb]").split("\n"):
		var found: RegExMatch = _speaker.search(line)
		if found == null:
			lines.append(line)
			continue
		lines.append("[color=#%s]%s:[/color] %s" % [UiStyle.CAPTION_SPEAKER.to_html(), found.get_string(1),
			line.substr(found.get_end())])
	return "\n".join(lines)


func _build() -> void:
	_clip = Control.new()
	_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop = TextureRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.modulate = UiStyle.PHOTO_BACKDROP
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.visible = false
	_clip.add_child(_backdrop)
	_photo = TextureRect.new()
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_SCALE
	_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_photo.visible = false
	_clip.add_child(_photo)
	add_child(_clip)

	_curtain = ColorRect.new()
	_curtain.color = Color.BLACK
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.modulate.a = 0.0
	add_child(_curtain)

	_top_bar = _bar(Control.PRESET_TOP_WIDE)
	_bottom_bar = _bar(Control.PRESET_BOTTOM_WIDE)
	var header := MarginContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = UiStyle.LETTERBOX_HEIGHT
	header.add_theme_constant_override("margin_left", UiStyle.MARGIN)
	header.add_theme_constant_override("margin_right", UiStyle.MARGIN)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chapter = UiStyle.label("", UiStyle.FONT_TITLE, UiStyle.SIZE_CHAPTER, UiStyle.TEXT_DIM)
	_chapter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chapter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_chapter.size_flags_vertical = Control.SIZE_FILL
	line.add_child(_chapter)
	_clock = UiStyle.label("", UiStyle.FONT_HUD, UiStyle.SIZE_CHAPTER, UiStyle.TEXT_DIM, true)
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock.size_flags_vertical = Control.SIZE_FILL
	line.add_child(_clock)
	header.add_child(line)
	_top_bar.add_child(header)

	_caption_area = MarginContainer.new()
	_caption_area.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption_area.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caption_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_box = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = UiStyle.CAPTION_BOX
	box.set_corner_radius_all(UiStyle.PANEL_RADIUS)
	box.content_margin_left = UiStyle.CAPTION_PADDING_H
	box.content_margin_right = UiStyle.CAPTION_PADDING_H
	box.content_margin_top = UiStyle.CAPTION_PADDING_V
	box.content_margin_bottom = UiStyle.CAPTION_PADDING_V
	_caption_box.add_theme_stylebox_override("panel", box)
	_caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_box.modulate.a = 0.0
	_caption = RichTextLabel.new()
	_caption.bbcode_enabled = true
	_caption.fit_content = true
	_caption.scroll_active = false
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_font_override("normal_font", UiStyle.font(UiStyle.FONT_CAPTION))
	_caption.add_theme_font_size_override("normal_font_size", UiStyle.SIZE_SUBTITLE)
	_caption.add_theme_color_override("default_color", UiStyle.PLACARD_WHITE)
	_caption.add_theme_constant_override("outline_size", UiStyle.CAPTION_OUTLINE_SIZE)
	_caption.add_theme_color_override("font_outline_color", UiStyle.CAPTION_OUTLINE)
	_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var speech := HBoxContainer.new()
	speech.add_theme_constant_override("separation", UiStyle.CAPTION_FACE_GAP)
	speech.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in 2:
		var face := FacePhoto.new(UiStyle.CAPTION_FACE_SIZE)
		face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_speaker_faces.append(face)
	speech.add_child(_speaker_faces[0])
	speech.add_child(_caption)
	speech.add_child(_speaker_faces[1])
	_caption_box.add_child(speech)
	center.add_child(_caption_box)
	_caption_area.add_child(center)
	add_child(_caption_area)


func _bar(preset: Control.LayoutPreset) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color.BLACK
	bar.set_anchors_and_offsets_preset(preset)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	return bar

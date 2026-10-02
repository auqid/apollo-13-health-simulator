extends CanvasLayer
## A cutscene photo with a slow pan and zoom. Captions and subtitles sit at the bottom.
## Hiding the photo leaves the cabin visible.

const UiStyle := preload("res://scenes/ui/ui_style.gd")
const Tuning := preload("res://sim/tuning.gd")

const GROUP := "cutscene_view"

var _photo: TextureRect
var _caption: Label
var _from := Vector2.ZERO
var _to := Vector2.ZERO


func _ready() -> void:
	add_to_group(GROUP)
	layer = UiStyle.LAYER_HUD + 2
	_build()
	visible = false


func show_photo(texture: Texture2D, flip: bool) -> void:
	_photo.texture = texture
	_photo.visible = texture != null
	var travel: float = 36.0 if flip else -36.0
	_from = Vector2(-travel, -18.0)
	_to = Vector2(travel, 12.0)
	set_pan(0.0)
	visible = true


func hide_photo() -> void:
	_photo.visible = false
	_photo.texture = null
	visible = true


func set_pan(t: float) -> void:
	var zoom: float = lerpf(1.0, Tuning.CUTSCENE_PHOTO_ZOOM, smoothstep(0.0, 1.0, t))
	_photo.scale = Vector2(zoom, zoom)
	_photo.position = _from.lerp(_to, smoothstep(0.0, 1.0, t))


func show_caption(text: String) -> void:
	_caption.text = text
	_caption.visible = not text.is_empty()
	visible = true


func hide_view() -> void:
	_photo.texture = null
	_photo.visible = false
	_caption.text = ""
	visible = false


func _build() -> void:
	var clip := Control.new()
	clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_photo = TextureRect.new()
	_photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_photo.offset_left = -48.0
	_photo.offset_top = -48.0
	_photo.offset_right = 48.0
	_photo.offset_bottom = 48.0
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_photo.pivot_offset = Vector2(960.0, 540.0)
	clip.add_child(_photo)
	add_child(clip)
	var bar := MarginContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.add_theme_constant_override("margin_left", 160)
	bar.add_theme_constant_override("margin_right", 160)
	bar.add_theme_constant_override("margin_bottom", 48)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption = UiStyle.label("", UiStyle.FONT_CAPTION, UiStyle.SIZE_CAPTION)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_constant_override("outline_size", UiStyle.CAPTION_OUTLINE_SIZE)
	_caption.add_theme_color_override("font_outline_color", UiStyle.CAPTION_OUTLINE)
	bar.add_child(_caption)
	add_child(bar)

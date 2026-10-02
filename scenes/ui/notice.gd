extends CanvasLayer
## One line of text at the bottom of the screen for captions and presenter hints. Fades in and
## out slowly; never flashes.

const UiStyle := preload("res://scenes/ui/ui_style.gd")

var _label: Label
var _tween: Tween


func _ready() -> void:
	layer = UiStyle.LAYER_NOTICE
	var area := MarginContainer.new()
	area.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	area.grow_vertical = Control.GROW_DIRECTION_BEGIN
	area.add_theme_constant_override("margin_bottom", UiStyle.MARGIN)
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiStyle.label("", UiStyle.FONT_CAPTION, UiStyle.SIZE_CAPTION)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_constant_override("outline_size", UiStyle.CAPTION_OUTLINE_SIZE)
	_label.add_theme_color_override("font_outline_color", UiStyle.CAPTION_OUTLINE)
	_label.modulate.a = 0.0
	area.add_child(_label)
	add_child(area)
	Director.notice_requested.connect(show_notice)


func show_notice(text: String, hold_s: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	if text.is_empty():
		_tween.tween_property(_label, "modulate:a", 0.0, UiStyle.FADE_S)
		return
	_label.text = text
	_tween.tween_property(_label, "modulate:a", 1.0, UiStyle.FADE_S)
	if hold_s > 0.0:
		_tween.tween_interval(hold_s)
		_tween.tween_property(_label, "modulate:a", 0.0, UiStyle.FADE_S)

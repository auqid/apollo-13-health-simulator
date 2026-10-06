extends CanvasLayer
## Presenter notices (paused, muted, alarm silenced, restart) in a small box at the top centre,
## away from the story captions at the bottom. Fades in and out slowly; never flashes.

const UiStyle := preload("res://scenes/ui/ui_style.gd")

var _box: PanelContainer
var _label: Label
var _tween: Tween


func _ready() -> void:
	layer = UiStyle.LAYER_NOTICE
	var area := MarginContainer.new()
	area.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	area.add_theme_constant_override("margin_top", UiStyle.NOTICE_TOP)
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = PanelContainer.new()
	var style := UiStyle.panel_box()
	style.content_margin_left = UiStyle.NOTICE_PADDING_H
	style.content_margin_right = UiStyle.NOTICE_PADDING_H
	style.content_margin_top = UiStyle.NOTICE_PADDING_V
	style.content_margin_bottom = UiStyle.NOTICE_PADDING_V
	_box.add_theme_stylebox_override("panel", style)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.modulate.a = 0.0
	_label = UiStyle.label("", UiStyle.FONT_HUD, UiStyle.SIZE_NOTICE)
	_box.add_child(_label)
	center.add_child(_box)
	area.add_child(center)
	add_child(area)
	Director.notice_requested.connect(show_notice)


func show_notice(text: String, hold_s: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	if text.is_empty():
		_tween.tween_property(_box, "modulate:a", 0.0, UiStyle.FADE_S)
		return
	_label.text = text
	_tween.tween_property(_box, "modulate:a", 1.0, UiStyle.FADE_S)
	if hold_s > 0.0:
		_tween.tween_interval(hold_s)
		_tween.tween_property(_box, "modulate:a", 0.0, UiStyle.FADE_S)

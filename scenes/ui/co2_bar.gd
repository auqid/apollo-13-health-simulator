extends Control
## Horizontal CO2 bar with a marker at the 7.6 mmHg safe limit. Teal below the limit, amber above.

const Tuning := preload("res://sim/tuning.gd")
const UiStyle := preload("res://scenes/ui/ui_style.gd")

var co2_mmhg: float = 0.0:
	set(value):
		co2_mmhg = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(0, UiStyle.CO2_BAR_HEIGHT + 2 * UiStyle.CO2_MARKER_OVERHANG)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var top: float = UiStyle.CO2_MARKER_OVERHANG
	var track := Rect2(0, top, size.x, UiStyle.CO2_BAR_HEIGHT)
	draw_rect(track, UiStyle.BAR_TRACK)
	var fill: float = clampf(co2_mmhg / Tuning.HUD_CO2_BAR_MAX_MMHG, 0.0, 1.0)
	var fill_color: Color = UiStyle.CAUTION_AMBER if co2_mmhg > Tuning.CO2_ALARM_MMHG else UiStyle.SENSOR_TEAL
	draw_rect(Rect2(track.position, Vector2(size.x * fill, track.size.y)), fill_color)
	var marker_x: float = size.x * Tuning.CO2_ALARM_MMHG / Tuning.HUD_CO2_BAR_MAX_MMHG
	draw_line(Vector2(marker_x, 0), Vector2(marker_x, size.y), UiStyle.PLACARD_WHITE, UiStyle.CO2_MARKER_WIDTH)

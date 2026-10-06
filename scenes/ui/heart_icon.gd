extends Control
## A small heart that beats at a heart rate: it swells on each beat and settles. At most about two
## beats a second, and it changes size, not brightness, so nothing flashes.

const UiStyle := preload("res://scenes/ui/ui_style.gd")

## How long the swell takes to settle, and how much bigger the heart gets on a beat.
const BEAT_SETTLE_S := 0.12
const BEAT_SWELL := 0.25
const REST_SCALE := 0.8

var bpm: float = 70.0
var color: Color = UiStyle.SENSOR_TEAL
var _beat_s: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(UiStyle.HEART_ICON_SIZE, UiStyle.HEART_ICON_SIZE)


func _process(delta: float) -> void:
	_beat_s += delta
	var period_s: float = 60.0 / maxf(bpm, 1.0)
	if _beat_s >= period_s:
		_beat_s = fmod(_beat_s, period_s)
	queue_redraw()


func _draw() -> void:
	var swell: float = exp(-_beat_s / BEAT_SETTLE_S) * BEAT_SWELL
	var span: float = minf(size.x, size.y) * (REST_SCALE + swell)
	var middle: Vector2 = size * 0.5
	var lobe: float = span * 0.27
	draw_circle(middle + Vector2(-lobe * 0.95, -lobe * 0.35), lobe, color)
	draw_circle(middle + Vector2(lobe * 0.95, -lobe * 0.35), lobe, color)
	draw_colored_polygon(PackedVector2Array([middle + Vector2(-span * 0.5, -lobe * 0.15),
		middle + Vector2(span * 0.5, -lobe * 0.15), middle + Vector2(0.0, span * 0.5)]), color)

extends RefCounted
## Instrument panels drawn as textures instead of modelled (SPEC.md section 8). Each layout is a
## list of elements in metres on the panel, origin top left, y down. The painter draws gauges,
## switches, breakers and unlit lamp windows; the cabin adds the lamps' glow and the placards
## (Label3D) from the same layout, so they line up.
## TODO(fact-check): placard wording and positions are a plausible LM arrangement, not a replica.

const UiStyle := preload("res://scenes/ui/ui_style.gd")

const PX_PER_M := 800.0
const SUPERSAMPLE := 2

const FACE := Color("#4D5450")
const BLOCK := Color("#444A47")
const SEAM := Color("#2A2E2C")
const BEZEL := Color("#2C302E")
const METAL := Color("#B9BCB6")
const METAL_DARK := Color("#6E726E")
const FDAI_SKY := Color("#A7A9A3")
const FDAI_GROUND := Color("#222524")
const WALL := Color("#5E6560")
const WALL_ALT := Color("#596059")
const WALL_SEAM := Color("#474D49")
## Unlit lamp windows: the palette's warning red and caution amber at about a quarter brightness.
const RED_UNLIT := Color("#370F0C")
const AMBER_UNLIT := Color("#3F2E10")

## Gauge proportions as fractions of the radius.
const GAUGE_FACE := 0.84
const GAUGE_TICK_IN := 0.62
const GAUGE_TICK_OUT := 0.78
const GAUGE_TICK_WIDTH := 0.05
const GAUGE_NEEDLE := 0.68
const GAUGE_NEEDLE_WIDTH := 0.07
const GAUGE_CAP := 0.1
const GAUGE_TICKS := 11
const GAUGE_START_DEG := 135.0
const GAUGE_SWEEP_DEG := 270.0
const FDAI_BALL := 0.82
const LINE_M := 0.004

const CONSOLE_SIZE := Vector2(1.9, 0.72)
const CONSOLE: Array = [
	{"kind": "block", "x": 0.03, "y": 0.03, "w": 0.76, "h": 0.66},
	{"kind": "block", "x": 0.82, "y": 0.03, "w": 0.26, "h": 0.66},
	{"kind": "block", "x": 1.11, "y": 0.03, "w": 0.76, "h": 0.66},
	{"kind": "toggles", "x": 0.09, "y": 0.09, "count": 9, "dx": 0.06, "size": 0.022},
	{"kind": "placard", "text": "ENGINE ARM", "x": 0.33, "y": 0.145},
	{"kind": "fdai", "x": 0.2, "y": 0.38, "r": 0.15},
	{"kind": "tape", "x": 0.4, "y": 0.22, "w": 0.035, "h": 0.3},
	{"kind": "tape", "x": 0.45, "y": 0.22, "w": 0.035, "h": 0.3},
	{"kind": "gauge", "x": 0.62, "y": 0.31, "r": 0.075, "value": 0.35},
	{"kind": "gauge", "x": 0.42, "y": 0.61, "r": 0.045, "value": 0.6},
	{"kind": "gauge", "x": 0.53, "y": 0.61, "r": 0.045, "value": 0.2},
	{"kind": "gauge", "x": 0.64, "y": 0.61, "r": 0.045, "value": 0.8},
	{"kind": "button", "x": 0.07, "y": 0.58, "w": 0.08, "h": 0.06},
	{"kind": "button", "x": 0.18, "y": 0.58, "w": 0.08, "h": 0.06},
	{"kind": "placard", "text": "ABORT", "x": 0.11, "y": 0.665},
	{"kind": "placard", "text": "ABORT STAGE", "x": 0.22, "y": 0.665},
	{"kind": "lamp", "name": "master_alarm", "color": "red", "x": 0.7, "y": 0.1, "w": 0.07, "h": 0.05},
	{"kind": "placard", "text": "MASTER ALARM", "x": 0.735, "y": 0.175},
	{"kind": "display", "x": 0.85, "y": 0.07, "w": 0.2, "h": 0.06},
	{"kind": "lamps", "x": 0.845, "y": 0.2, "cols": 4, "rows": 5, "dx": 0.055, "dy": 0.045, "w": 0.045, "h": 0.03},
	{"kind": "lamp", "name": "co2", "color": "amber", "x": 0.845, "y": 0.425, "w": 0.045, "h": 0.03},
	{"kind": "placard", "text": "CO2", "x": 0.8675, "y": 0.475},
	{"kind": "toggles", "x": 0.87, "y": 0.6, "count": 3, "dx": 0.07, "size": 0.022},
	{"kind": "toggles", "x": 1.17, "y": 0.09, "count": 9, "dx": 0.06, "size": 0.022},
	{"kind": "lamp", "name": "master_alarm", "color": "red", "x": 1.13, "y": 0.18, "w": 0.07, "h": 0.05},
	{"kind": "placard", "text": "MASTER ALARM", "x": 1.165, "y": 0.255},
	{"kind": "fdai", "x": 1.7, "y": 0.38, "r": 0.15},
	{"kind": "tape", "x": 1.43, "y": 0.22, "w": 0.035, "h": 0.3},
	{"kind": "tape", "x": 1.48, "y": 0.22, "w": 0.035, "h": 0.3},
	{"kind": "gauge", "x": 1.24, "y": 0.61, "r": 0.045, "value": 0.45},
	{"kind": "gauge", "x": 1.35, "y": 0.61, "r": 0.045, "value": 0.3},
	{"kind": "gauge", "x": 1.46, "y": 0.61, "r": 0.045, "value": 0.7},
	{"kind": "gauge", "x": 1.57, "y": 0.61, "r": 0.045, "value": 0.5},
	{"kind": "placard", "text": "CABIN", "x": 1.24, "y": 0.675},
	{"kind": "placard", "text": "SUIT", "x": 1.35, "y": 0.675},
	{"kind": "placard", "text": "GLYCOL", "x": 1.46, "y": 0.675},
	{"kind": "placard", "text": "O2", "x": 1.57, "y": 0.675},
	{"kind": "knob", "x": 1.72, "y": 0.62, "r": 0.03},
	{"kind": "knob", "x": 1.81, "y": 0.62, "r": 0.03},
]

const PILLAR_SIZE := Vector2(0.3, 0.68)
const PILLAR: Array = [
	{"kind": "block", "x": 0.02, "y": 0.02, "w": 0.26, "h": 0.64},
	{"kind": "gauge", "x": 0.15, "y": 0.14, "r": 0.07, "value": 0.55},
	{"kind": "gauge", "x": 0.15, "y": 0.33, "r": 0.07, "value": 0.25},
	{"kind": "gauge", "x": 0.15, "y": 0.52, "r": 0.06, "value": 0.7},
	{"kind": "toggles", "x": 0.1, "y": 0.63, "count": 2, "dx": 0.1, "size": 0.018},
]

const BREAKERS_SIZE := Vector2(0.9, 0.7)
const BREAKERS: Array = [
	{"kind": "block", "x": 0.02, "y": 0.02, "w": 0.86, "h": 0.66},
	{"kind": "breakers", "x": 0.065, "y": 0.08, "cols": 15, "rows": 9, "dx": 0.055, "dy": 0.068, "r": 0.011},
	{"kind": "frame", "x": 0.035, "y": 0.045, "w": 0.2725, "h": 0.61},
	{"kind": "frame", "x": 0.3075, "y": 0.045, "w": 0.275, "h": 0.61},
	{"kind": "frame", "x": 0.5825, "y": 0.045, "w": 0.2775, "h": 0.61},
]

const ECS_SIZE := Vector2(0.62, 0.85)
const ECS: Array = [
	{"kind": "block", "x": 0.02, "y": 0.02, "w": 0.58, "h": 0.81},
	{"kind": "gauge", "x": 0.17, "y": 0.17, "r": 0.11, "value": 0.15},
	{"kind": "placard", "text": "PART PRESS CO2", "x": 0.17, "y": 0.31},
	{"kind": "gauge", "x": 0.45, "y": 0.17, "r": 0.09, "value": 0.55},
	{"kind": "placard", "text": "CABIN PRESS", "x": 0.45, "y": 0.29},
	{"kind": "gauge", "x": 0.45, "y": 0.43, "r": 0.09, "value": 0.4},
	{"kind": "placard", "text": "CABIN TEMP", "x": 0.45, "y": 0.55},
	{"kind": "lamp", "name": "co2", "color": "amber", "x": 0.09, "y": 0.37, "w": 0.16, "h": 0.06},
	{"kind": "placard", "text": "CO2", "x": 0.17, "y": 0.465},
	{"kind": "knob", "x": 0.17, "y": 0.56, "r": 0.05},
	{"kind": "toggles", "x": 0.1, "y": 0.7, "count": 5, "dx": 0.1, "size": 0.022},
]

const SIDE_CONSOLE_SIZE := Vector2(0.9, 0.24)
const SIDE_CONSOLE: Array = [
	{"kind": "block", "x": 0.02, "y": 0.02, "w": 0.86, "h": 0.2},
	{"kind": "toggles", "x": 0.08, "y": 0.09, "count": 7, "dx": 0.08, "size": 0.02},
	{"kind": "knob", "x": 0.72, "y": 0.12, "r": 0.035},
	{"kind": "knob", "x": 0.81, "y": 0.12, "r": 0.035},
]

const HATCH_SIZE := Vector2(0.84, 0.84)
const HATCH: Array = [{"kind": "hatch_disc", "x": 0.42, "y": 0.42, "r": 0.41}]

const FRONT_HATCH_SIZE := Vector2(0.9, 0.58)
const FRONT_HATCH: Array = [{"kind": "hatch_door", "x": 0.03, "y": 0.03, "w": 0.84, "h": 0.52}]

const WALL_TILE_SIZE := Vector2(1.2, 1.2)
const WALL_TILE: Array = [{"kind": "wall"}]

static var _cache: Dictionary = {}


## The texture for a layout, painted once and shared.
static func texture(key: String, size_m: Vector2, layout: Array, background: Color = FACE) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var painter := Painter.new(size_m, PX_PER_M * SUPERSAMPLE, background)
	for element: Dictionary in layout:
		painter.draw(element)
	var image: Image = painter.image
	image.resize(ceili(size_m.x * PX_PER_M), ceili(size_m.y * PX_PER_M), Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps()
	var result := ImageTexture.create_from_image(image)
	_cache[key] = result
	return result


static func lamp_color(name: String) -> Color:
	return UiStyle.WARNING_RED if name == "red" else UiStyle.CAUTION_AMBER


class Painter extends RefCounted:
	var image: Image
	var px_per_m: float

	func _init(size_m: Vector2, pixels_per_m: float, background: Color) -> void:
		px_per_m = pixels_per_m
		image = Image.create_empty(ceili(size_m.x * px_per_m), ceili(size_m.y * px_per_m), false, Image.FORMAT_RGBA8)
		image.fill(background)

	func draw(e: Dictionary) -> void:
		var x: float = e.get("x", 0.0)
		var y: float = e.get("y", 0.0)
		match str(e["kind"]):
			"block":
				rect(x, y, e["w"], e["h"], BLOCK)
				frame(x, y, e["w"], e["h"], LINE_M, SEAM)
			"frame":
				frame(x, y, e["w"], e["h"], LINE_M * 0.6, UiStyle.PLACARD_WHITE)
			"gauge":
				gauge(x, y, e["r"], e.get("value", 0.5))
			"fdai":
				fdai(x, y, e["r"])
			"tape":
				tape(x, y, e["w"], e["h"])
			"toggles":
				for i in int(e["count"]):
					toggle(x + i * float(e["dx"]), y, e["size"], i % 3 != 1)
			"breakers":
				for row in int(e["rows"]):
					for col in int(e["cols"]):
						var pulled: bool = (row * 7 + col * 3) % 10 < 2
						breaker(x + col * float(e["dx"]), y + row * float(e["dy"]), e["r"], pulled)
			"lamps":
				for row in int(e["rows"]):
					for col in int(e["cols"]):
						var tint: String = "red" if row < 2 else "amber"
						lamp(x + col * float(e["dx"]), y + row * float(e["dy"]), e["w"], e["h"], tint)
			"lamp":
				lamp(x, y, e["w"], e["h"], e["color"])
			"button":
				rect(x, y, e["w"], e["h"], BEZEL)
				rect(x + LINE_M, y + LINE_M, float(e["w"]) - 2 * LINE_M, float(e["h"]) - 2 * LINE_M, METAL_DARK)
			"display":
				rect(x, y, e["w"], e["h"], UiStyle.INSTRUMENT_BLACK)
				frame(x, y, e["w"], e["h"], LINE_M, BEZEL)
			"knob":
				circle(x, y, e["r"], UiStyle.INSTRUMENT_BLACK)
				line(x, y, x, y - float(e["r"]) * 0.85, float(e["r"]) * 0.2, UiStyle.PLACARD_WHITE)
			"hatch_disc":
				hatch_disc(x, y, e["r"])
			"hatch_door":
				hatch_door(x, y, e["w"], e["h"])
			"wall":
				wall()

	func rect(x: float, y: float, w: float, h: float, color: Color) -> void:
		var rx: int = roundi(x * px_per_m)
		var ry: int = roundi(y * px_per_m)
		var rw: int = maxi(roundi((x + w) * px_per_m) - rx, 1)
		var rh: int = maxi(roundi((y + h) * px_per_m) - ry, 1)
		image.fill_rect(Rect2i(rx, ry, rw, rh), color)

	func frame(x: float, y: float, w: float, h: float, t: float, color: Color) -> void:
		rect(x, y, w, t, color)
		rect(x, y + h - t, w, t, color)
		rect(x, y, t, h, color)
		rect(x + w - t, y, t, h, color)

	func circle(cx: float, cy: float, r: float, color: Color) -> void:
		ring(cx, cy, r, r, color)

	## Fills the band between radius r and r - thickness.
	func ring(cx: float, cy: float, r: float, thickness: float, color: Color) -> void:
		var pcx: float = cx * px_per_m
		var pcy: float = cy * px_per_m
		var outer: float = r * px_per_m
		var inner: float = maxf(r - thickness, 0.0) * px_per_m
		for row in range(floori(pcy - outer), ceili(pcy + outer) + 1):
			var dy: float = row + 0.5 - pcy
			if absf(dy) > outer:
				continue
			var half_outer: float = sqrt(outer * outer - dy * dy)
			if absf(dy) >= inner:
				_span(pcx - half_outer, pcx + half_outer, row, color)
			else:
				var half_inner: float = sqrt(inner * inner - dy * dy)
				_span(pcx - half_outer, pcx - half_inner, row, color)
				_span(pcx + half_inner, pcx + half_outer, row, color)

	func line(x0: float, y0: float, x1: float, y1: float, width: float, color: Color) -> void:
		var length_px: float = Vector2(x1 - x0, y1 - y0).length() * px_per_m
		var steps: int = maxi(ceili(length_px / maxf(width * px_per_m * 0.5, 1.0)), 1)
		for i in steps + 1:
			var t: float = float(i) / steps
			circle(lerpf(x0, x1, t), lerpf(y0, y1, t), width * 0.5, color)

	func gauge(cx: float, cy: float, r: float, value: float) -> void:
		circle(cx, cy, r, BEZEL)
		circle(cx, cy, r * GAUGE_FACE, UiStyle.INSTRUMENT_BLACK)
		for i in GAUGE_TICKS:
			var angle: float = deg_to_rad(GAUGE_START_DEG + GAUGE_SWEEP_DEG * i / (GAUGE_TICKS - 1))
			var direction := Vector2(cos(angle), sin(angle))
			line(cx + direction.x * r * GAUGE_TICK_IN, cy + direction.y * r * GAUGE_TICK_IN,
				cx + direction.x * r * GAUGE_TICK_OUT, cy + direction.y * r * GAUGE_TICK_OUT,
				r * GAUGE_TICK_WIDTH, UiStyle.PLACARD_WHITE)
		var needle: float = deg_to_rad(GAUGE_START_DEG + GAUGE_SWEEP_DEG * clampf(value, 0.0, 1.0))
		line(cx, cy, cx + cos(needle) * r * GAUGE_NEEDLE, cy + sin(needle) * r * GAUGE_NEEDLE,
			r * GAUGE_NEEDLE_WIDTH, UiStyle.PLACARD_WHITE)
		circle(cx, cy, r * GAUGE_CAP, METAL_DARK)

	## The attitude ball: light sky over dark ground, a horizon line and a small pitch ladder.
	func fdai(cx: float, cy: float, r: float) -> void:
		circle(cx, cy, r, BEZEL)
		var ball: float = r * FDAI_BALL
		circle(cx, cy, ball, FDAI_GROUND)
		var pcx: float = cx * px_per_m
		var pcy: float = cy * px_per_m
		var pball: float = ball * px_per_m
		for row in range(floori(pcy - pball), ceili(pcy)):
			var dy: float = row + 0.5 - pcy
			if absf(dy) <= pball:
				var half: float = sqrt(pball * pball - dy * dy)
				_span(pcx - half, pcx + half, row, FDAI_SKY)
		rect(cx - ball, cy - LINE_M * 0.5, ball * 2.0, LINE_M, UiStyle.PLACARD_WHITE)
		for rung: float in [-0.5, -0.25, 0.25, 0.5]:
			var color: Color = UiStyle.INSTRUMENT_BLACK if rung < 0.0 else UiStyle.PLACARD_WHITE
			rect(cx - ball * 0.2, cy + rung * ball - LINE_M * 0.5, ball * 0.4, LINE_M, color)
		rect(cx - ball * 0.45, cy - LINE_M, ball * 0.3, LINE_M * 2.0, UiStyle.CAUTION_AMBER)
		rect(cx + ball * 0.15, cy - LINE_M, ball * 0.3, LINE_M * 2.0, UiStyle.CAUTION_AMBER)

	func tape(x: float, y: float, w: float, h: float) -> void:
		rect(x, y, w, h, UiStyle.INSTRUMENT_BLACK)
		var ticks: int = 12
		for i in ticks + 1:
			var long_tick: bool = i % 4 == 0
			rect(x, y + h * i / ticks - LINE_M * 0.3, w * (0.6 if long_tick else 0.35), LINE_M * 0.6, UiStyle.PLACARD_WHITE)
		rect(x + w * 0.55, y + h * 0.42, w * 0.45, h * 0.05, UiStyle.CAUTION_AMBER)

	func toggle(cx: float, cy: float, size: float, up: bool) -> void:
		circle(cx, cy, size * 0.55, METAL_DARK)
		circle(cx, cy, size * 0.35, BEZEL)
		var tip_y: float = cy + (-1.0 if up else 1.0) * size * 0.95
		line(cx, cy, cx, tip_y, size * 0.3, METAL)
		circle(cx, tip_y, size * 0.22, METAL)

	## A round breaker knob. Pulled breakers (open, after the power-down) show a white collar.
	func breaker(cx: float, cy: float, r: float, pulled: bool) -> void:
		circle(cx, cy, r * 1.25, BEZEL)
		if pulled:
			circle(cx, cy, r, UiStyle.PLACARD_WHITE)
			circle(cx, cy, r * 0.72, UiStyle.INSTRUMENT_BLACK)
		else:
			circle(cx, cy, r, UiStyle.INSTRUMENT_BLACK)

	## An unlit caution or warning lamp window; the cabin adds the glow on top when it's lit.
	func lamp(x: float, y: float, w: float, h: float, tint: String) -> void:
		rect(x, y, w, h, BEZEL)
		rect(x + LINE_M, y + LINE_M, w - 2 * LINE_M, h - 2 * LINE_M, RED_UNLIT if tint == "red" else AMBER_UNLIT)

	## The overhead docking hatch: a dished door inside a latch ring, with a central handle.
	func hatch_disc(cx: float, cy: float, r: float) -> void:
		circle(cx, cy, r, BEZEL)
		circle(cx, cy, r * 0.9, WALL_ALT)
		ring(cx, cy, r * 0.9, r * 0.025, SEAM)
		ring(cx, cy, r * 0.55, r * 0.02, WALL_SEAM)
		for i in 12:
			var angle: float = TAU * (i + 0.5) / 12.0
			var latch := Vector2(cx + cos(angle) * r * 0.95, cy + sin(angle) * r * 0.95)
			circle(latch.x, latch.y, r * 0.04, METAL_DARK)
		circle(cx, cy, r * 0.16, BEZEL)
		rect(cx - r * 0.42, cy - r * 0.045, r * 0.84, r * 0.09, METAL_DARK)
		circle(cx - r * 0.42, cy, r * 0.06, METAL_DARK)
		circle(cx + r * 0.42, cy, r * 0.06, METAL_DARK)

	func hatch_door(x: float, y: float, w: float, h: float) -> void:
		rect(x, y, w, h, WALL_ALT)
		frame(x, y, w, h, LINE_M * 2.0, SEAM)
		frame(x + w * 0.04, y + h * 0.06, w * 0.92, h * 0.88, LINE_M, SEAM)
		rect(x + w * 0.42, y + h * 0.44, w * 0.16, h * 0.08, METAL)
		rect(x + w * 0.02, y + h * 0.2, w * 0.03, h * 0.12, METAL_DARK)
		rect(x + w * 0.02, y + h * 0.68, w * 0.03, h * 0.12, METAL_DARK)

	## Grey-green wall in large panels with offset seams, so it doesn't read as tiles. Tiles seamlessly.
	func wall() -> void:
		var tile: Vector2 = Vector2(image.get_width(), image.get_height()) / px_per_m
		var half_x: float = tile.x * 0.5
		var left_split: float = tile.y * 0.4
		var right_split: float = tile.y * 0.75
		rect(0.0, left_split, half_x, tile.y - left_split, WALL_ALT)
		rect(half_x, 0.0, half_x, right_split, WALL_ALT)
		for seam_x: float in [0.0, half_x]:
			rect(seam_x - LINE_M * 0.5, 0.0, LINE_M, tile.y, WALL_SEAM)
		rect(0.0, left_split - LINE_M * 0.5, half_x, LINE_M, WALL_SEAM)
		rect(half_x, right_split - LINE_M * 0.5, half_x, LINE_M, WALL_SEAM)
		rect(0.0, -LINE_M * 0.5, tile.x, LINE_M, WALL_SEAM)
		for i in 8:
			var along: float = (i + 0.5) * tile.y / 8.0
			circle(LINE_M * 3.0, along, LINE_M * 0.8, WALL_SEAM)
			circle(half_x + LINE_M * 3.0, along, LINE_M * 0.8, WALL_SEAM)

	func _span(x0: float, x1: float, row: int, color: Color) -> void:
		var a: int = roundi(x0)
		var b: int = roundi(x1)
		if b > a and row >= 0 and row < image.get_height():
			image.fill_rect(Rect2i(a, row, b - a, 1), color)

extends RefCounted
## Visual style shared by the on-screen UI (SPEC.md section 8): palette, fonts, sizes and spacing
## at the 1920x1080 base resolution, plus how mission times are written.

const PANEL_GREY := Color("#5E6560")
const INSTRUMENT_BLACK := Color("#1A1D1C")
const PLACARD_WHITE := Color("#ECE9E1")
const CAUTION_AMBER := Color("#E2A33B")
const WARNING_RED := Color("#C4372C")
const SENSOR_TEAL := Color("#8CCFC1")
const COLD_TINT := Color("#9DB8D9")
## Plain dark background until the 3D cabin exists.
const BACKDROP := Color("#0E1110")

const TEXT_DIM := Color(PLACARD_WHITE, 0.62)
const TEXT_FAINT := Color(PLACARD_WHITE, 0.42)
const PANEL_FILL := Color(INSTRUMENT_BLACK, 0.86)
const PANEL_LINE := Color(SENSOR_TEAL, 0.32)
const FOCUS_FILL := Color(SENSOR_TEAL, 0.10)
const BAR_TRACK := Color(PLACARD_WHITE, 0.12)

const FONT_HUD := "res://assets/fonts/Barlow-Medium.ttf"
const FONT_HUD_LIGHT := "res://assets/fonts/Barlow-Regular.ttf"
const FONT_HUD_STRONG := "res://assets/fonts/Barlow-SemiBold.ttf"
const FONT_CAPTION := "res://assets/fonts/BarlowCondensed-Regular.ttf"
const FONT_TITLE := "res://assets/fonts/BarlowCondensed-SemiBold.ttf"

## Font sizes in pixels at 1080p. Body text is never below 20.
const SIZE_LABEL := 20
const SIZE_BODY := 22
const SIZE_NAME := 24
const SIZE_ENV_VALUE := 28
const SIZE_VITAL := 32
const SIZE_CAPTION := 32
const SIZE_CLOCK := 46

const LAYER_HUD := 10
const LAYER_NOTICE := 15
const LAYER_DEBUG := 20

const MARGIN := 40
const PANEL_PADDING := 24
const ROW_PADDING := 12
const ROW_PADDING_V := 4
const PANEL_RADIUS := 4
const LINE_WIDTH := 1
const FOCUS_BAR_WIDTH := 3
const ROW_GAP := 10
const SECTION_GAP := 20
## Fits the name column, four vital columns and the row and panel padding.
const HUD_PANEL_WIDTH := 552
const NAME_COLUMN_WIDTH := 96
const VITAL_COLUMN_WIDTH := 96
const CO2_BAR_HEIGHT := 10
const CO2_MARKER_OVERHANG := 5
const CO2_MARKER_WIDTH := 2
const DEBUG_PANEL_WIDTH := 660
const DEBUG_PANEL_TOP := 200
const DEBUG_FILL := Color(INSTRUMENT_BLACK, 0.96)
const DEBUG_LINE := Color(PANEL_GREY, 0.9)
const DEBUG_SPIN_WIDTH := 150
const DEBUG_ID_WIDTH := 44
const DEBUG_STATUS_WIDTH := 96
const DEBUG_SCROLL_GUTTER := 18
const DEBUG_BUTTON_FILL := Color(PANEL_GREY, 0.45)
const DEBUG_BUTTON_HOVER := Color(PANEL_GREY, 0.75)
const DEBUG_BUTTON_PRESSED := Color(SENSOR_TEAL, 0.35)
const DEBUG_BUTTON_PADDING_H := 10
const DEBUG_BUTTON_PADDING_V := 4
const CAPTION_OUTLINE_SIZE := 8
const CAPTION_OUTLINE := Color(0.0, 0.0, 0.0, 0.85)
const FADE_S := 0.4

static var _fonts: Dictionary = {}


## A font from assets/fonts, with tabular figures if asked. Falls back to Godot's default font
## if the file is missing, so a missing asset never crashes the game.
static func font(path: String, tabular: bool = false) -> Font:
	var key: String = path + (":tnum" if tabular else "")
	if _fonts.has(key):
		return _fonts[key]
	var result: Font = ThemeDB.fallback_font
	if ResourceLoader.exists(path):
		result = load(path)
	else:
		push_warning("Missing font %s, using the default font" % path)
	if tabular:
		var variation := FontVariation.new()
		variation.base_font = result
		variation.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
		result = variation
	_fonts[key] = result
	return result


static func label(text: String, font_path: String, size: int, color: Color = PLACARD_WHITE,
		tabular: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(font_path, tabular))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func panel_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL_FILL
	box.border_color = PANEL_LINE
	box.set_border_width_all(LINE_WIDTH)
	box.set_corner_radius_all(PANEL_RADIUS)
	box.set_content_margin_all(PANEL_PADDING)
	return box


static func divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = PANEL_LINE
	line.custom_minimum_size = Vector2(0, LINE_WIDTH)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Mission clock as GET hhh:mm:ss.
static func format_get(get_hours: float) -> String:
	var total_s: int = floori(maxf(get_hours, 0.0) * 3600.0 + 1e-6)
	return "%03d:%02d:%02d" % [floori(total_s / 3600.0), floori((total_s % 3600) / 60.0), total_s % 60]


## Mission clock without seconds, as hhh:mm.
static func format_get_short(get_hours: float) -> String:
	return format_get(get_hours).left(6)


## A duration in plain words, like "23 h 06 min".
static func format_hours(hours: float) -> String:
	var total_min: int = floori(maxf(hours, 0.0) * 60.0 + 1e-6)
	return "%d h %02d min" % [floori(total_min / 60.0), total_min % 60]

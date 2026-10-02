extends Node
## Presenter flow and keys (SPEC.md section 7), handled here so they work in every state.
## For now the flow is a single timeskip from the explosion to splashdown; cutscenes, polls
## and the reentry sequence come with the full state machine.

const Timeline := preload("res://sim/timeline.gd")
const Tuning := preload("res://sim/tuning.gd")
const UiStyle := preload("res://scenes/ui/ui_style.gd")

signal hud_visibility_changed(visible: bool)
signal debug_visibility_changed(visible: bool)
## hold_s = 0 keeps the notice up until the next one; empty text hides it.
signal notice_requested(text: String, hold_s: float)

const FOCUS_ACTIONS: Dictionary = {
	"focus_lovell": "lovell",
	"focus_swigert": "swigert",
	"focus_haise": "haise",
}
const START_NOTICE := "Press Space to start the timeskip"
const PAUSED_NOTICE := "Paused. Press Space to continue"
const RESTART_NOTICE := "Press R again to restart"
const SPLASHDOWN_NOTICE := "Splashdown at GET %s. Press R twice to restart"

var hud_visible: bool = true
var debug_visible: bool = false
var _restart_armed_until_ms: int = 0


func _ready() -> void:
	Game.target_reached.connect(_on_target_reached)
	Game.caption_requested.connect(_on_caption_requested)
	_apply_command_line.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	var handled: bool = true
	if event.is_action_pressed("advance"):
		_advance()
	elif event.is_action_pressed("toggle_debug"):
		set_debug_visible(not debug_visible)
	elif event.is_action_pressed("toggle_hud"):
		hud_visible = not hud_visible
		hud_visibility_changed.emit(hud_visible)
	elif event.is_action_pressed("toggle_fullscreen"):
		_toggle_fullscreen()
	elif event.is_action_pressed("restart"):
		_restart()
	else:
		handled = false
		for action: String in FOCUS_ACTIONS:
			if event.is_action_pressed(action):
				Game.set_focus(FOCUS_ACTIONS[action])
				handled = true
	if handled:
		get_viewport().set_input_as_handled()


func set_debug_visible(value: bool) -> void:
	debug_visible = value
	debug_visibility_changed.emit(debug_visible)


func _advance() -> void:
	if Timeline.at_splashdown(Game.state):
		return
	Game.toggle_play()
	notice_requested.emit("" if Game.running else PAUSED_NOTICE, 0.0)


func _restart() -> void:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms <= _restart_armed_until_ms:
		_restart_armed_until_ms = 0
		Game.reset()
		notice_requested.emit(START_NOTICE, 0.0)
		return
	_restart_armed_until_ms = now_ms + roundi(Tuning.RESTART_CONFIRM_S * 1000.0)
	notice_requested.emit(RESTART_NOTICE, Tuning.RESTART_CONFIRM_S)


func _toggle_fullscreen() -> void:
	var window: Window = get_window()
	window.mode = Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


func _on_target_reached(at_get: float) -> void:
	if Timeline.at_splashdown(Game.state):
		notice_requested.emit(SPLASHDOWN_NOTICE % UiStyle.format_get(at_get), 0.0)


func _on_caption_requested(text: String) -> void:
	notice_requested.emit(text, Tuning.CAPTION_HOLD_S)


## Development shortcuts after "--", e.g. godot --path . -- --get=100 --play --debug
func _apply_command_line() -> void:
	var notice: String = START_NOTICE
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--get="):
			Game.seek(arg.trim_prefix("--get=").to_float())
		elif arg == "--play":
			Game.play()
			notice = ""
		elif arg == "--debug":
			set_debug_visible(true)
	notice_requested.emit(notice, 0.0)

extends Node
## Session flow (SPEC.md section 1) and presenter keys (section 7). Keys are handled here so
## they work in every state. Cutscenes play photos, mission audio and captions.

const Timeline := preload("res://sim/timeline.gd")
const SimModel := preload("res://sim/sim_model.gd")
const SimState := preload("res://sim/sim_state.gd")
const Tuning := preload("res://sim/tuning.gd")
const UiStyle := preload("res://scenes/ui/ui_style.gd")
const StageCard := preload("res://scenes/ui/stage_card.gd")
const CutsceneView := preload("res://scenes/ui/cutscene_view.gd")
const BioAudio := preload("res://audio/bio_audio.gd")
const Effects := preload("res://fx/effects.gd")

signal hud_visibility_changed(visible: bool)
signal debug_visibility_changed(visible: bool)
## hold_s = 0 keeps the notice up until the next one; empty text hides it.
signal notice_requested(text: String, hold_s: float)

const FOCUS_ACTIONS: Dictionary = {
	"focus_lovell": "lovell",
	"focus_swigert": "swigert",
	"focus_haise": "haise",
}
const PHASE_INTRO := "intro"
const PHASE_CUTSCENE := "cutscene"
const PHASE_POLL := "poll"
const PHASE_HOLD := "hold"
const PHASE_TIMESKIP := "timeskip"
const PHASE_REENTRY := "reentry"
const PHASE_SCORECARD := "scorecard"
const PAUSED_NOTICE := "Paused. Press Space to continue"
const RESTART_NOTICE := "Press R again to restart"

var hud_visible: bool = true
var debug_visible: bool = false
## intro, cutscene, poll, hold, timeskip, reentry or scorecard.
var phase: String = PHASE_INTRO
var event_index: int = 0
var _card_left_s: float = 0.0
var _hold_left_s: float = 0.0
var _clock_target: float = INF
var _restart_armed_until_ms: int = 0
var _card: StageCard
## Where the current cutscene goes when it ends: poll or timeskip.
var _cutscene_next: String = PHASE_POLL
var _shots: Array = []
var _shot_index: int = 0
var _shot_left_s: float = 0.0
var _shot_elapsed_s: float = 0.0
var _caption_index: int = 0
var _silence_left_s: float = 0.0
var _resume_after_silence: bool = false
## Asset paths a cutscene asked for and did not find.
var missing_assets: PackedStringArray = []


func _ready() -> void:
	Game.target_reached.connect(_on_target_reached)
	Game.caption_requested.connect(_on_caption_requested)
	_boot.call_deferred()


func _process(delta: float) -> void:
	if phase == PHASE_INTRO:
		_card_left_s -= delta
		if _card_left_s <= 0.0:
			skip()
	elif phase == PHASE_CUTSCENE:
		_run_cutscene(delta)
	elif phase == PHASE_HOLD:
		_hold_left_s -= delta
		if _hold_left_s <= 0.0:
			finish_choice_hold()
	elif phase == PHASE_TIMESKIP or phase == PHASE_REENTRY:
		_run_timeskip_captions(delta)
		var rate: float = _clock_rate()
		if Game.running and not is_equal_approx(rate, Game.rate_h_per_s):
			Game.set_rate(rate)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	var handled: bool = true
	if event.is_action_pressed("advance"):
		skip()
	elif event.is_action_pressed("choose_a"):
		choose("a")
	elif event.is_action_pressed("choose_b"):
		choose("b")
	elif event.is_action_pressed("toggle_debug"):
		set_debug_visible(not debug_visible)
	elif event.is_action_pressed("toggle_hud"):
		hud_visible = not hud_visible
		hud_visibility_changed.emit(hud_visible)
	elif event.is_action_pressed("toggle_fullscreen"):
		_toggle_fullscreen()
	elif event.is_action_pressed("toggle_mute"):
		_toggle_mute()
	elif event.is_action_pressed("silence_alarm"):
		_silence_alarm()
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


func restart_now() -> void:
	_restart_armed_until_ms = 0
	notice_requested.emit("", 0.0)
	start_session()


## Ids and labels for the debug panel, in play order.
func flow_states() -> Array:
	var states: Array = [{"id": PHASE_INTRO, "label": "Intro"}]
	for event: Dictionary in Timeline.event_list(Game.events):
		var tag: String = str(event["id"]).to_upper()
		states.append({"id": "%s_cutscene" % event["id"], "label": "%s cutscene" % tag})
		states.append({"id": "%s_poll" % event["id"], "label": "%s poll" % tag})
		if event["id"] != "e5":
			states.append({"id": "%s_timeskip" % event["id"], "label": "%s timeskip" % tag})
	states.append({"id": PHASE_REENTRY, "label": "Reentry"})
	states.append({"id": PHASE_SCORECARD, "label": "Scorecard"})
	return states


func start_session() -> void:
	Game.clear_plan()
	Game.pause()
	Game.begin_at(float(Game.events["intro"]["start_get"]))
	event_index = 0
	phase = PHASE_INTRO
	_card_left_s = float(Game.events["intro"]["duration_s"])
	_apply_view("front_windows", "earth")
	var card := _stage()
	if card != null:
		card.show_intro(Game.events["intro"]["text"])


## Space. Skips a card, finishes the choice highlight, pauses a timeskip, or skips reentry.
func skip() -> void:
	match phase:
		PHASE_INTRO:
			_begin_cutscene()
		PHASE_CUTSCENE:
			_end_cutscene()
		PHASE_HOLD:
			finish_choice_hold()
		PHASE_TIMESKIP:
			if _silence_left_s > 0.0:
				return
			_toggle_timeskip()
		PHASE_REENTRY:
			complete_clock()
		PHASE_POLL, PHASE_SCORECARD:
			pass


## A or B during a poll. Anywhere else, the key is accepted and does nothing.
func choose(option_key: String) -> void:
	if phase != PHASE_POLL:
		return
	var event: Dictionary = _current_event()
	if Timeline.find_option(event, option_key).is_empty():
		return
	Game.set_choice(event["id"], option_key)
	phase = PHASE_HOLD
	_hold_left_s = Tuning.POLL_CHOICE_HOLD_S
	var card := _stage()
	if card != null:
		card.highlight(option_key)


func finish_choice_hold() -> void:
	if phase != PHASE_HOLD:
		return
	_hold_left_s = 0.0
	if _current_event()["id"] == "e5":
		_begin_reentry()
	elif _choice_has_reveal():
		_play_reveal_then_timeskip()
	else:
		_begin_timeskip()


## Jumps a running timeskip or the reentry coast straight to its target.
func complete_clock() -> void:
	if phase != PHASE_TIMESKIP and phase != PHASE_REENTRY:
		return
	var dest: float = _clock_target
	Game.pause()
	if Game.state.time.current_get < dest - Timeline.EPSILON_H:
		Game.seek(dest)
	_arrive()


func jump_to_state(state_id: String) -> void:
	Game.pause()
	_hold_left_s = 0.0
	_card_left_s = 0.0
	if state_id == PHASE_INTRO:
		start_session()
		return
	var events: Array = Timeline.event_list(Game.events)
	if state_id == PHASE_SCORECARD:
		_use_historical_plan(events.size())
		Game.replay_to(INF)
		event_index = events.size() - 1
		_begin_scorecard()
		return
	if state_id == PHASE_REENTRY:
		_use_historical_plan(events.size())
		event_index = events.size() - 1
		Game.replay_to(_event_get(events[event_index]))
		_begin_reentry()
		return
	var parts: PackedStringArray = state_id.split("_")
	if parts.size() != 2:
		push_warning("Unknown session state '%s'" % state_id)
		return
	var index: int = _index_of(parts[0])
	if index < 0 or parts[1] not in [PHASE_CUTSCENE, PHASE_POLL, PHASE_TIMESKIP]:
		push_warning("Unknown session state '%s'" % state_id)
		return
	var sm_before: bool = Game.state.flags.sm_jettisoned
	_use_historical_plan(index + 1 if parts[1] == PHASE_TIMESKIP else index)
	event_index = index
	Game.replay_to(_event_get(events[index]))
	_apply_event_view()
	if parts[1] == PHASE_CUTSCENE:
		_start_event_cutscene(sm_before)
	elif parts[1] == PHASE_POLL:
		_show_poll()
	else:
		_begin_timeskip()


func _begin_cutscene() -> void:
	var events: Array = Timeline.event_list(Game.events)
	var event: Dictionary = events[event_index]
	var sm_before: bool = Game.state.flags.sm_jettisoned
	var at_get: float = _event_get(event)
	if Game.state.time.current_get < at_get - Timeline.EPSILON_H:
		Game.seek(at_get)
	_apply_event_view()
	_start_event_cutscene(sm_before)


func _start_event_cutscene(sm_already_gone: bool) -> void:
	_cutscene_next = PHASE_POLL
	var event: Dictionary = _current_event()
	if event["id"] == "e5" and sm_already_gone:
		_start_shots([{"kind": "cabin", "duration_s": 5.0,
			"caption": "The Service Module is already gone. Odyssey is waiting."}])
		return
	if event["id"] == "e5":
		_start_shots(_reveal_shots(str(event.get("cutscene", {}).get("reveal", ""))))
		return
	_start_shots(event.get("cutscene", {}).get("shots", []))


func _begin_poll() -> void:
	_hide_cutscene()
	_show_poll()


func _show_poll() -> void:
	phase = PHASE_POLL
	var event: Dictionary = _current_event()
	var card := _stage()
	if card != null:
		card.show_poll(event["poll"]["question"], event["poll"]["options"])


func _begin_timeskip() -> void:
	var events: Array = Timeline.event_list(Game.events)
	_clock_target = _event_get(events[event_index + 1])
	phase = PHASE_TIMESKIP
	_caption_index = 0
	_silence_left_s = 0.0
	_resume_after_silence = false
	_hide_cutscene()
	var card := _stage()
	if card != null:
		card.hide_card()
	notice_requested.emit("", 0.0)
	Game.set_rate(_clock_rate())
	Game.play(_clock_target)


func _begin_reentry() -> void:
	_hide_cutscene()
	_clock_target = Game.state.time.splashdown_get
	phase = PHASE_REENTRY
	var steps: PackedStringArray = []
	for step: Dictionary in Game.events.get("reentry", {}).get("steps", []):
		steps.append(step.get("title", step["id"]))
	var card := _stage()
	if card != null:
		card.show_reentry(steps)
	Game.set_rate(_clock_rate())
	Game.play(_clock_target)


func _begin_scorecard() -> void:
	_hide_cutscene()
	phase = PHASE_SCORECARD
	Game.pause()
	var card: Dictionary = Game.events["scorecard"]
	var when: String = "Splashdown at GET %s." % UiStyle.format_get(Game.state.time.current_get)
	var stage := _stage()
	if stage != null:
		stage.show_scorecard(card["title"], when, card["closing"])


func _arrive() -> void:
	if phase == PHASE_TIMESKIP:
		event_index += 1
		_begin_cutscene()
	elif phase == PHASE_REENTRY:
		_begin_scorecard()


func _toggle_timeskip() -> void:
	if Game.running:
		Game.pause()
		notice_requested.emit(PAUSED_NOTICE, 0.0)
	else:
		notice_requested.emit("", 0.0)
		Game.set_rate(_clock_rate())
		Game.play(_clock_target)


func _clock_rate() -> float:
	var at_get: float = Game.state.time.current_get
	var splashdown: float = Game.state.time.splashdown_get
	if at_get >= splashdown - Tuning.REENTRY_BEFORE_SPLASHDOWN_H:
		return Tuning.TIMESKIP_SLOW_H_PER_S
	for burn: Dictionary in Tuning.BURNS:
		if burn["name"] != "PC+2 burn":
			continue
		var start: float = burn["get"]
		if at_get >= start and at_get < start + float(burn["duration_h"]):
			return Tuning.TIMESKIP_SLOW_H_PER_S
	return Tuning.TIMESKIP_H_PER_S


func _on_target_reached(_at_get: float) -> void:
	if phase == PHASE_TIMESKIP or phase == PHASE_REENTRY:
		_arrive()


func _use_historical_plan(count: int) -> void:
	Game.clear_plan()
	var events: Array = Timeline.event_list(Game.events)
	var historical: Dictionary = Timeline.historical_plan(Game.events)
	for i in mini(count, events.size()):
		var event_id: String = events[i]["id"]
		Game.plan[event_id] = historical[event_id]


func _event_get(event: Dictionary) -> float:
	return Timeline.event_get(event, _plan_preview())


## A state with the planned choices applied, so splashdown-relative times are right.
func _plan_preview() -> SimState:
	var preview: SimState = SimModel.initial_state()
	for event_id: String in Game.plan:
		preview = Timeline.choose(preview, Game.events, event_id, Game.plan[event_id])
	return preview


func _play_reveal_then_timeskip() -> void:
	var option: Dictionary = Timeline.find_option(_current_event(), Game.state.decisions.get(_current_event()["id"], ""))
	_cutscene_next = PHASE_TIMESKIP
	_start_shots(_reveal_shots(str(option.get("reveal", ""))))


func _choice_has_reveal() -> bool:
	var option: Dictionary = Timeline.find_option(_current_event(), Game.state.decisions.get(_current_event()["id"], ""))
	return not str(option.get("reveal", "")).is_empty()


func _reveal_shots(reveal_id: String) -> Array:
	var reveal: Dictionary = Game.events.get("reveals", {}).get(reveal_id, {})
	var shots: Array = reveal.get("shots", [])
	if shots.is_empty():
		return [{"kind": "cabin", "duration_s": 4.0, "caption": "The Service Module comes off."}]
	return shots


func _start_shots(shots: Array) -> void:
	phase = PHASE_CUTSCENE
	_shots = _with_cabin_beats(shots)
	_shot_index = -1
	_shot_left_s = 0.0
	var card := _stage()
	if card != null:
		card.hide_card()
	if shots.is_empty():
		_end_cutscene()
		return
	_advance_shot()


func _run_cutscene(delta: float) -> void:
	if _shot_index < 0 or _shot_index >= _shots.size():
		return
	_shot_elapsed_s += delta
	_shot_left_s -= delta
	var shot: Dictionary = _shots[_shot_index]
	if shot.get("kind", "") == "photo":
		var view := _cutscene()
		if view != null:
			view.set_pan(clampf(_shot_elapsed_s / maxf(float(shot.get("duration_s", 1.0)), 0.1), 0.0, 1.0))
	_show_shot_line(shot)
	if _shot_left_s <= 0.0:
		_advance_shot()


func _advance_shot() -> void:
	_shot_index += 1
	if _shot_index >= _shots.size():
		_end_cutscene()
		return
	var shot: Dictionary = _shots[_shot_index]
	_shot_elapsed_s = 0.0
	_shot_left_s = maxf(float(shot.get("duration_s", 4.0)), 0.5)
	_begin_shot(shot)


func _begin_shot(shot: Dictionary) -> void:
	var view := _cutscene()
	var kind: String = shot.get("kind", "cabin")
	if kind == "bang":
		if view != null:
			view.hide_photo()
		var bio := _bio()
		if bio != null:
			bio.play_bang()
		var effects := _effects()
		if effects != null:
			effects.play_explosion_dim()
	elif kind == "photo":
		var texture: Texture2D = _load_texture(str(shot.get("image", "")))
		if view != null:
			if texture != null:
				view.show_photo(texture, _shot_index % 2 == 1)
			else:
				view.hide_photo()
	elif kind == "audio":
		if view != null:
			view.hide_photo()
		var clip_s: float = _play_clip(str(shot.get("audio", "")))
		if clip_s > _shot_left_s:
			_shot_left_s = clip_s + 0.4
	else:
		if view != null:
			view.hide_photo()
	_show_shot_line(shot)


func _show_shot_line(shot: Dictionary) -> void:
	var line: String = str(shot.get("caption", ""))
	for cue: Variant in shot.get("subtitles", []):
		if cue is not Dictionary:
			continue
		var start_s: float = float(cue.get("at_s", 0.0))
		var hold_s: float = float(cue.get("hold_s", 3.0))
		if _shot_elapsed_s >= start_s and _shot_elapsed_s < start_s + hold_s:
			line = str(cue.get("text", line))
			break
	var view := _cutscene()
	if view != null:
		view.show_caption(line)


func _end_cutscene() -> void:
	_shots = []
	_shot_index = -1
	_hide_cutscene()
	if _cutscene_next == PHASE_TIMESKIP:
		_begin_timeskip()
	else:
		_begin_poll()


func _hide_cutscene() -> void:
	var view := _cutscene()
	if view != null:
		view.hide_view()
	var bio := _bio()
	if bio != null:
		bio.stop_voice()


func _with_cabin_beats(shots: Array) -> Array:
	var prepared: Array = []
	var previous_photo: bool = false
	for shot: Variant in shots:
		if shot is not Dictionary:
			continue
		var is_photo: bool = shot.get("kind", "") == "photo"
		if is_photo and previous_photo:
			prepared.append({"kind": "cabin", "duration_s": 2.5, "caption": str(shot.get("caption", ""))})
		prepared.append(shot)
		previous_photo = is_photo
	return prepared


## Plays a clip on the Voice bus. Returns its length in seconds, or 0 when the file is missing.
func _play_clip(path: String) -> float:
	if path.is_empty() or not _asset_exists(path):
		return 0.0
	var bio := _bio()
	if bio == null or not bio.play_voice_file(path):
		return 0.0
	return bio.voice_length_s()


func _load_texture(path: String) -> Texture2D:
	if not _asset_exists(path):
		return null
	var resource: Resource = load(path)
	return resource as Texture2D


func _asset_exists(path: String) -> bool:
	if path.is_empty():
		return false
	if ResourceLoader.exists(path):
		return true
	if path not in missing_assets:
		missing_assets.append(path)
	return false


func _run_timeskip_captions(delta: float) -> void:
	if phase != PHASE_TIMESKIP:
		return
	if _silence_left_s > 0.0:
		_silence_left_s -= delta
		if _silence_left_s <= 0.0 and _resume_after_silence:
			_resume_after_silence = false
			notice_requested.emit("", 0.0)
			Game.set_rate(_clock_rate())
			Game.play(_clock_target)
		return
	var captions: Array = _current_event().get("timeskip", {}).get("captions", [])
	if _caption_index >= captions.size():
		return
	var caption: Dictionary = captions[_caption_index]
	if Game.state.time.current_get + Timeline.EPSILON_H < float(caption.get("get", INF)):
		return
	_caption_index += 1
	notice_requested.emit(str(caption.get("text", "")), 0.0)
	_play_clip(str(caption.get("audio", "")))
	var silence_s: float = float(caption.get("silence_s", 0.0))
	if silence_s > 0.0:
		_resume_after_silence = Game.running
		_silence_left_s = silence_s
		Game.pause()


func _cutscene() -> CutsceneView:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(CutsceneView.GROUP)
	if nodes.is_empty():
		return null
	return nodes[0] as CutsceneView


func _bio() -> BioAudio:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(BioAudio.GROUP)
	if nodes.is_empty():
		return null
	return nodes[0] as BioAudio


func _effects() -> Effects:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(Effects.GROUP)
	if nodes.is_empty():
		return null
	return nodes[0] as Effects


func _current_event() -> Dictionary:
	return Timeline.event_list(Game.events)[event_index]


func _index_of(event_id: String) -> int:
	var events: Array = Timeline.event_list(Game.events)
	for i in events.size():
		if events[i]["id"] == event_id:
			return i
	return -1


func _apply_event_view() -> void:
	var event: Dictionary = _current_event()
	_apply_view(event.get("camera", "front_windows"), event.get("outside", "earth"))


func _apply_view(preset_name: String, outside: String) -> void:
	var cabin := get_tree().get_first_node_in_group("cabin")
	if cabin == null:
		return
	cabin.camera_go_to(preset_name, true)
	cabin.set_outside_view(outside)


func _stage() -> StageCard:
	if _card == null:
		_card = get_tree().get_first_node_in_group(StageCard.GROUP)
	return _card


func _restart() -> void:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms <= _restart_armed_until_ms:
		restart_now()
		return
	_restart_armed_until_ms = now_ms + roundi(Tuning.RESTART_CONFIRM_S * 1000.0)
	notice_requested.emit(RESTART_NOTICE, Tuning.RESTART_CONFIRM_S)


func _toggle_mute() -> void:
	var bio := _bio()
	if bio == null:
		return
	var is_muted: bool = bio.toggle_mute()
	notice_requested.emit("Muted." if is_muted else "Sound on.", Tuning.CAPTION_HOLD_S)


func _silence_alarm() -> void:
	var bio := _bio()
	if bio == null:
		return
	var stopped: bool = bio.silence_alarm()
	notice_requested.emit("Alarm silenced." if stopped else "No alarm.", Tuning.CAPTION_HOLD_S)


func _toggle_fullscreen() -> void:
	var window: Window = get_window()
	window.mode = Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


func _on_caption_requested(text: String) -> void:
	notice_requested.emit(text, Tuning.CAPTION_HOLD_S)


func _boot() -> void:
	_collect_missing_assets(Game.events)
	start_session()
	_apply_command_line()


func _collect_missing_assets(node: Variant) -> void:
	if node is Dictionary:
		for key: String in node:
			var value: Variant = node[key]
			if (key == "audio" or key == "image") and value is String:
				_asset_exists(value)
			elif key == "images" and value is Array:
				for path: Variant in value:
					_asset_exists(str(path))
			else:
				_collect_missing_assets(value)
	elif node is Array:
		for item: Variant in node:
			_collect_missing_assets(item)


## Development shortcuts after "--", e.g. godot --path . -- --debug --fx=co2
func _apply_command_line() -> void:
	var cabin := get_tree().get_first_node_in_group("cabin")
	var effects := get_tree().get_first_node_in_group("effects")
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--debug":
			set_debug_visible(true)
		elif arg == "--no-hud":
			hud_visible = false
			hud_visibility_changed.emit(hud_visible)
		elif arg.begins_with("--camera=") and cabin != null:
			cabin.camera_go_to(arg.trim_prefix("--camera="), true)
		elif arg.begins_with("--outside=") and cabin != null:
			cabin.set_outside_view(arg.trim_prefix("--outside="))
		elif arg.begins_with("--fx-strength=") and effects != null:
			effects.set_strength(arg.trim_prefix("--fx-strength=").to_float())
		elif arg.begins_with("--fx=") and effects != null:
			effects.set_mode(arg.trim_prefix("--fx="))

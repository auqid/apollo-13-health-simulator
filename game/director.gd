extends Node
## Session flow (SPEC.md section 1) and presenter keys (section 7). Keys are handled here so
## they work in every state. Cutscenes play photos, mission audio and captions.

const Timeline := preload("res://sim/timeline.gd")
const History := preload("res://sim/history.gd")
const SimModel := preload("res://sim/sim_model.gd")
const SimState := preload("res://sim/sim_state.gd")
const Tuning := preload("res://sim/tuning.gd")
const UiStyle := preload("res://scenes/ui/ui_style.gd")
const StageCard := preload("res://scenes/ui/stage_card.gd")
const CutsceneView := preload("res://scenes/ui/cutscene_view.gd")
const BioAudio := preload("res://audio/bio_audio.gd")
const Effects := preload("res://fx/effects.gd")
const Hud := preload("res://scenes/ui/hud.gd")
const Exterior := preload("res://scenes/space/exterior.gd")
const Cabin := preload("res://scenes/cabin/cabin.gd")

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
const PAUSED_NOTICE := "Paused. Press P or Space to continue"
const RESTART_NOTICE := "Press R again to restart"
const DECISION_KICKER := "Decision %d of %d"
const SAME_AS_1970 := "Same call as 1970."
const CALL_IN_1970 := "In 1970, the call was: %s."
const SCORE_MATCHES := "You made the same call as 1970 on %d of %d decisions."

var hud_visible: bool = true
var debug_visible: bool = false
## intro, cutscene, poll, hold, timeskip, reentry or scorecard.
var phase: String = PHASE_INTRO
var event_index: int = 0
var _card_left_s: float = 0.0
## Seconds until the intro's cold open plays ("Houston, we've had a problem."), or below 0 once done.
var _intro_audio_s: float = -1.0
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
## How long the current shot runs, after stretching it to fit its audio.
var _shot_span_s: float = 1.0
## >= 0 while the picture dips to black before the next shot.
var _cut_left_s: float = -1.0
var _caption_index: int = 0
## A timeskip stops its clock for a silence, a caption being read or a clip: seconds left, and
## whether to run on after.
var _clock_hold_s: float = 0.0
var _resume_after_hold: bool = false
## A caption with "read_s" and a clip shows on its own first; its clip waits here until then.
var _held_clip: Dictionary = {}
## The caption the current beat wants, and the subtitles of the mission audio playing over it,
## timed in seconds since that clip started. A subtitle shows while it is spoken; the beat's
## caption shows between lines.
var _caption_base: String = ""
var _cues: Array = []
var _cue_s: float = 0.0
## A new photo or the splash keeps its own caption up this long before the subtitles carry on,
## and only lines that start after it can show.
var _base_hold_s: float = 0.0
var _cue_floor_s: float = -INF
## Asset paths a cutscene asked for and did not find.
var missing_assets: PackedStringArray = []
var _reentry_fired: Dictionary = {}
var _reentry_hold_s: float = 0.0
var _reentry_holding: bool = false
var _reentry_beat: String = ""
var _reentry_beat_span: float = 1.0
var _parachute_playing: bool = false
## Reentry photos still to show, and what comes after them.
var _photo_queue: Array = []
var _after_photos: String = ""
var _radio_blackout: bool = false
var _map_left_s: float = 0.0
## "", "exterior" or "map". Debug preview, cleared when a real shot takes the camera.
var _space_preview: String = ""
var _preview_t: float = 0.0
## Votes for --autoplay, one letter per event ("aaaaa" is the 1970 path), or "" when off.
var _autoplay: String = ""
var _autoplay_wait_s: float = 0.0


func _ready() -> void:
	# Keeps reading the presenter keys while the game is paused; _process stops itself instead.
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.target_reached.connect(_on_target_reached)
	Game.caption_requested.connect(_on_caption_requested)
	_boot.call_deferred()


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if _space_preview != "" and _space_preview != "map" and phase != PHASE_CUTSCENE:
		_preview_t = fposmod(_preview_t + delta / _preview_span(), 1.0)
		var space := _exterior()
		if space != null:
			space.set_progress(_preview_t)
	if phase == PHASE_INTRO and _space_preview == "":
		_card_left_s -= delta
		if _intro_audio_s >= 0.0:
			_intro_audio_s -= delta
			if _intro_audio_s < 0.0:
				_play_clip(str(Game.events["intro"].get("audio", "")))
		if _card_left_s <= 0.0:
			skip()
	elif phase == PHASE_CUTSCENE:
		_run_cutscene(delta)
	elif phase == PHASE_POLL or phase == PHASE_SCORECARD:
		_run_autoplay(delta)
	elif phase == PHASE_HOLD:
		_hold_left_s -= delta
		if _hold_left_s <= 0.0:
			finish_choice_hold()
	elif phase == PHASE_TIMESKIP or phase == PHASE_REENTRY:
		if phase == PHASE_REENTRY:
			_run_reentry(delta)
		else:
			_run_timeskip_captions(delta)
		var rate: float = _clock_rate()
		if Game.running and not is_equal_approx(rate, Game.rate_h_per_s):
			Game.set_rate(rate)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	var handled: bool = true
	var paused: bool = get_tree().paused
	var enter: bool = event is InputEventKey and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)
	if event.is_action_pressed("pause_game"):
		toggle_pause()
	elif event.is_action_pressed("advance"):
		if paused:
			set_paused(false)
		else:
			skip()
	elif paused and (enter or event.is_action_pressed("choose_a") or event.is_action_pressed("choose_b")):
		pass
	elif enter:
		if phase == PHASE_SCORECARD:
			_reveal_scorecard(true)
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
	set_paused(false)
	notice_requested.emit("", 0.0)
	start_session()


## P: stops everything where it is (cutscene, mission audio, clock, cards) so the presenter can
## talk, and starts it again. Space also carries on.
func toggle_pause() -> void:
	set_paused(not get_tree().paused)


func set_paused(on: bool) -> void:
	if on == get_tree().paused:
		return
	if on:
		var effects := _effects()
		if effects != null:
			effects.clear_blink()
	get_tree().paused = on
	notice_requested.emit(PAUSED_NOTICE if on else "", 0.0)


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
	_clear_reentry_presentation()
	Game.clear_plan()
	Game.pause()
	Game.begin_at(float(Game.events["intro"]["start_get"]))
	event_index = 0
	phase = PHASE_INTRO
	_card_left_s = float(Game.events["intro"]["duration_s"])
	_intro_audio_s = float(Game.events["intro"].get("audio_at_s", -1.0))
	_apply_view("front_windows", "earth")
	notice_requested.emit("", 0.0)
	_show_intro_card()


func _show_intro_card() -> void:
	var card := _stage()
	if card == null:
		return
	var intro: Dictionary = Game.events["intro"]
	var photo: Texture2D = _load_texture(str(intro.get("photo", "")))
	card.show_intro(str(intro.get("text", "")), str(intro.get("how_to", "")), photo, str(intro.get("photo_caption", "")),
		str(intro.get("quote", "")), str(intro.get("quote_by", "")))


## Space. Skips a card, finishes the choice highlight, pauses the game during a timeskip, or
## skips the reentry. While paused, Space carries on instead (see _unhandled_input).
func skip() -> void:
	match phase:
		PHASE_INTRO:
			_begin_cutscene()
		PHASE_CUTSCENE:
			_end_cutscene()
		PHASE_HOLD:
			finish_choice_hold()
		PHASE_TIMESKIP:
			if _map_left_s > 0.0:
				_finish_opening_map()
				return
			if _clock_hold_s > 0.0:
				return
			toggle_pause()
		PHASE_REENTRY:
			complete_clock()
		PHASE_SCORECARD:
			_reveal_scorecard(false)
		PHASE_POLL:
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
		var reveal: Dictionary = _reveal_lines(event, option_key)
		card.show_reveal(reveal["line"], reveal["note"], reveal["watch"], reveal["historical"])
	var bio := _bio()
	if bio != null:
		bio.play_quindar(false)


## What the card says after a vote: whether it matches 1970, the option's note if it has one, and
## what to watch in the timeskip.
func _reveal_lines(event: Dictionary, picked: String) -> Dictionary:
	var chosen: Dictionary = Timeline.find_option(event, picked)
	var historical_key: String = ""
	for option: Dictionary in event.get("poll", {}).get("options", []):
		if option.get("historical", false):
			historical_key = str(option.get("key", ""))
	var historical: Dictionary = Timeline.find_option(event, historical_key)
	var line: String = SAME_AS_1970
	if not chosen.get("historical", false):
		line = CALL_IN_1970 % str(historical.get("label", ""))
	return {
		"line": line,
		"note": str(chosen.get("note", "")),
		"watch": UiStyle.watch_line(str(event.get("watch", ""))),
		"historical": historical_key,
	}


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
	if phase == PHASE_REENTRY:
		_clear_reentry_presentation()
		Game.pause()
		if Game.state.time.current_get < Game.state.time.splashdown_get - Timeline.EPSILON_H:
			Game.seek(Game.state.time.splashdown_get)
		_begin_scorecard()
		return
	var dest: float = _clock_target
	Game.pause()
	if Game.state.time.current_get < dest - Timeline.EPSILON_H:
		Game.seek(dest)
	_arrive()


func jump_to_state(state_id: String) -> void:
	set_paused(false)
	_clear_reentry_presentation()
	Game.pause()
	_hold_left_s = 0.0
	_card_left_s = 0.0
	if state_id == PHASE_INTRO:
		start_session()
		return
	var events: Array = Timeline.event_list(Game.events)
	if state_id == PHASE_SCORECARD:
		_fill_unset_choices()
		Game.replay_to(INF)
		event_index = events.size() - 1
		_begin_scorecard()
		return
	if state_id == PHASE_REENTRY:
		_fill_unset_choices()
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
	_use_historical_plan(index + 1 if parts[1] == PHASE_TIMESKIP else index)
	event_index = index
	Game.replay_to(_event_get(events[index]))
	_apply_event_view()
	if parts[1] == PHASE_CUTSCENE:
		_start_event_cutscene()
	elif parts[1] == PHASE_POLL:
		_show_poll()
	else:
		_begin_timeskip()


func _begin_cutscene() -> void:
	var events: Array = Timeline.event_list(Game.events)
	var event: Dictionary = events[event_index]
	var at_get: float = _event_get(event)
	if Game.state.time.current_get < at_get - Timeline.EPSILON_H:
		Game.seek(at_get)
	_apply_event_view()
	_start_event_cutscene()


## An event whose cutscene is a reveal (E5 lets the Service Module go) shows it, unless an earlier
## vote already played that reveal (the fast return drops it at E2).
func _start_event_cutscene() -> void:
	_cutscene_next = PHASE_POLL
	var event: Dictionary = _current_event()
	var reveal_id: String = str(event.get("cutscene", {}).get("reveal", ""))
	if reveal_id.is_empty():
		_start_shots(event.get("cutscene", {}).get("shots", []))
	elif _reveal_already_played(reveal_id):
		_start_shots([{"kind": "cabin", "duration_s": 5.0,
			"caption": "The Service Module is already gone. Odyssey is waiting."}])
	else:
		_start_shots(_reveal_shots(reveal_id))


## Whether a vote before the current event already played this reveal. Reading the flags instead
## would be wrong: reaching E5 applies its own reveal before its cutscene starts.
func _reveal_already_played(reveal_id: String) -> bool:
	for event: Dictionary in Timeline.event_list(Game.events):
		if event["id"] == _current_event()["id"]:
			return false
		var option: Dictionary = Timeline.find_option(event, str(Game.state.decisions.get(event["id"], "")))
		if str(option.get("reveal", "")) == reveal_id:
			return true
	return false


func _begin_poll() -> void:
	_hide_cutscene()
	_set_cinematic(false)
	_show_poll()


func _show_poll() -> void:
	phase = PHASE_POLL
	var event: Dictionary = _current_event()
	var card := _stage()
	if card != null:
		var kicker: String = DECISION_KICKER % [event_index + 1, Timeline.event_list(Game.events).size()]
		card.show_poll(event["poll"]["question"], event["poll"]["options"], kicker, Tuning.POLL_COUNTDOWN_S)
	_set_spotlight("")
	_autoplay_wait_s = Tuning.AUTOPLAY_VOTE_S
	var bio := _bio()
	if bio != null:
		bio.play_quindar(true)


## --autoplay: votes a while after each poll opens, and reveals the scorecard a row at a time.
func _run_autoplay(delta: float) -> void:
	if _autoplay.is_empty():
		return
	_autoplay_wait_s -= delta
	if _autoplay_wait_s > 0.0:
		return
	if phase == PHASE_POLL:
		choose(_autoplay[mini(event_index, _autoplay.length() - 1)])
	else:
		_autoplay_wait_s = Tuning.AUTOPLAY_ROW_S
		_reveal_scorecard(false)


## Lights up the value a decision changes while its timeskip runs. Empty clears it.
func _set_spotlight(key: String) -> void:
	var hud := _hud()
	if hud != null:
		hud.set_spotlight(key)


func _begin_timeskip() -> void:
	var events: Array = Timeline.event_list(Game.events)
	_clock_target = _event_get(events[event_index + 1])
	phase = PHASE_TIMESKIP
	_caption_index = 0
	_clock_hold_s = 0.0
	_resume_after_hold = false
	_held_clip = {}
	_hide_cutscene()
	var card := _stage()
	if card != null:
		card.hide_card()
	notice_requested.emit("", 0.0)
	_map_left_s = Tuning.MAP_HOLD_S
	var next_title: String = str(events[event_index + 1].get("title", ""))
	_set_cinematic(true, "Next: %s" % next_title)
	_present_map(Game.state.time.current_get, Game.state.time.splashdown_get, _clock_target, next_title)


func _begin_reentry() -> void:
	_hide_cutscene()
	_clear_reentry_presentation()
	_reentry_fired.clear()
	_clock_target = Game.state.time.splashdown_get
	phase = PHASE_REENTRY
	var card := _stage()
	if card != null:
		card.hide_card()
	notice_requested.emit("", 0.0)
	_set_cinematic(true, "Reentry")
	var view := _cutscene()
	if view != null:
		view.show_heart_rate(true)
	Game.set_rate(_clock_rate())
	Game.play(_clock_target)


func _begin_scorecard() -> void:
	_clear_reentry_presentation()
	_hide_cutscene()
	phase = PHASE_SCORECARD
	Game.pause()
	var card: Dictionary = Game.events["scorecard"]
	var stage := _stage()
	if stage != null:
		var choices: Array = _scorecard_choices()
		var same: int = 0
		for choice: Dictionary in choices:
			if choice.get("historical", false):
				same += 1
		var summary: String = SCORE_MATCHES % [same, choices.size()]
		stage.show_scorecard(card["title"], choices, _scorecard_rows(), card["closing"], summary)


func _reveal_scorecard(everything: bool) -> void:
	var stage := _stage()
	if stage == null:
		return
	if everything:
		stage.reveal_all()
	else:
		stage.reveal_next()


func _scorecard_choices() -> Array:
	var choices: Array = []
	for event: Dictionary in Timeline.event_list(Game.events):
		var picked: String = str(Game.state.decisions.get(event["id"], ""))
		var option: Dictionary = Timeline.find_option(event, picked)
		choices.append({
			"poll": event["title"],
			"choice": option.get("label", picked),
			"historical": option.get("historical", false),
		})
	return choices


func _scorecard_rows() -> Array:
	var you: Dictionary = Game.metrics.scorecard(Game.state)
	var rows: Array = []
	for row: Dictionary in Game.events["scorecard"]["rows"]:
		var key: String = row["key"]
		rows.append({
			"label": row["label"],
			"you": History.format_you(key, you[key]),
			"history": row["history"],
			"verdict": History.verdict(you[key], key),
		})
	return rows


func _arrive() -> void:
	if phase == PHASE_TIMESKIP:
		event_index += 1
		_begin_cutscene()
	elif phase == PHASE_REENTRY:
		_begin_recovery()


func _run_reentry(delta: float) -> void:
	_advance_cues(delta)
	if _reentry_holding:
		_reentry_hold_s -= delta
		_tick_reentry_beat()
		if _reentry_hold_s <= 0.0:
			_end_reentry_beat()
		return
	if _parachute_playing:
		_tick_parachute()
	_fire_reentry_steps()


func _fire_reentry_steps() -> void:
	var now: float = Game.state.time.current_get
	for step: Dictionary in Game.events.get("reentry", {}).get("steps", []):
		var id: String = str(step.get("id", ""))
		if _reentry_fired.has(id):
			continue
		var at_get: float = Game.state.time.splashdown_get + float(step.get("get_from_splashdown", 0.0))
		if now + Timeline.EPSILON_H < at_get:
			return
		if id == "splashdown":
			return
		_reentry_fired[id] = true
		_present_reentry_step(step)
		if _reentry_holding or id == "blackout":
			return


func _present_reentry_step(step: Dictionary) -> void:
	var id: String = str(step.get("id", ""))
	if id == "lm_jettison":
		_hide_reentry_photo()
		_caption_base = _step_caption(step)
		var clip_s: float = _play_clip(str(step.get("audio", "")))
		_start_cues(step.get("subtitles", []) if clip_s > 0.0 else [])
		_reentry_beat = "farewell"
		_reentry_holding = true
		_reentry_hold_s = maxf(clip_s + Tuning.CLIP_TAIL_S, Tuning.REENTRY_FAREWELL_HOLD_S)
		_reentry_beat_span = _reentry_hold_s
		_fade_in_beat()
		_present_exterior("pan", "earth", "lm_jettison")
		Game.pause()
	elif id == "blackout":
		_start_radio_blackout(step)
	elif id == "contact":
		_end_radio_blackout()
		# The radio from contact to splashdown runs on under the photo, the descent and the splash.
		var clip_s: float = _play_clip(str(step.get("audio", "")))
		_start_cues(step.get("subtitles", []) if clip_s > 0.0 else [])
		_start_photos(step.get("photos", []), "descent")


## The capsule under its parachutes, following the clock from contact to splashdown.
func _start_descent() -> void:
	_hide_reentry_photo()
	_set_caption_base(_step_caption(_reentry_step("contact")))
	_parachute_playing = true
	_fade_in_beat()
	_present_exterior("pan", "earth", "parachute")
	Game.set_rate(_clock_rate())
	Game.play(_clock_target)


## Shows reentry photos one after another with the clock stopped, then carries on with next:
## "plasma", "descent" or "scorecard". Photos whose file is missing are skipped.
func _start_photos(photos: Array, next: String) -> void:
	_photo_queue = []
	for photo: Variant in photos:
		if photo is Dictionary and _asset_exists(str(photo.get("image", ""))):
			_photo_queue.append(photo)
	_after_photos = next
	_next_photo()


func _next_photo() -> void:
	if _photo_queue.is_empty():
		_reentry_beat = ""
		_reentry_holding = false
		match _after_photos:
			"plasma":
				_start_plasma()
			"descent":
				_start_descent()
			_:
				_begin_scorecard()
		return
	var photo: Dictionary = _photo_queue.pop_front()
	_reentry_beat = "photo"
	_reentry_holding = true
	_reentry_hold_s = float(photo.get("hold_s", Tuning.REENTRY_PHOTO_HOLD_S))
	_hide_space()
	_fade_in_beat()
	_show_photo_entry(photo, false)
	_set_caption_base(str(photo.get("caption", "")), Tuning.CAPTION_BEAT_S)
	Game.pause()


func _begin_recovery() -> void:
	if _reentry_beat == "splash" or _reentry_beat == "photo" or phase != PHASE_REENTRY:
		return
	_end_radio_blackout()
	_parachute_playing = false
	_reentry_holding = false
	_start_splash()


func _start_plasma() -> void:
	var bio := _bio()
	if bio != null:
		bio.stop_voice()
	_reentry_beat = "plasma"
	_reentry_holding = true
	_reentry_hold_s = Tuning.REENTRY_PLASMA_S
	_hide_reentry_photo()
	_cues = []
	_set_caption_base(_step_caption(_reentry_step("entry")))
	_fade_in_beat()
	_present_exterior("bay", "earth", "plasma")
	Game.pause()


func _finish_plasma() -> void:
	var blackout_get: float = _reentry_get("blackout")
	if Game.state.time.current_get < blackout_get - Timeline.EPSILON_H:
		Game.seek(blackout_get)
	_reentry_fired["blackout"] = true
	_hide_space()
	_start_radio_blackout(_reentry_step("blackout"))
	Game.set_rate(_clock_rate())
	Game.play(_clock_target)


func _start_splash() -> void:
	_reentry_beat = "splash"
	_reentry_holding = true
	_reentry_hold_s = Tuning.REENTRY_SPLASH_S
	var step: Dictionary = _reentry_step("splashdown")
	_set_caption_base(_step_caption(step), Tuning.CAPTION_BEAT_S)
	_present_exterior("pan", "earth", "splash")
	Game.pause()


func _tick_reentry_beat() -> void:
	if _reentry_beat == "farewell":
		var farewell_t: float = clampf(1.0 - _reentry_hold_s / maxf(_reentry_beat_span, 0.5), 0.0, 1.0)
		var separating := _exterior()
		if separating != null:
			separating.set_progress(farewell_t)
		return
	if _reentry_beat != "plasma" and _reentry_beat != "splash":
		return
	var span: float = Tuning.REENTRY_PLASMA_S if _reentry_beat == "plasma" else Tuning.REENTRY_SPLASH_S
	var t: float = clampf(1.0 - _reentry_hold_s / span, 0.0, 1.0)
	var space := _exterior()
	if space != null:
		space.set_progress(t)
	if _reentry_beat != "plasma":
		return
	var cover: float = smoothstep(0.72, 1.0, t) * Tuning.FX_RADIO_BLACKOUT
	var effects := _effects()
	if effects != null:
		effects.set_radio_blackout(cover)


func _tick_parachute() -> void:
	var start: float = _reentry_get("contact")
	var end: float = Game.state.time.splashdown_get
	var span: float = maxf(end - start, 0.001)
	var t: float = clampf((Game.state.time.current_get - start) / span, 0.0, 1.0)
	var space := _exterior()
	if space != null:
		space.set_progress(t)


func _end_reentry_beat() -> void:
	var beat: String = _reentry_beat
	_reentry_holding = false
	_reentry_beat = ""
	if beat == "farewell":
		_start_photos(_reentry_step("lm_jettison").get("photos", []), "plasma")
	elif beat == "plasma":
		_finish_plasma()
	elif beat == "splash":
		_start_photos(_reentry_step("splashdown").get("photos", []), "scorecard")
	elif beat == "photo":
		_next_photo()
	else:
		Game.set_rate(_clock_rate())
		Game.play(_clock_target)


func _start_radio_blackout(step: Dictionary) -> void:
	_radio_blackout = true
	_hide_reentry_photo()
	var line: String = _step_caption(step)
	if Game.state.flags.heat_shield_risk:
		var extra: String = str(step.get("heat_shield_text", ""))
		if not extra.is_empty():
			line = extra if line.is_empty() else "%s\n%s" % [line, extra]
	_cues = []
	_set_caption_base(line)
	var bio := _bio()
	if bio != null:
		bio.stop_voice()
		bio.set_radio_blackout(true)
	var effects := _effects()
	if effects != null:
		effects.set_radio_blackout(Tuning.FX_RADIO_BLACKOUT)
	Game.set_rate(_blackout_rate())


func _end_radio_blackout() -> void:
	if not _radio_blackout:
		return
	_radio_blackout = false
	var bio := _bio()
	if bio != null:
		bio.set_radio_blackout(false)
	var effects := _effects()
	if effects != null:
		effects.set_radio_blackout(0.0)


## A steady rate that fits the whole blackout into screen_s. Working it out from the time left
## each frame would slow the clock forever and never reach contact.
func _blackout_rate() -> float:
	var span_h: float = maxf(_reentry_get("contact") - _reentry_get("blackout"), 0.001)
	var screen_s: float = float(_reentry_step("blackout").get("screen_s", 20.0))
	return span_h / maxf(screen_s, 1.0)


func _clear_reentry_presentation() -> void:
	_radio_blackout = false
	_reentry_holding = false
	_reentry_beat = ""
	_parachute_playing = false
	_photo_queue = []
	_reentry_hold_s = 0.0
	var bio := _bio()
	if bio != null:
		bio.set_radio_blackout(false)
		bio.stop_voice()
	var effects := _effects()
	if effects != null:
		effects.set_radio_blackout(0.0)
	var view := _cutscene()
	if view != null:
		view.show_heart_rate(false)
	_set_cinematic(false)
	_set_spotlight("")
	_hide_cutscene()


func _reentry_step(step_id: String) -> Dictionary:
	for step: Dictionary in Game.events.get("reentry", {}).get("steps", []):
		if step.get("id", "") == step_id:
			return step
	return {}


func _reentry_get(step_id: String) -> float:
	return Game.state.time.splashdown_get + float(_reentry_step(step_id).get("get_from_splashdown", 0.0))


func _step_caption(step: Dictionary) -> String:
	var lines: PackedStringArray = []
	for line: Variant in step.get("captions", []):
		lines.append(str(line))
	return "\n".join(lines)


## The one place story captions go, so two never stack. hold_s > 0 fades it out by itself.
func _show_caption(text: String, hold_s: float = 0.0) -> void:
	var view := _cutscene()
	if view != null:
		view.show_caption(text, hold_s)


func _clear_caption() -> void:
	_caption_base = ""
	_cues = []
	_show_caption("")


## Cinematic bars with a chapter and the clock for story moments. The HUD fades out meanwhile.
func _set_cinematic(on: bool, chapter: String = "") -> void:
	var view := _cutscene()
	if view != null:
		view.set_letterbox(on)
		if on:
			view.set_chapter(chapter)
	var hud := _hud()
	if hud != null:
		hud.set_cinematic(on)


## A reentry beat cuts in from black instead of popping.
func _fade_in_beat() -> void:
	var view := _cutscene()
	if view != null:
		view.set_curtain(1.0)
		view.open_curtain(Tuning.CUTSCENE_DIP_OPEN_S)


## "2 of 5 · The return burn" for the event being played.
func _chapter_text() -> String:
	var events: Array = Timeline.event_list(Game.events)
	return "%d of %d · %s" % [event_index + 1, events.size(), str(_current_event().get("title", ""))]


## A photo from events.json: "image", and optionally "fit": "contain" for a photo shown whole, and
## "focus": [x, y] for the part of a cropped photo to keep in view. A missing file shows the cabin.
func _show_photo_entry(entry: Dictionary, flip: bool) -> void:
	var view := _cutscene()
	if view == null:
		return
	var texture: Texture2D = _load_texture(str(entry.get("image", "")))
	if texture == null:
		view.hide_photo()
		return
	var focus := Vector2(0.5, 0.5)
	var spot: Array = entry.get("focus", [])
	if spot.size() == 2:
		focus = Vector2(float(spot[0]), float(spot[1]))
	view.show_photo(texture, flip, str(entry.get("fit", "")) == "contain", focus)


func _hide_reentry_photo() -> void:
	var view := _cutscene()
	if view != null:
		view.hide_photo()


func _hud() -> Hud:
	var nodes: Array[Node] = get_tree().get_nodes_in_group("hud")
	if nodes.is_empty():
		return null
	return nodes[0] as Hud


func _clock_rate() -> float:
	if _radio_blackout:
		return _blackout_rate()
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


func _fill_unset_choices() -> void:
	var historical: Dictionary = Timeline.historical_plan(Game.events)
	for event_id: String in historical:
		if not Game.plan.has(event_id):
			Game.plan[event_id] = historical[event_id]


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
	_cut_left_s = -1.0
	var card := _stage()
	if card != null:
		card.hide_card()
	_clear_caption()
	_set_spotlight("")
	if shots.is_empty():
		_end_cutscene()
		return
	_set_cinematic(true, _chapter_text())
	var view := _cutscene()
	if view != null:
		view.set_curtain(1.0)
	_advance_shot()


func _run_cutscene(delta: float) -> void:
	if _shot_index < 0 or _shot_index >= _shots.size():
		return
	_shot_elapsed_s += delta
	_advance_cues(delta)
	var shot: Dictionary = _shots[_shot_index]
	_animate_shot(shot)
	if _cut_left_s >= 0.0:
		_cut_left_s -= delta
		if _cut_left_s < 0.0:
			_advance_shot()
		return
	_shot_left_s -= delta
	if _shot_left_s <= 0.0:
		_close_shot()


## Moves the exterior camera or the photo pan along the shot. It keeps moving while the picture dips.
func _animate_shot(shot: Dictionary) -> void:
	var t: float = clampf(_shot_elapsed_s / maxf(_shot_span_s, 0.1), 0.0, 1.0)
	if shot.get("kind", "") == "exterior":
		var space := _exterior()
		if space != null:
			space.set_progress(t)
	elif shot.get("kind", "") == "photo":
		var view := _cutscene()
		if view != null:
			view.set_pan(t)
	else:
		_set_cabin_dolly(smoothstep(0.0, 1.0, t) * Tuning.CUTSCENE_CABIN_DOLLY_M)


## Dips to black before the next shot. After the last shot the cutscene ends without a dip.
func _close_shot() -> void:
	if _shot_index + 1 >= _shots.size():
		_end_cutscene()
		return
	_cut_left_s = Tuning.CUTSCENE_DIP_CLOSE_S
	var view := _cutscene()
	if view != null:
		view.close_curtain(Tuning.CUTSCENE_DIP_CLOSE_S)


func _advance_shot() -> void:
	_cut_left_s = -1.0
	_shot_index += 1
	if _shot_index >= _shots.size():
		_end_cutscene()
		return
	var shot: Dictionary = _shots[_shot_index]
	_shot_elapsed_s = 0.0
	_shot_left_s = maxf(float(shot.get("duration_s", 4.0)), 0.5)
	_shot_span_s = _shot_left_s
	_begin_shot(shot)
	_shot_span_s = _shot_left_s
	var view := _cutscene()
	if view != null:
		view.open_curtain(Tuning.CUTSCENE_DIP_OPEN_S)


func _set_cabin_dolly(metres: float) -> void:
	var cabin := _cabin_node()
	if cabin != null and cabin.camera != null:
		cabin.camera.dolly_m = metres


func _begin_shot(shot: Dictionary) -> void:
	_hide_space()
	_set_cabin_dolly(0.0)
	var view := _cutscene()
	var kind: String = shot.get("kind", "cabin")
	if kind == "exterior":
		if view != null:
			view.hide_photo()
		_present_exterior(str(shot.get("move", "orbit")), str(shot.get("body", "earth")), str(shot.get("action", "")))
		if str(shot.get("audio", "")) != "":
			var clip_s: float = _play_clip(str(shot.get("audio", "")))
			if clip_s > 0.0:
				_shot_left_s = maxf(_shot_left_s, clip_s + Tuning.CLIP_TAIL_S)
	elif kind == "map":
		if view != null:
			view.hide_photo()
		_present_map(Game.state.time.current_get, Game.state.time.splashdown_get)
	elif kind == "bang":
		if view != null:
			view.hide_photo()
		var bio := _bio()
		if bio != null:
			bio.play_bang()
		var effects := _effects()
		if effects != null:
			effects.play_explosion_dim()
		var cabin := _cabin_node()
		if cabin != null and cabin.camera != null:
			cabin.camera.jolt()
	elif kind == "photo":
		var playing := _bio()
		if playing != null:
			playing.stop_voice()
		_show_photo_entry(shot, _shot_index % 2 == 1)
	elif kind == "audio":
		if view != null:
			view.hide_photo()
		var clip_s: float = _play_clip(str(shot.get("audio", "")))
		if clip_s > 0.0:
			_shot_left_s = maxf(_shot_left_s, clip_s + Tuning.CLIP_TAIL_S)
	else:
		if view != null:
			view.hide_photo()
	_caption_base = str(shot.get("caption", ""))
	_start_cues(shot.get("subtitles", []))


## Starts a clip's subtitles from its first moment. Each cue is {at_s, hold_s, text}.
func _start_cues(cues: Array) -> void:
	_cues = cues
	_cue_s = 0.0
	_base_hold_s = 0.0
	_cue_floor_s = -INF
	_refresh_caption()


## The beat's own caption, shown between subtitles. With hold_s it shows first for that long,
## even over a line being spoken.
func _set_caption_base(text: String, hold_s: float = 0.0) -> void:
	_caption_base = text
	if hold_s > 0.0:
		_base_hold_s = hold_s
		_cue_floor_s = _cue_s
	_refresh_caption()


func _advance_cues(delta: float) -> void:
	if _cues.is_empty():
		return
	_cue_s += delta
	_base_hold_s = maxf(_base_hold_s - delta, 0.0)
	_refresh_caption()


func _refresh_caption() -> void:
	if _base_hold_s > 0.0:
		_show_caption(_caption_base)
		return
	_show_caption(active_line(_cues, _cue_s, _caption_base, _cue_floor_s))


## The subtitle being spoken t seconds into a clip, or fallback between lines. A cue stays up a
## little past its hold (CAPTION_BRIDGE_S) unless the next line starts, so short gaps don't flicker.
## Lines that started before earliest_s are skipped.
static func active_line(cues: Array, t: float, fallback: String, earliest_s: float = -INF) -> String:
	for i in cues.size():
		var cue: Variant = cues[i]
		if cue is not Dictionary:
			continue
		var start_s: float = float(cue.get("at_s", 0.0))
		if start_s < earliest_s:
			continue
		var end_s: float = start_s + float(cue.get("hold_s", 3.0))
		var next_s: float = INF
		if i + 1 < cues.size() and cues[i + 1] is Dictionary:
			next_s = float(cues[i + 1].get("at_s", INF))
		end_s = maxf(end_s, minf(next_s, end_s + Tuning.CAPTION_BRIDGE_S))
		if t >= start_s and t < end_s:
			return str(cue.get("text", fallback))
	return fallback


func _end_cutscene() -> void:
	_shots = []
	_shot_index = -1
	_cut_left_s = -1.0
	_hide_cutscene()
	if _cutscene_next == PHASE_TIMESKIP:
		_begin_timeskip()
	else:
		_begin_poll()


## Debug: orbit the intact stack. Click Cabin in the debug panel to come back.
func preview_exterior() -> void:
	_begin_space_preview("exterior", "orbit", "earth", "")


## Debug: the Service Module panel, debris and oxygen cloud, looping.
func preview_explosion() -> void:
	var shot: Dictionary = _shot_with_action("explosion")
	_begin_space_preview("explosion", str(shot.get("move", "bay")), str(shot.get("body", "earth")), "explosion")


## Debug: the push-in on the docking tunnel, with Odyssey going dark and Aquarius lighting up.
func preview_lifeboat() -> void:
	var shot: Dictionary = _shot_with_action("lifeboat")
	_begin_space_preview("lifeboat", str(shot.get("move", "push_in")), str(shot.get("body", "earth")), "lifeboat")


## Debug: the descent engine burning for the trip home.
func preview_burn() -> void:
	var shot: Dictionary = _shot_with_action("burn")
	_begin_space_preview("burn", str(shot.get("move", "orbit")), str(shot.get("body", "moon")), "burn")


## Debug: Odyssey heat-shield first, plasma building, then a fade toward black.
func preview_plasma() -> void:
	_begin_space_preview("plasma", "bay", "earth", "plasma")


## Debug: drogues, then the three main parachutes, descending.
func preview_parachute() -> void:
	_begin_space_preview("parachute", "pan", "earth", "parachute")


## Debug: the splash, then the capsule floating.
func preview_splash() -> void:
	_begin_space_preview("splash", "pan", "earth", "splash")


## Debug: Odyssey and Aquarius leaving the damaged Service Module.
func preview_sm_jettison() -> void:
	var shot: Dictionary = _shot_with_action("sm_jettison")
	_begin_space_preview("sm_jettison", str(shot.get("move", "orbit")), str(shot.get("body", "earth")), "sm_jettison")


## Debug: Aquarius drifting off Odyssey, with the puff from the tunnel.
func preview_lm_jettison() -> void:
	_begin_space_preview("lm_jettison", "pan", "earth", "lm_jettison")


## Debug: the free-return map with the ship at the current GET.
func preview_map() -> void:
	_space_preview = "map"
	var card := _stage()
	if card != null:
		card.hide_card()
	Game.pause()
	_present_map(Game.state.time.current_get, Game.state.time.splashdown_get)


## Debug: back to the cabin, and the card for whatever the session was doing.
func preview_cabin() -> void:
	var shot: Dictionary = {}
	if phase == PHASE_CUTSCENE and _shot_index >= 0 and _shot_index < _shots.size():
		shot = _shots[_shot_index]
	_hide_space()
	var kind: String = str(shot.get("kind", ""))
	if kind == "exterior":
		_present_exterior(str(shot.get("move", "orbit")), str(shot.get("body", "earth")), str(shot.get("action", "")))
		var space := _exterior()
		if space != null:
			space.set_progress(clampf(_shot_elapsed_s / maxf(float(shot.get("duration_s", 1.0)), 0.1), 0.0, 1.0))
		return
	if kind == "map":
		_present_map(Game.state.time.current_get, Game.state.time.splashdown_get)
		return
	_restore_stage()


func _finish_opening_map() -> void:
	_map_left_s = 0.0
	_hide_space()
	if phase != PHASE_TIMESKIP:
		return
	_set_cinematic(false)
	_set_spotlight(str(_current_event().get("watch", "")))
	Game.set_rate(_clock_rate())
	Game.play(_clock_target)


func _begin_space_preview(which: String, move: String, body: String, action: String) -> void:
	_space_preview = which
	_preview_t = 0.0
	var card := _stage()
	if card != null:
		card.hide_card()
	Game.pause()
	_present_exterior(move, body, action)


func _preview_span() -> float:
	if _space_preview in ["explosion", "lifeboat", "sm_jettison", "burn"]:
		var shot: Dictionary = _shot_with_action(_space_preview)
		return maxf(float(shot.get("duration_s", Tuning.EXTERIOR_PREVIEW_S)), 0.5)
	if _space_preview == "lm_jettison":
		return Tuning.REENTRY_FAREWELL_HOLD_S
	if _space_preview == "plasma":
		return Tuning.REENTRY_PLASMA_S
	if _space_preview == "parachute":
		return Tuning.REENTRY_PARACHUTE_S
	if _space_preview == "splash":
		return Tuning.REENTRY_SPLASH_S
	return Tuning.EXTERIOR_PREVIEW_S


func _shot_with_action(action: String) -> Dictionary:
	for event: Dictionary in Timeline.event_list(Game.events):
		var found: Dictionary = _find_action(event.get("cutscene", {}).get("shots", []), action)
		if not found.is_empty():
			return found
	for reveal_id: String in Game.events.get("reveals", {}):
		var reveal: Dictionary = Game.events["reveals"][reveal_id]
		var found: Dictionary = _find_action(reveal.get("shots", []), action)
		if not found.is_empty():
			return found
	return {}


func _find_action(shots: Array, action: String) -> Dictionary:
	for shot: Variant in shots:
		if shot is Dictionary and str(shot.get("action", "")) == action:
			return shot
	return {}


func _present_exterior(move: String, body: String, action: String = "") -> void:
	var cabin := _cabin_node()
	if cabin != null:
		cabin.set_presented(false)
	# Aquarius's legs go down at GET 061:00; a debug preview shows them as its shot would.
	var gear_down: bool = Game.state.time.current_get >= Tuning.LM_GEAR_DOWN_GET
	if _space_preview != "":
		gear_down = action not in ["explosion", "lifeboat"]
	var space := _exterior()
	if space != null:
		space.show_exterior(move, body, action, gear_down)


func _present_map(get_h: float, splashdown_h: float, next_get_h: float = -1.0, next_label: String = "") -> void:
	var cabin := _cabin_node()
	if cabin != null:
		cabin.set_presented(false)
	var space := _exterior()
	if space != null:
		space.show_map(get_h, splashdown_h, next_get_h, next_label)


func _hide_space() -> void:
	_space_preview = ""
	_map_left_s = 0.0
	var space := _exterior()
	if space != null:
		space.hide_view()
	var cabin := _cabin_node()
	if cabin != null:
		cabin.set_presented(true)


func _restore_stage() -> void:
	var card := _stage()
	if card == null:
		return
	match phase:
		PHASE_INTRO:
			_show_intro_card()
		PHASE_POLL:
			_show_poll()
		PHASE_HOLD, PHASE_SCORECARD:
			card.restore()
		_:
			card.hide_card()


func _exterior() -> Exterior:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(Exterior.GROUP)
	if nodes.is_empty():
		return null
	return nodes[0] as Exterior


func _cabin_node() -> Cabin:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(Cabin.GROUP)
	if nodes.is_empty():
		return null
	return nodes[0] as Cabin


func _hide_cutscene() -> void:
	_hide_space()
	_set_cabin_dolly(0.0)
	_caption_base = ""
	_cues = []
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


## Timeskip captions fire as the clock passes their GET. One with "silence_s" or "read_s" stops the
## clock for that long; one with "audio" stops it while the clip plays, with its subtitles. With
## both, the caption is read first, on its own, and then the clip plays, unless the caption is
## just the words the clip speaks (a crew quote): then the clip plays at once.
func _run_timeskip_captions(delta: float) -> void:
	if phase != PHASE_TIMESKIP:
		return
	_advance_cues(delta)
	if _map_left_s > 0.0:
		_map_left_s -= delta
		if _map_left_s <= 0.0:
			_finish_opening_map()
		return
	if _clock_hold_s > 0.0:
		_clock_hold_s -= delta
		if _clock_hold_s <= 0.0 and not _held_clip.is_empty():
			var held: Dictionary = _held_clip
			_held_clip = {}
			_clock_hold_s = _start_timeskip_clip(held)
		if _clock_hold_s <= 0.0 and _resume_after_hold:
			_resume_after_hold = false
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
	_caption_base = str(caption.get("text", ""))
	_start_cues([])
	var hold_s: float = maxf(float(caption.get("silence_s", 0.0)), float(caption.get("read_s", 0.0)))
	if hold_s > 0.0 and not str(caption.get("audio", "")).is_empty() and not is_spoken(caption):
		_held_clip = caption
	else:
		hold_s = maxf(hold_s, _start_timeskip_clip(caption))
	if hold_s > 0.0:
		_resume_after_hold = Game.running
		_clock_hold_s = hold_s
		Game.pause()


## Whether a caption's text is exactly what its clip says, line by line, as a crew quote's is.
static func is_spoken(caption: Dictionary) -> bool:
	var lines: PackedStringArray = []
	for cue: Variant in caption.get("subtitles", []):
		if cue is Dictionary:
			lines.append(str(cue.get("text", "")))
	return not lines.is_empty() and "\n".join(lines) == str(caption.get("text", ""))


## Plays a timeskip caption's clip with its subtitles. Returns how long to stop the clock for it,
## or 0 if it has no clip or the file is missing.
func _start_timeskip_clip(caption: Dictionary) -> float:
	var clip_s: float = _play_clip(str(caption.get("audio", "")))
	if clip_s <= 0.0:
		return 0.0
	_start_cues(caption.get("subtitles", []))
	return clip_s + Tuning.CLIP_TAIL_S


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
	_show_caption(text, Tuning.CAPTION_HOLD_S)


func _boot() -> void:
	_collect_missing_assets(Game.events)
	start_session()
	_apply_command_line()


func _collect_missing_assets(node: Variant) -> void:
	if node is Dictionary:
		for key: String in node:
			var value: Variant = node[key]
			if (key == "audio" or key == "image" or key == "photo") and value is String:
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
		elif arg == "--autoplay" or arg.begins_with("--autoplay="):
			var picks: String = arg.trim_prefix("--autoplay").trim_prefix("=").to_lower()
			_autoplay = picks if picks.length() > 0 and picks.replace("a", "").replace("b", "").is_empty() else "aaaaa"
		elif arg.begins_with("--jump="):
			jump_to_state(arg.trim_prefix("--jump="))
		elif arg.begins_with("--preview="):
			var preview: String = "preview_" + arg.trim_prefix("--preview=")
			if has_method(preview):
				call(preview)

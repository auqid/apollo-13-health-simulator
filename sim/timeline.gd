extends RefCounted
## The mission timeline from data/events.json: when each event starts, applying poll choices when
## their event is reached, and advancing the model up to splashdown. Static and pure, shared by
## the game and the tests.

const SimModel := preload("res://sim/sim_model.gd")
const SimState := preload("res://sim/sim_state.gd")
const Metrics := preload("res://sim/metrics.gd")
const Tuning := preload("res://sim/tuning.gd")

const EVENTS_PATH: String = "res://data/events.json"
## Float tolerance for "the clock has reached this GET", in hours.
const EPSILON_H: float = 1e-9


## Loads events.json, or reports why it can't and returns an empty dictionary.
static func load_events(path: String = EVENTS_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing %s" % path)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("%s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		push_error("%s is not a JSON object" % path)
		return {}
	return json.data


static func event_list(events: Dictionary) -> Array:
	return events.get("events", [])


static func find_event(events: Dictionary, event_id: String) -> Dictionary:
	for event: Dictionary in event_list(events):
		if event.get("id", "") == event_id:
			return event
	return {}


static func find_option(event: Dictionary, option_key: String) -> Dictionary:
	for option: Dictionary in event.get("poll", {}).get("options", []):
		if option.get("key", "") == option_key:
			return option
	return {}


## Start GET of an event or reentry step. Times given relative to splashdown move with E2's choice.
static func event_get(event: Dictionary, state: SimState) -> float:
	if event.has("get"):
		return float(event["get"])
	return state.time.splashdown_get + float(event.get("get_from_splashdown", 0.0))


## A plan (event id -> option key) that picks the historical option for every event.
static func historical_plan(events: Dictionary) -> Dictionary:
	var plan: Dictionary = {}
	for event: Dictionary in event_list(events):
		for option: Dictionary in event.get("poll", {}).get("options", []):
			if option.get("historical", false):
				plan[event["id"]] = option["key"]
	return plan


## Applies a poll choice and records it. Returns the state unchanged if the option doesn't exist.
static func choose(state: SimState, events: Dictionary, event_id: String, option_key: String) -> SimState:
	var option: Dictionary = find_option(find_event(events, event_id), option_key)
	if option.is_empty():
		push_error("No option '%s' for event '%s'" % [option_key, event_id])
		return state
	var next: SimState = SimModel.apply_effects(state, option.get("effects", {}))
	next = _apply_reveal(next, events, option.get("reveal", ""))
	next.decisions[event_id] = option_key
	return next


static func at_splashdown(state: SimState) -> bool:
	return state.time.current_get >= state.time.splashdown_get - EPSILON_H


## Advances by up to dt_hours, stopping at splashdown. Reaching an event applies its cutscene reveal
## and, if the plan has a choice for it, that choice. Always takes at least one model step.
static func advance(state: SimState, dt_hours: float, events: Dictionary, plan: Dictionary,
		metrics: Metrics = null) -> SimState:
	var s: SimState = _apply_due(state, events, plan)
	var target_get: float = minf(s.time.current_get + maxf(dt_hours, 0.0), s.time.splashdown_get)
	var done: bool = false
	while not done:
		var step_to: float = minf(target_get, _next_event_get(s, events))
		s = SimModel.step(s, maxf(step_to - s.time.current_get, 0.0))
		s = _apply_due(s, events, plan)
		if metrics != null:
			metrics.observe(s)
		target_get = minf(target_get, s.time.splashdown_get)
		done = s.time.current_get >= target_get - EPSILON_H
	return s


## Advances in steps of at most max_step_h until target_get or splashdown, whichever comes first.
static func run_to(state: SimState, target_get: float, events: Dictionary, plan: Dictionary,
		metrics: Metrics = null, max_step_h: float = Tuning.SEEK_STEP_H) -> SimState:
	var s: SimState = state
	while s.time.current_get < minf(target_get, s.time.splashdown_get) - EPSILON_H:
		var remaining_h: float = minf(target_get, s.time.splashdown_get) - s.time.current_get
		s = advance(s, minf(max_step_h, remaining_h), events, plan, metrics)
	return s


## Like run_to, but the target is an event, re-checked as choices move it (E5 moves with E2).
static func run_to_event(state: SimState, event_id: String, events: Dictionary, plan: Dictionary,
		metrics: Metrics = null, max_step_h: float = Tuning.SEEK_STEP_H) -> SimState:
	var event: Dictionary = find_event(events, event_id)
	if event.is_empty():
		push_error("No event '%s'" % event_id)
		return state
	return run_to_mark(state, event, events, plan, metrics, max_step_h)


## Like run_to, but the target is anything with "get" or "get_from_splashdown" (an event or a
## reentry step), re-checked every step because choices can move splashdown.
static func run_to_mark(state: SimState, mark: Dictionary, events: Dictionary, plan: Dictionary,
		metrics: Metrics = null, max_step_h: float = Tuning.SEEK_STEP_H) -> SimState:
	var s: SimState = state
	while s.time.current_get < minf(event_get(mark, s), s.time.splashdown_get) - EPSILON_H:
		var remaining_h: float = minf(event_get(mark, s), s.time.splashdown_get) - s.time.current_get
		s = advance(s, minf(max_step_h, remaining_h), events, plan, metrics)
	return s


static func _apply_due(state: SimState, events: Dictionary, plan: Dictionary) -> SimState:
	var s: SimState = state
	for event: Dictionary in event_list(events):
		if event_get(event, s) > s.time.current_get + EPSILON_H:
			break
		var event_id: String = event["id"]
		if event_id not in s.reached_events:
			s = s.copy()
			s.reached_events.append(event_id)
			s = _apply_reveal(s, events, event.get("cutscene", {}).get("reveal", ""))
		if plan.has(event_id) and not s.decisions.has(event_id):
			s = choose(s, events, event_id, plan[event_id])
	return s


static func _next_event_get(state: SimState, events: Dictionary) -> float:
	for event: Dictionary in event_list(events):
		var start_get: float = event_get(event, state)
		if start_get > state.time.current_get + EPSILON_H:
			return start_get
	return INF


static func _apply_reveal(state: SimState, events: Dictionary, reveal_id: String) -> SimState:
	if reveal_id.is_empty():
		return state
	var reveal: Dictionary = events.get("reveals", {}).get(reveal_id, {})
	if reveal.is_empty():
		push_error("No reveal '%s' in events.json" % reveal_id)
		return state
	return SimModel.apply_effects(state, reveal.get("effects", {}))

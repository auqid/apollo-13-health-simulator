extends Node
## The live simulation: current state, the plan of poll choices, the mission clock, debug holds
## and the focused crew member. Runs one sim tick per physics frame and emits state_changed.

const SimModel := preload("res://sim/sim_model.gd")
const SimState := preload("res://sim/sim_state.gd")
const Metrics := preload("res://sim/metrics.gd")
const Timeline := preload("res://sim/timeline.gd")
const Tuning := preload("res://sim/tuning.gd")

signal state_changed(state: SimState)
signal clock_changed(running: bool, rate_h_per_s: float)
signal focus_changed(crew_id: String)
signal target_reached(at_get: float)
signal caption_requested(text: String)

var events: Dictionary = {}
var state: SimState
var metrics: Metrics
## Poll choices applied when the clock reaches each event: event id -> option key.
var plan: Dictionary = {}
var focused_crew: String = SimState.CREW_IDS[0]
var running: bool = false
var rate_h_per_s: float = Tuning.TIMESKIP_H_PER_S
var target_get: float = INF


func _ready() -> void:
	events = Timeline.load_events()
	plan = Timeline.historical_plan(events)
	reset()


func _physics_process(delta: float) -> void:
	var dt_h: float = 0.0
	if running:
		dt_h = minf(rate_h_per_s * delta, maxf(target_get - state.time.current_get, 0.0))
	var had_fever_caption: bool = metrics.fever_caption_get >= 0.0
	_set_state(Timeline.advance(state, dt_h, events, plan, metrics))
	if not had_fever_caption and metrics.fever_caption_get >= 0.0:
		caption_requested.emit(str(events.get("captions", {}).get("fever", "")))
	if running and (state.time.current_get >= target_get - Timeline.EPSILON_H or Timeline.at_splashdown(state)):
		running = false
		clock_changed.emit(running, rate_h_per_s)
		target_reached.emit(state.time.current_get)


## Back to the explosion with the clock stopped and no holds. The plan is kept.
func reset() -> void:
	running = false
	target_get = INF
	metrics = Metrics.new()
	var fresh: SimState = SimModel.initial_state()
	metrics.observe(fresh)
	_set_state(fresh)
	clock_changed.emit(running, rate_h_per_s)


## Runs the clock until to_get or splashdown, then emits target_reached.
func play(to_get: float = INF) -> void:
	if Timeline.at_splashdown(state):
		return
	target_get = to_get
	running = true
	clock_changed.emit(running, rate_h_per_s)


func pause() -> void:
	running = false
	clock_changed.emit(running, rate_h_per_s)


func toggle_play() -> void:
	if running:
		pause()
	else:
		play(target_get if target_get > state.time.current_get + Timeline.EPSILON_H else INF)


func set_rate(h_per_s: float) -> void:
	rate_h_per_s = h_per_s
	clock_changed.emit(running, rate_h_per_s)


## Moves the clock to to_get. Going back replays the mission from the explosion.
func seek(to_get: float) -> void:
	if to_get >= state.time.current_get:
		_set_state(Timeline.run_to(state, to_get, events, plan, metrics))
		return
	var runner := func(fresh: SimState) -> SimState:
		return Timeline.run_to(fresh, to_get, events, plan, metrics)
	_rebuild(runner, state.overrides)


## Replays from the explosion to an event or reentry step from events.json.
func jump_to(mark: Dictionary) -> void:
	var runner := func(fresh: SimState) -> SimState:
		return Timeline.run_to_mark(fresh, mark, events, plan, metrics)
	_rebuild(runner, state.overrides)


## Sets the option the plan picks for an event. Changing a choice already made replays to now.
func set_choice(event_id: String, option_key: String) -> void:
	plan[event_id] = option_key
	if state.decisions.has(event_id) and state.decisions[event_id] != option_key:
		_replay_to_now(state.overrides)


## Holds a value (an override path from SimState) until it's released.
func hold(path: String, value: float) -> void:
	var next: SimState = state.copy()
	next.overrides[path] = value
	_set_state(SimModel.step(next, 0.0))


## Releases a hold and replays to now, so the value goes back to what the model says.
func release(path: String) -> void:
	if not state.overrides.has(path):
		return
	var remaining: Dictionary[String, float] = state.overrides.duplicate()
	remaining.erase(path)
	_replay_to_now(remaining)


func release_all() -> void:
	if not state.overrides.is_empty():
		var no_holds: Dictionary[String, float] = {}
		_replay_to_now(no_holds)


func set_focus(crew_id: String) -> void:
	if crew_id == focused_crew or not state.crew.has(crew_id):
		return
	focused_crew = crew_id
	focus_changed.emit(crew_id)


func _replay_to_now(holds: Dictionary[String, float]) -> void:
	var now_get: float = state.time.current_get
	var runner := func(fresh: SimState) -> SimState:
		return Timeline.run_to(fresh, now_get, events, plan, metrics)
	_rebuild(runner, holds)


## Replays the mission from the explosion without holds, then puts the holds back.
func _rebuild(run: Callable, holds: Dictionary[String, float]) -> void:
	var kept_holds: Dictionary[String, float] = holds.duplicate()
	metrics = Metrics.new()
	var fresh: SimState = SimModel.initial_state()
	metrics.observe(fresh)
	var rebuilt: SimState = run.call(fresh)
	if kept_holds.is_empty():
		_set_state(rebuilt)
		return
	var held: SimState = rebuilt.copy()
	held.overrides = kept_holds
	_set_state(SimModel.step(held, 0.0))


func _set_state(next: SimState) -> void:
	state = next
	state_changed.emit(state)

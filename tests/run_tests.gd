extends SceneTree
## Simulation and data tests, no addons.
## Run: godot --headless --path . --script res://tests/run_tests.gd (exit code 0 means pass)

const Tuning := preload("res://sim/tuning.gd")
const History := preload("res://sim/history.gd")
const SimState := preload("res://sim/sim_state.gd")
const SimModel := preload("res://sim/sim_model.gd")
const Metrics := preload("res://sim/metrics.gd")
const Timeline := preload("res://sim/timeline.gd")
const GameScript := preload("res://game/game.gd")
const FxMapping := preload("res://fx/fx_mapping.gd")
const Effects := preload("res://fx/effects.gd")
const CabinScene := preload("res://scenes/cabin/cabin.tscn")
const Cabin := preload("res://scenes/cabin/cabin.gd")
const AudioMix := preload("res://audio/audio_mix.gd")
const MapPath := preload("res://scenes/space/map_path.gd")
const Exterior := preload("res://scenes/space/exterior.gd")
const Spacecraft := preload("res://scenes/space/spacecraft.gd")
const UiStyle := preload("res://scenes/ui/ui_style.gd")
const CrewLook := preload("res://scenes/ui/crew_look.gd")
const CutsceneView := preload("res://scenes/ui/cutscene_view.gd")

const EFFECT_KEYS: Array[String] = ["flags", "power_margin", "fatigue"]
const TEXT_KEYS: Array[String] = ["text", "question", "label", "hint", "note", "title", "closing", "history", "caption",
	"heat_shield_text", "how_to", "photo_caption", "quote", "quote_by"]
const EVENT_IDS: Array[String] = ["e1", "e2", "e3", "e4", "e5"]
## Voices with no photo beside their lines.
const NO_PHOTO_SPEAKERS: Array[String] = ["Photographic helicopter"]
## These drive the autoloads, which are not in the tree yet during _init.
const SESSION_TESTS: Array[String] = [
	"test_every_option_combination_reaches_the_scorecard",
	"test_reentry_plays_through_in_about_a_minute",
	"test_a_vote_reveals_the_1970_call",
	"test_subtitles_follow_the_mission_audio",
	"test_pause_holds_everything_until_resumed",
	"test_subtitles_show_the_speakers_photos",
	"test_timeskip_captions_stay_up_long_enough_to_read",
]
## Frame step for tests that play the session in real time.
const FRAME_S: float = 1.0 / 60.0
## Step size for the 32 full runs; every event and CO2 peak lands on a step.
const COMBO_STEP_H: float = 0.1


class Run extends RefCounted:
	var state: SimState
	var metrics: Metrics


var _checks: int = 0
var _failures: int = 0
var _test_failures: int = 0
var _events: Dictionary = {}
## Plan label (like "abaab") -> Run to splashdown, so tests share full runs.
var _full_runs: Dictionary = {}


func _init() -> void:
	var test_names: Array[String] = []
	for method: Dictionary in get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and method_name not in SESSION_TESTS:
			test_names.append(method_name)
	for test_name in test_names:
		_run_one(test_name)
	_run_session_tests.call_deferred(test_names.size())


func _run_session_tests(already: int) -> void:
	for test_name in SESSION_TESTS:
		_run_one(test_name)
	print("%d tests, %d checks, %d failures" % [already + SESSION_TESTS.size(), _checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run_one(test_name: String) -> void:
	_test_failures = 0
	var checks_before: int = _checks
	call(test_name)
	# A script error stops a test without failing a check, so a test that checked nothing failed.
	_check(_checks > checks_before, "%s made at least one check (a script error stops a test early)" % test_name)
	print("%s  %s" % ["PASS" if _test_failures == 0 else "FAIL", test_name])


# --- Helpers ---

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		_test_failures += 1
		print("    failed: ", message)


func _near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_check(absf(actual - expected) <= tolerance,
		"%s: expected %.4f ± %.4f, got %.4f" % [message, expected, tolerance, actual])


func _load_events() -> Dictionary:
	if _events.is_empty():
		_events = Timeline.load_events()
	return _events


## The historical plan with some choices changed, e.g. _plan({"e2": "b"}).
func _plan(changes: Dictionary = {}) -> Dictionary:
	var plan: Dictionary = Timeline.historical_plan(_load_events())
	plan.merge(changes, true)
	return plan


func _run_plan(plan: Dictionary, until_get: float = INF, step_h: float = Tuning.SEEK_STEP_H) -> Run:
	var run := Run.new()
	run.metrics = Metrics.new()
	run.state = Timeline.run_to(SimModel.initial_state(), until_get, _load_events(), plan, run.metrics, step_h)
	return run


func _plan_label(plan: Dictionary) -> String:
	var label: String = ""
	for event_id in EVENT_IDS:
		label += str(plan.get(event_id, "-"))
	return label


func _full_run(plan: Dictionary) -> Run:
	var label: String = _plan_label(plan)
	if not _full_runs.has(label):
		_full_runs[label] = _run_plan(plan, INF, COMBO_STEP_H)
	return _full_runs[label]


func _scorecard(plan: Dictionary) -> Dictionary:
	var run: Run = _full_run(plan)
	return run.metrics.scorecard(run.state)


func _flags(values: Dictionary = {}) -> SimState.Flags:
	var flags := SimState.Flags.new()
	for flag: String in values:
		flags.set(flag, values[flag])
	return flags


## [peak value, GET of the peak] of the CO2 curve between E3 and GET 100.
func _co2_peak(flags: SimState.Flags) -> Array[float]:
	var best: Array[float] = [-INF, 0.0]
	var scan_get: float = 88.0
	while scan_get <= 100.0:
		var co2: float = SimModel.co2_at(flags, scan_get)
		if co2 > best[0]:
			best = [co2, scan_get]
		scan_get += 0.01
	return best


func _event_get(event: Dictionary, splashdown_get: float) -> float:
	if event.has("get"):
		return float(event["get"])
	return splashdown_get + float(event["get_from_splashdown"])


func _same_keys(a: Dictionary, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for value: Variant in b:
		if not a.has(value):
			return false
	return true


func _collect_text(node: Variant, out: Array[String]) -> void:
	if node is Dictionary:
		for key: String in node:
			var value: Variant = node[key]
			if key in TEXT_KEYS and value is String:
				out.append(value)
			elif key == "captions" and value is Array:
				for caption: Variant in value:
					if caption is String:
						out.append(caption)
			_collect_text(value, out)
	elif node is Array:
		for item: Variant in node:
			_collect_text(item, out)


func _collect_asset_paths(node: Variant, out: Array[String]) -> void:
	if node is Dictionary:
		for key: String in node:
			var value: Variant = node[key]
			if key in ["audio", "image", "photo", "face"] and value is String and not value.is_empty():
				out.append(value)
			elif key == "images" and value is Array:
				for path: Variant in value:
					out.append(str(path))
			_collect_asset_paths(value, out)
	elif node is Array:
		for item: Variant in node:
			_collect_asset_paths(item, out)


# --- Data tests ---

func test_events_json_parses() -> void:
	var data: Dictionary = _load_events()
	for key in ["intro", "events", "reveals", "reentry", "captions", "scorecard"]:
		_check(data.has(key), "events.json has '%s'" % key)


func test_events_are_in_order_at_spec_times() -> void:
	var events: Array = _load_events().get("events", [])
	var ids: PackedStringArray = []
	for event: Dictionary in events:
		ids.append(event["id"])
	_check(",".join(ids) == "e1,e2,e3,e4,e5", "events are e1 to e5 in order, got %s" % [ids])
	if events.size() != 5:
		return
	_near(_event_get(events[0], Tuning.STANDARD_SPLASHDOWN_GET), Tuning.EXPLOSION_GET, 1e-9, "e1 at the explosion")
	_near(_event_get(events[2], Tuning.STANDARD_SPLASHDOWN_GET), Tuning.CO2_FAST_RISE_END_GET, 1e-9,
		"e3 where the fast CO2 rise ends")
	_near(float(events[4]["get_from_splashdown"]), -Tuning.POWER_UP_WINDOW_H, 1e-9,
		"e5 starts the power-up window")
	for splashdown: float in Tuning.SPLASHDOWN_GET_BY_RETURN.values():
		var previous: float = -INF
		for event: Dictionary in events:
			var event_get: float = _event_get(event, splashdown)
			_check(event_get > previous, "%s comes after the previous event (splashdown %.1f)" % [event["id"], splashdown])
			previous = event_get


func test_every_poll_has_two_valid_options() -> void:
	for event: Dictionary in _load_events().get("events", []):
		var poll: Dictionary = event.get("poll", {})
		var options: Array = poll.get("options", [])
		_check(not str(poll.get("question", "")).is_empty(), "%s has a question" % event["id"])
		_check(options.size() == 2, "%s has two options" % event["id"])
		var historical_count: int = 0
		for option: Dictionary in options:
			var where: String = "%s option %s" % [event["id"], option.get("key", "?")]
			_check(not str(option.get("label", "")).is_empty(), where + " has a label")
			_check(not str(option.get("good", "")).is_empty(), where + " has a good line")
			_check(not str(option.get("cost", "")).is_empty(), where + " has a cost line")
			_check(not str(option.get("label", "")).contains("historical"), where + " does not say it is historical")
			if option.get("historical", false):
				historical_count += 1
				_check(option["key"] == "a", where + " is historical, so it should be option a")
			var effects: Dictionary = option.get("effects", {})
			for key: String in effects:
				_check(key in EFFECT_KEYS, where + " uses a known effect key, got '%s'" % key)
			var flags: Dictionary = effects.get("flags", {})
			_check(not flags.is_empty(), where + " sets at least one flag")
			for flag: String in flags:
				_check(Tuning.FLAG_VALUES.has(flag), where + " sets a known flag, got '%s'" % flag)
				if Tuning.FLAG_VALUES.has(flag):
					_check(flags[flag] in Tuning.FLAG_VALUES[flag],
						where + " sets %s to an allowed value, got %s" % [flag, flags[flag]])
		_check(historical_count == 1, "%s has exactly one historical option" % event["id"])


func test_historical_options_match_flag_defaults() -> void:
	for event: Dictionary in _load_events().get("events", []):
		for option: Dictionary in event["poll"]["options"]:
			if not option.get("historical", false):
				continue
			var effects: Dictionary = option["effects"]
			for flag: String in effects["flags"]:
				_check(effects["flags"][flag] == Tuning.FLAG_VALUES[flag][0],
					"%s historical option keeps %s at its default" % [event["id"], flag])
			_check(not effects.has("power_margin") and not effects.has("fatigue"),
				"%s historical option has no numeric deltas" % event["id"])


func test_reveal_references_exist() -> void:
	var data: Dictionary = _load_events()
	var reveals: Dictionary = data.get("reveals", {})
	for event: Dictionary in data.get("events", []):
		var cutscene_reveal: String = event.get("cutscene", {}).get("reveal", "")
		_check(cutscene_reveal.is_empty() or reveals.has(cutscene_reveal), "%s cutscene reveal exists" % event["id"])
		for option: Dictionary in event["poll"]["options"]:
			var option_reveal: String = option.get("reveal", "")
			_check(option_reveal.is_empty() or reveals.has(option_reveal), "%s option reveal exists" % event["id"])
	for reveal_id: String in reveals:
		for key: String in reveals[reveal_id].get("effects", {}):
			_check(key in EFFECT_KEYS, "reveal %s uses a known effect key" % reveal_id)


## The fastest way home (E2-B) ends the cold coast early, so a caption after that end never comes
## up on that path. Every caption still falls inside its timeskip on the normal-speed path.
func test_timeskip_captions_fall_inside_their_timeskip() -> void:
	var events: Array = _load_events().get("events", [])
	var longest: float = Tuning.SPLASHDOWN_GET_BY_RETURN.values().max()
	for splashdown: float in Tuning.SPLASHDOWN_GET_BY_RETURN.values():
		for i in range(events.size() - 1):
			var start: float = _event_get(events[i], splashdown)
			var end: float = _event_get(events[i + 1], splashdown)
			var previous: float = start
			for caption: Dictionary in events[i].get("timeskip", {}).get("captions", []):
				var caption_get: float = caption["get"]
				_check(caption_get > start and (caption_get < end or splashdown < longest),
					"%s caption at GET %.1f falls between %.1f and %.1f" % [events[i]["id"], caption_get, start, end])
				_check(caption_get >= previous, "%s captions are in GET order (%.3f)" % [events[i]["id"], caption_get])
				previous = caption_get


func test_cutscenes_have_editable_shots() -> void:
	var data: Dictionary = _load_events()
	for event: Dictionary in data.get("events", []):
		var shots: Array = event.get("cutscene", {}).get("shots", [])
		if event["id"] == "e5":
			shots = data["reveals"]["service_module"]["shots"]
		_check(not shots.is_empty(), "%s has cutscene shots" % event["id"])
		var total_s: float = 0.0
		for shot: Dictionary in shots:
			_check(shot.has("kind") and float(shot.get("duration_s", 0.0)) > 0.0, "%s shot has a kind and a duration" % event["id"])
			total_s += float(shot["duration_s"])
			for cue: Dictionary in shot.get("subtitles", []):
				_check(cue.has("text") and float(cue.get("at_s", -1.0)) >= 0.0 and float(cue.get("hold_s", 0.0)) > 0.0,
					"%s subtitle can be edited" % event["id"])
		_check(total_s >= 20.0 and total_s <= 45.0, "%s cutscene is 20 to 45 seconds (%.0f)" % [event["id"], total_s])
	var e1_shots: Array = data["events"][0]["cutscene"]["shots"]
	_check(e1_shots[0]["kind"] == "bang", "E1 opens with the bang")
	_check(e1_shots[1]["kind"] == "exterior" and e1_shots[1]["action"] == "explosion", "the bang cuts to a silent exterior explosion")
	_check(e1_shots[2]["kind"] == "audio", "the problem audio plays after the explosion shot")
	_check(e1_shots[3]["action"] == "lifeboat", "E1 ends with the move into Aquarius")
	var sm_shot: Dictionary = data["reveals"]["service_module"]["shots"][0]
	var sm_photo: Dictionary = data["reveals"]["service_module"]["shots"][1]
	_check(sm_shot["kind"] == "exterior" and sm_shot["action"] == "sm_jettison", "the Service Module jettison is an exterior shot")
	_check(sm_shot["audio"].ends_with("e5_sm.mp3"), "Lovell and Haise play over the jettison")
	_check(sm_photo["kind"] == "photo" and sm_photo["image"].ends_with("service_module.jpg"), "then the photo of what the crew saw")
	_check(Exterior.sm_separation(0.0) < 0.05 and Exterior.sm_separation(1.0) > 0.9, "Odyssey and Aquarius move off the Service Module")
	_check(Exterior.lm_separation(0.0) < 0.05 and Exterior.lm_separation(1.0) > 0.9, "Aquarius drifts away from Odyssey")
	_check(Exterior.lm_puff(0.1) > Exterior.lm_puff(1.0), "the tunnel puff is at the start of the separation")
	_check(Exterior.panel_travel("explosion", 0.0) < 0.05, "the panel starts seated")
	_check(Exterior.panel_travel("explosion", 1.0) > 0.9, "the panel ends clear of the hull")
	_check(Exterior.cloud_alpha("lifeboat", 1.0) > 0.05 and Exterior.cloud_alpha("lifeboat", 1.0) < Exterior.cloud_alpha("lifeboat", 0.0),
		"the oxygen cloud is still there on the lifeboat shot, and fading")
	var glow_early: Vector2 = Exterior.window_glow("lifeboat", 0.0)
	var glow_late: Vector2 = Exterior.window_glow("lifeboat", 1.0)
	_check(glow_early.x > glow_early.y and glow_late.y > glow_late.x, "Odyssey's windows go dark as Aquarius lights up")
	var e2_open: Dictionary = data["events"][1]["cutscene"]["shots"][0]
	_check(e2_open["kind"] == "exterior" and e2_open["move"] == "orbit", "E2 opens on an exterior orbit")
	var far_side: bool = false
	for caption: Dictionary in data["events"][0]["timeskip"]["captions"]:
		if "Artemis II in 2026" in caption["text"]:
			far_side = true
	_check(far_side, "the far-side caption names the distance record")


## Aquarius flew with its legs folded until Haise reported them "down and locked" at 061:00:10,
## after the explosion and before the far side, so the explosion shots fold them and later shots don't.
func test_aquarius_legs_go_down_at_061() -> void:
	var events: Array = Timeline.event_list(_load_events())
	_check(Tuning.LM_GEAR_DOWN_GET > Tuning.EXPLOSION_GET and Tuning.LM_GEAR_DOWN_GET < float(events[1]["get"]),
		"the gear goes down after the explosion and before the return burn")
	var holder := Node3D.new()
	var craft := Spacecraft.new(holder)
	var legs: Array = craft.get("_legs")
	_check(legs.size() == 4, "Aquarius has four legs")
	craft.set_landing_gear(false)
	var stowed_foot: Vector3 = legs[0].transform * Vector3(Spacecraft.LEG_FOOT.x, Spacecraft.LEG_FOOT.y, 0.0)
	craft.set_landing_gear(true)
	var deployed_foot: Vector3 = legs[0].transform * Vector3(Spacecraft.LEG_FOOT.x, Spacecraft.LEG_FOOT.y, 0.0)
	_check(stowed_foot.x < deployed_foot.x - 1.0, "folded, the footpad hangs in close to the descent stage")
	_check(stowed_foot.y < deployed_foot.y, "folded, the leg hangs straight down")
	holder.free()


func test_map_and_exterior_camera_follow_the_mission() -> void:
	var outbound: Vector2 = MapPath.position(60.0, 142.9)
	var far: Vector2 = MapPath.position(MapPath.FAR_SIDE_GET, 142.9)
	var home: Vector2 = MapPath.position(142.9, 142.9)
	var early: Vector2 = MapPath.position(60.0, 119.0)
	_check(outbound.distance_to(MapPath.MOON) < outbound.distance_to(MapPath.EARTH),
		"by GET 60 the ship is closer to the Moon than to Earth")
	_check(is_equal_approx(outbound.x, early.x) and is_equal_approx(outbound.y, early.y),
		"the outbound leg does not depend on the return speed")
	_check(far.x > MapPath.MOON.x, "the far-side pass is beyond the Moon")
	_check(home.distance_to(MapPath.EARTH) < 0.5, "splashdown is back at Earth")
	var fast_return: Vector2 = MapPath.position(100.0, 119.0)
	var slow_return: Vector2 = MapPath.position(100.0, 142.9)
	_check(fast_return.distance_to(MapPath.EARTH) < slow_return.distance_to(MapPath.EARTH),
		"the fast return is farther along the trip home at the same GET")
	var wide: Transform3D = Exterior.camera_transform("orbit", 0.0)
	var close: Transform3D = Exterior.camera_transform("push_in", 1.0)
	_check(wide.origin.distance_to(close.origin) > 1.0, "push-in ends closer than the orbit starts")
	_check(Exterior.camera_transform("pan", 0.0).origin.distance_to(Exterior.camera_transform("pan", 1.0).origin) > 1.0,
		"the pan travels")
	var exterior := Exterior.new()
	exterior.build()
	_check(exterior.get_child_count() > 3, "the exterior scene builds the stack, planets and map")
	exterior.free()


func test_reentry_sequence_is_timed_from_splashdown() -> void:
	var steps: Dictionary = {}
	for step: Dictionary in _load_events().get("reentry", {}).get("steps", []):
		steps[step["id"]] = step
	_check(is_equal_approx(steps["lm_jettison"]["get_from_splashdown"], -1.41), "farewell is 1.41 h before splashdown on every path")
	_check("Farewell, Aquarius" in steps["lm_jettison"]["captions"][0], "Kerwin's farewell line")
	_check(steps["lm_jettison"]["audio"].ends_with("e5_farewell.mp3"), "farewell audio")
	_near(float(steps["blackout"]["screen_s"]), 20.0, 0.1, "blackout compresses to about 20 s")
	_check("about six minutes" in steps["blackout"]["captions"][0], "blackout caption")
	_check("heat shield" in steps["blackout"]["heat_shield_text"], "heat-shield line for the fast return")
	_check(not steps["contact"].has("images"), "the parachute still is replaced by the descent")
	_check(steps["contact"]["action"] == "parachute", "contact plays the parachute shot")
	_check(steps["contact"]["audio"].ends_with("e5_splash.mp3"), "splashdown audio")
	_check(Exterior.plasma_strength(0.0) < Exterior.plasma_strength(1.0), "the plasma glow builds")
	var early_chutes: Vector2 = Exterior.parachute_open(0.2)
	var late_chutes: Vector2 = Exterior.parachute_open(0.9)
	_check(early_chutes.x > early_chutes.y, "drogues open before the mains")
	_check(late_chutes.y > 0.8 and late_chutes.y > late_chutes.x, "three mains are open at the end of the descent")
	_check(Exterior.splash_float(0.0) < 0.2 and Exterior.splash_float(1.0) > 0.9, "splashdown ends with the capsule floating")
	var endings: PackedStringArray = []
	for photo: Dictionary in steps["splashdown"].get("photos", []):
		endings.append(str(photo["image"]).get_file())
	_check("recovery.jpg" in endings, "recovery photo after splashdown, got %s" % [endings])
	for splashdown: float in Tuning.SPLASHDOWN_GET_BY_RETURN.values():
		var jettison: float = splashdown + float(steps["lm_jettison"]["get_from_splashdown"])
		var blackout: float = splashdown + float(steps["blackout"]["get_from_splashdown"])
		var contact: float = splashdown + float(steps["contact"]["get_from_splashdown"])
		_check(jettison < blackout and blackout < contact and contact < splashdown, "reentry order before splashdown %.1f" % splashdown)


func test_each_timeskip_spotlights_what_its_decision_changes() -> void:
	var events: Array = _load_events()["events"]
	for i in events.size():
		var event: Dictionary = events[i]
		var watch: String = str(event.get("watch", ""))
		if i == events.size() - 1:
			_check(watch.is_empty(), "%s goes straight to the reentry, so it has nothing to watch" % event["id"])
			continue
		_check(UiStyle.SPOTLIGHTS.has(watch), "%s watches something the HUD can show, got '%s'" % [event["id"], watch])
		_check(not UiStyle.watch_line(watch).is_empty(), "%s has a watch line for the reveal" % event["id"])


func test_reentry_steps_are_in_order_before_splashdown() -> void:
	var previous: float = -INF
	for step: Dictionary in _load_events().get("reentry", {}).get("steps", []):
		var offset: float = step["get_from_splashdown"]
		_check(offset > previous and offset <= 0.0, "reentry step %s is in order" % step["id"])
		previous = offset
	_check(is_equal_approx(previous, 0.0), "reentry ends at splashdown")


func test_scorecard_rows_match_history() -> void:
	var rows: Array = _load_events().get("scorecard", {}).get("rows", [])
	var keys: Array[String] = []
	for row: Dictionary in rows:
		keys.append(row["key"])
		_check(not str(row.get("label", "")).is_empty() and not str(row.get("history", "")).is_empty(),
			"scorecard row %s has a label and a history value" % row["key"])
	_check(_same_keys(History.BENCHMARKS, keys), "scorecard rows match history.gd benchmarks, got %s" % [keys])
	for key: String in History.BENCHMARKS:
		_check(History.BENCHMARKS[key]["better"] in ["lower", "higher"], "benchmark %s says which way is better" % key)


func test_on_screen_text_is_clean() -> void:
	var texts: Array[String] = []
	_collect_text(_load_events(), texts)
	_check(texts.size() > 40, "found the on-screen text (%d strings)" % texts.size())
	for text in texts:
		_check(not text.contains("TODO"), "no TODO in on-screen text: '%s'" % text)
		_check(text == text.strip_edges() and not text.contains("  "), "no stray spaces: '%s'" % text)
		var first: String = text.left(1)
		_check(first == first.to_upper() or first == "“", "starts like a sentence: '%s'" % text)


func test_asset_paths_point_into_assets() -> void:
	var paths: Array[String] = []
	_collect_asset_paths(_load_events(), paths)
	_check(paths.size() >= 10, "found the asset paths (%d)" % paths.size())
	for path in paths:
		_check(path.begins_with("res://assets/audio/") or path.begins_with("res://assets/images/"),
			"asset path is under assets/: %s" % path)
		_check(ResourceLoader.exists(path), "asset is in the project: %s" % path)


func test_everyone_on_screen_has_a_photo() -> void:
	var people: Dictionary = _load_events().get("people", {})
	for crew_id in SimState.CREW_IDS:
		_check(people.has(SimState.CREW_NAMES[crew_id]), "%s is in people" % SimState.CREW_NAMES[crew_id])
	for person: String in people:
		var path: String = str(people[person].get("face", ""))
		_check(ResourceLoader.exists(path), "%s's photo is in the project: %s" % [person, path])
		_check(not str(people[person].get("role", "")).is_empty(), "%s has a role" % person)
	# Speakers are found at the start of each subtitle line, each once, in order.
	_check(CutsceneView.speakers("Lovell: “One hundred per cent.”\nBrand: “Roger.”") == PackedStringArray(["Lovell", "Brand"]),
		"both speakers of an exchange, in order")
	_check(CutsceneView.speakers("Lovell: “One.”\nLovell: “Two.”") == PackedStringArray(["Lovell"]), "a speaker shows once")
	_check(CutsceneView.speakers("Haise is running a fever.").is_empty(), "a story caption has no speaker")
	# Everyone who speaks, in a subtitle or a timeskip quote, has a photo to show beside the line.
	var lines: Array[String] = []
	var clips: Dictionary = {}
	_collect_subtitled(_load_events(), clips)
	for path: String in clips:
		for cue: Dictionary in clips[path]:
			lines.append(str(cue["text"]))
	for event: Dictionary in Timeline.event_list(_load_events()):
		for caption: Dictionary in event.get("timeskip", {}).get("captions", []):
			lines.append(str(caption["text"]))
	var speakers: Dictionary = {}
	for line in lines:
		for person: String in CutsceneView.speakers(line):
			speakers[person] = true
	_check(speakers.size() >= 6, "found the speakers (%s)" % ", ".join(speakers.keys()))
	for person: String in speakers:
		_check(people.has(person) or person in NO_PHOTO_SPEAKERS, "%s has a photo to show when speaking" % person)


# --- Crew look tests ---

func test_crew_status_reads_plainly() -> void:
	var env := SimState.Env.new()
	var member := SimState.CrewMember.new()
	member.hr = Tuning.CREW_HEART_RACING_BPM - 10.0
	_check(CrewLook.status(member, env) == "Steady", "a calm crew member is steady")
	_check(not CrewLook.is_warning(member, env), "steady is not a warning")
	member.hr = Tuning.CREW_HEART_RACING_BPM
	_check(CrewLook.status(member, env) == "Heart racing", "a fast heart shows when nothing else does")
	env.cabin_temp_c = Tuning.CREW_COLD_BELOW_C - 0.5
	_check(CrewLook.status(member, env) == "Cold", "a cool cabin makes them cold")
	env.cabin_temp_c = Tuning.FX_SHAKE_BELOW_C - 0.5
	_check(CrewLook.status(member, env) == "Shivering", "below the shivering line they shiver")
	member.fatigue = Tuning.CREW_TIRED_FATIGUE
	_check(CrewLook.status(member, env) == "Shivering, tired", "two words, most serious first")
	member.fatigue = Tuning.CREW_EXHAUSTED_FATIGUE
	_check(CrewLook.status(member, env) == "Shivering, exhausted", "worn out further is exhausted")
	_check(not CrewLook.is_warning(member, env), "cold and tired are shown, but not as warnings")
	member.body_temp_c = Tuning.FEVER_CAPTION_C
	_check(CrewLook.status(member, env) == "Fever, shivering", "a fever comes first")
	_check(CrewLook.is_warning(member, env), "a fever is a warning")
	env.co2_mmhg = Tuning.CO2_ALARM_MMHG + 1.0
	_check(CrewLook.status(member, env) == "Fever, breathing hard", "high CO2 comes before the cold")
	member.body_temp_c = Tuning.BODY_TEMP_C
	_check(CrewLook.is_warning(member, env), "high CO2 is a warning")
	member.hydration = Tuning.CREW_THIRSTY_HYDRATION - 0.1
	env.co2_mmhg = Tuning.CO2_START_MMHG
	env.cabin_temp_c = Tuning.CABIN_START_C
	member.fatigue = Tuning.FATIGUE_START
	_check(CrewLook.status(member, env) == "Thirsty", "short of water they are thirsty")
	_check(Tuning.CREW_STATUS_WORDS >= 1, "the status shows at least one word")


func test_crew_photos_show_cold_fever_and_tiredness() -> void:
	var env := SimState.Env.new()
	var member := SimState.CrewMember.new()
	_check(CrewLook.cold(env) == 0.0, "a warm cabin leaves the photo as it is")
	_check(CrewLook.flush(member) == 0.0, "a normal temperature shows no flush")
	_check(CrewLook.tired(member) == 0.0, "a rested crew member does not look worn out")
	var last_cold: float = 0.0
	for cabin_c: float in [15.0, 10.0, 6.0, Tuning.FX_TINT_FULL_C]:
		env.cabin_temp_c = cabin_c
		_check(CrewLook.cold(env) >= last_cold, "colder looks colder (%.1f °C)" % cabin_c)
		last_cold = CrewLook.cold(env)
	_near(CrewLook.cold(env), 1.0, 0.001, "full cold tint at the coldest")
	member.body_temp_c = Tuning.FEVER_PEAK_C
	_near(CrewLook.flush(member), 1.0, 0.001, "full flush at the peak of the fever")
	member.fatigue = 1.0
	_near(CrewLook.tired(member), 1.0, 0.001, "fully worn out at the most fatigue")


# --- Tuning and history tests ---

func test_tuning_tables_cover_every_flag_value() -> void:
	var tables: Dictionary = {
		"heating": Tuning.CABIN_FLOOR_C_BY_HEATING,
		"return_mode": Tuning.SPLASHDOWN_GET_BY_RETURN,
		"adapter": Tuning.CO2_CURVE_BY_ADAPTER,
		"ration": Tuning.WATER_END_PCT_BY_RATION,
	}
	for flag: String in tables:
		_check(_same_keys(tables[flag], Tuning.FLAG_VALUES[flag]), "tuning table for %s covers its values" % flag)
	for ration_table: Dictionary in [Tuning.HYDRATION_END_BY_RATION, Tuning.DRINK_L_PER_DAY_BY_RATION,
			Tuning.WEIGHT_LOSS_KG_PER_H_BY_RATION]:
		_check(_same_keys(ration_table, Tuning.FLAG_VALUES["ration"]), "ration table covers every ration")


func test_tuning_lands_on_the_1970_benchmarks() -> void:
	var bench: Dictionary = History.BENCHMARKS
	_near(Tuning.STANDARD_TRIP_H, bench["duration_h"]["value"], 1e-9, "standard trip length")
	_near(Tuning.CABIN_FLOOR_C_BY_HEATING["off"], bench["coldest_cabin_c"]["value"], 1e-9, "historical cabin floor")
	_near(Tuning.CO2_CURVE_BY_ADAPTER["wait"]["peak_mmhg"], bench["peak_co2_mmhg"]["value"], 1e-9, "historical CO2 peak")
	_near(Tuning.DRINK_L_PER_DAY_BY_RATION["strict"], bench["drink_l_per_day"]["value"], 1e-9, "historical ration")
	_near(Tuning.WATER_END_PCT_BY_RATION["strict"], bench["water_left_pct"]["value"], 1e-9, "historical water left")
	_near(Tuning.WEIGHT_LOSS_KG_PER_H_BY_RATION["strict"] * Tuning.STANDARD_TRIP_H, bench["weight_loss_kg"]["value"],
		0.05, "historical weight loss")
	_near(Tuning.POWER_MARGIN_START, bench["power_margin"]["value"], 1e-9, "historical power margin")
	_near(Tuning.CO2_ALARM_MMHG, History.CO2_SAFE_LIMIT_MMHG, 1e-9, "CO2 alarm at the SP-368 limit")


# --- Model tests ---

func test_initial_state_matches_the_spec() -> void:
	var s: SimState = SimModel.initial_state()
	_near(s.time.current_get, 55.9, 1e-9, "starts at the explosion")
	_near(s.time.splashdown_get, 142.9, 1e-9, "historical splashdown")
	_near(s.env.cabin_temp_c, 21.0, 1e-9, "cabin 21 °C")
	_near(s.env.co2_mmhg, 1.0, 1e-9, "CO2 1.0 mmHg")
	_near(s.env.pressure_psi, 4.8, 0.03 + 1e-9, "pressure 4.8 psi")
	_near(s.env.water_pct, 100.0, 1e-9, "water 100%")
	_near(s.env.power_margin, 100.0, 1e-9, "power margin 100")
	_near(s.stress, 25.0, 1e-9, "explosion stress +25 bpm")
	var base_hr: Dictionary = {"lovell": 68.0, "swigert": 72.0, "haise": 70.0}
	for crew_id in SimState.CREW_IDS:
		var member: SimState.CrewMember = s.crew[crew_id]
		_near(member.hydration, 1.0, 1e-9, crew_id + " hydration 1.0")
		_near(member.fatigue, 0.25, 1e-9, crew_id + " fatigue 0.25")
		_near(member.body_temp_c, 36.8, 1e-9, crew_id + " body temperature 36.8 °C")
		_near(Tuning.BASE_HR_BPM_BY_CREW[crew_id], base_hr[crew_id], 1e-9, crew_id + " base heart rate")
		_near(member.hr, base_hr[crew_id] + 8.0 * 0.25 + 25.0, 2.0 + 1e-9, crew_id + " heart rate includes the stress spike")


func test_step_and_apply_effects_leave_their_input_alone() -> void:
	var s: SimState = SimModel.initial_state()
	var hr_before: float = s.crew["lovell"].hr
	var rng_before: int = s.rng_state
	var noise_before: PackedFloat64Array = s.noise["lovell.hr"].duplicate()
	var next: SimState = SimModel.step(s, 1.0)
	_check(next != s, "step returns a new state")
	_near(s.time.current_get, 55.9, 0.0, "input clock unchanged")
	_near(s.crew["lovell"].hr, hr_before, 0.0, "input heart rate unchanged")
	_check(s.rng_state == rng_before and s.noise["lovell.hr"] == noise_before, "input noise unchanged")
	_near(next.time.current_get, 56.9, 1e-9, "new state is one hour later")
	var chosen: SimState = SimModel.apply_effects(s, {"flags": {"heating": "one"}, "power_margin": -30})
	_check(s.flags.heating == "off" and is_equal_approx(s.env.power_margin, 100.0), "apply_effects leaves its input alone")
	_check(chosen.flags.heating == "one" and is_equal_approx(chosen.env.power_margin, 70.0), "apply_effects applies them")


func test_cabin_cools_toward_the_chosen_floor() -> void:
	var off := _flags()
	var heater := _flags({"heating": "one"})
	var early := _flags({"power_up": "early"})
	_near(SimModel.cabin_temp_at(off, 55.9, 142.9), 21.0, 1e-9, "21 °C until cooling starts at GET 56")
	_near(SimModel.cabin_temp_at(off, 78.0, 142.9), 3.0 + 18.0 * exp(-1.0), 1e-9, "one 22 h time constant in")
	_near(SimModel.cabin_temp_at(off, 142.9, 142.9), 3.35, 0.01, "about 3.3 °C at splashdown with everything off")
	_near(SimModel.cabin_temp_at(heater, 142.9, 142.9), 10.21, 0.01, "about 10 °C at splashdown with one heater")
	_near(SimModel.cabin_temp_at(early, 137.9, 142.9), SimModel.cabin_temp_at(off, 137.9, 142.9), 1e-9,
		"no extra warmth before E5")
	_near(SimModel.cabin_temp_at(early, 140.9, 142.9) - SimModel.cabin_temp_at(off, 140.9, 142.9), 5.0, 1e-9,
		"powering up early adds 5 °C for the final hours")
	_near(_full_run(_plan()).metrics.coldest_cabin_c, 3.35, 0.01, "historical run bottoms out near 3 °C")


func test_co2_climbs_then_peaks_and_settles_per_adapter_choice() -> void:
	var wait := _flags()
	var now := _flags({"adapter": "now"})
	_near(SimModel.co2_at(wait, 55.9), 1.0, 1e-9, "1.0 mmHg at the explosion")
	_near(SimModel.co2_at(wait, 80.0), 2.0, 1e-9, "2.0 mmHg at GET 80")
	_near(SimModel.co2_at(wait, 88.0), 8.0, 1e-9, "8.0 mmHg at E3")
	_check(SimModel.co2_at(wait, 87.4) < 7.6 and SimModel.co2_at(wait, 87.5) > 7.6, "the alarm level is crossed just before E3")
	var wait_peak: Array[float] = _co2_peak(wait)
	_near(wait_peak[0], 15.0, 0.001, "wait: peaks at 15 mmHg")
	_near(wait_peak[1], 91.5, 0.011, "wait: peak around GET 91.5")
	_check(SimModel.co2_at(wait, 93.5) < 2.1, "wait: falls to about 1.5 within 2 hours")
	_near(SimModel.co2_at(wait, 100.0), 1.5, 0.01, "wait: settles at 1.5 mmHg")
	var now_peak: Array[float] = _co2_peak(now)
	_near(now_peak[0], 10.0, 0.001, "now: peaks at 10 mmHg")
	_near(now_peak[1], 89.5, 0.011, "now: peak around GET 89.5")
	_near(SimModel.co2_at(now, 100.0), 2.5, 0.01, "now: settles at 2.5 mmHg because the seal leaks")
	_near(_full_run(_plan()).metrics.peak_co2_mmhg, 15.0, 0.05, "historical run peaks at 15 mmHg")
	_near(_full_run(_plan({"e3": "b"})).metrics.peak_co2_mmhg, 10.0, 0.05, "build-now run peaks at 10 mmHg")


func test_stress_spikes_at_the_explosion_burns_and_reentry() -> void:
	var calm := _flags()
	var exposed := _flags({"heat_shield_risk": true})
	_near(SimModel.stress_at(calm, 55.9, 142.9), 25.0, 1e-9, "explosion +25 bpm")
	_near(SimModel.stress_at(calm, 56.9, 142.9), 12.5, 1e-9, "halfway through the 2 h fade")
	_near(SimModel.stress_at(calm, 58.0, 142.9), 0.0, 1e-9, "explosion stress gone after 2 h")
	_near(SimModel.stress_at(calm, 79.47, 142.9), 10.0, 1e-9, "PC+2 burn +10 bpm")
	_near(SimModel.stress_at(calm, 79.6, 142.9), 0.0, 1e-9, "burn stress ends with the burn")
	_near(SimModel.stress_at(calm, 142.0, 142.9), 0.0, 1e-9, "calm before entry")
	_near(SimModel.stress_at(calm, 142.8, 142.9), 15.0, 1e-9, "reentry +15 bpm")
	_near(SimModel.stress_at(exposed, 142.8, 142.9), 35.0, 1e-9, "reentry +35 bpm with the heat shield exposed")
	_near(SimModel.stress_at(exposed, 118.9, 119.0), 35.0, 1e-9, "the fast return reenters before GET 119")


func test_haise_fever_depends_on_hydration_at_get_115() -> void:
	var strict: Run = _full_run(_plan())
	_check(strict.state.fever, "strict ration: Haise's infection starts at GET 115")
	_near(strict.metrics.fever_caption_get, 115.0 + 10.0 / 1.3, 0.06, "fever caption when he reaches 38 °C")
	_near(strict.metrics.peak_body_temp_c["haise"], 38.3, 1e-6, "fever peaks at 38.3 °C")
	for crew_id: String in ["lovell", "swigert"]:
		_check(strict.metrics.peak_body_temp_c[crew_id] <= 37.0, crew_id + " has no fever")
	var ramp: SimState = Timeline.run_to(SimModel.initial_state(), 120.0, _load_events(), _plan())
	_near(ramp.crew["haise"].body_temp_c, 37.65, 1e-6, "halfway up the fever ramp at GET 120")

	var moderate: Run = _full_run(_plan({"e4": "b"}))
	_check(not moderate.state.fever, "moderate ration: no infection")
	_check(moderate.metrics.fever_caption_get < 0.0, "moderate ration: no fever caption")
	_near(moderate.metrics.peak_body_temp_c["haise"], 36.8, 1e-9, "moderate ration: Haise stays at 36.8 °C or below")

	var fast: Run = _full_run(_plan({"e2": "b"}))
	_check(fast.state.fever, "fast return on the strict ration: the infection still starts at GET 115")
	_check(fast.metrics.fever_caption_get < 0.0, "but splashdown at GET 119 comes before 38 °C")

	var held: SimState = Timeline.run_to(SimModel.initial_state(), 110.0, _load_events(), _plan())
	held.overrides[SimState.crew_path("haise", "hydration")] = 0.9
	held = Timeline.run_to(held, 116.0, _load_events(), _plan())
	_check(not held.fever, "holding Haise's hydration above 0.7 through GET 115 prevents it")


func test_spo2_stays_95_to_99_even_at_high_co2() -> void:
	var s: SimState = Timeline.run_to(SimModel.initial_state(), 91.5, _load_events(), _plan())
	_near(s.env.co2_mmhg, 15.0, 0.01, "at the historical CO2 peak")
	var lowest: float = INF
	var highest: float = -INF
	for _tick in 600:
		s = SimModel.step(s, 0.0)
		for crew_id in SimState.CREW_IDS:
			lowest = minf(lowest, s.crew[crew_id].spo2)
			highest = maxf(highest, s.crew[crew_id].spo2)
	_check(lowest >= 96.0 - 1e-9 and highest <= 98.0 + 1e-9,
		"SpO2 stays 97 ± 1 at 15 mmHg CO2, got %.2f to %.2f" % [lowest, highest])
	s.overrides[SimState.crew_path("haise", "spo2")] = 80.0
	s = SimModel.step(s, 0.0)
	_near(s.crew["haise"].spo2, 95.0, 1e-9, "a debug hold can't push SpO2 below 95")
	s.overrides[SimState.crew_path("haise", "spo2")] = 100.0
	s = SimModel.step(s, 0.0)
	_near(s.crew["haise"].spo2, 99.0, 1e-9, "or above 99")


func test_co2_raises_heart_and_breathing_rate_not_spo2() -> void:
	var base: SimState = Timeline.run_to(SimModel.initial_state(), 70.0, _load_events(), _plan())
	var held: SimState = base.copy()
	held.overrides[SimState.env_path("co2_mmhg")] = 12.0
	var low: SimState = SimModel.step(base, 0.0)
	var high: SimState = SimModel.step(held, 0.0)
	_near(high.env.co2_mmhg, 12.0, 1e-9, "CO2 is held at 12 mmHg")
	for crew_id in SimState.CREW_IDS:
		_near(high.crew[crew_id].hr - low.crew[crew_id].hr, 1.2 * (12.0 - 5.0), 1e-6, crew_id + ": +1.2 bpm per mmHg above 5")
		_near(high.crew[crew_id].rr - low.crew[crew_id].rr, 0.8 * (12.0 - 4.0), 1e-6, crew_id + ": +0.8 breaths per mmHg above 4")
		_near(high.crew[crew_id].spo2, low.crew[crew_id].spo2, 1e-9, crew_id + ": SpO2 unchanged")


func test_holds_stay_until_released() -> void:
	var s: SimState = Timeline.run_to(SimModel.initial_state(), 90.0, _load_events(), _plan())
	s.overrides[SimState.env_path("co2_mmhg")] = 3.0
	s.overrides[SimState.STRESS_PATH] = 30.0
	for _tick in 5:
		s = SimModel.step(s, 0.5)
	_near(s.env.co2_mmhg, 3.0, 1e-9, "held CO2 stays put as time passes")
	_near(s.stress, 30.0, 1e-9, "held stress stays put")
	_near(s.read_path(SimState.env_path("co2_mmhg")), 3.0, 1e-9, "read_path finds held values")
	s.overrides.clear()
	s = SimModel.step(s, 0.5)
	_near(s.env.co2_mmhg, SimModel.co2_at(s.flags, s.time.current_get), 1e-9, "released CO2 returns to its curve")
	_near(s.stress, 0.0, 1e-9, "released stress returns to the model")


func test_water_and_hydration_land_on_each_ration_ending() -> void:
	var strict: SimState = _full_run(_plan()).state
	_near(strict.env.water_pct, 9.0, 0.01, "strict: about 9% water left")
	_near(strict.crew["haise"].hydration, 0.55, 0.001, "strict: hydration 0.55")
	var moderate: SimState = _full_run(_plan({"e4": "b"})).state
	_near(moderate.env.water_pct, 7.0, 0.01, "moderate: about 7% water left")
	_near(moderate.crew["haise"].hydration, 0.80, 0.001, "moderate: hydration 0.80")
	var fast: SimState = _full_run(_plan({"e2": "b"})).state
	_near(fast.env.water_pct, 100.0 - 91.0 * (119.0 - 55.9) / 87.0, 0.01, "fast return: same daily use, so about 34% left")
	_near(fast.crew["haise"].hydration, 1.0 - 0.45 * (119.0 - 55.9) / 87.0, 0.001, "fast return: less dehydration")


func test_power_margin_applies_option_deltas_and_clamps_at_40() -> void:
	_near(_full_run(_plan()).state.env.power_margin, 100.0, 1e-9, "historical: 100")
	_near(_full_run(_plan({"e1": "b"})).state.env.power_margin, 70.0, 1e-9, "one heater: −30")
	_near(_full_run(_plan({"e2": "b"})).state.env.power_margin, 115.0, 1e-9, "fast return: +15")
	_near(_full_run(_plan({"e1": "b", "e5": "b"})).state.env.power_margin, 50.0, 1e-9, "heater and early power-up: −50")
	var drained: SimState = SimModel.apply_effects(SimModel.initial_state(), {"power_margin": -500.0})
	_near(drained.env.power_margin, 40.0, 1e-9, "clamped at 40")
	_near(SimModel.step(drained, 1.0).env.power_margin, 40.0, 1e-9, "and stays clamped while stepping")


func test_fatigue_builds_faster_in_the_cold_and_slower_with_a_heater() -> void:
	_near(SimModel.fatigue_rate_per_h(_flags(), 12.0), 0.008, 1e-12, "0.008 per hour")
	_near(SimModel.fatigue_rate_per_h(_flags(), 6.0), 0.012, 1e-12, "+0.004 per hour below 8 °C")
	_near(SimModel.fatigue_rate_per_h(_flags({"heating": "one"}), 12.0), 0.006, 1e-12, "x0.75 with a heater")
	_near(_full_run(_plan()).state.crew["lovell"].fatigue, 1.0, 1e-9, "historical: exhausted by splashdown")
	_near(_full_run(_plan({"e1": "b"})).state.crew["lovell"].fatigue, 0.25 + 0.006 * 87.0, 0.001, "heater: about 0.77")
	var waited: SimState = Timeline.run_to(SimModel.initial_state(), 95.0, _load_events(), _plan())
	var built: SimState = Timeline.run_to(SimModel.initial_state(), 95.0, _load_events(), _plan({"e3": "b"}))
	_near(built.crew["swigert"].fatigue - waited.crew["swigert"].fatigue, 0.15, 1e-9, "building the adapter now costs +0.15")


func test_crew_weight_loss_per_ration() -> void:
	_near(_scorecard(_plan())["weight_loss_kg"], 14.3, 0.05, "strict: about 14.3 kg combined")
	_near(_scorecard(_plan({"e4": "b"}))["weight_loss_kg"], 0.109 * 87.0, 1e-6, "moderate: 0.109 kg per hour")
	_near(_scorecard(_plan({"e2": "b"}))["weight_loss_kg"], 0.164 * 63.1, 1e-6, "fast return: fewer hours")


func test_vitals_noise_is_seeded_smooth_and_bounded() -> void:
	var a: SimState = Timeline.run_to(SimModel.initial_state(), 100.0, _load_events(), _plan())
	var b: SimState = Timeline.run_to(SimModel.initial_state(), 100.0, _load_events(), _plan())
	var same: bool = a.env.pressure_psi == b.env.pressure_psi
	for crew_id in SimState.CREW_IDS:
		for field: String in ["hr", "rr", "spo2"]:
			same = same and a.crew[crew_id].get(field) == b.crew[crew_id].get(field)
	_check(same, "two runs with the same seed give identical vitals")
	var biggest_jump: float = 0.0
	var biggest_offset: float = 0.0
	var s: SimState = a
	for _tick in 600:
		var next: SimState = SimModel.step(s, 0.0)
		var member: SimState.CrewMember = next.crew["lovell"]
		biggest_jump = maxf(biggest_jump, absf(member.hr - s.crew["lovell"].hr))
		var clean_hr: float = SimModel.heart_rate("lovell", next.env.cabin_temp_c, next.env.co2_mmhg,
			member.body_temp_c, member.fatigue, next.stress, 0.0)
		biggest_offset = maxf(biggest_offset, absf(member.hr - clean_hr))
		s = next
	_check(biggest_jump > 0.0, "vitals keep moving while the clock is stopped")
	_check(biggest_jump < 0.2, "and drift smoothly, at most %.3f bpm per tick" % biggest_jump)
	_check(biggest_offset <= 2.0 + 1e-9, "heart rate noise stays within ±2 bpm, got %.3f" % biggest_offset)


func test_timeline_applies_choices_when_the_clock_reaches_each_event() -> void:
	var events: Dictionary = _load_events()
	var plan: Dictionary = _plan({"e1": "b", "e2": "b"})
	var before_e2: SimState = Timeline.run_to(SimModel.initial_state(), 78.9, events, plan)
	_check(before_e2.flags.heating == "one" and before_e2.decisions.get("e1", "") == "b",
		"E1's choice is applied at the explosion")
	_check(before_e2.flags.return_mode == "standard" and not before_e2.decisions.has("e2"), "E2's choice waits for E2")
	var after_e2: SimState = Timeline.run_to(before_e2, 79.1, events, plan)
	_check(after_e2.flags.return_mode == "fast" and is_equal_approx(after_e2.time.splashdown_get, 119.0),
		"E2-B moves splashdown to GET 119")
	_check(after_e2.flags.sm_jettisoned and after_e2.flags.heat_shield_risk, "E2-B drops the Service Module")
	var no_plan: SimState = Timeline.run_to(SimModel.initial_state(), 90.0, events, {})
	_check(no_plan.decisions.is_empty() and no_plan.reached_events.size() == 3,
		"without a plan, events are reached but nothing is chosen")
	_near(Timeline.advance(no_plan, 0.0, events, {}).time.current_get, 90.0, 1e-9, "advancing by 0 h keeps the clock still")
	var fast_e5: SimState = Timeline.run_to_event(SimModel.initial_state(), "e5", events, _plan({"e2": "b"}))
	_near(fast_e5.time.current_get, 114.0, 1e-6, "on the fast return E5 is at GET 114")
	var standard_e5: SimState = Timeline.run_to_event(SimModel.initial_state(), "e5", events, _plan())
	_near(standard_e5.time.current_get, 137.9, 1e-6, "on the standard return E5 is at GET 137.9")
	_check(standard_e5.flags.sm_jettisoned, "the Service Module is jettisoned at E5")
	_check(not Timeline.run_to(SimModel.initial_state(), 137.8, events, _plan()).flags.sm_jettisoned, "and not before")


func test_historical_plan_matches_the_flag_defaults() -> void:
	var with_plan: SimState = _full_run(_plan()).state
	var without: SimState = _run_plan({}, INF, COMBO_STEP_H).state
	_check(without.decisions.is_empty() and with_plan.decisions.size() == 5, "only the planned run records choices")
	_near(without.env.water_pct, with_plan.env.water_pct, 1e-9, "same water")
	_near(without.env.power_margin, with_plan.env.power_margin, 1e-9, "same power margin")
	_check(without.fever == with_plan.fever, "same fever outcome")
	for crew_id in SimState.CREW_IDS:
		_near(without.crew[crew_id].hr, with_plan.crew[crew_id].hr, 1e-9, crew_id + " same heart rate")
		_near(without.crew[crew_id].fatigue, with_plan.crew[crew_id].fatigue, 1e-9, crew_id + " same fatigue")


func test_historical_run_matches_the_1970_scorecard() -> void:
	var card: Dictionary = _scorecard(_plan())
	var bench: Dictionary = History.BENCHMARKS
	_near(card["duration_h"], bench["duration_h"]["value"], 1e-6, "87 h")
	_near(card["coldest_cabin_c"], bench["coldest_cabin_c"]["value"], 0.5, "about 3 °C")
	_near(card["peak_co2_mmhg"], bench["peak_co2_mmhg"]["value"], 0.1, "about 15 mmHg")
	_near(card["drink_l_per_day"], bench["drink_l_per_day"]["value"], 1e-9, "0.18 L a day")
	_near(card["water_left_pct"], bench["water_left_pct"]["value"], 0.05, "about 9% water left")
	_near(card["weight_loss_kg"], bench["weight_loss_kg"]["value"], 0.05, "14.3 kg")
	_check(card["haise_infection"] == bench["haise_infection"]["value"], "Haise's infection")
	_near(card["power_margin"], bench["power_margin"]["value"], 1e-9, "power margin 100")
	_check(card["heat_shield_exposed"] == bench["heat_shield_exposed"]["value"], "heat shield stays covered")


func test_scorecard_compares_the_historical_path_and_the_all_b_path() -> void:
	var historical: Dictionary = _scorecard(_plan())
	for key: String in History.BENCHMARKS:
		_check(History.verdict(historical[key], key) == "same",
			"historical %s matches 1970 (you %s)" % [key, str(historical[key])])
	var all_b: Dictionary = _scorecard(_plan({"e1": "b", "e2": "b", "e3": "b", "e4": "b", "e5": "b"}))
	var expect: Dictionary = {
		"duration_h": "better",
		"coldest_cabin_c": "better",
		"peak_co2_mmhg": "better",
		"drink_l_per_day": "better",
		"water_left_pct": "better",
		"weight_loss_kg": "better",
		"haise_infection": "better",
		"power_margin": "worse",
		"heat_shield_exposed": "worse",
	}
	for key: String in expect:
		_check(History.verdict(all_b[key], key) == expect[key],
			"all-B %s is %s (you %s)" % [key, expect[key], str(all_b[key])])


func test_every_option_combination_reaches_splashdown_safely() -> void:
	var events: Dictionary = _load_events()
	for combo in 32:
		var plan: Dictionary = {}
		for i in EVENT_IDS.size():
			plan[EVENT_IDS[i]] = "b" if ((combo >> i) & 1) == 1 else "a"
		var label: String = _plan_label(plan)
		var metrics := Metrics.new()
		var s: SimState = SimModel.initial_state()
		var spo2_low: float = INF
		var spo2_high: float = -INF
		var hr_low: float = INF
		var hr_high: float = -INF
		var pressure_low: float = INF
		var pressure_high: float = -INF
		var power_low: float = INF
		var water_low: float = INF
		var finite: bool = true
		var guard: int = 0
		while not Timeline.at_splashdown(s) and guard < 10000:
			s = Timeline.advance(s, COMBO_STEP_H, events, plan, metrics)
			guard += 1
			for crew_id in SimState.CREW_IDS:
				var m: SimState.CrewMember = s.crew[crew_id]
				spo2_low = minf(spo2_low, m.spo2)
				spo2_high = maxf(spo2_high, m.spo2)
				hr_low = minf(hr_low, m.hr)
				hr_high = maxf(hr_high, m.hr)
				finite = finite and is_finite(m.hr) and is_finite(m.rr) and is_finite(m.spo2) \
					and is_finite(m.body_temp_c) and is_finite(m.hydration) and is_finite(m.fatigue)
			pressure_low = minf(pressure_low, s.env.pressure_psi)
			pressure_high = maxf(pressure_high, s.env.pressure_psi)
			power_low = minf(power_low, s.env.power_margin)
			water_low = minf(water_low, s.env.water_pct)
			finite = finite and is_finite(s.env.cabin_temp_c) and is_finite(s.env.co2_mmhg) and is_finite(s.stress)
		var run := Run.new()
		run.state = s
		run.metrics = metrics
		_full_runs[label] = run

		var fast: bool = plan["e2"] == "b"
		var strict: bool = plan["e4"] == "a"
		_near(s.time.current_get, 119.0 if fast else 142.9, 1e-6, label + " reaches splashdown")
		_check(",".join(s.reached_events) == "e1,e2,e3,e4,e5", label + " reaches every event in order")
		_check(s.decisions.size() == 5, label + " applies all five choices")
		_check(spo2_low >= 95.0 and spo2_high <= 99.0, label + " SpO2 stays 95-99, got %.2f-%.2f" % [spo2_low, spo2_high])
		_check(hr_low >= 50.0 and hr_high <= 140.0, label + " heart rate stays 50-140, got %.1f-%.1f" % [hr_low, hr_high])
		_check(pressure_low >= 4.77 - 1e-9 and pressure_high <= 4.83 + 1e-9,
			label + " pressure stays flat, got %.3f-%.3f" % [pressure_low, pressure_high])
		var expected_power: float = 100.0 - 30.0 * int(plan["e1"] == "b") + 15.0 * int(fast) - 20.0 * int(plan["e5"] == "b")
		_near(s.env.power_margin, expected_power, 1e-9, label + " power margin")
		_check(power_low >= 40.0, label + " power margin never drops below 40")
		_check(water_low > 0.0, label + " never runs out of water")
		_check(finite, label + " has no NaN or infinite values")
		_near(metrics.peak_co2_mmhg, 10.0 if plan["e3"] == "b" else 15.0, 0.05, label + " CO2 peak")
		_check(s.fever == strict, label + " Haise's infection follows the ration")
		_check((metrics.fever_caption_get >= 0.0) == (strict and not fast),
			label + " fever caption only on the strict, full-length trip")
		_check(s.flags.heat_shield_risk == fast, label + " heat shield risk only on the fast return")
		_check(s.flags.sm_jettisoned, label + " Service Module gone by splashdown")
		_check(_same_keys(metrics.scorecard(s), History.BENCHMARKS.keys()), label + " scorecard has every row")


# --- Game autoload tests (game.gd depends only on sim/, so it runs headless here) ---

func _new_game() -> GameScript:
	var game: GameScript = GameScript.new()
	game._ready()
	return game


func test_game_clock_runs_the_timeskip_to_splashdown() -> void:
	var game: GameScript = _new_game()
	game.play()
	var ticks: int = 0
	while game.running and ticks < 10000:
		game._physics_process(1.0 / 60.0)
		ticks += 1
	_near(game.state.time.current_get, 142.9, 1e-6, "the timeskip stops at splashdown")
	_check(absi(ticks - 2610) <= 2, "at 2 GET hours per second it takes about 43.5 s (%d ticks)" % ticks)
	_check(game.state.decisions.size() == 5, "the historical plan was applied on the way")
	game.free()


func test_game_seeking_back_replays_the_history() -> void:
	var game: GameScript = _new_game()
	game.seek(100.0)
	_near(game.metrics.peak_co2_mmhg, 15.0, 0.05, "past the CO2 peak")
	game.seek(80.0)
	_near(game.state.time.current_get, 80.0, 1e-6, "clock moved back")
	_near(game.metrics.peak_co2_mmhg, 2.0, 1e-6, "metrics replayed: no CO2 peak yet at GET 80")
	_check(",".join(game.state.reached_events) == "e1,e2", "only E1 and E2 reached")
	game.free()


func test_game_jump_and_choices_follow_the_plan() -> void:
	var game: GameScript = _new_game()
	game.set_choice("e2", "b")
	game.jump_to(Timeline.find_event(game.events, "e5"))
	_near(game.state.time.current_get, 114.0, 1e-6, "with E2-B planned, E5 is at GET 114")
	game.seek(100.0)
	game.set_choice("e1", "b")
	_near(game.state.time.current_get, 100.0, 1e-6, "changing a past choice keeps the clock where it is")
	_check(game.state.flags.heating == "one" and is_equal_approx(game.state.env.power_margin, 85.0),
		"and replays with the new choice (heater -30, fast return +15)")
	game.free()


func test_game_holds_release_back_to_the_model() -> void:
	var game: GameScript = _new_game()
	game.seek(70.0)
	var model_co2: float = game.state.env.co2_mmhg
	game.hold(SimState.env_path("co2_mmhg"), 12.0)
	game.hold(SimState.crew_path("haise", "fatigue"), 0.9)
	_near(game.state.env.co2_mmhg, 12.0, 1e-9, "CO2 held")
	game.seek(75.0)
	_near(game.state.crew["haise"].fatigue, 0.9, 1e-9, "holds stay while the clock moves")
	game.release(SimState.crew_path("haise", "fatigue"))
	_check(game.state.crew["haise"].fatigue < 0.9 and game.state.overrides.size() == 1, "released fatigue goes back to the model")
	_near(game.state.env.co2_mmhg, 12.0, 1e-9, "other holds survive the replay")
	game.release_all()
	_check(game.state.overrides.is_empty(), "release all clears every hold")
	_check(game.state.env.co2_mmhg > model_co2 and game.state.env.co2_mmhg < 2.0, "CO2 back on its curve")
	game.free()


# --- Effects and cabin ---

func test_light_level_follows_the_power_margin() -> void:
	_near(FxMapping.light_level(100.0), 1.0, 1e-9, "historical margin: full light")
	_near(FxMapping.light_level(40.0), 0.35 + 0.65 * 0.4, 1e-9, "the minimum margin still leaves 61% light")
	_near(FxMapping.light_level(50.0), 0.675, 1e-9, "heater and early power-up: 0.675")
	_near(FxMapping.light_level(115.0), 0.35 + 0.65 * 1.15, 1e-9, "fast return: slightly brighter than 1970")


func test_cabin_builds_with_presets_dimming_views_and_lamps() -> void:
	var cabin = CabinScene.instantiate()
	cabin.build()
	_check(",".join(cabin.preset_names()) == "front_windows,co2_panel,overhead", "three camera presets")
	_check(cabin.camera != null and cabin.camera.preset == "front_windows", "starts on the front windows")
	cabin.set_light_level(0.5)
	var dimmed: bool = not cabin._lights.is_empty()
	for light: OmniLight3D in cabin._lights:
		dimmed = dimmed and is_equal_approx(light.light_energy, cabin._base_energy[light] * 0.5)
	_check(dimmed, "set_light_level scales every cabin light")
	cabin.set_outside_view("moon")
	_check(cabin._bodies["moon"].visible and not cabin._bodies["earth"].visible, "Moon outside")
	cabin.set_outside_view("earth")
	_check(cabin._bodies["earth"].visible and not cabin._bodies["moon"].visible, "Earth outside")
	_check(",".join(cabin.lamp_names()) == "master_alarm,co2", "master alarm and CO2 lamps exist")
	cabin.set_lamp("co2", true)
	_check(cabin._lamps["co2"].emission_energy_multiplier > 0.0, "a lit lamp glows")
	cabin.set_lamp("co2", false)
	_check(is_zero_approx(cabin._lamps["co2"].emission_energy_multiplier), "an unlit lamp doesn't")
	cabin.free()


func test_co2_effects_follow_the_spec() -> void:
	_near(FxMapping.vignette(5.0), 0.0, 1e-9, "no vignette at 5 mmHg")
	_near(FxMapping.vignette(10.0), 0.5, 1e-9, "vignette 0.5 at 10 mmHg")
	_near(FxMapping.vignette(15.0), 0.7, 1e-9, "vignette capped at 0.7 at the 15 mmHg peak")
	_near(FxMapping.blur_px(8.0), 0.0, 1e-9, "no blur at 8 mmHg")
	_near(FxMapping.blur_px(15.0), 2.8, 1e-9, "2.8 px blur at the peak")
	_near(FxMapping.blur_px(30.0), 3.0, 1e-9, "blur capped at 3 px")
	_near(FxMapping.wobble_px(10.0), 0.0, 1e-9, "no HUD wobble at 10 mmHg")
	_near(FxMapping.wobble_px(15.0), 2.0, 1e-9, "2 px HUD wobble at the peak")


func test_cold_effects_follow_the_spec() -> void:
	_near(FxMapping.shake_rad(10.0), 0.0, 1e-9, "no shivering at 10 °C")
	_near(FxMapping.shake_rad(6.5), 0.0075, 1e-9, "half shake at 6.5 °C")
	_near(FxMapping.shake_rad(3.0), 0.015, 1e-9, "full 0.015 rad shake at 3 °C")
	_near(FxMapping.fog(12.0), 0.0, 1e-9, "no breath fog at 12 °C")
	_near(FxMapping.fog(7.5), 0.5, 1e-9, "half fog at 7.5 °C")
	_near(FxMapping.fog(3.0), 1.0, 1e-9, "full fog at 3 °C")
	_near(FxMapping.tint(18.0), 0.0, 1e-9, "no tint at 18 °C")
	_near(FxMapping.tint(3.0), Tuning.FX_TINT_MAX, 1e-9, "strongest tint at 3 °C")
	_check(FxMapping.tint(6.0) > FxMapping.tint(9.0), "tint grows as the cabin cools")


func test_condensation_follows_the_spec() -> void:
	_near(FxMapping.condensation(7.0, 119.0, "late", false), 0.0, 1e-9, "not before GET 120")
	_near(FxMapping.condensation(7.0, 121.0, "late", false), 1.0, 1e-9, "on below 8 °C after GET 120")
	_near(FxMapping.condensation(9.0, 121.0, "late", false), 0.0, 1e-9, "off above 8 °C")
	_near(FxMapping.condensation(10.2, 138.0, "late", true), 1.0, 1e-9, "on after E5-A even with the heater")
	_near(FxMapping.condensation(8.4, 139.0, "early", true), Tuning.FX_CONDENSATION_EARLY_POWER_UP, 1e-9,
		"less after E5-B")
	var history: Run = _full_run(_plan())
	_check(history.state.env.cabin_temp_c < 8.0, "the historical path ends cold enough for condensation")


func test_effects_never_flash_faster_than_three_times_a_second() -> void:
	_near(FxMapping.blink_depth(0.6), 0.0, 1e-9, "no blinks at 0.6 fatigue")
	_check(FxMapping.blink_depth(0.8) > 0.0 and FxMapping.blink_depth(1.0) <= 1.0, "blinks above 0.6, never fully black")
	var peaks: int = 0
	var previous: float = 0.0
	var rising: bool = true
	var t_s: float = 0.0
	while t_s <= Tuning.FX_BLINK_S + 0.05:
		var value: float = FxMapping.blink_profile(t_s)
		if rising and value < previous:
			peaks += 1
			rising = false
		previous = value
		t_s += 0.001
	_check(peaks == 1, "a blink is a single fade down and up, got %d peaks" % peaks)
	_near(Tuning.FX_BLINK_S, 0.25, 1e-9, "blinks last 250 ms")
	_check(Tuning.FX_BLINK_INTERVAL_S_MIN >= 8.0, "blinks are at least 8 s apart")
	_check(Tuning.FX_SHAKE_HZ <= 3.0, "the shake wanders at 3 Hz or slower")
	_check(Tuning.FX_WOBBLE_PERIODS_S.x >= 1.0 / 3.0 and Tuning.FX_WOBBLE_PERIODS_S.y >= 1.0 / 3.0, "the HUD wobble is slow")
	var dim_peak: float = FxMapping.explosion_dim(Tuning.FX_EXPLOSION_DIM_DROP_S)
	_near(dim_peak, Tuning.FX_EXPLOSION_DIM_DEPTH, 1e-9, "the explosion dim reaches its depth")
	var recovering: bool = true
	var last: float = dim_peak
	t_s = Tuning.FX_EXPLOSION_DIM_DROP_S
	while t_s < 5.0:
		var dim: float = FxMapping.explosion_dim(t_s)
		recovering = recovering and dim <= last + 1e-9
		last = dim
		t_s += 0.01
	_check(recovering and is_zero_approx(last), "after its one drop the dim only recovers, back to full light")


func test_forced_modes_show_one_driver() -> void:
	var fx: Effects = Effects.new()
	var state: SimState = SimModel.initial_state()
	fx.mode = Effects.MODE_CO2
	fx.strength = 1.0
	var co2: Dictionary = fx._targets(state)
	_near(co2["vignette"], Tuning.FX_VIGNETTE_MAX, 1e-9, "CO2 mode is the 15 mmHg vignette")
	_near(co2["blur_px"], 2.8, 1e-9, "and the peak blur, still under 3 px")
	_near(co2["wobble_px"], Tuning.FX_WOBBLE_MAX_PX, 1e-9, "and a 2 px HUD drift")
	_near(co2["shake"], 0.0, 1e-9, "without shivering")
	_near(co2["fog"], 0.0, 1e-9, "without breath fog")
	_near(co2["light"], 1.0, 1e-9, "with the lights left on")
	_near(co2["co2_lamp"], 1.0, 1e-9, "and the CO2 lamp on")
	fx.mode = Effects.MODE_COLD
	var cold: Dictionary = fx._targets(state)
	_near(cold["shake"], Tuning.FX_SHAKE_MAX_RAD, 1e-9, "cold mode shivers at full strength")
	_near(cold["fog"], 1.0, 1e-9, "full breath fog")
	_near(cold["tint"], Tuning.FX_TINT_MAX, 1e-9, "full cold tint")
	_near(cold["condensation"], 1.0, 1e-9, "condensation on")
	_near(cold["vignette"], 0.0, 1e-9, "no CO2 vignette in cold mode")
	fx.mode = Effects.MODE_FATIGUE
	var tired: Dictionary = fx._targets(state)
	_near(tired["fatigue"], 1.0, 1e-9, "fatigue mode")
	_near(tired["vignette"], 0.0, 1e-9, "fatigue mode leaves the view clear")
	fx.mode = Effects.MODE_POWER
	_near(fx._targets(state)["light"], FxMapping.light_level(Tuning.POWER_MARGIN_MIN), 1e-9, "power mode uses the minimum margin")
	fx.mode = Effects.MODE_EXPLOSION
	fx._dim_t = Tuning.FX_EXPLOSION_DIM_DROP_S
	var boom: Dictionary = fx._targets(state)
	_near(boom["light"], 1.0, 1e-9, "the explosion leaves the power margin alone")
	_near(boom["dim"], Tuning.FX_EXPLOSION_DIM_DEPTH, 1e-9, "and drops that share of the cabin light")
	_near(boom["master_lamp"], 1.0, 1e-9, "and lights the master alarm")
	_near(boom["blur_px"], 0.0, 1e-9, "without blurring the cabin")
	fx.free()


# --- Audio ---

func test_heartbeat_is_quiet_when_calm_and_clear_above_90() -> void:
	var calm: float = AudioMix.heartbeat_gain(70.0)
	var rising: float = AudioMix.heartbeat_gain(81.0)
	var loud: float = AudioMix.heartbeat_gain(90.0)
	var faster: float = AudioMix.heartbeat_gain(120.0)
	_check(calm < 0.08, "a calm heart rate stays quiet, got %.3f" % calm)
	_check(loud > calm * 4.0, "90 bpm is several times louder than calm")
	_check(loud > 0.3, "90 bpm is clearly audible, got %.3f" % loud)
	_near(faster, loud, 1e-9, "above 90 bpm the heartbeat stays at that level")
	_check(rising > calm and rising < loud, "it rises between calm and 90")
	var peak: float = 0.0
	var t_s: float = 0.0
	while t_s < 0.4:
		peak = maxf(peak, absf(AudioMix.heartbeat_wave(t_s)))
		t_s += 0.001
	_check(peak > 0.5 and peak <= 1.0, "a beat has a lub and a dub, peak %.2f" % peak)
	_near(AudioMix.heartbeat_wave(0.3), 0.0, 1e-6, "and then silence until the next beat")


func test_breathing_follows_one_cycle() -> void:
	_near(AudioMix.breath_envelope(0.0), 0.0, 1e-6, "a breath starts quiet")
	_check(AudioMix.breath_envelope(0.2) > 0.9, "the inhale peaks")
	_check(AudioMix.breath_envelope(0.7) > 0.5, "the exhale is there")
	_near(AudioMix.breath_envelope(1.0), 0.0, 0.05, "and the cycle ends quiet")


func test_alarm_can_be_silenced_until_the_cause_clears() -> void:
	var sounding: Dictionary = AudioMix.next_alarm(true, false)
	_check(sounding["playing"] and sounding["silenced"] == false, "an alarm sounds when it's wanted")
	var hushed: Dictionary = AudioMix.next_alarm(true, true)
	_check(not hushed["playing"] and hushed["silenced"], "S keeps this bout silent")
	var cleared: Dictionary = AudioMix.next_alarm(false, true)
	_check(not cleared["playing"] and not cleared["silenced"], "once the cause goes, the next alarm can sound")
	var again: Dictionary = AudioMix.next_alarm(true, cleared["silenced"])
	_check(again["playing"], "and it does")
	var loudest: float = 0.0
	var t_s: float = 0.0
	while t_s < Tuning.AUDIO_ALARM_STEP_S * 2.0:
		loudest = maxf(loudest, absf(AudioMix.alarm_wave(t_s)))
		t_s += 0.001
	_check(loudest < 0.25, "the alarm stays well below full scale, peak %.3f" % loudest)
	_check(loudest > 0.08, "and is still loud enough to notice")


func test_voice_ducks_bio_and_alarm_then_releases() -> void:
	var duck: float = 0.0
	duck = AudioMix.approach_duck(duck, 0.2, 0.2)
	_check(duck > 0.9, "a loud Voice bus ducks within a fraction of a second, got %.2f" % duck)
	duck = AudioMix.approach_duck(duck, 0.0, 0.05)
	_check(duck > 0.7, "it holds the duck briefly after Voice stops")
	duck = AudioMix.approach_duck(duck, 0.0, 2.0)
	_check(duck < 0.05, "then Bio and Alarm come back")
	for bus_name in AudioMix.DUCKED_BUSES:
		_check(bus_name != AudioMix.BUS_VOICE, "Voice itself is not ducked")


func test_each_event_sets_a_camera_and_an_outside_view() -> void:
	for event: Dictionary in _load_events()["events"]:
		_check(Cabin.PRESETS.has(event.get("camera", "")), "%s has a camera preset" % event["id"])
		_check(event.get("outside", "") in Cabin.OUTSIDE_VIEWS, "%s has an outside view" % event["id"])
		var outside: String = "moon" if event["id"] == "e2" else "earth"
		_check(event.get("outside", "") == outside, "%s looks out on %s" % [event["id"], outside])


func test_every_option_combination_reaches_the_scorecard() -> void:
	var session: Node = root.get_node_or_null("Director")
	var played: Node = root.get_node_or_null("Game")
	if session == null or played == null:
		_check(false, "the Game and Director autoloads are loaded")
		return
	for combo in 32:
		var picks: PackedStringArray = []
		for i in EVENT_IDS.size():
			picks.append("b" if ((combo >> i) & 1) == 1 else "a")
		var label: String = "".join(picks)
		session.call("start_session")
		var steps: int = 0
		var phase: String = session.get("phase")
		while phase != "scorecard" and steps < 40:
			steps += 1
			var before: String = phase
			if phase == "cutscene" and int(session.get("event_index")) == EVENT_IDS.size() - 1:
				var shots: Array = session.get("_shots")
				var dropped_early: bool = picks[1] == "b"
				var first: Dictionary = shots[0] if not shots.is_empty() else {}
				_check(dropped_early == (first.get("action", "") != "sm_jettison"),
					"%s E5 plays the Service Module jettison only if it is still attached" % label)
			if phase == "poll":
				session.call("choose", picks[int(session.get("event_index"))])
				session.call("finish_choice_hold")
			elif phase == "timeskip" or phase == "reentry":
				session.call("complete_clock")
			else:
				session.call("skip")
			phase = session.get("phase")
			if phase == before:
				break
		_check(phase == "scorecard", "%s reaches the scorecard (stopped in %s)" % [label, phase])
		var played_state: SimState = played.get("state")
		var splashdown: float = 119.0 if picks[1] == "b" else 142.9
		_near(played_state.time.current_get, splashdown, 1e-3, "%s splashdown" % label)
		for i in EVENT_IDS.size():
			_check(played_state.decisions.get(EVENT_IDS[i], "") == picks[i], "%s records %s" % [label, EVENT_IDS[i]])


func test_a_vote_reveals_the_1970_call() -> void:
	var session: Node = root.get_node_or_null("Director")
	if session == null:
		_check(false, "the Director autoload is loaded")
		return
	var e2: Dictionary = Timeline.find_event(_load_events(), "e2")
	var same: Dictionary = session.call("_reveal_lines", e2, "a")
	_check(same["line"] == "Same call as 1970.", "choosing the 1970 option says so, got '%s'" % same["line"])
	_check(same["historical"] == "a", "the 1970 option gets the badge")
	_check(same["note"].is_empty(), "the 1970 option has no note")
	var other: Dictionary = session.call("_reveal_lines", e2, "b")
	_check("Normal speed" in other["line"], "the other option names the 1970 call, got '%s'" % other["line"])
	_check("rejected" in other["note"], "the fast return explains why it was rejected in 1970")
	_check(other["watch"] == UiStyle.watch_line("splashdown"), "then it says what to watch")


func test_subtitles_follow_the_mission_audio() -> void:
	var session: Node = root.get_node_or_null("Director")
	if session == null:
		_check(false, "the Director autoload is loaded")
		return
	var cues: Array = [
		{"at_s": 1.0, "hold_s": 2.0, "text": "First"},
		{"at_s": 4.0, "hold_s": 2.0, "text": "Second"},
		{"at_s": 20.0, "hold_s": 2.0, "text": "Third"},
	]
	var bridge: float = Tuning.CAPTION_BRIDGE_S
	_check(session.call("active_line", cues, 0.5, "Base") == "Base", "the caption shows before the first line")
	_check(session.call("active_line", cues, 2.0, "Base") == "First", "a line shows while it is spoken")
	_check(session.call("active_line", cues, 3.5, "Base") == "First", "a short pause keeps the line up")
	_check(session.call("active_line", cues, 4.5, "Base") == "Second", "the next line replaces it as soon as it starts")
	_check(session.call("active_line", cues, 6.0 + bridge + 0.5, "Base") == "Base", "a long pause goes back to the caption")
	_check(session.call("active_line", cues, 21.0, "Base") == "Third", "the last line shows")
	# Every clip's lines are in order, inside the clip, and readable for at least 1.8 seconds.
	var clips: Dictionary = {}
	_collect_subtitled(_load_events(), clips)
	_check(clips.size() >= 8, "found the subtitled clips (%d)" % clips.size())
	for path: String in clips:
		var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
		var length_s: float = stream.get_length() if stream != null else INF
		var previous: float = -1.0
		for cue: Dictionary in clips[path]:
			var at_s: float = float(cue["at_s"])
			_check(at_s > previous and at_s + float(cue["hold_s"]) <= length_s + 0.5,
				"%s line at %.2f s is in order and inside the clip" % [path.get_file(), at_s])
			_check(float(cue["hold_s"]) >= 1.8, "%s line at %.2f s stays up long enough to read" % [path.get_file(), at_s])
			previous = at_s


func test_pause_holds_everything_until_resumed() -> void:
	var session: Node = root.get_node_or_null("Director")
	if session == null:
		_check(false, "the Director autoload is loaded")
		return
	_check(InputMap.has_action("pause_game"), "P is an Input Map action")
	_check(Tuning.POLL_COUNTDOWN_S == 0.0, "polls wait for the presenter, with no countdown")
	session.call("jump_to_state", "e1_cutscene")
	session.call("_process", FRAME_S)
	var elapsed: float = session.get("_shot_elapsed_s")
	session.call("toggle_pause")
	_check(paused, "P pauses the game")
	for i in 120:
		session.call("_process", FRAME_S)
	_check(is_equal_approx(session.get("_shot_elapsed_s"), elapsed), "the cutscene stands still while paused")
	_check(session.get("phase") == "cutscene", "pausing does not skip the cutscene")
	session.call("toggle_pause")
	_check(not paused, "P again carries on")
	session.call("_process", FRAME_S)
	_check(session.get("_shot_elapsed_s") > elapsed, "the cutscene moves again after resuming")
	session.call("set_paused", true)
	session.call("restart_now")
	_check(not paused and session.get("phase") == "intro", "restarting while paused starts the intro running")


## The photos beside a subtitle follow its speakers, from people in events.json.
func test_subtitles_show_the_speakers_photos() -> void:
	var played: Node = root.get_node_or_null("Game")
	if played == null:
		_check(false, "the Game autoload is loaded")
		return
	var view: CanvasLayer = CutsceneView.new()
	root.add_child(view)
	var shown: Dictionary = {
		"Lovell: “Houston, we've had a problem.”": 1,
		"Lovell: “Okay.”\nSwigert: “Roger.”": 2,
		"Lovell: “One hundred per cent.”\nBrand: “Roger.”": 2,
		"Kerwin: “Farewell, Aquarius, and we thank you.”": 1,
		"Haise is running a fever.": 0,
		"Photographic helicopter: “Splashdown.”": 0,
	}
	for text: String in shown:
		view.call("show_caption", text)
		var fade: Tween = view.get("_caption_tween")
		fade.custom_step(UiStyle.CAPTION_FADE_S * 4.0)
		_check(view.call("speaker_faces_shown") == shown[text], "%d photos beside '%s'" % [shown[text], text])
	root.remove_child(view)
	view.free()


## Every timeskip caption and crew quote stays on screen long enough to read: on the 1970 path,
## and in the cold coast when the fastest way home (E2-B) ends it at GET 114.
func test_timeskip_captions_stay_up_long_enough_to_read() -> void:
	var session: Node = root.get_node_or_null("Director")
	var played: Node = root.get_node_or_null("Game")
	if session == null or played == null:
		_check(false, "the Game and Director autoloads are loaded")
		return
	var view: CanvasLayer = CutsceneView.new()
	root.add_child(view)
	var quotes: int = 0
	for event: Dictionary in Timeline.event_list(_load_events()):
		var captions: Array = event.get("timeskip", {}).get("captions", [])
		for caption: Dictionary in captions:
			if not CutsceneView.speakers(str(caption["text"])).is_empty():
				quotes += 1
		if captions.is_empty():
			continue
		session.call("jump_to_state", "%s_timeskip" % event["id"])
		_check_reading_time(session, captions, _play_timeskip(session, played, view), "%s on the 1970 path" % event["id"], INF)
		if event["id"] != "e4":
			continue
		session.call("jump_to_state", "e4_timeskip")
		played.get("plan")["e2"] = "b"
		played.call("replay_to", float(event["get"]))
		session.call("_begin_timeskip")
		var ends_get: float = session.get("_clock_target")
		_near(ends_get, 114.0, 0.01, "the fast way home ends the cold coast at GET 114")
		_check_reading_time(session, captions, _play_timeskip(session, played, view), "e4 with the fast way home", ends_get)
	_check(quotes >= 8, "the crew's own words come up in the timeskips (%d quotes)" % quotes)
	root.remove_child(view)
	view.free()
	session.call("jump_to_state", "intro")


## Plays the current timeskip frame by frame. Returns caption text -> the longest it stayed on screen.
func _play_timeskip(session: Node, played: Node, view: Node) -> Dictionary:
	var longest: Dictionary = {}
	var shown: String = view.call("caption_text")
	var since_s: float = 0.0
	var t: float = 0.0
	while session.get("phase") == "timeskip" and t < 600.0:
		played.call("_physics_process", FRAME_S)
		session.call("_process", FRAME_S)
		t += FRAME_S
		var text: String = view.call("caption_text")
		if text != shown:
			shown = text
			since_s = t
		longest[shown] = maxf(float(longest.get(shown, 0.0)), t - since_s)
	return longest


## A caption needs READ_WORDS_PER_S, and at least READ_MIN_S. One with a clip is read on its own
## for read_s before the clip, so that alone must be enough, unless the clip speaks its words.
## (No audio plays in the tests, so a quote's read_s stands in for its clip.)
func _check_reading_time(session: Node, captions: Array, longest: Dictionary, label: String, until_get: float) -> void:
	for caption: Dictionary in captions:
		if float(caption["get"]) >= until_get:
			continue
		var text: String = str(caption["text"])
		var words: int = text.replace("\n", " ").split(" ", false).size()
		var needed: float = maxf(Tuning.READ_MIN_S, words / Tuning.READ_WORDS_PER_S)
		var stood: float = float(longest.get(text, 0.0))
		if caption.has("audio") and not session.call("is_spoken", caption):
			stood = float(caption.get("read_s", 0.0))
		_check(stood >= needed - FRAME_S, "%s: '%s…' stays up %.1f s; reading it takes %.1f s" % [
			label, text.left(40), stood, needed])


## Clip path -> its subtitles, for every shot, timeskip caption or reentry step that has both.
func _collect_subtitled(node: Variant, out: Dictionary) -> void:
	if node is Dictionary:
		if node.has("audio") and node.has("subtitles"):
			out[str(node["audio"])] = node["subtitles"]
		for key: String in node:
			_collect_subtitled(node[key], out)
	elif node is Array:
		for item: Variant in node:
			_collect_subtitled(item, out)


## Plays the reentry frame by frame, as the presenter would see it, with no key presses.
func test_reentry_plays_through_in_about_a_minute() -> void:
	var session: Node = root.get_node_or_null("Director")
	var played: Node = root.get_node_or_null("Game")
	if session == null or played == null:
		_check(false, "the Game and Director autoloads are loaded")
		return
	var blackout_step: Dictionary = {}
	for step: Dictionary in _load_events()["reentry"]["steps"]:
		if step["id"] == "blackout":
			blackout_step = step
	session.call("jump_to_state", "reentry")
	var elapsed_s: float = 0.0
	var blackout_from_s: float = -1.0
	var blackout_s: float = -1.0
	while elapsed_s < 180.0 and session.get("phase") == "reentry":
		played.call("_physics_process", FRAME_S)
		session.call("_process", FRAME_S)
		elapsed_s += FRAME_S
		var dark: bool = session.get("_radio_blackout")
		if dark and blackout_from_s < 0.0:
			blackout_from_s = elapsed_s
		elif not dark and blackout_from_s >= 0.0 and blackout_s < 0.0:
			blackout_s = elapsed_s - blackout_from_s
	_check(session.get("phase") == "scorecard", "the reentry ends on the scorecard (after %.0f s)" % elapsed_s)
	_check(elapsed_s < 90.0, "the reentry takes about a minute, not %.0f s" % elapsed_s)
	_near(blackout_s, float(blackout_step["screen_s"]), 1.0, "the radio blackout lasts its screen time")

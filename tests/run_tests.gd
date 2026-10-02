extends SceneTree
## Simulation and data tests, no addons.
## Run: godot --headless --path . --script res://tests/run_tests.gd (exit code 0 means pass)

const Tuning := preload("res://sim/tuning.gd")
const History := preload("res://sim/history.gd")

const EVENTS_PATH: String = "res://data/events.json"
const EFFECT_KEYS: Array[String] = ["flags", "power_margin", "fatigue"]
const TEXT_KEYS: Array[String] = ["text", "question", "label", "hint", "note", "title", "closing", "history"]

var _checks: int = 0
var _failures: int = 0
var _test_failures: int = 0


func _init() -> void:
	var test_names: Array[String] = []
	for method: Dictionary in get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_"):
			test_names.append(method_name)
	for test_name in test_names:
		_test_failures = 0
		call(test_name)
		print("%s  %s" % ["PASS" if _test_failures == 0 else "FAIL", test_name])
	print("%d tests, %d checks, %d failures" % [test_names.size(), _checks, _failures])
	quit(1 if _failures > 0 else 0)


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
	var json := JSON.new()
	var err: Error = json.parse(FileAccess.get_file_as_string(EVENTS_PATH))
	if err != OK:
		print("    events.json line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return {}
	return json.data


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
			if key == "audio" and value is String:
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
			_check(not str(option.get("hint", "")).is_empty(), where + " has a hint")
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


func test_timeskip_captions_fall_inside_their_timeskip() -> void:
	var events: Array = _load_events().get("events", [])
	for splashdown: float in Tuning.SPLASHDOWN_GET_BY_RETURN.values():
		for i in range(events.size() - 1):
			var start: float = _event_get(events[i], splashdown)
			var end: float = _event_get(events[i + 1], splashdown)
			for caption: Dictionary in events[i].get("timeskip", {}).get("captions", []):
				var caption_get: float = caption["get"]
				_check(caption_get > start and caption_get < end,
					"%s caption at GET %.1f falls between %.1f and %.1f" % [events[i]["id"], caption_get, start, end])


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

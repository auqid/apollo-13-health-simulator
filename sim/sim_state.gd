extends RefCounted
## Simulation state (SPEC.md section 3) with its initial values. Plain data with no Node
## dependencies; sim_model.gd creates and advances it.

const SimState := preload("res://sim/sim_state.gd")
const Tuning := preload("res://sim/tuning.gd")

const CREW_IDS: Array[String] = ["lovell", "swigert", "haise"]
const CREW_NAMES: Dictionary = {"lovell": "Lovell", "swigert": "Swigert", "haise": "Haise"}
## Values the debug panel can hold. Override paths are "env.<field>", "crew.<id>.<field>" or "stress".
const ENV_FIELDS: Array[String] = ["cabin_temp_c", "co2_mmhg", "pressure_psi", "water_pct", "power_margin"]
const CREW_FIELDS: Array[String] = ["hr", "spo2", "rr", "body_temp_c", "hydration", "fatigue"]
const STRESS_PATH: String = "stress"


class Env extends RefCounted:
	var cabin_temp_c: float = Tuning.CABIN_START_C
	var co2_mmhg: float = Tuning.CO2_START_MMHG
	var pressure_psi: float = Tuning.PRESSURE_PSI
	var water_pct: float = Tuning.WATER_START_PCT
	var power_margin: float = Tuning.POWER_MARGIN_START

	func copy() -> Env:
		var c := Env.new()
		c.cabin_temp_c = cabin_temp_c
		c.co2_mmhg = co2_mmhg
		c.pressure_psi = pressure_psi
		c.water_pct = water_pct
		c.power_margin = power_margin
		return c


class CrewMember extends RefCounted:
	var id: String = ""
	var hr: float = 0.0
	var spo2: float = Tuning.SPO2_BASE_PCT
	var rr: float = Tuning.RR_BASE_PER_MIN
	var body_temp_c: float = Tuning.BODY_TEMP_C
	var hydration: float = Tuning.HYDRATION_START
	var fatigue: float = Tuning.FATIGUE_START

	func copy() -> CrewMember:
		var c := CrewMember.new()
		c.id = id
		c.hr = hr
		c.spo2 = spo2
		c.rr = rr
		c.body_temp_c = body_temp_c
		c.hydration = hydration
		c.fatigue = fatigue
		return c


class Flags extends RefCounted:
	var heating: String = "off"
	var return_mode: String = "standard"
	var adapter: String = "wait"
	var ration: String = "strict"
	var power_up: String = "late"
	var heat_shield_risk: bool = false
	var sm_jettisoned: bool = false

	func copy() -> Flags:
		var c := Flags.new()
		c.heating = heating
		c.return_mode = return_mode
		c.adapter = adapter
		c.ration = ration
		c.power_up = power_up
		c.heat_shield_risk = heat_shield_risk
		c.sm_jettisoned = sm_jettisoned
		return c


class MissionTime extends RefCounted:
	var current_get: float = Tuning.EXPLOSION_GET
	var splashdown_get: float = Tuning.STANDARD_SPLASHDOWN_GET

	func copy() -> MissionTime:
		var c := MissionTime.new()
		c.current_get = current_get
		c.splashdown_get = splashdown_get
		return c


var env := Env.new()
var crew: Dictionary[String, CrewMember] = {}
var flags := Flags.new()
var time := MissionTime.new()
## Event-driven bpm added to every crew member's heart rate.
var stress: float = 0.0
## Haise's infection, decided once when the clock passes Tuning.FEVER_CHECK_GET.
var fever: bool = false
## Poll choices applied so far: event id -> option key.
var decisions: Dictionary[String, String] = {}
## Ids of the events whose start time has been reached, in order.
var reached_events: Array[String] = []
## Debug values held on every step: override path -> value.
var overrides: Dictionary[String, float] = {}
## Vitals noise: the RNG state, and one drift channel per noisy value as [from, to, tick, length].
var rng_state: int = 0
var noise: Dictionary[String, PackedFloat64Array] = {}


func _init() -> void:
	for crew_id in CREW_IDS:
		var member := CrewMember.new()
		member.id = crew_id
		crew[crew_id] = member


func copy() -> SimState:
	var c := SimState.new()
	c.env = env.copy()
	for crew_id in CREW_IDS:
		c.crew[crew_id] = crew[crew_id].copy()
	c.flags = flags.copy()
	c.time = time.copy()
	c.stress = stress
	c.fever = fever
	c.decisions = decisions.duplicate()
	c.reached_events = reached_events.duplicate()
	c.overrides = overrides.duplicate()
	c.rng_state = rng_state
	for channel: String in noise:
		c.noise[channel] = noise[channel].duplicate()
	return c


## Reads a value by override path, for the debug panel.
func read_path(path: String) -> float:
	var parts: PackedStringArray = path.split(".")
	if parts[0] == "env":
		return env.get(parts[1])
	if parts[0] == "crew":
		return crew[parts[1]].get(parts[2])
	return stress


static func crew_path(crew_id: String, field: String) -> String:
	return "crew.%s.%s" % [crew_id, field]


static func env_path(field: String) -> String:
	return "env.%s" % field

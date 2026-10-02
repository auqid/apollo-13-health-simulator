extends Node
## Heartbeat and breathing for the focused crew member, and the master alarm.
## Voice, Bio and Alarm are separate buses. Bio and Alarm duck while Voice is playing,
## so mission audio (Day 3) stays clear. M mutes everything. S silences the current alarm;
## the caution light is left alone.

const AudioMix := preload("res://audio/audio_mix.gd")
const SimModel := preload("res://sim/sim_model.gd")
const SimState := preload("res://sim/sim_state.gd")
const Tuning := preload("res://sim/tuning.gd")

const GROUP := "bio_audio"

var muted: bool = false
var _silenced: bool = false
var _alarm_playing: bool = false
var _volumes: Dictionary = {}
var _duck: float = 0.0
var _heart: AudioStreamPlayer
var _breath: AudioStreamPlayer
var _alarm: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _beat_pos_s: float = 0.0
var _beat_len_s: float = 1.0
var _breath_pos_s: float = 0.0
var _breath_len_s: float = 4.0
var _alarm_t_s: float = 0.0
var _breath_lp: float = 0.0
var _noise_state: int = 1
var _hr: float = 70.0
var _rr: float = 14.0


func _ready() -> void:
	add_to_group(GROUP)
	for bus_name in AudioMix.BUSES:
		_volumes[bus_name] = 1.0
	_ensure_buses()
	_heart = _tone_player(AudioMix.BUS_BIO)
	_breath = _tone_player(AudioMix.BUS_BIO)
	_alarm = _tone_player(AudioMix.BUS_ALARM)
	_voice = AudioStreamPlayer.new()
	_voice.bus = AudioMix.BUS_VOICE
	add_child(_voice)
	_apply_volumes()


func _exit_tree() -> void:
	for player in [_heart, _breath, _alarm, _voice]:
		if player != null:
			player.stop()


func toggle_mute() -> bool:
	muted = not muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index(AudioMix.BUS_MASTER), muted)
	return muted


## Stops the tone for this bout. Returns true when an alarm was actually sounding.
func silence_alarm() -> bool:
	var stopped: bool = _alarm_playing
	if _alarm_playing or _alarm_wanted():
		_silenced = true
		_alarm_playing = false
	return stopped


func set_bus_linear(bus_name: String, linear: float) -> void:
	if not _volumes.has(bus_name):
		return
	_volumes[bus_name] = clampf(linear, 0.0, 1.0)
	_apply_volumes()


func bus_linear(bus_name: String) -> float:
	return _volumes.get(bus_name, 1.0)


## A short tone on the Voice bus, so the duck can be heard before the mission audio exists.
func play_test_voice() -> void:
	_voice.stream = _voice_tone()
	_voice.play()


## 0 at the start of an inhale, crossing AUDIO_BREATH_INHALE at the start of the exhale.
func breath_phase() -> float:
	if _breath_len_s <= 0.0:
		return 0.0
	return clampf(_breath_pos_s / _breath_len_s, 0.0, 1.0)


func summary() -> String:
	var crew: String = "Lovell"
	var host := get_node_or_null("/root/Game")
	if host != null:
		var crew_id: String = host.get("focused_crew")
		crew = SimState.CREW_NAMES.get(crew_id, crew)
	var alarm: String = "off"
	if _alarm_playing:
		alarm = "on"
	elif _silenced:
		alarm = "silenced"
	var sound: String = "Muted" if muted else "Sound on"
	return "%s. %s at %.0f bpm, breathing %.0f. Alarm %s." % [sound, crew, _hr, _rr, alarm]


func _process(delta: float) -> void:
	_read_vitals()
	var alarm: Dictionary = AudioMix.next_alarm(_alarm_wanted(), _silenced)
	_silenced = alarm["silenced"]
	_alarm_playing = alarm["playing"]
	_fill(_heart, _heartbeat_sample)
	_fill(_breath, _breath_sample)
	_fill(_alarm, _alarm_sample)
	var voice_idx: int = AudioServer.get_bus_index(AudioMix.BUS_VOICE)
	var peak: float = 0.0
	if voice_idx >= 0:
		var peak_db: float = maxf(AudioServer.get_bus_peak_volume_left_db(voice_idx, 0), AudioServer.get_bus_peak_volume_right_db(voice_idx, 0))
		peak = db_to_linear(peak_db) if peak_db > -80.0 else 0.0
	var ducked: float = AudioMix.approach_duck(_duck, peak, delta)
	if not is_equal_approx(ducked, _duck):
		_duck = ducked
		_apply_volumes()
	else:
		_duck = ducked


func _read_vitals() -> void:
	var host := get_node_or_null("/root/Game")
	if host == null:
		return
	var state: SimState = host.get("state")
	if state == null:
		return
	var crew_id: String = str(host.get("focused_crew"))
	var member: SimState.CrewMember = state.crew[crew_id]
	_hr = member.hr
	_rr = maxf(member.rr, 1.0)


func _alarm_wanted() -> bool:
	var host := get_node_or_null("/root/Game")
	var co2: bool = false
	if host != null and host.get("state") != null:
		co2 = SimModel.co2_alarm(host.get("state"))
	var effects := get_tree().get_first_node_in_group("effects")
	var master: bool = effects != null and effects.master_alarm_lit()
	return co2 or master


func _heartbeat_sample(dt_s: float) -> float:
	if _beat_pos_s >= _beat_len_s:
		_beat_pos_s = 0.0
		_beat_len_s = 60.0 / maxf(_hr, 40.0)
	var sample: float = AudioMix.heartbeat_wave(_beat_pos_s) * AudioMix.heartbeat_gain(_hr)
	_beat_pos_s += dt_s
	return sample


func _breath_sample(dt_s: float) -> float:
	if _breath_pos_s >= _breath_len_s:
		_breath_pos_s = 0.0
		_breath_len_s = 60.0 / maxf(_rr, 1.0)
	var phase: float = _breath_pos_s / _breath_len_s
	_breath_lp = lerpf(_breath_lp, _noise(), 0.035)
	var sample: float = _breath_lp * AudioMix.breath_envelope(phase) * Tuning.AUDIO_BREATH_GAIN
	_breath_pos_s += dt_s
	return sample


func _alarm_sample(dt_s: float) -> float:
	if not _alarm_playing:
		_alarm_t_s = 0.0
		return 0.0
	var sample: float = AudioMix.alarm_wave(_alarm_t_s)
	_alarm_t_s += dt_s
	return sample


func _fill(player: AudioStreamPlayer, sample_at: Callable) -> void:
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	if playback == null:
		return
	var dt_s: float = 1.0 / Tuning.AUDIO_MIX_RATE
	var frames: int = playback.get_frames_available()
	for _i in frames:
		var sample: float = sample_at.call(dt_s)
		playback.push_frame(Vector2(sample, sample))


func _noise() -> float:
	_noise_state = (_noise_state * 1103515245 + 12345) & 0x7fffffff
	return float(_noise_state % 10000) / 5000.0 - 1.0


func _ensure_buses() -> void:
	for bus_name in [AudioMix.BUS_VOICE, AudioMix.BUS_BIO, AudioMix.BUS_ALARM]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var idx: int = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, AudioMix.BUS_MASTER)


func _tone_player(bus_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = Tuning.AUDIO_MIX_RATE
	stream.buffer_length = Tuning.AUDIO_BUFFER_S
	player.stream = stream
	player.bus = bus_name
	add_child(player)
	player.play()
	return player


func _apply_volumes() -> void:
	for bus_name in AudioMix.BUSES:
		var idx: int = AudioServer.get_bus_index(bus_name)
		if idx < 0:
			continue
		var db: float = AudioMix.volume_db(_volumes[bus_name])
		if bus_name in AudioMix.DUCKED_BUSES:
			db += _duck * Tuning.AUDIO_DUCK_DB
		AudioServer.set_bus_volume_db(idx, db)


func _voice_tone() -> AudioStreamWAV:
	var rate: int = Tuning.AUDIO_MIX_RATE
	var count: int = int(Tuning.AUDIO_TEST_VOICE_S * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var edge_s: float = 0.06
	for i in count:
		var t_s: float = float(i) / rate
		var env: float = 1.0
		if t_s < edge_s:
			env = t_s / edge_s
		elif t_s > Tuning.AUDIO_TEST_VOICE_S - edge_s:
			env = maxf(Tuning.AUDIO_TEST_VOICE_S - t_s, 0.0) / edge_s
		var wobble: float = 0.85 + 0.15 * sin(TAU * 3.0 * t_s)
		var sample: float = sin(TAU * Tuning.AUDIO_TEST_VOICE_HZ * t_s) * wobble * env * Tuning.AUDIO_TEST_VOICE_GAIN
		bytes.encode_s16(i * 2, clampi(int(sample * 32767.0), -32767, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	return wav

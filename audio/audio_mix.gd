extends RefCounted
## Loudness, envelopes and ducking for the synthesized heartbeat, breathing and alarm.
## No audio devices, so the tests can check them.

const Tuning := preload("res://sim/tuning.gd")

const BUS_MASTER := "Master"
const BUS_VOICE := "Voice"
const BUS_BIO := "Bio"
const BUS_ALARM := "Alarm"
const BUSES: Array[String] = [BUS_MASTER, BUS_VOICE, BUS_BIO, BUS_ALARM]
## Buses that drop while mission audio is playing on Voice.
const DUCKED_BUSES: Array[String] = [BUS_BIO, BUS_ALARM]


## 0 is silence, 1 is full bus volume (0 dB).
static func volume_db(linear: float) -> float:
	if linear <= 0.001:
		return Tuning.AUDIO_VOLUME_SILENT_DB
	return linear_to_db(clampf(linear, 0.0, 1.0))


## Quiet at a calm heart rate, and up to full by 90 bpm.
static func heartbeat_gain(hr_bpm: float) -> float:
	var rise: float = clampf(inverse_lerp(Tuning.AUDIO_HEART_QUIET_BPM, Tuning.AUDIO_HEART_LOUD_BPM, hr_bpm), 0.0, 1.0)
	rise *= rise
	return lerpf(Tuning.AUDIO_HEART_GAIN_CALM, Tuning.AUDIO_HEART_GAIN_LOUD, rise)


## One lub-dub. t_s is seconds since the start of this beat.
static func heartbeat_wave(t_s: float) -> float:
	var lub: float = _thump(t_s, 0.0, Tuning.AUDIO_HEART_LUB_WIDTH_S, Tuning.AUDIO_HEART_LUB_HZ)
	var dub: float = _thump(t_s, Tuning.AUDIO_HEART_DUB_AT_S, Tuning.AUDIO_HEART_DUB_WIDTH_S, Tuning.AUDIO_HEART_DUB_HZ)
	return lub + dub * 0.62


## phase is 0 to 1 through one breath: a shorter inhale, then the exhale.
static func breath_envelope(phase: float) -> float:
	var inhale: float = Tuning.AUDIO_BREATH_INHALE
	if phase < inhale:
		return sin(PI * phase / inhale)
	return sin(PI * (phase - inhale) / (1.0 - inhale)) * 0.8


## Alternating two tones. t_s grows for as long as the alarm is sounding.
static func alarm_wave(t_s: float) -> float:
	var step_s: float = Tuning.AUDIO_ALARM_STEP_S
	var local_s: float = fmod(t_s, step_s)
	var high: bool = int(floor(t_s / step_s)) % 2 == 1
	var hz: float = Tuning.AUDIO_ALARM_HIGH_HZ if high else Tuning.AUDIO_ALARM_LOW_HZ
	var env: float = 1.0
	if local_s < 0.02:
		env = local_s / 0.02
	elif local_s > step_s - 0.04:
		env = maxf(step_s - local_s, 0.0) / 0.04
	var tone: float = sin(TAU * hz * t_s) + 0.12 * sin(TAU * hz * 2.0 * t_s)
	return tone * env * Tuning.AUDIO_ALARM_GAIN


## 0 is no duck, 1 is fully ducked. Rises quickly when Voice is loud and lets go slowly.
static func approach_duck(current: float, voice_peak: float, delta_s: float) -> float:
	var target: float = 1.0 if voice_peak >= Tuning.AUDIO_VOICE_PEAK else 0.0
	var seconds: float = Tuning.AUDIO_DUCK_ATTACK_S if target > current else Tuning.AUDIO_DUCK_RELEASE_S
	if seconds <= 0.0:
		return target
	return lerpf(current, target, 1.0 - exp(-delta_s / seconds))


## The alarm can sound only while it's wanted and the presenter hasn't silenced this bout.
## Silencing clears itself once the cause goes away, so the next bout can sound.
static func next_alarm(wanted: bool, silenced: bool) -> Dictionary:
	if not wanted:
		return {"playing": false, "silenced": false}
	return {"playing": not silenced, "silenced": silenced}


static func _thump(t_s: float, at_s: float, width_s: float, hz: float) -> float:
	var x: float = t_s - at_s
	if x < 0.0 or x > width_s * 5.0:
		return 0.0
	return sin(TAU * hz * x) * exp(-x / width_s)

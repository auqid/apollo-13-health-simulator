extends Control
## A person's photo in a small frame, from "people" in events.json. For the crew it shows how they
## are (face.gdshader): cold, flushed with fever, worn out, and it swells very slightly with each
## breath at their breathing rate. It never shakes. Mission Control photos stay as they are.

const SimState := preload("res://sim/sim_state.gd")
const Tuning := preload("res://sim/tuning.gd")
const CrewLook := preload("res://scenes/ui/crew_look.gd")

const FACE_SHADER := "res://scenes/ui/face.gdshader"

## Breaths a minute; 0 holds the photo still.
var breaths_per_min: float = 0.0
var _photo: TextureRect
var _look: ShaderMaterial
var _breath_phase: float = 0.0


func _init(frame_size: Vector2) -> void:
	custom_minimum_size = frame_size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_photo = TextureRect.new()
	_photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# Breathing swells the photo from the shoulders up.
	_photo.pivot_offset = Vector2(frame_size.x * 0.5, frame_size.y)
	_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_look = ShaderMaterial.new()
	if ResourceLoader.exists(FACE_SHADER):
		_look.shader = load(FACE_SHADER)
	_photo.material = _look
	add_child(_photo)
	visible = false


## Shows this person's photo, or hides the frame if they have none or the file is missing.
func show_person(people: Dictionary, person: String) -> bool:
	var path: String = str(people.get(person, {}).get("face", ""))
	_photo.texture = load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
	visible = _photo.texture != null
	return visible


## How a crew member is right now.
func react(member: SimState.CrewMember, env: SimState.Env) -> void:
	_look.set_shader_parameter("cold", CrewLook.cold(env))
	_look.set_shader_parameter("flush", CrewLook.flush(member))
	_look.set_shader_parameter("tired", CrewLook.tired(member))
	breaths_per_min = member.rr


## The photo as it is, for someone in Mission Control.
func calm() -> void:
	for parameter: String in ["cold", "flush", "tired"]:
		_look.set_shader_parameter(parameter, 0.0)
	breaths_per_min = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	var breath: float = 0.0
	if breaths_per_min > 0.0:
		_breath_phase = fposmod(_breath_phase + TAU * breaths_per_min / 60.0 * delta, TAU)
		breath = 0.5 - 0.5 * cos(_breath_phase)
	_photo.scale = Vector2.ONE * (1.0 + Tuning.CREW_BREATH_SCALE * breath)

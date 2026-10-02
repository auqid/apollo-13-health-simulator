extends RefCounted
## Earth, Moon and starfield shared by the cabin windows and the exterior view.
## Textures are built once and reused, so a second scene does not regenerate them.

const ATMOSPHERE_SHADER := "res://scenes/cabin/atmosphere.gdshader"

const STAR_COUNT := 3000
const STAR_SEED := 1304
const STAR_MAP_SIZE := Vector2i(4096, 2048)
const STAR_BRIGHTNESS := 0.8
const PLANET_TEXTURE_SIZE := Vector2i(1024, 512)

static var _stars: Texture2D
static var _earth: StandardMaterial3D
static var _clouds: StandardMaterial3D
static var _moon: StandardMaterial3D
static var _atmosphere: ShaderMaterial


static func star_panorama() -> Texture2D:
	if _stars != null:
		return _stars
	var image := Image.create_empty(STAR_MAP_SIZE.x, STAR_MAP_SIZE.y, false, Image.FORMAT_L8)
	var rng := RandomNumberGenerator.new()
	rng.seed = STAR_SEED
	for _i in STAR_COUNT:
		var brightness: float = pow(rng.randf(), 3.0)
		var x: int = rng.randi_range(0, STAR_MAP_SIZE.x - 1)
		var y: int = rng.randi_range(0, STAR_MAP_SIZE.y - 1)
		image.set_pixel(x, y, Color(brightness, brightness, brightness))
	_stars = ImageTexture.create_from_image(image)
	return _stars


static func earth_material() -> StandardMaterial3D:
	if _earth == null:
		_earth = StandardMaterial3D.new()
		_earth.albedo_texture = _noise_texture(11, 2.5, [0.0, 0.55, 0.6, 0.7, 0.85, 1.0],
			[Color(0.02, 0.07, 0.2), Color(0.05, 0.18, 0.42), Color(0.2, 0.32, 0.22), Color(0.36, 0.33, 0.2),
			Color(0.5, 0.43, 0.3), Color(0.9, 0.9, 0.9)])
		_earth.roughness = 0.9
	return _earth


static func cloud_material() -> StandardMaterial3D:
	if _clouds == null:
		_clouds = StandardMaterial3D.new()
		_clouds.albedo_texture = _noise_texture(23, 4.0, [0.0, 0.5, 0.68, 1.0],
			[Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0.95)])
		_clouds.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_clouds.roughness = 1.0
	return _clouds


static func moon_material() -> StandardMaterial3D:
	if _moon == null:
		_moon = StandardMaterial3D.new()
		var noise := FastNoiseLite.new()
		noise.seed = 7
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		noise.frequency = 6.0 / PLANET_TEXTURE_SIZE.x
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 4
		_moon.albedo_texture = _noise_texture_from(noise, [0.0, 0.6, 1.0],
			[Color(0.5, 0.48, 0.45), Color(0.36, 0.35, 0.33), Color(0.22, 0.21, 0.2)])
		var bumps := NoiseTexture2D.new()
		bumps.width = PLANET_TEXTURE_SIZE.x
		bumps.height = PLANET_TEXTURE_SIZE.y
		bumps.seamless = true
		bumps.noise = noise
		bumps.as_normal_map = true
		bumps.bump_strength = 12.0
		_moon.normal_enabled = true
		_moon.normal_texture = bumps
		_moon.roughness = 1.0
	return _moon


static func atmosphere_material() -> ShaderMaterial:
	if _atmosphere == null:
		_atmosphere = ShaderMaterial.new()
		if ResourceLoader.exists(ATMOSPHERE_SHADER):
			_atmosphere.shader = load(ATMOSPHERE_SHADER)
	return _atmosphere


static func sphere(radius: float, material: Material, segments: int = 48) -> MeshInstance3D:
	var body := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = segments / 2
	body.mesh = mesh
	body.material_override = material
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return body


static func _noise_texture(seed_value: int, cycles: float, offsets: Array, colors: Array) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = cycles / PLANET_TEXTURE_SIZE.x
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	return _noise_texture_from(noise, offsets, colors)


static func _noise_texture_from(noise: FastNoiseLite, offsets: Array, colors: Array) -> NoiseTexture2D:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array(offsets)
	ramp.colors = PackedColorArray(colors)
	var texture := NoiseTexture2D.new()
	texture.width = PLANET_TEXTURE_SIZE.x
	texture.height = PLANET_TEXTURE_SIZE.y
	texture.seamless = true
	texture.noise = noise
	texture.color_ramp = ramp
	return texture

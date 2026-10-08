extends Node3D
## Daughter of the Wind: a white glider, a sky of clouds, and a fleet of giant metal airships.
##
## The whole world is put together here in code: the painted sky and the sun, the cloud manager,
## the glider with its input and camera, the fleet and the HUD. This script also fades the view to
## white when the camera is inside a cloud, and handles restart and the weather keys (1 / 2 / 3).
##
## Tests set the exported switches below before adding the scene to the tree.

const CloudManager := preload("res://scripts/cloud_manager.gd")
const Glider := preload("res://scripts/glider.gd")
const FlightInput := preload("res://scripts/flight_input.gd")
const ChaseCam := preload("res://scripts/chase_cam.gd")
const Fleet := preload("res://scripts/fleet.gd")
const Hud := preload("res://scripts/hud.gd")
const SkyShader := preload("res://shaders/sky.gdshader")

const START := Vector3(0, 620, 0)
const ZENITH := Color(0.09, 0.29, 0.7)
const HAZE := Color(0.73, 0.85, 0.96)
const SUN := Color(1.0, 0.95, 0.82)
const HAZE_DISTANCE := 8500.0

## False flies an empty sky (no ships), for tests of the flight alone.
@export var use_fleet := true
## False ignores gamepads, so a stuck stick cannot steer a test.
@export var use_pads := true
@export var show_hud := true

## The direction TO the sun.
var sun_dir := Vector3(-0.5, 0.55, -0.67).normalized()

var clouds: Node3D
var glider: Node3D
var input: Node
var cam: Camera3D
var fleet: Node3D
var hud: CanvasLayer

var _env: Environment
var _whiteout := 0.0


func _ready() -> void:
	_build_sky()

	glider = Glider.new()
	input = FlightInput.new()
	input.use_pads = use_pads
	add_child(input)
	glider.input = input
	add_child(glider)
	glider.reset(START)

	clouds = CloudManager.new()
	clouds.sun_dir = sun_dir
	clouds.haze_color = HAZE
	clouds.haze_distance = HAZE_DISTANCE
	clouds.focus = glider
	add_child(clouds)
	clouds.prewarm()
	glider.clouds = clouds

	if use_fleet:
		fleet = Fleet.new()
		fleet.focus = glider
		add_child(fleet)
		# Start with the convoy ahead and a little to one side, sailing nearly the same way.
		fleet.place(START + Vector3(260, -70, -1150), 0.22)
		glider.fleet = fleet

	cam = ChaseCam.new()
	cam.target = glider
	add_child(cam)
	cam.snap()
	cam.make_current()

	if show_hud:
		hud = Hud.new()
		hud.glider = glider
		hud.input = input
		add_child(hud)

	input.reset_pressed.connect(restart)
	input.weather_pressed.connect(clouds.set_weather)


func _build_sky() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SkyShader
	sky_mat.set_shader_parameter("zenith", ZENITH)
	sky_mat.set_shader_parameter("horizon", HAZE)
	sky_mat.set_shader_parameter("sun_color", SUN)
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 1.0
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Distance haze on the glider and the ships. The clouds do their own in their shaders.
	_env.fog_enabled = true
	_env.fog_light_color = HAZE
	_env.fog_density = 1.0 / HAZE_DISTANCE
	_env.fog_sky_affect = 0.0
	var world := WorldEnvironment.new()
	world.environment = _env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(-sun_dir, Vector3.UP)
	sun.light_color = SUN
	sun.light_energy = 1.25
	add_child(sun)


func restart() -> void:
	glider.reset(START)
	if fleet:
		fleet.place(START + Vector3(260, -70, -1150), 0.22)
	cam.snap()


func _process(delta: float) -> void:
	# White out as the camera goes into cloud, and thicken the haze around the glider with it.
	var thick: float = clouds.density_at(cam.global_position)
	_whiteout = lerpf(_whiteout, thick, 1.0 - exp(-6.0 * delta))
	_env.fog_density = lerpf(1.0 / HAZE_DISTANCE, 0.02, _whiteout * _whiteout)
	if hud:
		hud.whiteout = _whiteout

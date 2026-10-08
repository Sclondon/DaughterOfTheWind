extends Node3D
## Daughter of the Wind: a white glider, a sky of clouds, giant metal airships, and a windy coast.
##
## The whole world is put together here in code: the painted sky and the sun, the cloud manager,
## the glider with its input and camera, the HUD, and whatever the level adds on top:
##   "clouds"  the sea of clouds
##   "coast"   the sea, and an endless wall of towering terraced cliffs with farms, hamlets and
##             windmills on the ledges, and a valley running down to a beach with the castle in it
##             (coast.gd)
## Both have the battle (battle.gd): two fleets of airships fighting each other, with their
## fighters, and all of them firing on the glider. Shot down, she starts again.
## This script also fades the view to white when the camera is inside a cloud, and handles
## restart (R), the weather keys (1 / 2 / 3), switching level (L, or the button on the HUD) and
## switching rider between the glider and the witch on her broom (G, or its button).
##
## Tests set the exported switches below before adding the scene to the tree.

const CloudManager := preload("res://scripts/cloud_manager.gd")
const Glider := preload("res://scripts/glider.gd")
const FlightInput := preload("res://scripts/flight_input.gd")
const ChaseCam := preload("res://scripts/chase_cam.gd")
const Battle := preload("res://scripts/battle.gd")
const SunGlare := preload("res://scripts/sun_glare.gd")
const Coast := preload("res://scripts/coast.gd")
const Hud := preload("res://scripts/hud.gd")
const SkyShader := preload("res://shaders/sky.gdshader")

const LEVELS := ["clouds", "coast"]
const LEVEL_NAMES := {"clouds": "Sea of Clouds", "coast": "The Windward Coast"}
const RIDER_NAMES := {"glider": "Glider", "witch": "Witch"}
const ZENITH := Color(0.09, 0.29, 0.7)
const HAZE := Color(0.73, 0.85, 0.96)
const SUN := Color(1.0, 0.95, 0.82)
const HAZE_DISTANCE := 8500.0

## The level picked last, kept across a scene reload.
static var chosen := "clouds"
static var chosen_rider := "glider"

## Which level to build. Empty means the one picked last.
@export var level := ""
## "glider" or "witch". Empty means the one picked last.
@export var rider := ""
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
var battle: Node3D
## The first of the battle's two fleets (kept for the tests).
var fleet: Node3D
var coast: Node3D
var hud: CanvasLayer
var start := Vector3(0, 620, 0)
var start_heading := 0.0

var _env: Environment
var _whiteout := 0.0
# The middle of the circle the battle starts on, and how far round it the flagships begin.
# (Over the clouds: the nearest ships a little over a kilometre ahead, coming her way.)
var _battle_at := Vector3(-2900, 560, -1300)
var _battle_angle := 0.0


func _ready() -> void:
	if level == "":
		level = chosen
	_build_sky()

	if rider == "":
		rider = chosen_rider
	glider = Glider.new()
	glider.rider = rider
	input = FlightInput.new()
	input.use_pads = use_pads
	add_child(input)
	glider.input = input
	add_child(glider)

	clouds = CloudManager.new()
	clouds.sun_dir = sun_dir
	clouds.haze_color = HAZE
	clouds.haze_distance = HAZE_DISTANCE
	clouds.focus = glider
	if level == "coast":
		# Real ground below: no sea of clouds, and the cloud bases lifted clear of the hills.
		clouds.sea_enabled = false
		clouds.altitude_shift = 760.0
		clouds.wind = Vector3(5.0, 0.0, 0.7)
	add_child(clouds)
	glider.air.append(clouds)

	if level == "coast":
		coast = Coast.new()
		coast.focus = glider
		coast.sun_dir = sun_dir
		coast.haze_color = HAZE
		coast.sky_color = ZENITH
		coast.haze_distance = HAZE_DISTANCE
		coast.noise_tex = clouds.noise_texture()
		add_child(coast)
		glider.air.append(coast)
		glider.solids.append(coast)
		start = coast.start_position()
		start_heading = coast.start_heading()
		# The battle circles out over the sea, off to her right as she comes in toward the valley.
		_battle_at = Vector3(coast.shore_x(0.0) - 5200.0, 640.0, 4500.0)
		_battle_angle = -0.9
	if use_fleet:
		battle = Battle.new()
		battle.focus = glider
		battle.land = coast
		add_child(battle)
		fleet = battle.fleets[0]
		glider.solids.append(battle)
		glider.downed.connect(restart, CONNECT_DEFERRED)

	cam = ChaseCam.new()
	cam.target = glider
	add_child(cam)
	cam.make_current()

	# The sun's glare sits under the HUD.
	var lens := CanvasLayer.new()
	lens.layer = 0
	add_child(lens)
	var glare: ColorRect = SunGlare.new()
	glare.camera = cam
	glare.sun_dir = sun_dir
	glare.clouds = clouds
	glare.land = coast
	lens.add_child(glare)

	if show_hud:
		hud = Hud.new()
		hud.glider = glider
		hud.input = input
		hud.level_name = LEVEL_NAMES[level]
		hud.rider_name = RIDER_NAMES[rider]
		add_child(hud)
		hud.level_pressed.connect(next_level)
		hud.rider_pressed.connect(next_rider)
		glider.hurt.connect(hud.flash)

	restart()
	clouds.prewarm()
	input.reset_pressed.connect(restart)
	input.weather_pressed.connect(clouds.set_weather)
	input.level_pressed.connect(next_level)
	input.rider_pressed.connect(next_rider)


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
	# Distance haze on the glider, the ships and the land. The clouds and the ocean do their own.
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
	glider.reset(start, start_heading)
	if battle:
		battle.place(_battle_at, _battle_angle)
	if coast:
		coast.prewarm()
	cam.snap()


## Reload the scene as the next level in LEVELS.
func next_level() -> void:
	chosen = LEVELS[(LEVELS.find(level) + 1) % LEVELS.size()]
	chosen_rider = rider
	get_tree().reload_current_scene()


## Reload the scene with the other rider.
func next_rider() -> void:
	chosen = level
	chosen_rider = "glider" if rider == "witch" else "witch"
	get_tree().reload_current_scene()


func _process(delta: float) -> void:
	# White out as the camera goes into cloud, and thicken the haze around the glider with it.
	var thick: float = clouds.density_at(cam.global_position)
	_whiteout = lerpf(_whiteout, thick, 1.0 - exp(-6.0 * delta))
	_env.fog_density = lerpf(1.0 / HAZE_DISTANCE, 0.02, _whiteout * _whiteout)
	if hud:
		hud.whiteout = _whiteout

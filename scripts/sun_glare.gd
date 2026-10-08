extends ColorRect
## The sun's glare in the lens: a bloom round the sun, a few rays and a streak, and a string of
## faint ghosts across the screen, all added over the picture when the camera looks toward the
## sun. It dims when the sun goes behind a cloud or the land, and is gone when the sun is behind.

const GlareShader := preload("res://shaders/sun_glare.gdshader")

var camera: Camera3D
## The direction TO the sun.
var sun_dir := Vector3.UP
## Optional: something with density_at(world) (the clouds) and something with hit(world, radius)
## (the land), to tell when the sun is hidden.
var clouds: Node
var land: Node

var _strength := 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = GlareShader
	material = _mat


func _process(delta: float) -> void:
	if camera == null:
		return
	var eye: Vector3 = camera.global_position
	var want: float = 0.0
	var screen: Vector2 = get_viewport_rect().size
	var at := Vector2(0.5, 0.5)
	if (-camera.global_basis.z).dot(sun_dir) > 0.05:
		at = camera.unproject_position(eye + sun_dir * 1000.0) / screen
		# Full strength with the sun on screen, fading as it slides off the edge.
		var off: float = maxf(maxf(-at.x, at.x - 1.0), maxf(-at.y, at.y - 1.0))
		want = 1.0 - smoothstep(0.0, 0.35, off)
		# Is anything in the way?
		for reach: float in [150.0, 500.0, 1200.0, 2500.0]:
			var p: Vector3 = eye + sun_dir * reach
			if clouds:
				want *= 1.0 - clouds.density_at(p) * 0.8
			if land and land.hit(p, 1.0) != Vector3.ZERO:
				want = 0.0
	_strength = lerpf(_strength, want, 1.0 - exp(-7.0 * delta))
	visible = _strength > 0.005
	_mat.set_shader_parameter("sun", at)
	_mat.set_shader_parameter("strength", _strength)
	_mat.set_shader_parameter("aspect", screen.x / maxf(screen.y, 1.0))

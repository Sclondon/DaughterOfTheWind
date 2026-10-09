extends ColorRect
## Speed lines: thin white streaks that rush in from the edges of the screen toward the middle
## when the glider is going fast, and harder still when it boosts. Drawn over the whole screen
## by shaders/speed_lines.

const LinesShader := preload("res://shaders/speed_lines.gdshader")

## Whoever is flying: needs `airspeed` and `boosting`.
var flyer: Node3D

var _strength := 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = LinesShader
	material = _mat


func _process(delta: float) -> void:
	if flyer == null:
		return
	var want: float = smoothstep(44.0, 82.0, flyer.airspeed) * 0.75
	if flyer.boosting:
		want = maxf(want, 0.65) + 0.3
	_strength = lerpf(_strength, clampf(want, 0.0, 1.0), 1.0 - exp(-5.0 * delta))
	visible = _strength > 0.01
	var screen: Vector2 = get_viewport_rect().size
	_mat.set_shader_parameter("strength", _strength)
	_mat.set_shader_parameter("aspect", screen.x / maxf(screen.y, 1.0))

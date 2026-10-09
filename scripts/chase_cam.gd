extends Camera3D
## The camera that follows the glider: behind and a little above, leaning partway into the bank,
## and opening its field of view as the glider speeds up. It reads the glider's interpolated
## transform every frame so it stays smooth between physics steps.

const DISTANCE := 8.5
const HEIGHT := 2.3

var target: Node3D

var _dir := Vector3.FORWARD
var _up := Vector3.UP


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	near = 0.3
	far = 16000.0
	fov = 70.0


## Jump straight to where the camera wants to be (after a reset).
func snap() -> void:
	if target == null:
		return
	_dir = -target.global_basis.z
	_up = Vector3.UP
	_place(target.global_transform)


func _process(delta: float) -> void:
	if target == null:
		return
	var t: Transform3D = target.get_global_transform_interpolated()
	var fwd: Vector3 = -t.basis.z
	_dir = _dir.lerp(fwd, 1.0 - exp(-5.0 * delta))
	if _dir.length() < 0.01:
		_dir = fwd
	_dir = _dir.normalized()
	# Flying level, the camera mostly keeps the horizon flat. Nose high, nose low or upside down
	# (a loop), "up" stops meaning much, so it goes over with the glider instead of flipping.
	var level: float = (1.0 - smoothstep(0.45, 0.85, absf(fwd.y))) * smoothstep(-0.1, 0.35, t.basis.y.y)
	var up_goal: Vector3 = Vector3.UP * 0.7 * level + t.basis.y * (1.0 - 0.7 * level)
	_up = _up.lerp(up_goal, 1.0 - exp(-5.0 * delta))
	if _up.length() < 0.05:
		_up = t.basis.y
	_up = _up.normalized()
	_place(t)
	var speed: float = target.airspeed
	# The view opens out with speed, and kicks wider still while the jet is lit.
	var want_fov: float = 66.0 + clampf((speed - 25.0) / 55.0, 0.0, 1.0) * 26.0
	if target.boosting:
		want_fov += 12.0
	fov = lerpf(fov, minf(want_fov, 108.0), 1.0 - exp(-4.0 * delta))


func _place(t: Transform3D) -> void:
	var pos: Vector3 = t.origin - _dir * DISTANCE + _up * HEIGHT
	var look: Vector3 = (t.origin - t.basis.z * 6.0 + _up * 0.8) - pos
	# Square the up vector to the view so the camera never rolls suddenly.
	var view: Vector3 = look.normalized()
	var up: Vector3 = _up - view * _up.dot(view)
	if up.length() < 0.05:
		up = t.basis.y - view * t.basis.y.dot(view)
	global_transform = Transform3D(Basis.looking_at(look, up.normalized()), pos)

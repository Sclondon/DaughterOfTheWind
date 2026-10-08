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
	var up_goal: Vector3 = (Vector3.UP * 0.7 + t.basis.y * 0.3).normalized()
	_up = _up.lerp(up_goal, 1.0 - exp(-4.0 * delta)).normalized()
	_place(t)
	var speed: float = target.airspeed
	var want_fov: float = 68.0 + clampf((speed - 25.0) / 60.0, 0.0, 1.0) * 24.0
	fov = lerpf(fov, want_fov, 1.0 - exp(-3.0 * delta))


func _place(t: Transform3D) -> void:
	var pos: Vector3 = t.origin - _dir * DISTANCE + _up * HEIGHT
	var look: Vector3 = (t.origin - t.basis.z * 6.0 + _up * 0.8) - pos
	var up: Vector3 = _up
	if absf(look.normalized().dot(up)) > 0.97:
		up = t.basis.y
	global_transform = Transform3D(Basis.looking_at(look, up), pos)

extends Node3D
## The glider's flight. It is a small aerodynamic model rather than a canned "move forward" script:
## lift and drag come from the air moving over the wing, so diving buys speed, pulling up spends it,
## banking tilts the lift and turns you, and rising air under the clouds carries you up.
##
## Forward is -Z. The stick asks for a bank angle and an angle of attack; the nose is always being
## pulled back into the airflow (like a weathervane), which is what makes it settle into a glide.
## The air it flies through is the sum of `wind_at()` from everything in `air` (clouds, the coast's
## ridge lift), and everything in `solids` (the fleet, the land) pushes it back out through `hit()`.

signal bumped
## Struck by a shell. `downed` follows if that was the last of her health.
signal hurt
signal downed

const GliderModel := preload("res://scripts/glider_model.gd")
const WitchModel := preload("res://scripts/witch_model.gd")

const GRAVITY := 9.8
## Lift per unit of lift coefficient per (m/s)^2. With CL0 this sets the hands-off glide near 30 m/s.
const LIFT := 0.021
const CL0 := 0.5
const CL_SLOPE := 3.6
const STALL_AOA := 0.27
const CD0 := 0.022
const CD_INDUCED := 0.042
const BRAKE_CD := 0.16
const SIDE_GRIP := 0.03
## How hard the nose swings back into the airflow, per second.
const WEATHERVANE := 3.2
## Angle of attack (radians) a full pull asks for. Kept just under the stall.
const AOA_CMD := 0.24
const AOA_MAX := 0.26
## How much of the extra pull a level turn needs is added for you.
const TURN_ASSIST := 1.0
## Hands off, the nose eases up out of a dive and down out of a climb, back toward a level glide.
## Without it a glider swings up and down for minutes (the phugoid). The stick overrides it.
const SWING_DAMP := 0.22
const GLIDE_SLOPE := -0.06
const MAX_BANK := 1.08
const ROLL_GAIN := 3.2
const ROLL_RATE := 2.4
const STICK_SMOOTH := 7.0
const THRUST := 15.0
const BURN_TIME := 4.5
const RECHARGE_TIME := 9.0
const MAX_SPEED := 110.0
const BODY_RADIUS := 2.2
const MAX_HEALTH := 5
## Seconds unhurt before health starts to come back, then seconds per point.
const MEND_WAIT := 9.0
const MEND_EVERY := 5.0

var input: Node
## What is seen flying: "glider" or "witch". The flight is the same either way. Set before _ready.
var rider := "glider"
## Nodes with wind_at(world) -> Vector3. Their winds add up.
var air: Array = []
## Nodes with hit(world, radius) -> Vector3 (the push that gets a ball out of them, or ZERO).
var solids: Array = []

var velocity := Vector3(0, 0, -31)
## Jet fuel, 0..1. It refills when you are not burning it.
var burn := 1.0
var boosting := false
var health := MAX_HEALTH
var _mend := 0.0

# Read by the camera, HUD, trails and tests.
var airspeed := 31.0
var load_factor := 1.0
var climb := 0.0
var aoa := 0.0
var stalled := false
var looping := false
var rising_air := 0.0
## The stick as the glider feels it (smoothed). The model moves its flaps and wingtips from this.
var control := Vector2.ZERO
var model: Node3D

var _stick := Vector2.ZERO
var _burn_locked := false
var _last_air_dir := Vector3.ZERO


func _ready() -> void:
	model = WitchModel.new() if rider == "witch" else GliderModel.new()
	model.glider = self
	add_child(model)


func reset(at: Vector3, heading: float = 0.0) -> void:
	position = at
	basis = Basis(Vector3.UP, heading)
	velocity = -basis.z * 31.0
	burn = 1.0
	_burn_locked = false
	_stick = Vector2.ZERO
	_last_air_dir = Vector3.ZERO
	health = MAX_HEALTH
	_mend = 0.0
	reset_physics_interpolation()


## A shell has struck her: lose a point of health and get knocked along.
func take_hit(push: Vector3) -> void:
	if health <= 0:
		return
	health -= 1
	_mend = -MEND_WAIT
	velocity += push
	hurt.emit()
	if health <= 0:
		downed.emit()


## An explosion close by: thrown about, but unhurt.
func shove(push: Vector3) -> void:
	velocity += push


func _physics_process(dt: float) -> void:
	var want := Vector2.ZERO
	var want_boost := false
	var want_brake := false
	if input:
		want = input.stick
		want_boost = input.boost
		want_brake = input.brake
	_stick = _stick.lerp(want, 1.0 - exp(-STICK_SMOOTH * dt))
	control = _stick

	var wind := Vector3.ZERO
	for source: Node in air:
		wind += source.wind_at(position)
	rising_air = wind.y
	var air: Vector3 = velocity - wind
	var speed: float = maxf(air.length(), 0.01)
	var air_dir: Vector3 = air / speed

	# --- Turn the body: roll toward the bank the stick asks for, pitch for the angle of attack. ---
	var b: Basis = basis
	# First carry the body round with the flight path, so that curving the path (a turn, a pull-up)
	# does not leave the nose trailing behind it and rob the wing of its angle.
	if _last_air_dir != Vector3.ZERO:
		var swing: Vector3 = _last_air_dir.cross(air_dir)
		var swung: float = _last_air_dir.angle_to(air_dir)
		if swing.length() > 0.000001 and swung < 0.5:
			b = Basis(swing.normalized(), swung) * b
	_last_air_dir = air_dir
	var authority: float = clampf(speed / 22.0, 0.3, 1.0)
	var bank: float = atan2(-b.x.y, b.y.y)
	# Bank means little when pointing straight up or down, so ease the roll off there.
	var level_ish: float = 1.0 - smoothstep(0.8, 0.98, absf(b.z.y))
	var roll: float = clampf((_stick.x * MAX_BANK - bank) * ROLL_GAIN, -ROLL_RATE, ROLL_RATE)
	# Upside down with the stick held back or forward means a loop: do not roll her upright halfway
	# round, just keep the wings level (inverted counts as level) and let the stick nudge the roll.
	looping = b.y.y < 0.0 and absf(_stick.y) > 0.3
	if looping:
		roll = clampf(-b.x.y * ROLL_GAIN * 1.5 + _stick.x * ROLL_RATE * 0.5, -ROLL_RATE, ROLL_RATE)
	b = Basis(-b.z, roll * level_ish * authority * dt) * b

	var ask: float = _stick.y * AOA_CMD
	if b.y.y > 0.0:
		var cos_bank: float = maxf(cos(bank), 0.34)
		ask += TURN_ASSIST * (CL0 / CL_SLOPE) * (1.0 / cos_bank - 1.0) * level_ish
	ask -= SWING_DAMP * (asin(clampf(air_dir.y, -1.0, 1.0)) - GLIDE_SLOPE) * (1.0 - absf(_stick.y))
	ask = clampf(ask, -AOA_CMD, AOA_MAX)
	var vane: float = WEATHERVANE * authority
	b = Basis(b.x, ask * vane * dt) * b

	var nose: Vector3 = -b.z
	var axis: Vector3 = nose.cross(air_dir)
	if axis.length() > 0.0001:
		b = Basis(axis.normalized(), nose.angle_to(air_dir) * minf(vane * dt, 1.0)) * b
	b = b.orthonormalized()

	# --- Forces on the wing. ---
	var fwd: Vector3 = -b.z
	var up: Vector3 = b.y
	var right: Vector3 = b.x
	aoa = atan2(-air_dir.dot(up), air_dir.dot(fwd))
	var cl: float = CL0 + CL_SLOPE * aoa
	stalled = aoa > STALL_AOA
	if stalled:
		cl = (CL0 + CL_SLOPE * STALL_AOA) * maxf(0.35, 1.0 - (aoa - STALL_AOA) * 2.2)
	cl = clampf(cl, -0.9, 2.0)
	var q: float = LIFT * speed * speed
	var cd: float = CD0 + CD_INDUCED * cl * cl
	if want_brake:
		cd += BRAKE_CD
	var lift_dir: Vector3 = right.cross(air_dir).normalized()
	var acc: Vector3 = Vector3.DOWN * GRAVITY + lift_dir * q * cl - air_dir * q * cd
	# The wing resists sliding sideways, which is what makes a banked turn carve.
	acc -= right * air.dot(right) * speed * SIDE_GRIP

	if _burn_locked and burn > 0.25:
		_burn_locked = false
	boosting = want_boost and burn > 0.0 and not _burn_locked
	if boosting:
		acc += fwd * THRUST
		burn = maxf(burn - dt / BURN_TIME, 0.0)
		if burn <= 0.0:
			_burn_locked = true
	elif not want_boost:
		burn = minf(burn + dt / RECHARGE_TIME, 1.0)

	velocity += acc * dt
	velocity = velocity.limit_length(MAX_SPEED)
	position += velocity * dt
	basis = b

	for solid: Node in solids:
		var push: Vector3 = solid.hit(position, BODY_RADIUS)
		if push != Vector3.ZERO:
			var n: Vector3 = push.normalized()
			position += push
			var into: float = velocity.dot(n)
			if into < 0.0:
				velocity -= n * into * 1.5
				velocity *= 0.8
			bumped.emit()

	if health < MAX_HEALTH:
		_mend += dt
		if _mend >= MEND_EVERY:
			_mend = 0.0
			health += 1

	airspeed = speed
	load_factor = q * cl / GRAVITY
	climb = velocity.y

extends Node
## The pilot's hands: one stick, a boost and an air brake, from keys, a gamepad or touch.
##
## stick.x is roll (right is positive) and stick.y is pitch, where positive pulls the nose UP.
## Like a real stick, "down" pulls up: S / Down arrow / stick back / dragging down the screen.
## Touch: drag anywhere on the left 60% of the screen to steer, hold the right side to boost.
## Tests set `manual` and write the values themselves.

signal reset_pressed
signal weather_pressed(index: int)
signal level_pressed
signal rider_pressed

const STICK_RADIUS := 110.0
const DEADZONE := 0.18

var stick := Vector2.ZERO
var boost := false
var brake := false
var manual := false
var use_pads := true

## Where the touch stick is on screen, for the HUD to draw. `stick_touch` is -1 when no finger is down.
var stick_touch := -1
var stick_origin := Vector2.ZERO
var stick_now := Vector2.ZERO
var _boost_touch := -1


# Unhandled, so a tap on a HUD button does not also steer or boost.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			var width: float = get_viewport().get_visible_rect().size.x
			if event.position.x < width * 0.6:
				if stick_touch == -1:
					stick_touch = event.index
					stick_origin = event.position
					stick_now = event.position
			elif _boost_touch == -1:
				_boost_touch = event.index
		else:
			if event.index == stick_touch:
				stick_touch = -1
			if event.index == _boost_touch:
				_boost_touch = -1
	elif event is InputEventScreenDrag:
		if event.index == stick_touch:
			stick_now = event.position
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				reset_pressed.emit()
			KEY_L:
				level_pressed.emit()
			KEY_G:
				rider_pressed.emit()
			KEY_1:
				weather_pressed.emit(0)
			KEY_2:
				weather_pressed.emit(1)
			KEY_3:
				weather_pressed.emit(2)


func _physics_process(_delta: float) -> void:
	if manual:
		return
	var s := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		s.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		s.x += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		s.y += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		s.y -= 1.0
	var pad_boost := false
	var pad_brake := false
	if use_pads:
		var pad := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
		if pad.length() > DEADZONE:
			s += pad
		pad_boost = Input.is_joy_button_pressed(0, JOY_BUTTON_A) or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.5
		pad_brake = Input.is_joy_button_pressed(0, JOY_BUTTON_B) or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > 0.5
	if stick_touch != -1:
		s += (stick_now - stick_origin) / STICK_RADIUS
	stick = s.limit_length(1.0)
	boost = Input.is_physical_key_pressed(KEY_SPACE) or pad_boost or _boost_touch != -1
	brake = Input.is_physical_key_pressed(KEY_SHIFT) or pad_brake

extends CanvasLayer
## The little there is on screen: speed, height and climb in one corner, the jet's fuel as a thin
## bar, the touch stick while a finger is down, the white-out when flying through cloud, and the
## title and controls for the first few seconds. A small button in the top corner names the level
## and switches to the next one.

signal level_pressed

var glider: Node3D
var input: Node
## 0..1, set by main: how deep in cloud the camera is.
var whiteout := 0.0
var level_name := ""

var _white: ColorRect
var _stats: Label
var _fuel: ProgressBar
var _title: Label
var _help: Label
var _stick: Control
var _age := 0.0


class StickView extends Control:
	var input: Node

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if input == null or input.stick_touch == -1:
			return
		var origin: Vector2 = input.stick_origin
		var knob: Vector2 = origin + (input.stick_now - origin).limit_length(input.STICK_RADIUS)
		draw_arc(origin, input.STICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
		draw_circle(knob, 22.0, Color(1, 1, 1, 0.45))


func _ready() -> void:
	_white = ColorRect.new()
	_white.color = Color(0.95, 0.97, 1.0, 0.0)
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_white)

	_stick = StickView.new()
	_stick.input = input
	_stick.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stick)

	_stats = _label(20, HORIZONTAL_ALIGNMENT_LEFT)
	_pin(_stats, 0.0, 1.0, 0.0, 1.0, Rect2(24, -100, 300, 60))

	_fuel = ProgressBar.new()
	_fuel.show_percentage = false
	_fuel.min_value = 0.0
	_fuel.max_value = 1.0
	_fuel.custom_minimum_size = Vector2(170, 6)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.2)
	back.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.86, 0.55, 0.95)
	fill.set_corner_radius_all(3)
	_fuel.add_theme_stylebox_override("background", back)
	_fuel.add_theme_stylebox_override("fill", fill)
	_fuel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fuel)
	_pin(_fuel, 0.0, 1.0, 0.0, 1.0, Rect2(24, -30, 170, 6))

	var level := Button.new()
	level.text = "%s  ›" % level_name
	level.focus_mode = Control.FOCUS_NONE
	level.add_theme_font_size_override("font_size", 16)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(1, 1, 1, 0.18)
	plate.set_corner_radius_all(14)
	plate.set_content_margin_all(8)
	plate.content_margin_left = 14
	plate.content_margin_right = 14
	for state: String in ["normal", "hover", "pressed"]:
		level.add_theme_stylebox_override(state, plate)
	level.pressed.connect(func() -> void: level_pressed.emit())
	add_child(level)
	_pin(level, 1.0, 0.0, 1.0, 0.0, Rect2(-236, 16, 220, 36))

	_title = _label(54, HORIZONTAL_ALIGNMENT_CENTER)
	_title.text = "Daughter of the Wind"
	_pin(_title, 0.0, 0.0, 1.0, 0.0, Rect2(0, 64, 0, 76))

	_help = _label(18, HORIZONTAL_ALIGNMENT_CENTER)
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		_help.text = "Drag on the left to steer (down pulls up)  ·  hold the right side to boost"
	else:
		_help.text = "A / D bank   ·   S pull up, W dive   ·   Space boost   ·   Shift air brake   ·   R restart"
	_pin(_help, 0.0, 0.0, 1.0, 0.0, Rect2(0, 146, 0, 30))


## Anchor a control to part of the screen (left, top, right, bottom as 0..1) and place it with
## a rect of pixel offsets from those anchors.
func _pin(control: Control, left: float, top: float, right: float, bottom: float, rect: Rect2) -> void:
	control.anchor_left = left
	control.anchor_top = top
	control.anchor_right = right
	control.anchor_bottom = bottom
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.position.x + rect.size.x
	control.offset_bottom = rect.position.y + rect.size.y


func _label(size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	label.add_theme_color_override("font_outline_color", Color(0.15, 0.25, 0.45, 0.6))
	label.add_theme_constant_override("outline_size", 5)
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _process(delta: float) -> void:
	_age += delta
	_white.color.a = whiteout * 0.9
	var fade: float = 1.0 - smoothstep(6.0, 9.0, _age)
	_title.modulate.a = fade
	_help.modulate.a = fade
	_title.visible = fade > 0.0
	_help.visible = fade > 0.0
	if glider == null:
		return
	var climb: float = glider.climb
	var arrow: String = "▲" if climb > 0.5 else ("▼" if climb < -0.5 else "–")
	_stats.text = "%d km/h\n%d m  %s %.1f" % [int(glider.airspeed * 3.6), int(glider.position.y), arrow, absf(climb)]
	_fuel.value = glider.burn

extends SceneTree
## Checks the diorama: it loads with the rider in it, the camera turns all the way round and
## tips right up and down on a drag, the stick works the flaps, and the clouds drift.
## Run: godot --headless --fixed-fps 60 --path . -s res://tests/diorama_test.gd

const Diorama := preload("res://scenes/diorama.tscn")

var passed := 0
var failed := 0


func _initialize() -> void:
	_run()


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("%s  %s  (%s)" % ["PASS" if ok else "FAIL", what, detail])


func _drag(room: Node3D, by: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.relative = by
	room._unhandled_input(drag)


func _run() -> void:
	var room: Node3D = Diorama.instantiate()
	root.add_child(room)
	for i in 30:
		await process_frame
	_check("the glider is on show, held still", room.glider != null and room.glider.model != null and room.glider.position.length() < 1.0,
			"at %s" % room.glider.position)

	# Drag a long way sideways: the camera should go right round and face the other way and back.
	var seen := {}
	for i in 80:
		_drag(room, Vector2(-10, 0))
		await process_frame
		var facing: Vector3 = -room.cam.global_basis.z
		seen[Vector2i(roundi(facing.x), roundi(facing.z))] = true
	_check("the camera turns all the way round", seen.size() >= 4 and absf(room.yaw) > TAU, "turned %.1f times, faced %d ways" % [absf(room.yaw) / TAU, seen.size()])
	var highest: float = -9.0
	var lowest: float = 9.0
	for i in 60:
		_drag(room, Vector2(0, 10))
		await process_frame
		highest = maxf(highest, room.cam.global_position.y)
	for i in 120:
		_drag(room, Vector2(0, -10))
		await process_frame
		lowest = minf(lowest, room.cam.global_position.y)
	_check("it goes over the top and underneath", highest > room.distance * 0.95 and lowest < -room.distance * 0.9 and room.cam.global_position.distance_to(Vector3(0, 0.3, 0)) < room.distance + 0.01,
			"from %.1f m above to %.1f m below" % [highest, -lowest])

	room.input.manual = true
	room.input.stick = Vector2(1, 0)
	for i in 40:
		await process_frame
	_check("the stick still leans her and works the flaps", room.glider.control.x > 0.8 and room.glider.basis.x.y < -0.3, "control %.2f" % room.glider.control.x)

	# (Headless, the renderer does not keep the puffs' places, so work the drift out from the clock.)
	var before: float = room._time
	for i in 60:
		await process_frame
	var moved: float = (room.CLOUD_DRIFT * (room._time - before)).length()
	_check("the clouds drift by", moved > 3.0 and room._clouds.instance_count > 100, "%d puffs, moved %.1f m in a second" % [room._clouds.instance_count, moved])

	print("diorama_test: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

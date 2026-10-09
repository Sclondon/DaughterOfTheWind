extends SceneTree
## Checks the hair: however the frames fall (smooth, or slow and jerky), it never stretches.
## Run: godot --headless --path . -s res://tests/hair_test.gd

const Hair := preload("res://scripts/hair.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var head := Node3D.new()
	root.add_child(head)
	var hair: MeshInstance3D = Hair.new()
	hair.anchor = head
	root.add_child(hair)
	await process_frame
	var failed := 0
	# Fly the head at 30 m/s through a weave, at 60, 20 and 8 frames a second.
	for rate: float in [60.0, 20.0, 8.0]:
		var worst: float = 0.0
		var t: float = 0.0
		for i in int(rate * 6.0):
			t += 1.0 / rate
			head.position += Vector3(sin(t * 2.0) * 12.0, cos(t * 1.3) * 5.0, -30.0) / rate
			head.reset_physics_interpolation()
			hair._process(1.0 / rate)
			for strand: PackedVector3Array in hair._now:
				worst = maxf(worst, strand[0].distance_to(strand[hair.links]))
		var full: float = hair.link * hair.links
		var ok: bool = worst <= full * 1.02
		if not ok:
			failed += 1
		print("%s  the hair holds its length at %d frames a second  (longest %.2f m of %.2f m)" % ["PASS" if ok else "FAIL", int(rate), worst, full])
	print("hair_test: %d failed" % failed)
	quit(1 if failed > 0 else 0)

extends RefCounted
## Helpers for building meshes in code: the glider and the airships are all made from these.
## UVs come out in metres (around the ring, along the loft) so shaders can tile plates by size.


## Skins a row of rings into one smooth mesh. Every ring needs the same number of points, and the
## points must run counter-clockwise when you look back along the direction the rings advance in.
static func loft(rings: Array, capped: bool = true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = (rings[0] as PackedVector3Array).size()
	var w: int = n + 1
	var along: float = 0.0
	var last_mid := Vector3.ZERO
	for i in rings.size():
		var ring: PackedVector3Array = rings[i]
		var mid := Vector3.ZERO
		for p in ring:
			mid += p
		mid /= float(n)
		if i > 0:
			along += mid.distance_to(last_mid)
		last_mid = mid
		var around: float = 0.0
		for j in w:
			var p: Vector3 = ring[j % n]
			if j > 0:
				around += p.distance_to(ring[j - 1])
			st.set_uv(Vector2(around, along))
			st.add_vertex(p)
	for i in rings.size() - 1:
		for j in n:
			var a: int = i * w + j
			var b: int = a + 1
			var c: int = a + w
			var d: int = c + 1
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	if capped:
		_cap(st, rings[0], rings.size() * w, false)
		_cap(st, rings[rings.size() - 1], rings.size() * w + n + 1, true)
	st.generate_normals()
	return st.commit()


static func _cap(st: SurfaceTool, ring: PackedVector3Array, first: int, far_end: bool) -> void:
	var n: int = ring.size()
	var mid := Vector3.ZERO
	for p in ring:
		mid += p
	mid /= float(n)
	st.set_uv(Vector2.ZERO)
	st.add_vertex(mid)
	for p in ring:
		st.set_uv(Vector2(p.distance_to(mid), 0.0))
		st.add_vertex(p)
	for j in n:
		var a: int = first + 1 + j
		var b: int = first + 1 + (j + 1) % n
		st.add_index(first)
		st.add_index(b if far_end else a)
		st.add_index(a if far_end else b)


## Half thickness of a NACA 4-digit style aerofoil at u (0 = leading edge, 1 = trailing edge),
## for a section of thickness 1.
static func foil(u: float) -> float:
	return 5.0 * (0.2969 * sqrt(u) - 0.1260 * u - 0.3516 * u * u + 0.2843 * u * u * u - 0.1036 * u * u * u * u)


## Both halves of a wing, lofted along X. Forward is -Z. `rise` takes how far out along the wing
## a section is (0 at the root, 1 at the tip) and returns its height: that is what gives a gull wing.
static func wing(half_span: float, root_chord: float, tip_chord: float, sweep: float,
		thickness: float, rise: Callable, sections: int = 24, chord_steps: int = 8) -> ArrayMesh:
	var rings: Array = []
	for i in sections + 1:
		var s: float = lerpf(-1.0, 1.0, float(i) / float(sections))
		var a: float = absf(s)
		var chord: float = lerpf(root_chord, tip_chord, pow(a, 1.2)) * (1.0 - pow(a, 7.0) * 0.72)
		var lead: float = -root_chord * 0.4 + sweep * pow(a, 1.4) + (root_chord - chord) * 0.12
		var y0: float = rise.call(a)
		var thick: float = thickness * lerpf(1.0, 0.6, a) * chord
		var ring := PackedVector3Array()
		# Under the wing from the trailing edge to the nose, then back over the top.
		for k in chord_steps:
			var u: float = 0.5 * (1.0 + cos(PI * float(k) / float(chord_steps)))
			ring.append(Vector3(s * half_span, y0 - foil(u) * thick * 0.55, lead + u * chord))
		for k in chord_steps:
			var u: float = 0.5 * (1.0 - cos(PI * float(k) / float(chord_steps)))
			ring.append(Vector3(s * half_span, y0 + foil(u) * thick, lead + u * chord))
		rings.append(ring)
	return loft(rings)


## A flat panel with rounded edges, lofted along X: the glider's wing panels, flaps and round tips.
## `xs` are the X positions of its sections (ascending). `edges` takes an X and returns
## Vector2(leading edge z, trailing edge z) there, so the outline can be any shape. The panel thins
## where it narrows, which rounds off a tip like a pillow.
static func slab(xs: PackedFloat32Array, edges: Callable, thickness: float, steps: int = 6) -> ArrayMesh:
	var widest: float = 0.001
	for x in xs:
		var e: Vector2 = edges.call(x)
		widest = maxf(widest, e.y - e.x)
	var rings: Array = []
	for x in xs:
		var e: Vector2 = edges.call(x)
		var chord: float = maxf(e.y - e.x, 0.02)
		var mid: float = (e.x + e.y) * 0.5
		var half: float = thickness * 0.5 * sqrt(chord / widest)
		var ring := PackedVector3Array()
		# Under the panel from the trailing edge to the leading edge, then back over the top.
		for k in steps:
			var c: float = cos(PI * float(k) / float(steps))
			ring.append(Vector3(x, -half * 0.7 * sqrt(1.0 - pow(absf(c), 2.6)), mid + c * chord * 0.5))
		for k in steps:
			var c: float = -cos(PI * float(k) / float(steps))
			ring.append(Vector3(x, half * sqrt(1.0 - pow(absf(c), 2.6)), mid + c * chord * 0.5))
		rings.append(ring)
	return loft(rings)


## A hull lofted along Z, nose at -Z. `profile` takes t (0 at the nose, 1 at the tail) and returns
## Vector3(half width, half height, centre height). `power` above 2 squares the cross-section off;
## `belly` below 1 flattens the underside.
static func body(length: float, profile: Callable, around: int = 20, along: int = 24,
		power: float = 2.0, belly: float = 1.0) -> ArrayMesh:
	var rings: Array = []
	var e: float = 2.0 / power
	for i in along + 1:
		var t: float = float(i) / float(along)
		var shape: Vector3 = profile.call(t)
		var ring := PackedVector3Array()
		for j in around:
			# Start at the keel so the UV seam hides underneath.
			var ang: float = TAU * float(j) / float(around) - PI * 0.5
			var c: float = cos(ang)
			var s: float = sin(ang)
			var x: float = signf(c) * pow(absf(c), e) * shape.x
			var y: float = signf(s) * pow(absf(s), e) * shape.y
			if y < 0.0:
				y *= belly
			ring.append(Vector3(x, shape.z + y, lerpf(-0.5, 0.5, t) * length))
		rings.append(ring)
	return loft(rings)


## A round rod between two points (struts, arms, gun barrels).
static func rod(from: Vector3, to: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = from.distance_to(to) + radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 3
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	var dir: Vector3 = (to - from).normalized()
	var side: Vector3 = dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.UP).normalized()
	node.transform = Transform3D(Basis(side, dir, side.cross(dir)), (from + to) * 0.5)
	return node

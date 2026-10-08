extends Node3D
## The Windward Coast: the sea to the west, and to the east a wall of towering cliffs that runs
## north and south for ever. The cliffs climb out of the water in great steps, and the people live
## on the steps: every ledge is terraced fields, with hamlets and windmills built into the
## cliffside. The top is wild grass and woods. In one place a broad, gently sloping valley cuts
## down through the cliffs to a beach, and the castle stands in it with its town around it.
## The sea off the cliffs is a maze of rock spires and arches to weave through, and giant old
## trees stand in the valley and here and there along the cliffs.
##
## The shape of the land is one function, height_at(x, z). The ground is cut into square chunks
## that stream in around `focus` and are freed behind it: fine ones close by, coarse ones far off,
## none for open sea. Each chunk grows its own hamlets, windmills, trees and spires from a seed,
## so a place always has the same things in it.
##
## For the glider this node is both a solid and a wind:
##   hit(p, radius)  pushes it back out of the ground, the sea, spires, towers and windmills
##   wind_at(p)      the sea wind is pushed upward where it meets rising ground, so there is lift
##                   all along the cliffs to soar on, and sink behind the hills

const MeshKit := preload("res://scripts/mesh_kit.gd")
const TerrainShader := preload("res://shaders/terrain.gdshader")
const OceanShader := preload("res://shaders/ocean.gdshader")
const Toon := preload("res://scripts/toon.gd")

## The cliffs: how far in from the shore they reach (m), how many steps they climb in, how tall
## they are in all, and how much of each step is wall rather than ledge.
const CLIFF_WIDTH := 700.0
const TERRACES := 4
const CLIFF_HEIGHT := 720.0
const WALL_SHARE := 0.34
## The valley: where it meets the sea (z), and half its width there.
## shaders/ocean.gdshader repeats shore_x(), the valley and the sea bed, and shaders/terrain
## repeats river_z(): keep them in step.
const VALLEY_Z := 0.0
const VALLEY_HALF := 640.0
## How far up the valley the castle stands.
const CASTLE_INLAND := 1250.0
## The wind off the sea, blowing onto the cliffs.
const SEA_WIND := Vector3(8.0, 0.0, 1.0)

## Chunks: their side, the cell size of a fine and a coarse one, and how many chunks out from the
## focus are fine, have their buildings and trees, and exist at all.
const CHUNK := 1024.0
const CELL_FINE := 32.0
const CELL_COARSE := 64.0
const FINE_RADIUS := 2
const PROP_RADIUS := 4
const VIEW_RADIUS := 8
## Milliseconds of chunk building allowed per frame while flying.
const BUILD_BUDGET := 7.0
const OCEAN_SIZE := 34000.0

var focus: Node3D
var noise_tex: Texture2D
var sun_dir := Vector3.UP
var haze_color := Color(0.73, 0.85, 0.96)
var sky_color := Color(0.09, 0.29, 0.7)
var haze_distance := 8500.0
var world_seed := 414

## Where the castle stands (set in _ready).
var castle := Vector3.ZERO


class Chunk:
	var ground: MeshInstance3D  # null over open sea
	var fine := false
	var props: Node3D  # null until the focus has come within PROP_RADIUS
	var columns: Array = []
	var capsules: Array = []  # arches, as runs of [Vector3 from, Vector3 to, float radius]
	var arches := 0
	var great_trees := 0
	var houses := 0
	var ledge_houses := 0
	var windmills := 0
	var spires := 0


var _hills := FastNoiseLite.new()
var _woods := FastNoiseLite.new()
var _ground_mat: ShaderMaterial
var _rock_mat: ShaderMaterial
var _house_mat: ShaderMaterial
var _paints := {}
var _ocean: MeshInstance3D
var _chunks := {}  # Vector2i -> Chunk
var _queue: Array = []  # chunk keys waiting for work, nearest first
var _centre = null
# Upright things to bump into: [Vector3 foot, float height, float radius at the foot, float radius at the top].
# These are the castle's; each chunk keeps its own.
var _columns: Array = []
var _hubs: Array = []
var _box := BoxMesh.new()
var _prism := PrismMesh.new()
var _blob := SphereMesh.new()
var _crown := SphereMesh.new()
var _leaf_mat: ShaderMaterial


func _ready() -> void:
	_hills.seed = world_seed + 1
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 1.0 / 900.0
	_hills.fractal_octaves = 3
	_woods.seed = world_seed + 3
	_woods.frequency = 1.0 / 420.0
	_blob.radius = 1.0
	_blob.height = 2.0
	_blob.radial_segments = 7
	_blob.rings = 4

	_crown.radius = 1.0
	_crown.height = 2.0
	_crown.radial_segments = 14
	_crown.rings = 9
	_leaf_mat = Toon.tinted(110.0)

	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = TerrainShader
	_ground_mat.set_shader_parameter("noise_tex", noise_tex)
	_ground_mat.set_shader_parameter("valley_z", VALLEY_Z)
	_rock_mat = _ground_mat.duplicate() as ShaderMaterial
	_rock_mat.set_shader_parameter("use_farms", false)
	_house_mat = Toon.tinted(60.0)
	for paint: Array in [["cream", Color(0.9, 0.86, 0.76), 0.9], ["cap", Color(0.55, 0.25, 0.18), 0.7],
			["sail", Color(0.95, 0.93, 0.86), 0.8], ["timber", Color(0.35, 0.25, 0.18), 0.9],
			["stone", Color(0.76, 0.72, 0.64), 0.9], ["slate", Color(0.24, 0.33, 0.45), 0.6],
			["bark", Color(0.42, 0.31, 0.22), 0.9]]:
		_paints[paint[0]] = Toon.paint(paint[1], 45.0, true)

	var cx: float = shore_x(VALLEY_Z) + CASTLE_INLAND
	# Beside the stream, not in it.
	castle = Vector3(cx, 0.0, river_z(cx) + 210.0)
	castle.y = height_at(castle.x, castle.z)
	_build_ocean()
	_build_castle()
	if focus:
		prewarm()


## Where the glider starts: out over the sea, flying in toward the mouth of the valley.
func start_position() -> Vector3:
	return Vector3(shore_x(VALLEY_Z) - 2600.0, 430.0, VALLEY_Z + 500.0)


func start_heading() -> float:
	return -PI * 0.5 + 0.12


func _process(delta: float) -> void:
	for hub: Node3D in _hubs:
		hub.rotate_object_local(Vector3.BACK, delta * 0.9)
	if focus == null:
		return
	_ocean.position = Vector3(focus.global_position.x, 0.0, focus.global_position.z)
	_look_around()
	var began: int = Time.get_ticks_usec()
	while not _queue.is_empty() and float(Time.get_ticks_usec() - began) < BUILD_BUDGET * 1000.0:
		_work(_queue.pop_front())


## Build everything in range right now, instead of a little each frame.
func prewarm() -> void:
	_look_around()
	while not _queue.is_empty():
		_work(_queue.pop_front())


## What is standing right now, for the tests: chunks, houses (and how many of them are on the
## cliff ledges), windmills and spires.
func stats() -> Dictionary:
	var out := {"chunks": _chunks.size(), "houses": 0, "ledge_houses": 0, "windmills": 0, "spires": 0, "arches": 0, "great_trees": 0}
	for key: Vector2i in _chunks:
		var chunk: Chunk = _chunks[key]
		out["houses"] += chunk.houses
		out["ledge_houses"] += chunk.ledge_houses
		out["windmills"] += chunk.windmills
		out["spires"] += chunk.spires
		out["arches"] += chunk.arches
		out["great_trees"] += chunk.great_trees
	return out


# ----------------------------------------------------------------------------------------------
# The shape of the land

## Where the shoreline is (its x) at a given z. Made of plain sine waves so the ocean's shader
## can work out the very same line.
func shore_x(z: float) -> float:
	return 260.0 * sin(z / 1900.0 + 1.3) + 140.0 * sin(z / 830.0 + 4.1) + 60.0 * sin(z / 310.0 + 0.7)


## Metres inland from the shoreline (negative out at sea).
func inland(x: float, z: float) -> float:
	return x - shore_x(z)


## The middle of the valley (its z) at a given x: it winds a little as it goes inland.
func valley_mid(x: float) -> float:
	return VALLEY_Z + 260.0 * sin(x / 1700.0 + 0.5)


## Where the stream runs (its z) at a given x: down the middle of the valley, wandering.
func river_z(x: float) -> float:
	return valley_mid(x) + 55.0 * sin(x / 160.0 + 1.0)


## 0..1: how far into the valley a point is. 1 on its floor, 0 outside it. Inland its sides are
## ragged, with spurs and side-hollows, not a clean trough.
func valley(x: float, z: float) -> float:
	var d: float = maxf(inland(x, z), 0.0)
	var half: float = VALLEY_HALF + d * 0.08
	var ragged: float = _hills.get_noise_2d(x * 1.3 + 50.0, z * 1.3) * 0.26 * smoothstep(0.0, 300.0, d)
	return 1.0 - smoothstep(0.3, 1.0, absf(z - valley_mid(x)) / half + ragged)


## Height of the ground (or the sea bed, below zero) at a point.
func height_at(x: float, z: float) -> float:
	var d: float = inland(x, z)
	var v: float = valley(x, z)
	if d < 0.0:
		# The sea bed drops away fast under the cliffs, and shelves gently off the beach.
		return maxf(d * lerpf(0.9, 0.035, v), -120.0)
	# The cliffs: straight up out of the water, in steps. A wall, a ledge, a wall, a ledge... The
	# ledges wander (the noise), so they widen and pinch out instead of running like contour lines.
	var u: float = d / CLIFF_WIDTH
	var step_at: float = u * TERRACES + _hills.get_noise_2d(x * 0.7 + 300.0, z * 0.7) * 0.5 * smoothstep(0.08, 0.35, u)
	step_at = clampf(step_at, 0.0, float(TERRACES))
	var stairs: float = (floorf(step_at) + smoothstep(0.0, WALL_SHARE, step_at - floorf(step_at))) / float(TERRACES)
	var cliff: float = CLIFF_HEIGHT * (0.82 + 0.18 * _hills.get_noise_2d(x * 0.3 + 900.0, z * 0.3))
	# Above the last step, a tableland that rolls and climbs slowly inland.
	var high: float = stairs * cliff + smoothstep(CLIFF_WIDTH, CLIFF_WIDTH + 5000.0, d) * 150.0 \
			+ _hills.get_noise_2d(x, z) * 50.0 * smoothstep(CLIFF_WIDTH, CLIFF_WIDTH + 600.0, d)
	if v <= 0.0:
		return high
	# The valley floor: a beach, then a long gentle climb over hummocks and hollows, with the
	# stream in a dip down the middle.
	var rough: float = smoothstep(250.0, 700.0, d)
	var low: float = minf(d * 0.035, 10.0) + maxf(d - 280.0, 0.0) * 0.07 \
			+ _hills.get_noise_2d(x * 2.6, z * 2.6 + 700.0) * 19.0 * rough + _hills.get_noise_2d(x * 7.0 + 90.0, z * 7.0) * 5.0 * rough
	low -= 8.0 * exp(-pow((z - river_z(x)) / 36.0, 2.0)) * smoothstep(150.0, 400.0, d)
	# A knoll for the castle to stand on.
	low += 24.0 * exp(-Vector2(x - castle.x, z - castle.z).length_squared() / (210.0 * 210.0))
	return lerpf(high, minf(low, high), v)


## Which way the ground faces at a point.
func normal_at(x: float, z: float) -> Vector3:
	var e: float = 12.0
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e,
			height_at(x, z - e) - height_at(x, z + e)).normalized()


## 0..1: how much a point is farmland: the cliff's ledges and the valley floor. The top is left
## wild. (The ground mesh also keeps fields off the walls, by slope.)
func farm_at(x: float, z: float) -> float:
	var d: float = inland(x, z)
	var ledges: float = smoothstep(20.0, 60.0, d) * (1.0 - smoothstep(CLIFF_WIDTH * 0.97, CLIFF_WIDTH * 1.06, d))
	return maxf(ledges, smoothstep(0.55, 0.8, valley(x, z)) * smoothstep(330.0, 420.0, d))


## Is this a spot on one of the cliff's ledges, flat enough to build on?
func on_ledge(x: float, z: float) -> bool:
	var d: float = inland(x, z)
	return d > 60.0 and d < CLIFF_WIDTH * 0.95 and valley(x, z) < 0.05 and height_at(x, z) > 60.0 \
			and normal_at(x, z).y > 0.97


# ----------------------------------------------------------------------------------------------
# Streaming the ground

func _key_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CHUNK), floori(z / CHUNK))


func _look_around() -> void:
	var at: Vector2i = _key_of(focus.global_position.x, focus.global_position.z)
	if _centre != null and (_centre as Vector2i) == at:
		return
	_centre = at
	for key: Vector2i in _chunks.keys():
		if maxi(absi(key.x - at.x), absi(key.y - at.y)) > VIEW_RADIUS + 1:
			var old: Chunk = _chunks[key]
			if old.ground:
				old.ground.queue_free()
			if old.props:
				old.props.queue_free()
			_chunks.erase(key)
	_queue.clear()
	for dz in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
		for dx in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
			var key := Vector2i(at.x + dx, at.y + dz)
			if _needs_work(key):
				_queue.append(key)
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - at).length_squared() < (b - at).length_squared())


func _ring(key: Vector2i) -> int:
	var at: Vector2i = _centre
	return maxi(absi(key.x - at.x), absi(key.y - at.y))


func _needs_work(key: Vector2i) -> bool:
	var chunk: Chunk = _chunks.get(key)
	if chunk == null:
		return true
	var ring: int = _ring(key)
	if chunk.props == null and ring <= PROP_RADIUS:
		return true
	# Fine close by; back to coarse only once well clear, so a chunk on the border does not flip.
	if chunk.ground and not chunk.fine and ring <= FINE_RADIUS:
		return true
	return chunk.ground != null and chunk.fine and ring > FINE_RADIUS + 1


## Bring one chunk up to date: make it, refine or coarsen its ground, or grow its buildings.
func _work(key: Vector2i) -> void:
	var ring: int = _ring(key)
	var chunk: Chunk = _chunks.get(key)
	if chunk == null:
		chunk = Chunk.new()
		_chunks[key] = chunk
		chunk.fine = ring <= FINE_RADIUS
		chunk.ground = _build_ground(key, chunk.fine)
	elif chunk.ground and ((not chunk.fine and ring <= FINE_RADIUS) or (chunk.fine and ring > FINE_RADIUS + 1)):
		chunk.ground.queue_free()
		chunk.fine = ring <= FINE_RADIUS
		chunk.ground = _build_ground(key, chunk.fine)
	if chunk.props == null and ring <= PROP_RADIUS:
		_build_props(key, chunk)


## The ground mesh for one chunk, or null if it is all open sea. It has a skirt hanging from its
## edges, so no gap shows where a fine chunk meets a coarse one.
func _build_ground(key: Vector2i, fine: bool) -> MeshInstance3D:
	var x0: float = key.x * CHUNK
	var z0: float = key.y * CHUNK
	var dry := false
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0.5), Vector2(1, 0.5)]:
		if inland(x0 + corner.x * CHUNK, z0 + corner.y * CHUNK) > -40.0:
			dry = true
	if not dry:
		return null

	var cell: float = CELL_FINE if fine else CELL_COARSE
	var n: int = int(CHUNK / cell)
	# Heights on the chunk's grid plus one cell all round (for the slopes at the edges).
	var w: int = n + 3
	var heights := PackedFloat32Array()
	heights.resize(w * w)
	for j in w:
		for i in w:
			heights[j * w + i] = maxf(height_at(x0 + (i - 1) * cell, z0 + (j - 1) * cell), -8.0)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(w * w)
	normals.resize(w * w)
	colors.resize(w * w)
	for j in w:
		for i in w:
			# The outer ring is the skirt: the same place as the edge, hung lower.
			var ii: int = clampi(i, 1, n + 1)
			var jj: int = clampi(j, 1, n + 1)
			var x: float = x0 + (ii - 1) * cell
			var z: float = z0 + (jj - 1) * cell
			var h: float = heights[jj * w + ii]
			var skirt: bool = ii != i or jj != j
			var k: int = j * w + i
			verts[k] = Vector3(x, h - (cell * 1.5 if skirt else 0.0), z)
			var norm := Vector3(heights[jj * w + ii - 1] - heights[jj * w + ii + 1], 2.0 * cell,
					heights[(jj - 1) * w + ii] - heights[(jj + 1) * w + ii]).normalized()
			normals[k] = norm
			# Red carries the farmland to the shader, green the beach sand, blue where the stream may run.
			var flat: float = smoothstep(0.88, 0.96, norm.y)
			var farm: float = farm_at(x, z) * flat if h > 12.0 else 0.0
			var in_valley: float = valley(x, z)
			var sand: float = in_valley * (1.0 - smoothstep(7.0, 13.0, h))
			colors[k] = Color(farm, sand, in_valley * smoothstep(110.0, 260.0, inland(x, z)))

	var indices := PackedInt32Array()
	for j in w - 1:
		for i in w - 1:
			var a: int = j * w + i
			indices.append_array(PackedInt32Array([a, a + 1, a + w, a + 1, a + w + 1, a + w]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	ground.material_override = _ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	return ground


func _build_ocean() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(OCEAN_SIZE, OCEAN_SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = OceanShader
	mat.set_shader_parameter("noise_tex", noise_tex)
	mat.set_shader_parameter("sun_dir", sun_dir)
	mat.set_shader_parameter("haze_color", haze_color)
	mat.set_shader_parameter("sky_color", sky_color.lerp(haze_color, 0.45))
	mat.set_shader_parameter("haze_distance", haze_distance)
	_ocean = MeshInstance3D.new()
	_ocean.mesh = plane
	_ocean.material_override = mat
	_ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# It follows the glider every frame, so it must not be physics-interpolated.
	_ocean.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_ocean)


# ----------------------------------------------------------------------------------------------
# What grows on a chunk

## A random point in a chunk that passes `test` (called with x, z), or Vector3.INF.
func _find(rng: RandomNumberGenerator, key: Vector2i, test: Callable, tries: int) -> Vector3:
	for i in tries:
		var x: float = (key.x + rng.randf()) * CHUNK
		var z: float = (key.y + rng.randf()) * CHUNK
		if test.call(x, z):
			return Vector3(x, height_at(x, z), z)
	return Vector3.INF


func _on_rim(x: float, z: float) -> bool:
	var d: float = inland(x, z)
	return d > CLIFF_WIDTH * 1.02 and d < CLIFF_WIDTH * 1.25 and valley(x, z) < 0.05 and normal_at(x, z).y > 0.95


func _on_valley_floor(x: float, z: float) -> bool:
	return valley(x, z) > 0.75 and inland(x, z) > 420.0 and normal_at(x, z).y > 0.965 \
			and absf(z - river_z(x)) > 45.0 and Vector2(x - castle.x, z - castle.z).length() > 330.0


func _build_props(key: Vector2i, chunk: Chunk) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(key.x, key.y, world_seed))
	var holder := Node3D.new()
	add_child(holder)
	chunk.props = holder
	var x0: float = key.x * CHUNK
	var z0: float = key.y * CHUNK
	var mid_d: float = inland(x0 + CHUNK * 0.5, z0 + CHUNK * 0.5)
	if mid_d < -1600.0:
		return
	var walls: Array = []  # [Transform3D, Color] for each house body
	var roofs: Array = []
	var trees: Array = []
	var crowns: Array = []

	if mid_d > -CHUNK and mid_d < CLIFF_WIDTH + CHUNK:
		# Hamlets strung along the ledges. Houses only land where the ledge is flat, so each
		# hamlet follows its shelf of the cliff.
		for i in 2:
			var heart: Vector3 = _find(rng, key, on_ledge, 40)
			if heart == Vector3.INF:
				continue
			for k in rng.randi_range(7, 14):
				var at := Vector2(heart.x, heart.z) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10.0, 120.0)
				_add_house(at, rng, chunk, walls, roofs)
		# Windmills: out on the ledges among the fields, and on the rim at the very top.
		for i in 2:
			var on_top: bool = i == 1 and rng.randf() < 0.5
			var at: Vector3 = _find(rng, key, _on_rim if on_top else on_ledge, 30)
			if at != Vector3.INF and not _crowded(chunk.columns, at.x, at.z, 200.0):
				_add_windmill(holder, chunk, at, rng.randf_range(2.0, 3.2), rng)

	# Farmsteads on the valley floor.
	for i in 2:
		var stead: Vector3 = _find(rng, key, _on_valley_floor, 12)
		if stead != Vector3.INF:
			for k in rng.randi_range(2, 5):
				_add_house(Vector2(stead.x, stead.z) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(8.0, 50.0),
						rng, chunk, walls, roofs)

	# Trees: woods on the wild top, the odd tree among the fields on the ledges and in the valley.
	for i in 90:
		var x: float = x0 + rng.randf() * CHUNK
		var z: float = z0 + rng.randf() * CHUNK
		var d: float = inland(x, z)
		var wild: bool = d > CLIFF_WIDTH * 1.05 and valley(x, z) < 0.3
		if d < 40.0 or (not wild and rng.randf() > 0.14) or (wild and _woods.get_noise_2d(x, z) < 0.05):
			continue
		if height_at(x, z) < 14.0 or normal_at(x, z).y < 0.9:
			continue
		if absf(z - river_z(x)) < 22.0 and valley(x, z) > 0.3:
			continue
		var r: float = rng.randf_range(6.0, 13.0)
		var green := Color(0.16, 0.33, 0.14).lerp(Color(0.3, 0.46, 0.16), rng.randf())
		trees.append([Transform3D(Basis.from_scale(Vector3(r, r * rng.randf_range(1.0, 1.5), r)),
				Vector3(x, height_at(x, z) + r * 0.6, z)), green])

	# A giant old tree: in the valley most of all, now and then on a ledge or the top.
	var tx: float = x0 + rng.randf() * CHUNK
	var tz: float = z0 + rng.randf() * CHUNK
	var td: float = inland(tx, tz)
	if td > 80.0 and normal_at(tx, tz).y > 0.94 and absf(tz - river_z(tx)) > 60.0 \
			and Vector2(tx - castle.x, tz - castle.z).length() > 420.0:
		var in_valley: bool = valley(tx, tz) > 0.6 and td > 380.0
		if rng.randf() < (0.75 if in_valley else 0.2):
			_add_great_tree(holder, chunk.columns, Vector3(tx, height_at(tx, tz), tz),
					rng.randf_range(48.0, 88.0) if in_valley else rng.randf_range(34.0, 62.0), rng, crowns)
			chunk.great_trees += 1

	# The sea off the cliffs: a maze of stacks and arches, thickest close in, thinning out to sea.
	# The way in to the beach is kept clear.
	if mid_d < 0.0 and mid_d > -2700.0:
		var crowd: float = 1.0 - smoothstep(1500.0, 2700.0, -mid_d)
		for i in int(round(float(rng.randi_range(4, 8)) * crowd)):
			var px: float = x0 + rng.randf() * CHUNK
			var pz: float = z0 + rng.randf() * CHUNK
			if inland(px, pz) > -110.0 or valley(px, pz) > 0.0 or _crowded(chunk.columns, px, pz, 95.0):
				continue
			var tall: float = rng.randf_range(80.0, 430.0) * lerpf(0.55, 1.0, crowd)
			_add_spire(holder, chunk, Vector3(px, -25.0, pz), tall + 25.0, tall * rng.randf_range(0.13, 0.22) + 15.0, rng)
		for i in 2:
			var ax: float = x0 + rng.randf_range(0.15, 0.85) * CHUNK
			var az: float = z0 + rng.randf_range(0.15, 0.85) * CHUNK
			if rng.randf() < (0.8 if i == 0 else 0.4) * crowd and inland(ax, az) < -260.0 and valley(ax, az) <= 0.0:
				_add_arch(holder, chunk, Vector3(ax, 0.0, az), rng)

	# A pinnacle on the high ground.
	var sx: float = x0 + rng.randf() * CHUNK
	var sz: float = z0 + rng.randf() * CHUNK
	var sd: float = inland(sx, sz)
	if sd > CLIFF_WIDTH + 500.0 and valley(sx, sz) <= 0.0 and rng.randf() < 0.14:
		var tall: float = rng.randf_range(130.0, 260.0)
		_add_spire(holder, chunk, Vector3(sx, height_at(sx, sz) - 15.0, sz), tall, tall * rng.randf_range(0.13, 0.2) + 16.0, rng)

	_scatter(holder, walls, _box)
	_scatter(holder, roofs, _prism)
	_scatter(holder, trees, _blob)
	_scatter(holder, crowns, _crown, _leaf_mat)
	chunk.houses = walls.size()


func _crowded(columns: Array, x: float, z: float, gap: float) -> bool:
	for c: Array in columns:
		var foot: Vector3 = c[0]
		if Vector2(foot.x - x, foot.z - z).length() < gap:
			return true
	return false


func _add_house(at: Vector2, rng: RandomNumberGenerator, chunk: Chunk, walls: Array, roofs: Array) -> void:
	if normal_at(at.x, at.y).y < 0.955 or height_at(at.x, at.y) < 14.0:
		return
	if absf(at.y - river_z(at.x)) < 26.0 and valley(at.x, at.y) > 0.3:
		return
	if chunk and inland(at.x, at.y) < CLIFF_WIDTH and valley(at.x, at.y) < 0.05:
		chunk.ledge_houses += 1
	var size := Vector3(rng.randf_range(8.0, 14.0), rng.randf_range(4.5, 6.5), rng.randf_range(6.0, 9.0))
	var ground: float = height_at(at.x, at.y)
	var turn := Basis(Vector3.UP, rng.randf() * TAU)
	var wall := Color(0.9, 0.86, 0.76).lerp(Color(0.72, 0.66, 0.56), rng.randf())
	var tile: Color = [Color(0.62, 0.27, 0.18), Color(0.5, 0.3, 0.2), Color(0.32, 0.36, 0.42)][rng.randi() % 3]
	walls.append([Transform3D(turn.scaled_local(size), Vector3(at.x, ground + size.y * 0.5 - 0.5, at.y)), wall])
	var pitch: float = size.z * 0.45
	roofs.append([Transform3D(turn.scaled_local(Vector3(size.x + 1.2, pitch, size.z + 1.4)),
			Vector3(at.x, ground + size.y - 0.5 + pitch * 0.5, at.y)), tile])


## Many copies of one mesh, each with its own transform and colour, drawn in one go.
func _scatter(holder: Node3D, items: Array, mesh: Mesh, material: Material = null) -> void:
	if items.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material if material else _house_mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(node)


## A spire's radius, as a share of its foot, at a share t of the way up.
func _taper(t: float) -> float:
	return 1.0 - 0.72 * pow(t, 1.25)


func _add_spire(holder: Node3D, chunk: Chunk, foot: Vector3, height: float, radius: float, rng: RandomNumberGenerator) -> void:
	var sides: int = 11
	var levels: int = 9
	var lean := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * radius * 0.35
	var twist: float = rng.randf() * TAU
	var rings: Array = []
	for i in levels + 1:
		var t: float = float(i) / float(levels)
		var ring := PackedVector3Array()
		var mid := Vector2(lean.x, lean.y) * t * t
		for j in sides:
			# Counter-clockwise seen from above, as MeshKit.loft wants for rings that climb.
			var a: float = TAU * float(j) / float(sides) + twist
			var r: float = radius * _taper(t) * rng.randf_range(0.8, 1.15)
			ring.append(Vector3(mid.x + cos(a) * r, t * height, mid.y - sin(a) * r))
		rings.append(ring)
	var node := MeshInstance3D.new()
	node.mesh = MeshKit.loft(rings)
	node.material_override = _rock_mat
	node.position = foot
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(node)
	chunk.columns.append([foot, height, radius * 1.05, radius * _taper(1.0) * 1.1 + lean.length()])
	chunk.spires += 1


## A rock arch standing in the sea: a thick tube of rock bent over from one foot to the other,
## wide enough to fly through. It collides as a run of capsules along its curve.
func _add_arch(holder: Node3D, chunk: Chunk, at: Vector3, rng: RandomNumberGenerator) -> void:
	var span: float = rng.randf_range(140.0, 320.0)
	var rise: float = span * rng.randf_range(0.55, 0.95)
	var thick: float = rng.randf_range(16.0, 32.0)
	var yaw: float = rng.randf() * TAU
	var across := Vector3(cos(yaw), 0.0, sin(yaw))
	var side := Vector3(-sin(yaw), 0.0, cos(yaw))
	# The curve from foot to foot. Both feet go well under the water.
	var path := func(t: float) -> Vector3:
		var a: float = PI * t
		return at + across * (-cos(a) * span * 0.5) + Vector3.UP * (pow(maxf(sin(a), 0.0), 0.75) * (rise + 30.0) - 30.0)
	var steps: int = 14
	var sides: int = 9
	var rings: Array = []
	var middles: Array = []
	var radii: Array = []
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var mid: Vector3 = path.call(t)
		var along: Vector3 = ((path.call(minf(t + 0.02, 1.0)) as Vector3) - (path.call(maxf(t - 0.02, 0.0)) as Vector3)).normalized()
		# Thick legs, thinner over the top.
		var r: float = thick * (1.4 - 0.5 * sin(PI * t))
		var out: Vector3 = side.cross(along)
		var ring := PackedVector3Array()
		for j in sides:
			var ang: float = TAU * float(j) / float(sides)
			ring.append(mid + (out * cos(ang) + side * sin(ang)) * r * rng.randf_range(0.82, 1.16))
		rings.append(ring)
		middles.append(mid)
		radii.append(r)
	var node := MeshInstance3D.new()
	node.mesh = MeshKit.loft(rings)
	node.material_override = _rock_mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(node)
	for i in range(0, steps, 2):
		chunk.capsules.append([middles[i], middles[i + 2], ((radii[i] as float) + (radii[i + 2] as float)) * 0.5])
	chunk.arches += 1


## A giant old tree: a great flared trunk and a crown of big round masses of leaves. `reach` is
## the crown's radius. The leaf masses go into `crowns` to be drawn with the rest of the chunk's.
func _add_great_tree(holder: Node3D, columns: Array, at: Vector3, reach: float, rng: RandomNumberGenerator, crowns: Array) -> void:
	var trunk_h: float = reach * 0.8
	var girth: float = reach * 0.13
	var rings: Array = []
	var twist: float = rng.randf() * TAU
	for i in 7:
		var t: float = float(i) / 6.0
		# Flared at the roots, a little wider again where the boughs spread.
		var r: float = girth * (1.0 + 1.5 * pow(1.0 - t, 3.0) + 0.5 * pow(t, 4.0))
		var ring := PackedVector3Array()
		for j in 10:
			var a: float = TAU * float(j) / 10.0 + twist
			ring.append(Vector3(cos(a) * r * rng.randf_range(0.85, 1.15), t * trunk_h - 6.0, -sin(a) * r * rng.randf_range(0.85, 1.15)))
		rings.append(ring)
	var trunk := MeshInstance3D.new()
	trunk.mesh = MeshKit.loft(rings)
	trunk.material_override = _paints["bark"]
	trunk.position = at
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(trunk)
	# The crown: a low dome of leaf masses, biggest in the middle.
	var heart: Vector3 = at + Vector3.UP * (trunk_h + reach * 0.12)
	for i in 13:
		var out: float = sqrt(rng.randf()) * 0.85 if i > 0 else 0.0
		var ang: float = rng.randf() * TAU
		var r: float = reach * lerpf(0.52, 0.3, out) * rng.randf_range(0.85, 1.15)
		var where: Vector3 = heart + Vector3(cos(ang) * out * reach, (1.0 - out * out) * reach * 0.34 + rng.randf_range(-0.06, 0.06) * reach, sin(ang) * out * reach)
		var green := Color(0.2, 0.4, 0.15).lerp(Color(0.42, 0.58, 0.2), rng.randf())
		crowns.append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r, r * 0.78, r)), where), green])
	columns.append([at - Vector3.UP * 6.0, trunk_h + 6.0, girth * 2.0, girth * 1.2])
	columns.append([at + Vector3.UP * trunk_h * 0.85, reach * 0.75, reach * 0.9, reach * 0.35])


## A round stone tower with a pointed roof. Returns the height of the top of its walls.
func _add_tower(holder: Node3D, columns: Array, at: Vector2, height: float, radius: float) -> float:
	var ground: float = height_at(at.x, at.y) - 6.0
	var shaft := CylinderMesh.new()
	shaft.top_radius = radius * 0.86
	shaft.bottom_radius = radius
	shaft.height = height
	shaft.radial_segments = 12
	var body := MeshInstance3D.new()
	body.mesh = shaft
	body.material_override = _paints["stone"]
	body.position = Vector3(at.x, ground + height * 0.5, at.y)
	holder.add_child(body)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius * 1.1
	cone.height = radius * 2.6
	cone.radial_segments = 12
	var roof := MeshInstance3D.new()
	roof.mesh = cone
	roof.material_override = _paints["slate"]
	roof.position = Vector3(at.x, ground + height + cone.height * 0.5, at.y)
	holder.add_child(roof)
	columns.append([Vector3(at.x, ground, at.y), height + cone.height, radius, radius * 0.4])
	return ground + height


## Four sails on a hub, turning in the wind. The hub's -Z faces the wind.
func _add_sails(parent: Node3D, at: Vector3, reach: float, rng: RandomNumberGenerator) -> void:
	var hub := Node3D.new()
	hub.position = at
	hub.rotation.z = rng.randf() * TAU
	parent.add_child(hub)
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.z = TAU * float(i) / 4.0
		hub.add_child(arm)
		arm.add_child(MeshKit.rod(Vector3.ZERO, Vector3(0, reach, 0), reach * 0.014, _paints["timber"]))
		var vane := MeshInstance3D.new()
		var cloth := BoxMesh.new()
		cloth.size = Vector3(reach * 0.21, reach * 0.75, 0.1)
		vane.mesh = cloth
		vane.material_override = _paints["sail"]
		vane.position = Vector3(reach * 0.11, reach * 0.61, 0.0)
		arm.add_child(vane)
	_hubs.append(hub)
	# Forget the hub when its chunk is let go.
	hub.tree_exiting.connect(func() -> void: _hubs.erase(hub))


func _add_windmill(holder: Node3D, chunk: Chunk, at: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var mill := Node3D.new()
	mill.position = at - Vector3.UP
	# Face into the sea wind.
	mill.rotation.y = atan2(SEA_WIND.x, SEA_WIND.z) + rng.randf_range(-0.15, 0.15)
	mill.scale = Vector3.ONE * size
	holder.add_child(mill)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 2.3
	shaft.bottom_radius = 3.8
	shaft.height = 16.0
	shaft.radial_segments = 10
	var body := MeshInstance3D.new()
	body.mesh = shaft
	body.material_override = _paints["cream"]
	body.position.y = 8.0
	mill.add_child(body)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.9
	cone.height = 4.2
	cone.radial_segments = 10
	var roof := MeshInstance3D.new()
	roof.mesh = cone
	roof.material_override = _paints["cap"]
	roof.position.y = 18.1
	mill.add_child(roof)
	_add_sails(mill, Vector3(0, 15.0, -3.1), 11.5, rng)
	chunk.columns.append([mill.position, 19.0 * size, 4.0 * size, 2.5 * size])
	chunk.windmills += 1


# ----------------------------------------------------------------------------------------------
# The castle

## The castle in the valley: a square of walls with a tower at each corner and a gatehouse facing
## the sea, a keep inside with a turret at each corner, and one great tower rising out of the
## keep with a windmill's sails turning on its seaward face. The town stands around it.
func _build_castle() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 99
	var holder := Node3D.new()
	add_child(holder)
	var here := Vector2(castle.x, castle.z)
	var half: float = 105.0
	var top: float = castle.y + 30.0

	# The curtain wall, sunk into the knoll so it stays level on sloping ground.
	for side: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var wall := MeshInstance3D.new()
		var slab := BoxMesh.new()
		slab.size = Vector3(9.0 if side.x != 0.0 else half * 2.0, 70.0, half * 2.0 if side.x != 0.0 else 9.0)
		wall.mesh = slab
		wall.material_override = _paints["stone"]
		wall.position = Vector3(here.x + side.x * half, top - 35.0, here.y + side.y * half)
		holder.add_child(wall)
	for corner: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		_add_tower(holder, _columns, here + corner * half, 78.0, 15.0)
	# The gatehouse: two towers close together in the seaward wall.
	for side: float in [-1.0, 1.0]:
		_add_tower(holder, _columns, here + Vector2(-half, side * 17.0), 66.0, 10.0)

	# The keep.
	var keep := MeshInstance3D.new()
	var block := BoxMesh.new()
	block.size = Vector3(84.0, 96.0, 70.0)
	keep.mesh = block
	keep.material_override = _paints["stone"]
	keep.position = Vector3(here.x + 12.0, castle.y + 38.0, here.y)
	holder.add_child(keep)
	var gable := MeshInstance3D.new()
	gable.mesh = _prism
	gable.material_override = _paints["slate"]
	gable.transform = Transform3D(Basis.from_scale(Vector3(92.0, 34.0, 76.0)), keep.position + Vector3(0, 48.0 + 17.0, 0))
	holder.add_child(gable)
	_columns.append([Vector3(keep.position.x, castle.y - 10.0, keep.position.z), 130.0, 55.0, 30.0])
	for corner: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		_add_tower(holder, _columns, Vector2(keep.position.x, keep.position.z) + Vector2(corner.x * 42.0, corner.y * 35.0), 118.0, 10.0)
	# The great tower, with the sails.
	var great := Vector2(keep.position.x + 8.0, keep.position.z)
	var great_top: float = _add_tower(holder, _columns, great, 205.0, 19.0)
	var mount := Node3D.new()
	mount.position = Vector3(great.x, great_top - 30.0, great.y)
	mount.rotation.y = atan2(SEA_WIND.x, SEA_WIND.z)
	holder.add_child(mount)
	_add_sails(mount, Vector3(0, 0, -19.5), 46.0, rng)

	# The great tree: older than the castle, across the stream from it.
	var crowns: Array = []
	var tree_x: float = castle.x - 120.0
	var tree_z: float = river_z(tree_x) - 260.0
	_add_great_tree(holder, _columns, Vector3(tree_x, height_at(tree_x, tree_z), tree_z), 125.0, rng, crowns)
	_scatter(holder, crowns, _crown, _leaf_mat)

	# The town, outside the walls.
	var walls: Array = []
	var roofs: Array = []
	for k in 150:
		var out: float = rng.randf_range(half + 40.0, half + 230.0)
		_add_house(here + Vector2.from_angle(rng.randf() * TAU) * out, rng, null, walls, roofs)
	_scatter(holder, walls, _box)
	_scatter(holder, roofs, _prism)


# ----------------------------------------------------------------------------------------------
# For the glider

func _near_columns(world: Vector3) -> Array:
	var out: Array = []
	if Vector2(world.x - castle.x, world.z - castle.z).length() < 700.0:
		out.append_array(_columns)
	var at: Vector2i = _key_of(world.x, world.z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var chunk: Chunk = _chunks.get(Vector2i(at.x + dx, at.y + dz))
			if chunk:
				out.append_array(chunk.columns)
	return out


## If a ball at a world position is in the ground, the sea, a spire, a tower or a windmill,
## returns the push that gets it out. Vector3.ZERO means it is in clear air.
func hit(world: Vector3, radius: float) -> Vector3:
	var ground: float = height_at(world.x, world.z)
	var low: float = world.y - radius
	if low < maxf(ground, 0.0):
		if ground <= 0.0:
			return Vector3.UP * -low
		var n: Vector3 = normal_at(world.x, world.z)
		return n * maxf((ground - low) * n.y, 0.05)
	for c: Array in _near_columns(world):
		var foot: Vector3 = c[0]
		var height: float = c[1]
		var up: float = world.y - foot.y
		if up < -radius or up > height + radius:
			continue
		var reach: float = lerpf(c[2], c[3], clampf(up / height, 0.0, 1.0)) + radius
		var out := Vector3(world.x - foot.x, 0.0, world.z - foot.z)
		if out.length() < reach:
			if out.length() < 0.01:
				out = Vector3.RIGHT
			return out.normalized() * (reach - out.length())
	var at: Vector2i = _key_of(world.x, world.z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var chunk: Chunk = _chunks.get(Vector2i(at.x + dx, at.y + dz))
			if chunk == null:
				continue
			for c: Array in chunk.capsules:
				var nearest: Vector3 = Geometry3D.get_closest_point_to_segment(world, c[0], c[1])
				var away: Vector3 = world - nearest
				var reach: float = float(c[2]) + radius
				if away.length() < reach:
					if away.length() < 0.01:
						away = Vector3.UP
					return away.normalized() * (reach - away.length())
	return Vector3.ZERO


## The air's velocity at a world point: where the sea wind meets rising ground it is pushed up
## (ridge lift), and it sinks again in the lee. It fades with height above the ground.
func wind_at(world: Vector3) -> Vector3:
	var e: float = 110.0
	var x: float = world.x
	var z: float = world.z
	var slope := Vector2(maxf(height_at(x + e, z), 0.0) - maxf(height_at(x - e, z), 0.0),
			maxf(height_at(x, z + e), 0.0) - maxf(height_at(x, z - e), 0.0)) / (2.0 * e)
	var above: float = maxf(world.y - maxf(height_at(x, z), 0.0), 0.0)
	var lift: float = clampf((SEA_WIND.x * slope.x + SEA_WIND.z * slope.y) * 1.6, -5.0, 13.0)
	return Vector3(0.0, lift * exp(-above / 260.0), 0.0)

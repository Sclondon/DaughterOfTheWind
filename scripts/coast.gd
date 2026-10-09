extends Node3D
## The Windward Coast: the sea to the west, and to the east a wall of towering cliffs that runs
## north and south for ever. The cliffs climb out of the water in great broken steps, ribbed with
## buttresses and gullies, hung with outcrops and standing rock towers. People live in them:
## cities are built into the cliff face, houses stacked on houses up the rock, laced together
## with stairways and arched viaducts, with towers standing over them. Here and there a ledge
## is still terraced fields. The top is wild grass and woods.
##
## In one place a broad, gently sloping valley cuts down through the cliffs to a beach, and the
## castle stands in it with its town and a grove of giant old trees. Every couple of kilometres
## along the coast a trench does the same, far narrower: a slot of sea running in between sheer
## walls, crossed by a high arched bridge, to fly up and under.
##
## The sea off the cliffs is a maze of rock spires and arches to weave through. Far inland, behind
## it all, stands a painted backdrop (shaders/backdrop): a wood of great trees, hills, and two
## ranges of mountains, drawn as flat cut-outs.
##
## The shape of the land is one function, height_at(x, z). The ground is cut into square chunks
## that stream in around `focus` and are freed behind it: fine ones close by, coarse ones far off,
## none for open sea. Each chunk grows its own city, towers, rocks, trees and spires from a seed,
## so a place always has the same things in it.
##
## For the glider this node is both a solid and a wind:
##   hit(p, radius)  pushes it back out of the ground, the sea, spires, towers, bridges and windmills
##   wind_at(p)      the sea wind is pushed upward where it meets rising ground, so there is lift
##                   all along the cliffs to soar on, and sink behind the hills

const MeshKit := preload("res://scripts/mesh_kit.gd")
const TerrainShader := preload("res://shaders/terrain.gdshader")
const OceanShader := preload("res://shaders/ocean.gdshader")
const BuildingShader := preload("res://shaders/building.gdshader")
const BackdropShader := preload("res://shaders/backdrop.gdshader")
const Toon := preload("res://scripts/toon.gd")

## The cliffs: how far in from the shore they reach (m), how many steps they climb in, how tall
## they are in all, and how much of each step is wall rather than ledge.
const CLIFF_WIDTH := 700.0
const TERRACES := 4
const CLIFF_HEIGHT := 720.0
const WALL_SHARE := 0.34
## The valley: where it meets the sea (z), and half its width there.
## shaders/ocean.gdshader repeats shore_x(), the valley, the trenches and the sea bed, and
## shaders/terrain repeats river_z(): keep them in step.
const VALLEY_Z := 0.0
const VALLEY_HALF := 640.0
## The trenches: one to every this many metres of coast (none where the valley is), half their
## width at the mouth, and how far in the sea runs before the floor climbs out of it.
const TRENCH_SPACING := 2200.0
const TRENCH_HALF := 190.0
const TRENCH_WATER := 380.0
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
## Points along one side of a fine chunk's grid of heights: its cells, plus one all round.
const GRID_W := 35
## Milliseconds of chunk building allowed per frame while flying.
const BUILD_BUDGET := 7.0
const OCEAN_SIZE := 34000.0
## The painted backdrop: how far inland each of its four flats stands (the wood, the hills, the
## mountains, the far range), and the nearest each is let come to the glider. The last is the
## size of the piece of sphere they are drawn on (inside the camera's range).
const BACKDROP_INLAND := [7000.0, 10000.0, 15000.0, 23000.0]
const BACKDROP_KEEP := [6500.0, 9500.0, 14000.0, 21000.0]
const BACKDROP_RADIUS := 14500.0

## Plaster and roof tiles for the cities.
const PLASTER := [Color(0.93, 0.88, 0.76), Color(0.95, 0.94, 0.9), Color(0.9, 0.74, 0.5), Color(0.87, 0.66, 0.57),
		Color(0.82, 0.74, 0.6), Color(0.74, 0.81, 0.84), Color(0.92, 0.82, 0.62)]
const TILES := [Color(0.7, 0.33, 0.2), Color(0.56, 0.27, 0.2), Color(0.62, 0.3, 0.16), Color(0.3, 0.38, 0.5), Color(0.25, 0.44, 0.45)]
const STONE := Color(0.72, 0.68, 0.6)

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
	# Heights on the fine grid (GRID_W x GRID_W, one cell beyond the chunk all round). Empty
	# until something needs it.
	var grid := PackedFloat32Array()
	var columns: Array = []
	var capsules: Array = []  # arches and bridge decks, as runs of [Vector3 from, Vector3 to, float radius]
	var arches := 0
	var great_trees := 0
	var houses := 0
	var city_houses := 0
	var towers := 0
	var stairs := 0
	var bridges := 0
	var windmills := 0
	var spires := 0
	var rock_towers := 0
	var outcrops := 0


var _hills := FastNoiseLite.new()
var _woods := FastNoiseLite.new()
var _ground_mat: ShaderMaterial
var _rock_mat: ShaderMaterial
var _outcrop_mat: ShaderMaterial
var _house_mat: ShaderMaterial
var _building_mat: ShaderMaterial
var _backdrop_mat: ShaderMaterial
var _paints := {}
var _ocean: MeshInstance3D
var _backdrop: MeshInstance3D
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
var _arch: ArrayMesh
var _rock: ArrayMesh
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
	_leaf_mat = Toon.tinted()
	_arch = _make_arch()
	_rock = _make_rock()

	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = TerrainShader
	_ground_mat.set_shader_parameter("noise_tex", noise_tex)
	_ground_mat.set_shader_parameter("valley_z", VALLEY_Z)
	_ground_mat.set_shader_parameter("rim", 0.0)
	_rock_mat = _ground_mat.duplicate() as ShaderMaterial
	_rock_mat.set_shader_parameter("use_farms", false)
	_outcrop_mat = _rock_mat.duplicate() as ShaderMaterial
	_outcrop_mat.set_shader_parameter("all_rock", true)
	_house_mat = Toon.tinted()
	_building_mat = ShaderMaterial.new()
	_building_mat.shader = BuildingShader
	for paint: Array in [["cream", Color(0.9, 0.86, 0.76), 0.9], ["cap", Color(0.55, 0.25, 0.18), 0.7],
			["sail", Color(0.95, 0.93, 0.86), 0.8], ["timber", Color(0.35, 0.25, 0.18), 0.9],
			["stone", Color(0.76, 0.72, 0.64), 0.9], ["slate", Color(0.24, 0.33, 0.45), 0.6],
			["bark", Color(0.42, 0.31, 0.22), 0.9]]:
		_paints[paint[0]] = Toon.paint(paint[1])

	var cx: float = shore_x(VALLEY_Z) + CASTLE_INLAND
	# Beside the stream, not in it.
	castle = Vector3(cx, 0.0, river_z(cx) + 210.0)
	castle.y = height_at(castle.x, castle.z)
	_build_ocean()
	_build_backdrop()
	_build_castle()
	if focus:
		_follow()
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
	_follow()
	_look_around()
	var began: int = Time.get_ticks_usec()
	while not _queue.is_empty() and float(Time.get_ticks_usec() - began) < BUILD_BUDGET * 1000.0:
		_work(_queue.pop_front())


## Keep the sea and the backdrop centred on the glider.
func _follow() -> void:
	var at: Vector3 = focus.global_position
	_ocean.position = Vector3(at.x, 0.0, at.z)
	_backdrop.position = Vector3(at.x, 0.0, at.z)
	# The flats stand where they stand, but back away if she flies inland at them.
	_backdrop_mat.set_shader_parameter("planes", Vector4(
			maxf(BACKDROP_INLAND[0], at.x + BACKDROP_KEEP[0]), maxf(BACKDROP_INLAND[1], at.x + BACKDROP_KEEP[1]),
			maxf(BACKDROP_INLAND[2], at.x + BACKDROP_KEEP[2]), maxf(BACKDROP_INLAND[3], at.x + BACKDROP_KEEP[3])))


## Build everything in range right now, instead of a little each frame.
func prewarm() -> void:
	_look_around()
	while not _queue.is_empty():
		_work(_queue.pop_front())


## What is standing right now, for the tests.
func stats() -> Dictionary:
	var out := {"chunks": _chunks.size(), "houses": 0, "city_houses": 0, "towers": 0, "stairs": 0, "bridges": 0,
			"windmills": 0, "spires": 0, "rock_towers": 0, "outcrops": 0, "arches": 0, "great_trees": 0}
	for key: Vector2i in _chunks:
		var chunk: Chunk = _chunks[key]
		out["houses"] += chunk.houses
		out["city_houses"] += chunk.city_houses
		out["towers"] += chunk.towers
		out["stairs"] += chunk.stairs
		out["bridges"] += chunk.bridges
		out["windmills"] += chunk.windmills
		out["spires"] += chunk.spires
		out["rock_towers"] += chunk.rock_towers
		out["outcrops"] += chunk.outcrops
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
	var across: float = absf(z - valley_mid(x)) / (VALLEY_HALF + d * 0.08)
	if across > 1.3:
		return 0.0
	var ragged: float = _hills.get_noise_2d(x * 1.3 + 50.0, z * 1.3) * 0.26 * smoothstep(0.0, 300.0, d)
	return 1.0 - smoothstep(0.3, 1.0, across + ragged)


## Which trench a stretch of coast belongs to. Number 0 is the valley's stretch and has none.
func trench_index(z: float) -> int:
	return int(floorf(z / TRENCH_SPACING + 0.5))


## Where trench k meets the sea (its z). (Plain sines again, for the ocean's shader.)
func trench_z(k: int) -> float:
	return (float(k) + 0.3 * sin(float(k) * 2.4 + 1.0)) * TRENCH_SPACING


## The middle of trench k (its z) at a given x: they wind more tightly than the valley.
func trench_mid(k: int, x: float) -> float:
	return trench_z(k) + 110.0 * sin(x / 330.0 + float(k) * 1.7)


## Half the width of trench k, d metres inland: each has its own, and they pinch in as they go.
func trench_half(k: int, d: float) -> float:
	return TRENCH_HALF * (0.75 + 0.25 * sin(float(k) * 5.1)) * (1.0 - 0.45 * smoothstep(400.0, 2600.0, d))


## 0..1: how far into a trench a point is. 1 on its floor, 0 outside. The sides are sheer.
func trench(x: float, z: float) -> float:
	var k: int = trench_index(z)
	if k == 0:
		return 0.0
	var across: float = absf(z - trench_mid(k, x)) / trench_half(k, inland(x, z))
	if across >= 1.0:
		return 0.0
	return 1.0 - smoothstep(0.5, 1.0, across)


## The floor of a trench, d metres inland: under the sea at first, then a long climb to the top.
func trench_floor(d: float) -> float:
	return -14.0 + maxf(d - TRENCH_WATER, 0.0) * 0.26


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
	var broken: float = smoothstep(0.03, 0.2, u)
	var step_at: float = u * TERRACES + _hills.get_noise_2d(x * 0.7 + 300.0, z * 0.7) * 0.5 * smoothstep(0.08, 0.35, u)
	# Buttresses and gullies: the walls are pushed out along sharp ribs and cut back between them.
	step_at += (0.4 - 2.0 * absf(_hills.get_noise_2d(x * 4.0 + 40.0, z * 4.0))) * 0.5 * broken
	step_at = clampf(step_at, 0.0, float(TERRACES))
	var stairs: float = (floorf(step_at) + smoothstep(0.0, WALL_SHARE, step_at - floorf(step_at))) / float(TERRACES)
	var cliff: float = CLIFF_HEIGHT * (0.82 + 0.18 * _hills.get_noise_2d(x * 0.3 + 900.0, z * 0.3))
	# Above the last step, a tableland that rolls and climbs slowly inland.
	var high: float = stairs * cliff + smoothstep(CLIFF_WIDTH, CLIFF_WIDTH + 5000.0, d) * 150.0 \
			+ _hills.get_noise_2d(x, z) * 50.0 * smoothstep(CLIFF_WIDTH, CLIFF_WIDTH + 600.0, d)
	# Lumps and hollows all over the cliff, so no ledge is level and no wall is a plane.
	if d < CLIFF_WIDTH * 1.5:
		high += _hills.get_noise_2d(x * 5.0 + 7.0, z * 5.0 + 60.0) * 13.0 * broken * (1.0 - smoothstep(CLIFF_WIDTH * 1.05, CLIFF_WIDTH * 1.5, d))
	if v <= 0.0:
		var t: float = trench(x, z)
		if t > 0.0:
			high = lerpf(high, minf(trench_floor(d), high), t)
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


## 0..1: how much a point is farmland: the valley floor, and a ledge of the cliffs here and
## there (most of the cliffs are rock and city). The top is left wild. (The ground mesh also
## keeps fields off the walls, by slope.)
func farm_at(x: float, z: float) -> float:
	var d: float = inland(x, z)
	var ledges: float = smoothstep(20.0, 60.0, d) * (1.0 - smoothstep(CLIFF_WIDTH * 0.97, CLIFF_WIDTH * 1.06, d)) \
			* smoothstep(0.1, 0.3, _woods.get_noise_2d(900.0, z * 0.22)) * (1.0 - trench(x, z))
	return maxf(ledges, smoothstep(0.55, 0.8, valley(x, z)) * smoothstep(330.0, 420.0, d))


## 0..1: how built-up the cliffs are at a point. The cities come and go along the coast.
func city_at(x: float, z: float) -> float:
	if valley(x, z) > 0.0:
		return 0.0
	return smoothstep(-0.12, 0.2, _woods.get_noise_2d(z * 0.25, 333.0))


## Is this a spot on one of the cliff's ledges, flat enough to build on?
func on_ledge(x: float, z: float) -> bool:
	var d: float = inland(x, z)
	return d > 60.0 and d < CLIFF_WIDTH * 0.95 and valley(x, z) < 0.05 and height_at(x, z) > 60.0 \
			and normal_at(x, z).y > 0.95


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
## One job at a time: a chunk that needs both its ground and its buildings goes back on the
## front of the queue for the second, so the two never land in the same frame.
func _work(key: Vector2i) -> void:
	var ring: int = _ring(key)
	var chunk: Chunk = _chunks.get(key)
	var wants_props: bool = ring <= PROP_RADIUS and (chunk == null or chunk.props == null)
	if chunk == null:
		chunk = Chunk.new()
		_chunks[key] = chunk
		chunk.fine = ring <= FINE_RADIUS
		chunk.ground = _build_ground(key, chunk)
	elif chunk.ground and ((not chunk.fine and ring <= FINE_RADIUS) or (chunk.fine and ring > FINE_RADIUS + 1)):
		chunk.ground.queue_free()
		chunk.fine = ring <= FINE_RADIUS
		chunk.ground = _build_ground(key, chunk)
	elif wants_props:
		_build_props(key, chunk)
		return
	if wants_props:
		_queue.push_front(key)


## A chunk's heights on the fine grid, worked out once and kept: the fine ground mesh is made
## from it, the city is stood on it, and the glider is stopped by it.
func _grid_for(key: Vector2i, chunk: Chunk) -> PackedFloat32Array:
	if chunk.grid.is_empty():
		var grid := PackedFloat32Array()
		grid.resize(GRID_W * GRID_W)
		var x0: float = key.x * CHUNK - CELL_FINE
		var z0: float = key.y * CHUNK - CELL_FINE
		for j in GRID_W:
			for i in GRID_W:
				grid[j * GRID_W + i] = maxf(height_at(x0 + i * CELL_FINE, z0 + j * CELL_FINE), -8.0)
		chunk.grid = grid
	return chunk.grid


## The height at a point on a chunk's fine grid, on the same triangles the mesh is made of.
func _on_grid(grid: PackedFloat32Array, key: Vector2i, x: float, z: float) -> float:
	var gx: float = (x - key.x * CHUNK) / CELL_FINE + 1.0
	var gz: float = (z - key.y * CHUNK) / CELL_FINE + 1.0
	var i: int = clampi(int(floorf(gx)), 0, GRID_W - 2)
	var j: int = clampi(int(floorf(gz)), 0, GRID_W - 2)
	var fx: float = clampf(gx - float(i), 0.0, 1.0)
	var fz: float = clampf(gz - float(j), 0.0, 1.0)
	var a: int = j * GRID_W + i
	if fx + fz <= 1.0:
		return grid[a] + (grid[a + 1] - grid[a]) * fx + (grid[a + GRID_W] - grid[a]) * fz
	var far: float = grid[a + GRID_W + 1]
	return far + (grid[a + GRID_W] - far) * (1.0 - fx) + (grid[a + 1] - far) * (1.0 - fz)


## The ground mesh for one chunk, or null if it is all open sea. It has a skirt hanging from its
## edges, so no gap shows where a fine chunk meets a coarse one.
func _build_ground(key: Vector2i, chunk: Chunk) -> MeshInstance3D:
	var x0: float = key.x * CHUNK
	var z0: float = key.y * CHUNK
	var dry := false
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0.5), Vector2(1, 0.5)]:
		if inland(x0 + corner.x * CHUNK, z0 + corner.y * CHUNK) > -40.0:
			dry = true
	if not dry:
		return null

	var cell: float = CELL_FINE if chunk.fine else CELL_COARSE
	var n: int = int(CHUNK / cell)
	# Heights on the chunk's grid plus one cell all round (for the slopes at the edges).
	var w: int = n + 3
	var heights: PackedFloat32Array
	if chunk.fine:
		heights = _grid_for(key, chunk)
	else:
		heights = PackedFloat32Array()
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
			# (The head of a trench has a little beach too.)
			var sand: float = maxf(in_valley, trench(x, z)) * (1.0 - smoothstep(7.0, 13.0, h))
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
	mat.set_shader_parameter("valley_z", VALLEY_Z)
	mat.set_shader_parameter("valley_half", VALLEY_HALF)
	mat.set_shader_parameter("trench_spacing", TRENCH_SPACING)
	mat.set_shader_parameter("trench_half", TRENCH_HALF)
	mat.set_shader_parameter("trench_water", TRENCH_WATER)
	_ocean = MeshInstance3D.new()
	_ocean.mesh = plane
	_ocean.material_override = mat
	_ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# It follows the glider every frame, so it must not be physics-interpolated.
	_ocean.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_ocean)


## The painted backdrop's canvas: the eastern side of a big sphere round the glider, from below
## the horizon to well above the highest peak. shaders/backdrop paints the flats onto it.
func _build_backdrop() -> void:
	var across: int = 28
	var up: int = 8
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for j in up + 1:
		var el: float = deg_to_rad(lerpf(-30.0, 42.0, float(j) / float(up)))
		for i in across + 1:
			var az: float = deg_to_rad(lerpf(-96.0, 96.0, float(i) / float(across)))
			verts.append(Vector3(cos(el) * cos(az), sin(el), cos(el) * sin(az)) * BACKDROP_RADIUS)
	for j in up:
		for i in across:
			var a: int = j * (across + 1) + i
			indices.append_array(PackedInt32Array([a, a + 1, a + across + 1, a + 1, a + across + 2, a + across + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_backdrop_mat = ShaderMaterial.new()
	_backdrop_mat.shader = BackdropShader
	_backdrop_mat.set_shader_parameter("noise_tex", noise_tex)
	_backdrop_mat.set_shader_parameter("sun_dir", sun_dir)
	_backdrop_mat.set_shader_parameter("haze_color", haze_color)
	_backdrop_mat.set_shader_parameter("haze_distance", haze_distance * 2.1)
	_backdrop_mat.set_shader_parameter("ground", CLIFF_HEIGHT + 150.0)
	_backdrop = MeshInstance3D.new()
	_backdrop.mesh = mesh
	_backdrop.material_override = _backdrop_mat
	_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_backdrop.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_backdrop)


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


## The lists a chunk's many small things are gathered in, each drawn in one go at the end (see
## _flush). Every entry is [Transform3D, Color].
func _new_bag() -> Dictionary:
	return {"walls": [], "roofs": [], "plain": [], "arches": [], "rocks": [], "trees": [], "crowns": []}


func _flush(holder: Node3D, bag: Dictionary) -> void:
	_scatter(holder, bag["walls"], _box, _building_mat)
	_scatter(holder, bag["roofs"], _prism)
	_scatter(holder, bag["plain"], _box)
	_scatter(holder, bag["arches"], _arch)
	_scatter(holder, bag["rocks"], _rock, _outcrop_mat)
	_scatter(holder, bag["trees"], _blob)
	_scatter(holder, bag["crowns"], _crown, _leaf_mat)


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
	var bag: Dictionary = _new_bag()
	var trees: Array = bag["trees"]

	# The cliffs: the city, its towers, stairs and viaducts, and the rock.
	if chunk.ground and mid_d > -CHUNK * 0.75 and mid_d < CLIFF_WIDTH + CHUNK * 0.75:
		_build_cliff(key, chunk, holder, rng, bag)
	var k0: int = trench_index(z0)
	var k1: int = trench_index(z0 + CHUNK)
	_add_trench_bridge(key, chunk, holder, k0, bag)
	if k1 != k0:
		_add_trench_bridge(key, chunk, holder, k1, bag)

	# Farmsteads on the valley floor.
	for i in 2:
		var stead: Vector3 = _find(rng, key, _on_valley_floor, 12)
		if stead != Vector3.INF:
			for k in rng.randi_range(2, 5):
				_add_house(Vector2(stead.x, stead.z) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(8.0, 50.0),
						rng, chunk, bag)

	# Trees: woods on the wild top, the odd tree on the ledges and in the valley.
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

	# Giant old trees: groves of them in the valley, and one or two to most stretches of the
	# top and the broader ledges.
	for i in 5:
		var tx: float = x0 + rng.randf() * CHUNK
		var tz: float = z0 + rng.randf() * CHUNK
		var td: float = inland(tx, tz)
		var in_valley: bool = valley(tx, tz) > 0.6 and td > 380.0
		var luck: float = rng.randf()
		var reach: float = rng.randf_range(52.0, 96.0) if in_valley else rng.randf_range(38.0, 72.0)
		if td < 80.0 or luck > (0.8 if in_valley else 0.45) or trench(tx, tz) > 0.0:
			continue
		if normal_at(tx, tz).y < 0.94 or (absf(tz - river_z(tx)) < 60.0 and valley(tx, tz) > 0.0) \
				or Vector2(tx - castle.x, tz - castle.z).length() < 420.0 or _crowded(chunk.columns, tx, tz, reach * 1.6):
			continue
		_add_great_tree(holder, chunk.columns, Vector3(tx, height_at(tx, tz), tz), reach, rng, bag["crowns"])
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

	# Pinnacles on the high ground.
	for i in 2:
		var sx: float = x0 + rng.randf() * CHUNK
		var sz: float = z0 + rng.randf() * CHUNK
		var sd: float = inland(sx, sz)
		if sd > CLIFF_WIDTH + 400.0 and valley(sx, sz) <= 0.0 and trench(sx, sz) <= 0.0 and rng.randf() < 0.16:
			var tall: float = rng.randf_range(130.0, 260.0)
			_add_spire(holder, chunk, Vector3(sx, height_at(sx, sz) - 15.0, sz), tall, tall * rng.randf_range(0.13, 0.2) + 16.0, rng)

	_flush(holder, bag)
	chunk.houses = (bag["walls"] as Array).size()


## Everything that stands on a chunk of the cliffs. It is all stood on the chunk's fine grid of
## heights, so it sits on the ground as drawn, and stays inside the chunk.
func _build_cliff(key: Vector2i, chunk: Chunk, holder: Node3D, rng: RandomNumberGenerator, bag: Dictionary) -> void:
	var grid: PackedFloat32Array = _grid_for(key, chunk)
	var x0: float = key.x * CHUNK
	var z0: float = key.y * CHUNK
	var plain: Array = bag["plain"]
	var arches: Array = bag["arches"]
	var rocks: Array = bag["rocks"]

	# The city's districts: houses shoulder to shoulder in rows that step up the slope, each row
	# looking out over the roofs of the one below.
	for s in 11:
		var cx: float = x0 + rng.randf_range(0.15, 0.85) * CHUNK
		var cz: float = z0 + rng.randf_range(0.15, 0.85) * CHUNK
		var rows: int = rng.randi_range(7, 13)
		var cols: int = rng.randi_range(10, 20)
		var luck: float = rng.randf()
		var cd: float = inland(cx, cz)
		if cd < 45.0 or cd > CLIFF_WIDTH * 0.95 or luck > city_at(cx, cz) * 1.6:
			continue
		var slope := Vector2(_on_grid(grid, key, cx + 30.0, cz) - _on_grid(grid, key, cx - 30.0, cz),
				_on_grid(grid, key, cx, cz + 30.0) - _on_grid(grid, key, cx, cz - 30.0)) / 60.0
		if _on_grid(grid, key, cx, cz) < 10.0 or slope.length() < 0.08 or slope.length() > 2.0:
			continue
		var down: Vector2 = -slope.normalized()
		var along := Vector2(-down.y, down.x)
		for r in rows:
			for c in cols:
				var rr: float = (float(r) + 0.5) / float(rows) * 2.0 - 1.0
				var cc: float = (float(c) + 0.5) / float(cols) * 2.0 - 1.0
				var gap: float = rng.randf()
				var nudge: float = rng.randf_range(-1.5, 1.5)
				# (A round patch, with the odd gap for a yard or a lane.)
				if rr * rr + cc * cc > 1.15 or gap < 0.1:
					continue
				var at: Vector2 = Vector2(cx, cz) + along * (cc * float(cols) * 7.8 + nudge) - down * (rr * float(rows) * 7.0)
				_add_city_house(key, chunk, grid, at, atan2(down.x, down.y), 0.1, rng, bag)

	# And houses on their own between the districts, wherever the rock is not sheer.
	for i in 420:
		var x: float = x0 + rng.randf() * CHUNK
		var z: float = z0 + rng.randf() * CHUNK
		var d: float = inland(x, z)
		if d < 8.0 or d > CLIFF_WIDTH * 0.98 or rng.randf() > city_at(x, z):
			continue
		_add_city_house(key, chunk, grid, Vector2(x, z), INF, 0.4, rng, bag)

	# Towers standing over the roofs.
	for i in 6:
		var x: float = x0 + rng.randf_range(0.05, 0.95) * CHUNK
		var z: float = z0 + rng.randf_range(0.05, 0.95) * CHUNK
		var d: float = inland(x, z)
		var tall: float = rng.randf_range(38.0, 84.0)
		var radius: float = rng.randf_range(5.5, 9.0)
		if d < 30.0 or d > CLIFF_WIDTH or city_at(x, z) < 0.45 or _crowded(chunk.columns, x, z, 60.0):
			continue
		var h: float = _on_grid(grid, key, x, z)
		var low: float = minf(minf(_on_grid(grid, key, x + radius, z), _on_grid(grid, key, x - radius, z)),
				minf(_on_grid(grid, key, x, z + radius), _on_grid(grid, key, x, z - radius)))
		if h < 8.0 or h - low > 40.0:
			continue
		_add_tower(holder, chunk.columns, Vector2(x, z), tall + h - low + 6.0, radius, low - 6.0)
		chunk.towers += 1

	# Stairways: flights zigzagging up the cliff from the water.
	for s in 3:
		var z: float = z0 + rng.randf_range(0.1, 0.9) * CHUNK
		var d: float = rng.randf_range(10.0, 40.0)
		var way: float = 1.0 if rng.randf() < 0.5 else -1.0
		var flights: int = rng.randi_range(9, 16)
		if city_at(shore_x(z) + 100.0, z) < 0.35:
			continue
		var from := Vector3(shore_x(z) + d, 0.0, z)
		from.y = _on_grid(grid, key, from.x, from.z) + 0.8
		for flight in flights:
			z = clampf(z + way * rng.randf_range(30.0, 58.0), z0 + 2.0, z0 + CHUNK - 2.0)
			d += rng.randf_range(16.0, 44.0)
			var to := Vector3(shore_x(z) + d, 0.0, z)
			if d > CLIFF_WIDTH or to.x < x0 or to.x > x0 + CHUNK or from.x < x0 or from.x > x0 + CHUNK:
				break
			to.y = _on_grid(grid, key, to.x, to.z) + 0.8
			if from.y > 3.0 and to.y > 3.0:
				plain.append([_beam(from, to, 5.0, 1.8), STONE])
				chunk.stairs += 1
			from = to
			way = -way

	# Viaducts: a road carried level along the cliff on a row of arches, over the gullies.
	for s in 3:
		var z1: float = z0 + rng.randf_range(0.06, 0.6) * CHUNK
		var z2: float = z1 + rng.randf_range(110.0, 300.0)
		var d: float = rng.randf_range(50.0, CLIFF_WIDTH * 0.9)
		var a := Vector3(shore_x(z1) + d, 0.0, z1)
		var b := Vector3(shore_x(z2) + d, 0.0, z2)
		if minf(a.x, b.x) < x0 or maxf(a.x, b.x) > x0 + CHUNK or z2 > z0 + CHUNK or city_at(a.x, z1) < 0.35:
			continue
		a.y = _on_grid(grid, key, a.x, a.z)
		b.y = _on_grid(grid, key, b.x, b.z)
		if minf(a.y, b.y) < 6.0 or absf(a.y - b.y) > 18.0:
			continue
		var deck: float = maxf(a.y, b.y) + 2.0
		var run: Vector3 = Vector3(b.x - a.x, 0.0, b.z - a.z)
		var along: Vector3 = run.normalized()
		var spans: int = maxi(int(round(run.length() / 26.0)), 2)
		var span: float = run.length() / float(spans)
		var stood := 0
		for i in spans:
			var mid: Vector3 = a + run * ((float(i) + 0.5) / float(spans))
			var low: float = INF
			for t: float in [-0.5, 0.0, 0.5]:
				low = minf(low, _on_grid(grid, key, mid.x + along.x * span * t, mid.z + along.z * span * t))
			var tall: float = deck - low + 6.0
			if tall < 10.0 or low < 2.0:
				continue
			arches.append([Transform3D(Basis(along * span, Vector3.UP * tall, along.cross(Vector3.UP) * 6.0), Vector3(mid.x, low - 6.0, mid.z)), STONE])
			stood += 1
		if stood > 0:
			plain.append([_beam(Vector3(a.x, deck + 0.6, a.z), Vector3(b.x, deck + 0.6, b.z), 7.5, 1.6), STONE.darkened(0.12)])
			chunk.bridges += 1

	# Rock towers: pinnacles standing up out of the ledges and against the walls.
	for i in 8:
		var x: float = x0 + rng.randf() * CHUNK
		var z: float = z0 + rng.randf() * CHUNK
		var d: float = inland(x, z)
		var tall: float = rng.randf_range(60.0, 240.0)
		var girth: float = tall * rng.randf_range(0.12, 0.2) + 10.0
		if d < 30.0 or d > CLIFF_WIDTH * 1.15 or valley(x, z) > 0.0 or _crowded(chunk.columns, x, z, 80.0):
			continue
		var h: float = _on_grid(grid, key, x, z)
		if h < 4.0:
			continue
		_add_spire(holder, chunk, Vector3(x, h - 30.0, z), tall + 30.0, girth, rng)
		chunk.rock_towers += 1

	# Outcrops: blocks of rock jutting from every steep face, so the walls have real ledges,
	# overhangs and shadows and a broken edge against the sky.
	for i in 340:
		var x: float = x0 + rng.randf() * CHUNK
		var z: float = z0 + rng.randf() * CHUNK
		var d: float = inland(x, z)
		var size: float = rng.randf_range(12.0, 34.0) * (1.7 if rng.randf() < 0.12 else 1.0)
		var squash := Vector3(rng.randf_range(0.7, 1.3), rng.randf_range(0.6, 1.5), rng.randf_range(0.7, 1.3))
		var spin := Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		if d < 4.0 or d > CLIFF_WIDTH * 1.2 or valley(x, z) > 0.2:
			continue
		var h: float = _on_grid(grid, key, x, z)
		var grad := Vector2(_on_grid(grid, key, x + 10.0, z) - _on_grid(grid, key, x - 10.0, z),
				_on_grid(grid, key, x, z + 10.0) - _on_grid(grid, key, x, z - 10.0)) / 20.0
		if h < 2.0 or grad.length() < 0.7:
			continue
		# Pushed a little way out of the face.
		var out: Vector2 = -grad.normalized() * size * 0.2
		rocks.append([Transform3D(Basis.from_euler(spin).scaled_local(squash * size), Vector3(x + out.x, h, z + out.y)), Color.BLACK])
		if size > 36.0:
			chunk.columns.append([Vector3(x + out.x, h - size * 0.7, z + out.y), size * 1.4, size * 0.6, size * 0.45])
		chunk.outcrops += 1

	# A windmill or two still turns: on a ledge among the fields, or on the rim at the very top.
	var on_top: bool = rng.randf() < 0.5
	var mill: Vector3 = _find(rng, key, _on_rim if on_top else on_ledge, 14)
	if mill != Vector3.INF and not _crowded(chunk.columns, mill.x, mill.z, 120.0):
		_add_windmill(holder, chunk, mill, rng.randf_range(2.0, 3.2), rng)


## One house of the city: dug into the slope behind it and standing tall on the side that faces
## out, so they pile up the cliff one above another, and hang from the walls. `yaw` is the way it faces (INF: straight
## down the slope it stands on), give or take `loose`.
func _add_city_house(key: Vector2i, chunk: Chunk, grid: PackedFloat32Array, at: Vector2, yaw: float, loose: float,
		rng: RandomNumberGenerator, bag: Dictionary) -> void:
	var wide: float = rng.randf_range(13.0, 20.0)
	var deep: float = rng.randf_range(12.0, 17.0)
	var rise: float = rng.randf_range(9.0, 21.0) + (14.0 if rng.randf() < 0.18 else 0.0)
	var turn: float = rng.randf()
	var look: int = rng.randi()
	var x0: float = key.x * CHUNK
	var z0: float = key.y * CHUNK
	if at.x < x0 or at.x > x0 + CHUNK or at.y < z0 or at.y > z0 + CHUNK:
		return
	var h: float = _on_grid(grid, key, at.x, at.y)
	if h < 5.0:
		return
	var grad := Vector2(_on_grid(grid, key, at.x + 8.0, at.y) - _on_grid(grid, key, at.x - 8.0, at.y),
			_on_grid(grid, key, at.x, at.y + 8.0) - _on_grid(grid, key, at.x, at.y - 8.0)) / 16.0
	var steep: float = grad.length()
	# A hall now and then, where there is room for one.
	if look % 23 == 0 and steep < 0.7:
		wide *= 2.0
		deep *= 1.7
		rise += 16.0
	var drop: float = steep * deep
	if drop > 95.0:
		return
	if yaw == INF:
		yaw = atan2(-grad.x, -grad.y) if steep > 0.08 else turn * TAU
	# On a slope its foot goes down to the ground at its front. On a wall too steep for that it
	# hangs: its back is bedded in the rock and the rest juts out over the drop.
	var tall: float = minf(drop + 4.0, 26.0) + rise
	var foot: float = h + drop * 0.5 + rise - tall
	var facing := Basis(Vector3.UP, yaw + (turn - 0.5) * loose)
	var plaster: Color = PLASTER[look % PLASTER.size()]
	var tile: Color = TILES[(look / 7) % TILES.size()]
	(bag["walls"] as Array).append([Transform3D(facing.scaled_local(Vector3(wide, tall, deep)), Vector3(at.x, foot + tall * 0.5, at.y)),
			plaster.lerp(Color(0.7, 0.64, 0.55), turn * 0.3)])
	if look % 4 == 0:
		# A flat roof with a low wall round it.
		(bag["plain"] as Array).append([Transform3D(facing.scaled_local(Vector3(wide + 1.0, 1.4, deep + 1.0)), Vector3(at.x, foot + tall + 0.4, at.y)), STONE])
	else:
		var pitch: float = deep * 0.4
		# (The ridge runs along the house's longer side.)
		var roof: Basis = facing if deep >= wide else facing * Basis(Vector3.UP, PI * 0.5)
		var across: Vector3 = Vector3(wide + 1.4, pitch, deep + 1.6) if deep >= wide else Vector3(deep + 1.6, pitch, wide + 1.4)
		(bag["roofs"] as Array).append([Transform3D(roof.scaled_local(across), Vector3(at.x, foot + tall + pitch * 0.5, at.y)), tile])
	chunk.city_houses += 1


## A long flat box laid from one point to another (a flight of stairs, a road deck), as a
## transform for the unit box.
func _beam(from: Vector3, to: Vector3, width: float, thick: float) -> Transform3D:
	var along: Vector3 = (to - from).normalized()
	var side: Vector3 = along.cross(Vector3.UP).normalized()
	var up: Vector3 = side.cross(along)
	return Transform3D(Basis(side * width, up * thick, -along * (from.distance_to(to) + width * 0.5)), (from + to) * 0.5)


## The bridge over trench k, if this is the chunk it stands in: a row of tall arches from wall to
## wall, high above the water, with a gate tower at each end. The arches are wide enough to fly
## through.
func _add_trench_bridge(key: Vector2i, chunk: Chunk, holder: Node3D, k: int, bag: Dictionary) -> void:
	if k == 0:
		return
	var bx: float = shore_x(trench_z(k)) + 190.0 + 70.0 * sin(float(k) * 3.3)
	var mid: float = trench_mid(k, bx)
	if _key_of(bx, mid) != key:
		return
	var half: float = trench_half(k, inland(bx, mid))
	var za: float = mid - half * 1.05
	var zb: float = mid + half * 1.05
	var deck: float = minf(minf(height_at(bx, za), height_at(bx, zb)) - 8.0, 250.0)
	if deck < 90.0:
		return
	# Bring each end in to where the wall is, and bed it in.
	for i in 14:
		if height_at(bx, za + 12.0) < deck + 6.0:
			break
		za += 12.0
	for i in 14:
		if height_at(bx, zb - 12.0) < deck + 6.0:
			break
		zb -= 12.0
	za -= 10.0
	zb += 10.0
	var spans: int = maxi(int(round((zb - za) / 95.0)), 2)
	var span: float = (zb - za) / float(spans)
	var tall: float = deck + 16.0
	for i in spans:
		(bag["arches"] as Array).append([Transform3D(Basis(Vector3(0, 0, span), Vector3(0, tall, 0), Vector3(-15.0, 0, 0)),
				Vector3(bx, -16.0, za + (float(i) + 0.5) * span)), STONE])
		if i > 0:
			chunk.columns.append([Vector3(bx, -16.0, za + float(i) * span), tall, span * 0.09, span * 0.09])
	# The solid band over the arches.
	var band: float = tall * 0.1
	chunk.capsules.append([Vector3(bx, deck - band * 0.5, za), Vector3(bx, deck - band * 0.5, zb), band * 0.5 + 4.0])
	(bag["plain"] as Array).append([Transform3D(Basis.from_scale(Vector3(18.0, 3.0, zb - za + 8.0)), Vector3(bx, deck + 1.5, (za + zb) * 0.5)), STONE.darkened(0.12)])
	for end: float in [za + 6.0, zb - 6.0]:
		_add_tower(holder, chunk.columns, Vector2(bx, end), 78.0, 11.0, deck - 26.0)
	chunk.bridges += 1


func _crowded(columns: Array, x: float, z: float, gap: float) -> bool:
	for c: Array in columns:
		var foot: Vector3 = c[0]
		if Vector2(foot.x - x, foot.z - z).length() < gap:
			return true
	return false


## A farmhouse on flat ground (the valley, and the castle's town).
func _add_house(at: Vector2, rng: RandomNumberGenerator, chunk: Chunk, bag: Dictionary) -> void:
	if normal_at(at.x, at.y).y < 0.955 or height_at(at.x, at.y) < 14.0:
		return
	if absf(at.y - river_z(at.x)) < 26.0 and valley(at.x, at.y) > 0.3:
		return
	var size := Vector3(rng.randf_range(8.0, 14.0), rng.randf_range(4.5, 6.5), rng.randf_range(6.0, 9.0))
	var ground: float = height_at(at.x, at.y)
	var turn := Basis(Vector3.UP, rng.randf() * TAU)
	var wall := Color(0.9, 0.86, 0.76).lerp(Color(0.72, 0.66, 0.56), rng.randf())
	var tile: Color = [Color(0.62, 0.27, 0.18), Color(0.5, 0.3, 0.2), Color(0.32, 0.36, 0.42)][rng.randi() % 3]
	(bag["walls"] as Array).append([Transform3D(turn.scaled_local(size), Vector3(at.x, ground + size.y * 0.5 - 0.5, at.y)), wall])
	var pitch: float = size.z * 0.45
	(bag["roofs"] as Array).append([Transform3D(turn.scaled_local(Vector3(size.x + 1.2, pitch, size.z + 1.4)),
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


## One flat-shaded triangle facing along `normal`, whichever way round its corners are given.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	# (Godot's front faces wind clockwise.)
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
	for p: Vector3 in [a, b, c]:
		st.set_normal(normal)
		st.add_vertex(p)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	_tri(st, a, b, c, normal)
	_tri(st, a, c, d, normal)


## One span of a bridge: a block one unit wide, tall and thick, standing on y = 0, with a round-
## headed opening through it. Stretched to fit, a row of them makes a viaduct.
func _make_arch() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps: int = 12
	var curve: Array = []
	for i in steps + 1:
		var a: float = PI - PI * float(i) / float(steps)
		curve.append(Vector2(cos(a) * 0.42, sin(a) * 0.9))
	for face: float in [0.5, -0.5]:
		var n := Vector3(0, 0, signf(face))
		for i in steps:
			var p: Vector2 = curve[i]
			var q: Vector2 = curve[i + 1]
			_quad(st, Vector3(p.x, p.y, face), Vector3(q.x, q.y, face), Vector3(q.x, 1.0, face), Vector3(p.x, 1.0, face), n)
		for leg: float in [-1.0, 1.0]:
			_quad(st, Vector3(0.42 * leg, 0.0, face), Vector3(0.5 * leg, 0.0, face), Vector3(0.5 * leg, 1.0, face), Vector3(0.42 * leg, 1.0, face), n)
	# The underside of the arch.
	for i in steps:
		var p: Vector2 = curve[i]
		var q: Vector2 = curve[i + 1]
		var mid: Vector2 = (p + q) * 0.5
		_quad(st, Vector3(p.x, p.y, 0.5), Vector3(q.x, q.y, 0.5), Vector3(q.x, q.y, -0.5), Vector3(p.x, p.y, -0.5),
				-Vector3(mid.x / 0.42, mid.y / 0.9, 0.0).normalized())
	_quad(st, Vector3(-0.5, 1, 0.5), Vector3(0.5, 1, 0.5), Vector3(0.5, 1, -0.5), Vector3(-0.5, 1, -0.5), Vector3.UP)
	for side: float in [-0.5, 0.5]:
		_quad(st, Vector3(side, 0, 0.5), Vector3(side, 1, 0.5), Vector3(side, 1, -0.5), Vector3(side, 0, -0.5), Vector3(signf(side), 0, 0))
	return st.commit()


## A lump of rock: a twenty-sided ball knocked out of shape, with flat faces.
func _make_rock() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 5
	var g: float = (1.0 + sqrt(5.0)) * 0.5
	var corners: Array = []
	for p: Vector3 in [Vector3(-1, g, 0), Vector3(1, g, 0), Vector3(-1, -g, 0), Vector3(1, -g, 0), Vector3(0, -1, g), Vector3(0, 1, g),
			Vector3(0, -1, -g), Vector3(0, 1, -g), Vector3(g, 0, -1), Vector3(g, 0, 1), Vector3(-g, 0, -1), Vector3(-g, 0, 1)]:
		corners.append(p.normalized() * rng.randf_range(0.68, 1.12))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: Array in [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
			[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]:
		var a: Vector3 = corners[face[0]]
		var b: Vector3 = corners[face[1]]
		var c: Vector3 = corners[face[2]]
		var n: Vector3 = (b - a).cross(c - a).normalized()
		if n.dot(a + b + c) < 0.0:
			n = -n
		_tri(st, a, b, c, n)
	return st.commit()


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
## `foot` is the height its base goes down to; left out, it is sunk a little into the ground there.
func _add_tower(holder: Node3D, columns: Array, at: Vector2, height: float, radius: float, foot: float = INF) -> float:
	var ground: float = foot if foot != INF else height_at(at.x, at.y) - 6.0
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

	# The great trees: older than the castle. The biggest stands across the stream from it, and
	# the rest of the grove is strung out up the valley.
	var bag: Dictionary = _new_bag()
	var crowns: Array = bag["crowns"]
	for tree: Array in [[-120.0, -260.0, 125.0], [-460.0, 250.0, 84.0], [330.0, -330.0, 96.0], [620.0, 280.0, 78.0], [-700.0, -300.0, 70.0]]:
		var tree_x: float = castle.x + float(tree[0])
		var tree_z: float = river_z(tree_x) + float(tree[1])
		_add_great_tree(holder, _columns, Vector3(tree_x, height_at(tree_x, tree_z), tree_z), tree[2], rng, crowns)

	# The town, outside the walls.
	for k in 150:
		var out: float = rng.randf_range(half + 40.0, half + 230.0)
		_add_house(here + Vector2.from_angle(rng.randf() * TAU) * out, rng, null, bag)
	_flush(holder, bag)


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


## The height of the ground as it is drawn: on the mesh's own triangles where the chunk is built
## (the mesh cuts the corners of height_at()'s sharpest ridges and gullies), height_at() elsewhere.
func surface_at(x: float, z: float) -> float:
	var key: Vector2i = _key_of(x, z)
	var chunk: Chunk = _chunks.get(key)
	if chunk == null or chunk.grid.is_empty():
		return height_at(x, z)
	return _on_grid(chunk.grid, key, x, z)


## If a ball at a world position is in the ground, the sea, a spire, a tower, a bridge or a
## windmill, returns the push that gets it out. Vector3.ZERO means it is in clear air.
func hit(world: Vector3, radius: float) -> Vector3:
	var ground: float = surface_at(world.x, world.z)
	var low: float = world.y - radius
	if low < maxf(ground, 0.0):
		if ground <= 0.0:
			return Vector3.UP * -low
		var e: float = 10.0
		var n: Vector3 = Vector3(surface_at(world.x - e, world.z) - surface_at(world.x + e, world.z), 2.0 * e,
				surface_at(world.x, world.z - e) - surface_at(world.x, world.z + e)).normalized()
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

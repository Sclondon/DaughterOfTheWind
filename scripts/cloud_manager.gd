extends Node3D
## The sky's clouds, and the air they stand in.
##
## The sky is cut into square cells, one grid per cloud layer (see LAYERS). Cells stream in around
## `focus` and are freed behind it. What a cell holds depends only on its grid position and
## `world_seed`, so flying away and back finds the same clouds. A slow noise map decides where the
## cloud banks and the clear gaps are, and `coverage` (the weather) scales how much sky fills in.
##
## Each cloud is a heap of puffs drawn as one MultiMesh per cell with shaders/cloud_puff. Nearby
## cells use a rounder sphere than far ones. The towers spread out at the top into a thunderhead's
## anvil. Round every cloud's edge sit a few tiny tufts, which break off and blow away when
## something flies by, and grow back later. Under everything lies the sea of clouds, one big sheet
## that follows the focus (shaders/cloud_sea), and far above everything the cirrus, one more sheet
## with mares' tails painted on it (shaders/cirrus).
##
## The whole lot drifts on the wind: this node moves, and cells are worked out in its own space.
##
## The manager also answers questions about the air, in world space:
##   density_at(p)  0..1, how deep inside cloud a point is (the camera's whiteout uses it)
##   stirrer        set this to the glider and the puffs it flies through are swooshed aside
##   add_stirrer()  anything else that should stir them; one with a radius (an airship) ploughs a
##                  tunnel through the cloud that stays open for a while behind it
##   wind_at(p)     the air's velocity at a point: thermals rising under the cumulus and towers,
##                  gusts inside cloud, and the strong lift over the cloud sea that carries a
##                  sinking glider back up.

const PuffShader := preload("res://shaders/cloud_puff.gdshader")
const SeaShader := preload("res://shaders/cloud_sea.gdshader")
const CirrusShader := preload("res://shaders/cirrus.gdshader")

const SEA_Y := 0.0
const SEA_AMP := 170.0
const SEA_SIZE := 18000.0
const SEA_STEP := 100.0
## How many cells may be generated per frame while streaming.
const BUILDS_PER_FRAME := 2
## Lift (m/s) the air gives a glider that has sunk into the cloud sea.
const RESCUE_LIFT := 30.0
const WEATHERS := [0.55, 1.0, 1.7]
## The cirrus: how high it lies, how far out the sheet reaches, and how much of it is streaked
## in each of the WEATHERS.
const CIRRUS_Y := 3600.0
const CIRRUS_REACH := 13000.0
const CIRRUS_COVER := [0.3, 0.5, 0.8]
## Which way a thunderhead's anvil is blown out (a fixed direction, not `wind`, so that a place
## always grows the same cloud).
const ANVIL_LEAN := Vector2(0.93, 0.37)

## One entry per cloud layer.
##   cell       side of a grid cell (m)            radius     cells kept each way around the focus
##   lod        cells (each way) drawn with the rounder sphere
##   base, base_jitter   height of the flat bottoms
##   coverage   how much of the sky this layer fills in fair weather (0..1)
##   max_clouds most clouds in one cell            size       half width of a cloud, min..max (m)
##   puff       puff radius, min..max (m)          tall       height as a share of its half width
##   squash     vertical scale of the puffs (flat wisps use less than 1)
##   flat_base  true gives the puffs a flat cumulus bottom
##   thermal    strength of the rising air under the cloud (0 for none)
##   max_puffs  cap on puffs in one cloud's heap
##   tufts      how many tiny loose puffs sit round its edge
##   anvil      true spreads the top out into a thunderhead
const LAYERS := [
	{
		"name": "cumulus", "cell": 900.0, "radius": 4, "lod": 1,
		"base": 330.0, "base_jitter": 60.0, "coverage": 0.52, "max_clouds": 2,
		"size": Vector2(110.0, 250.0), "puff": Vector2(36.0, 76.0), "tall": 0.95,
		"squash": 1.0, "flat_base": true, "thermal": 1.0, "max_puffs": 64, "tufts": 9, "anvil": false,
	},
	{
		"name": "towers", "cell": 2600.0, "radius": 2, "lod": 2,
		"base": 60.0, "base_jitter": 40.0, "coverage": 0.4, "max_clouds": 1,
		"size": Vector2(380.0, 640.0), "puff": Vector2(130.0, 230.0), "tall": 2.3,
		"squash": 1.0, "flat_base": false, "thermal": 1.5, "max_puffs": 100, "tufts": 16, "anvil": true,
	},
	{
		"name": "wisps", "cell": 1300.0, "radius": 3, "lod": 0,
		"base": 1250.0, "base_jitter": 220.0, "coverage": 0.48, "max_clouds": 2,
		"size": Vector2(200.0, 460.0), "puff": Vector2(30.0, 62.0), "tall": 0.1,
		"squash": 0.5, "flat_base": false, "thermal": 0.0, "max_puffs": 40, "tufts": 4, "anvil": false,
	},
]

## What to stream the clouds around (the glider).
var focus: Node3D
var wind := Vector3(5.0, 0.0, 2.0)
## How far the clouds have drifted so far.
var drift := Vector3.ZERO
## The weather: 1 is fair, less is clearer, more is heavier.
var coverage := 1.0
var world_seed := 20261008
## The glider: puffs near it are pushed aside and swirled round in its wake, then drift slowly
## back to where they belong. (One more entry in `stirrers`; see add_stirrer for the rest.)
var stirrer: Node3D:
	set(node):
		if stirrer:
			remove_stirrer(stirrer)
		stirrer = node
		if node:
			add_stirrer(node)
## Everything that stirs the clouds (Stirrer).
var stirrers: Array = []
## False leaves out the sea of clouds (and its lift), for a level with real ground below.
var sea_enabled := true
## Raises every layer's base by this much, to clear high ground.
var altitude_shift := 0.0

var sun_dir := Vector3.UP
var lit_color := Color(1.0, 0.97, 0.91)
var shade_color := Color(0.55, 0.65, 0.84)
var haze_color := Color(0.8, 0.88, 0.95)
var rim_color := Color(1.0, 0.95, 0.85)
var haze_distance := 6000.0


class Cloud:
	var center := Vector3.ZERO  # of the ball that holds every puff
	var radius := 0.0
	var foot := Vector3.ZERO  # middle of the base
	var foot_radius := 0.0
	var top_y := 0.0
	var thermal := 0.0
	var puffs := PackedFloat32Array()  # x, y, z, radius for each puff


class Cell:
	var node: MultiMeshInstance3D  # null when the cell is clear sky
	var clouds: Array = []
	var puff_count := 0
	var base: Array = []  # where each puff belongs (Transform3D)
	var radii := PackedFloat32Array()
	var tuft := PackedByteArray()  # 1 for the tiny loose puffs, 0 for the heap
	var spans: Array = []  # one per cloud: [first puff, one past its last, Cloud]
	# Puffs knocked out of place: index -> [Vector3 offset, Vector3 velocity,
	# seconds a ship's tunnel still holds it open, seconds since a tuft broke off (0: it has not)]
	var stirred := {}


## Something that stirs the clouds as it flies through them.
class Stirrer:
	var node: Node3D
	var radius := 0.0  # 0 for something small; more makes it a hull that ploughs a tunnel
	var half := 0.0  # half its length, along its own Z
	var last := Vector3.INF
	var velocity := Vector3.ZERO


var _cells: Array = []  # per layer: Dictionary of Vector2i -> Cell
var _centers: Array = []  # per layer: the cell the focus is in (null before the first look)
var _queue: Array = []  # cells waiting to be generated: [layer index, Vector2i]
var _materials: Array = []
var _mesh_hi: SphereMesh
var _mesh_lo: SphereMesh
var _noise_tex: ImageTexture
var _cover := FastNoiseLite.new()
var _gust := FastNoiseLite.new()
var _sea: MeshInstance3D
var _sea_mat: ShaderMaterial
var _cirrus: MeshInstance3D
var _cirrus_mat: ShaderMaterial
var _hull_turn := 0
var _time := 0.0
var _unsettled := {}  # cells with stirred puffs still out of place


func _ready() -> void:
	# This node is moved every frame by the wind, so it must not be physics-interpolated.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_cover.seed = world_seed
	_cover.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cover.frequency = 1.0 / 5200.0
	_gust.seed = world_seed + 7
	_gust.frequency = 0.02
	_noise_tex = _make_noise()
	_mesh_hi = _make_sphere(36, 18)
	_mesh_lo = _make_sphere(20, 11)
	for layer: Dictionary in LAYERS:
		var mat := ShaderMaterial.new()
		mat.shader = PuffShader
		var reach: float = float(layer["cell"]) * float(layer["radius"])
		mat.set_shader_parameter("fade_start", reach * 0.8)
		mat.set_shader_parameter("fade_end", reach * 0.97)
		_paint(mat)
		_materials.append(mat)
		_cells.append({})
		_centers.append(null)
	_build_sea()
	_build_cirrus()


func _paint(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("noise_tex", _noise_tex)
	mat.set_shader_parameter("sun_dir", sun_dir)
	mat.set_shader_parameter("lit_color", lit_color)
	mat.set_shader_parameter("shade_color", shade_color)
	mat.set_shader_parameter("haze_color", haze_color)
	mat.set_shader_parameter("haze_distance", haze_distance)
	if mat.shader == PuffShader:
		mat.set_shader_parameter("rim_color", rim_color)


func _make_noise() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = world_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var smooth: Image = noise.get_seamless_image(256, 256, false, false, 0.1, true)
	# Cell noise: the distance to the nearest of a scatter of points. Turned upside down it is a
	# field of round domes with creases between them, which is what makes things look billowy.
	var cells := FastNoiseLite.new()
	cells.seed = world_seed + 3
	cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	cells.frequency = 0.03
	cells.fractal_type = FastNoiseLite.FRACTAL_NONE
	cells.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	var bumps: Image = cells.get_seamless_image(256, 256, false, false, 0.1, true)
	# Red holds the smooth noise, green the cell noise.
	var image := Image.create(256, 256, false, Image.FORMAT_RG8)
	for y in 256:
		for x in 256:
			image.set_pixel(x, y, Color(smooth.get_pixel(x, y).r, bumps.get_pixel(x, y).r, 0.0))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _make_sphere(segments: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


func _build_sea() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SEA_SIZE, SEA_SIZE)
	var cuts: int = int(SEA_SIZE / SEA_STEP) - 1
	plane.subdivide_width = cuts
	plane.subdivide_depth = cuts
	_sea_mat = ShaderMaterial.new()
	_sea_mat.shader = SeaShader
	_paint(_sea_mat)
	_sea_mat.set_shader_parameter("amp", SEA_AMP)
	_sea_mat.set_shader_parameter("reach", SEA_SIZE * 0.5)
	_sea = MeshInstance3D.new()
	_sea.mesh = plane
	_sea.material_override = _sea_mat
	_sea.position.y = SEA_Y
	_sea.extra_cull_margin = SEA_AMP * 2.0
	_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sea.visible = sea_enabled
	add_child(_sea)


func _build_cirrus() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(CIRRUS_REACH, CIRRUS_REACH) * 2.0
	_cirrus_mat = ShaderMaterial.new()
	_cirrus_mat.shader = CirrusShader
	_paint(_cirrus_mat)
	_cirrus_mat.set_shader_parameter("reach", CIRRUS_REACH)
	_cirrus_mat.set_shader_parameter("cover", CIRRUS_COVER[1])
	_cirrus_mat.set_shader_parameter("wind_dir", ANVIL_LEAN.normalized())
	_cirrus = MeshInstance3D.new()
	_cirrus.mesh = plane
	_cirrus.material_override = _cirrus_mat
	_cirrus.position.y = CIRRUS_Y + altitude_shift
	_cirrus.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cirrus)


## Have something else stir the clouds as it moves. With a `radius` and a `length` it is a hull
## (an airship, lying along its own Z): it shoves the puffs right out of its way, and the tunnel
## it leaves stays open for HOLE_TIME before the cloud closes in again.
func add_stirrer(node: Node3D, radius: float = 0.0, length: float = 0.0) -> void:
	var s := Stirrer.new()
	s.node = node
	s.radius = radius
	s.half = length * 0.5
	stirrers.append(s)


func remove_stirrer(node: Node3D) -> void:
	stirrers = stirrers.filter(func(s: Stirrer) -> bool: return s.node != node)


func _process(delta: float) -> void:
	_time += delta
	drift += wind * delta
	position = drift
	_sea_mat.set_shader_parameter("drift", Vector2(drift.x, drift.z))
	# The cirrus is so high it hardly seems to move: it drifts at a fifth of the wind.
	_cirrus_mat.set_shader_parameter("drift", Vector2(drift.x, drift.z) * 0.2)
	if focus == null:
		return
	var here: Vector3 = focus.global_position - drift
	# The sheet steps along with the focus in whole grid steps, so its billows never swim.
	_sea.position = Vector3(snappedf(here.x, SEA_STEP), SEA_Y, snappedf(here.z, SEA_STEP))
	_cirrus.position = Vector3(here.x, CIRRUS_Y + altitude_shift, here.z)
	_look_around(here)
	for i in BUILDS_PER_FRAME:
		if _queue.is_empty():
			break
		var job: Array = _queue.pop_front()
		_build(job[0], job[1])
	_stir(delta)


## How far beyond a puff's own edge a stirrer's wake reaches it.
const STIR_REACH := 26.0
## How long the tunnel a hull ploughs stays open behind it, in seconds.
const HOLE_TIME := 30.0
## A tuft that breaks off blows away and thins to nothing in TUFT_LIFE seconds, and a new one
## has grown in its place TUFT_BACK seconds after that.
const TUFT_LIFE := 7.0
const TUFT_BACK := 30.0
const TUFT_GROW := 4.0


## Push the puffs near the stirrers about, and let the ones already knocked loose swirl and settle.
func _stir(delta: float) -> void:
	var hulls: Array = []
	for s: Stirrer in stirrers.duplicate():
		if not is_instance_valid(s.node):
			stirrers.erase(s)
			continue
		var at: Vector3 = s.node.global_position
		if "velocity" in s.node:
			s.velocity = s.node.velocity
		elif s.last.is_finite() and delta > 0.0 and at.distance_to(s.last) < 60.0:
			s.velocity = (at - s.last) / delta
		else:
			# Its first frame, or it has just been put somewhere else.
			s.velocity = Vector3.ZERO
		s.last = at
		if s.radius > 0.0:
			hulls.append(s)
		else:
			_stir_with(s, delta)
	# The hulls are big and slow, so they take turns: one a frame, for all the frames it waited.
	if not hulls.is_empty():
		_hull_turn = (_hull_turn + 1) % hulls.size()
		_stir_with(hulls[_hull_turn], delta * hulls.size())

	for cell: Cell in _unsettled.keys():
		if cell.node == null or not is_instance_valid(cell.node):
			_unsettled.erase(cell)
			continue
		var mm: MultiMesh = cell.node.multimesh
		for i: int in cell.stirred.keys():
			var entry: Array = cell.stirred[i]
			var offset: Vector3 = entry[0]
			var velocity: Vector3 = entry[1]
			var hold: float = entry[2]
			var loose: float = entry[3]
			var home: Transform3D = cell.base[i]
			if loose > 0.0:
				# A tuft that has broken off: it is carried away, rising a little and thinning to
				# nothing; much later a new one swells up where it used to sit.
				loose += delta
				entry[3] = loose
				if loose < TUFT_LIFE:
					velocity *= exp(-0.45 * delta)
					velocity.y += 1.2 * delta
					offset += velocity * delta
					entry[0] = offset
					entry[1] = velocity
					var left: float = 1.0 - loose / TUFT_LIFE
					mm.set_instance_transform(i, Transform3D(home.basis * (left * (2.0 - left)), home.origin + offset))
				elif loose < TUFT_LIFE + TUFT_BACK:
					entry[0] = Vector3.ZERO
					entry[1] = Vector3.ZERO
					mm.set_instance_transform(i, Transform3D(home.basis * 0.0, home.origin))
				elif loose < TUFT_LIFE + TUFT_BACK + TUFT_GROW:
					var grown: float = (loose - TUFT_LIFE - TUFT_BACK) / TUFT_GROW
					mm.set_instance_transform(i, Transform3D(home.basis * grown, home.origin))
				else:
					cell.stirred.erase(i)
					mm.set_instance_transform(i, home)
				continue
			# A weak pull home and a lot of drag: they billow out fast and close back in slowly.
			# A puff a ship shoved aside is not pulled home at all until its tunnel's time is up.
			if hold > 0.0:
				hold = maxf(hold - delta, 0.0)
				entry[2] = hold
			else:
				velocity -= offset * 0.1 * delta
			velocity *= exp(-0.8 * delta)
			offset += velocity * delta
			var limit: float = cell.radii[i] * 2.5
			if offset.length() > limit:
				offset = offset.normalized() * limit
			if hold <= 0.0 and offset.length() < 0.4 and velocity.length() < 0.3:
				cell.stirred.erase(i)
				mm.set_instance_transform(i, home)
				continue
			entry[0] = offset
			entry[1] = velocity
			# A puff knocked loose thins a little while it is out of place, and one beside a
			# ship's tunnel thins a good deal more, which is what opens the hole up.
			var held: float = minf(hold / 6.0, 1.0)
			var thin: float = 1.0 - lerpf(0.3, 0.5, held) * minf(offset.length() / (limit * lerpf(1.0, 0.3, held)), 1.0)
			mm.set_instance_transform(i, Transform3D(home.basis * thin, home.origin + offset))
		if cell.stirred.is_empty():
			_unsettled.erase(cell)


## One stirrer's push on the puffs round it.
func _stir_with(s: Stirrer, delta: float) -> void:
	if not s.node.is_visible_in_tree():
		return
	var speed: float = s.velocity.length()
	if speed < 2.0:
		return
	var p: Vector3 = s.node.global_position - drift
	var ahead: Vector3 = s.velocity / speed
	var hull: bool = s.radius > 0.0
	var axis: Vector3 = s.node.global_basis.z.normalized()
	# Nothing further from a cloud's middle than this can touch any of its puffs.
	var bound: float = s.half + s.radius + STIR_REACH + 80.0
	for li in LAYERS.size():
		var cells: Dictionary = _cells[li]
		var at: Vector2i = _cell_of(p, LAYERS[li]["cell"])
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var cell: Cell = cells.get(Vector2i(at.x + dx, at.y + dz))
				if cell == null or cell.node == null:
					continue
				for span: Array in cell.spans:
					var cloud: Cloud = span[2]
					var far: float = cloud.radius + bound
					if p.distance_squared_to(cloud.center) > far * far:
						continue
					for i in range(span[0], span[1]):
						var entry = cell.stirred.get(i)
						var here: Vector3 = (cell.base[i] as Transform3D).origin
						if entry != null:
							if (entry[3] as float) > 0.0:
								continue
							here += entry[0]
						var away: Vector3 = here - p
						if hull:
							# Measured from the hull's whole length, not just its middle.
							away -= axis * clampf(away.dot(axis), -s.half, s.half)
						var reach: float = cell.radii[i] * (0.75 if hull else 1.0) + s.radius + STIR_REACH
						var gap: float = away.length()
						if gap >= reach:
							continue
						if entry == null:
							entry = [Vector3.ZERO, Vector3.ZERO, 0.0, 0.0]
							cell.stirred[i] = entry
							_unsettled[cell] = true
						var aside: Vector3 = away - ahead * away.dot(ahead)
						aside = aside.normalized() if aside.length() > 0.5 else Vector3.UP
						var near: float = 1.0 - gap / reach
						if cell.tuft[i] == 1:
							# A tuft comes away whole and is carried off in the wake.
							entry[1] = (aside * 0.5 + ahead * 0.45 + ahead.cross(aside) * 0.35) * minf(speed, 60.0) * (0.5 + near)
							entry[3] = 0.001
						elif hull:
							# Shouldered straight out of the way, and dragged along a little.
							entry[1] = (entry[1] as Vector3) + (aside * 70.0 + ahead * speed * 0.4) * near * delta
							entry[2] = HOLE_TIME
						else:
							# Shoved aside from the line of flight, dragged along in the wake, and spun round it.
							var push: float = near * speed * 2.4 * delta
							entry[1] = (entry[1] as Vector3) + (aside * 0.9 + ahead * 0.55 + ahead.cross(aside) * 0.8) * push


## Build every cell in range right now (at the start, or after the weather changes),
## instead of a few per frame.
func prewarm() -> void:
	if focus == null:
		return
	_look_around(focus.global_position - drift)
	while not _queue.is_empty():
		var job: Array = _queue.pop_front()
		_build(job[0], job[1])


## Pick one of WEATHERS (0 clear, 1 fair, 2 heavy) and regrow the sky to match.
func set_weather(index: int) -> void:
	index = clampi(index, 0, WEATHERS.size() - 1)
	coverage = WEATHERS[index]
	_cirrus_mat.set_shader_parameter("cover", CIRRUS_COVER[index])
	_unsettled.clear()
	for li in LAYERS.size():
		var cells: Dictionary = _cells[li]
		for key: Vector2i in cells:
			var cell: Cell = cells[key]
			if cell.node:
				cell.node.queue_free()
		cells.clear()
		_centers[li] = null
	_queue.clear()
	prewarm()


## The shared noise texture (red: smooth noise, green: cell noise), for other shaders to reuse.
func noise_texture() -> ImageTexture:
	return _noise_tex


## How many cells and puffs are alive, for the tests and for tuning.
func stats() -> Dictionary:
	var cells := 0
	var clouds := 0
	var puffs := 0
	var tufts := 0
	for li in LAYERS.size():
		var layer_cells: Dictionary = _cells[li]
		cells += layer_cells.size()
		for key: Vector2i in layer_cells:
			var cell: Cell = layer_cells[key]
			clouds += cell.clouds.size()
			puffs += cell.puff_count
			tufts += cell.tuft.count(1)
	return {"cells": cells, "clouds": clouds, "puffs": puffs, "tufts": tufts, "queued": _queue.size()}


## Every cloud alive right now (their positions are in this node's drifting space).
func all_clouds() -> Array:
	var out: Array = []
	for li in LAYERS.size():
		var layer_cells: Dictionary = _cells[li]
		for key: Vector2i in layer_cells:
			out.append_array((layer_cells[key] as Cell).clouds)
	return out


# ----------------------------------------------------------------------------------------------
# Streaming

func _cell_of(p: Vector3, size: float) -> Vector2i:
	return Vector2i(floori(p.x / size), floori(p.z / size))


func _look_around(here: Vector3) -> void:
	var changed := false
	for li in LAYERS.size():
		var layer: Dictionary = LAYERS[li]
		var at: Vector2i = _cell_of(here, layer["cell"])
		if _centers[li] != null and (_centers[li] as Vector2i) == at:
			continue
		_centers[li] = at
		_restream(li, at)
		changed = true
	if changed:
		# Nearest cells first.
		_queue.sort_custom(func(a: Array, b: Array) -> bool:
			return _job_distance(a, here) < _job_distance(b, here))


func _job_distance(job: Array, here: Vector3) -> float:
	var size: float = LAYERS[job[0]]["cell"]
	var key: Vector2i = job[1]
	return Vector2((key.x + 0.5) * size - here.x, (key.y + 0.5) * size - here.z).length()


func _restream(li: int, at: Vector2i) -> void:
	var layer: Dictionary = LAYERS[li]
	var radius: int = layer["radius"]
	var lod: int = layer["lod"]
	var cells: Dictionary = _cells[li]
	# Let go of cells that have fallen behind (one cell of slack stops flicker at the edge).
	for key: Vector2i in cells.keys():
		if maxi(absi(key.x - at.x), absi(key.y - at.y)) > radius + 1:
			var old: Cell = cells[key]
			if old.node:
				old.node.queue_free()
			cells.erase(key)
	# Drop this layer's stale jobs, then ask for whatever is missing.
	_queue = _queue.filter(func(job: Array) -> bool: return job[0] != li)
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var key := Vector2i(at.x + dx, at.y + dz)
			if cells.has(key):
				var cell: Cell = cells[key]
				if cell.node:
					cell.node.multimesh.mesh = _mesh_for(lod, dx, dz)
			else:
				_queue.append([li, key])


func _mesh_for(lod: int, dx: int, dz: int) -> SphereMesh:
	return _mesh_hi if maxi(absi(dx), absi(dz)) <= lod else _mesh_lo


func _build(li: int, key: Vector2i) -> void:
	var cells: Dictionary = _cells[li]
	if cells.has(key):
		return
	var cell: Cell = _generate(li, key)
	cells[key] = cell
	if cell.node:
		var at: Vector2i = _centers[li]
		cell.node.multimesh.mesh = _mesh_for(LAYERS[li]["lod"], key.x - at.x, key.y - at.y)
		add_child(cell.node)


# ----------------------------------------------------------------------------------------------
# Growing a cell's clouds

func _generate(li: int, key: Vector2i) -> Cell:
	var layer: Dictionary = LAYERS[li]
	var size: float = layer["cell"]
	var cell := Cell.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(key.x, key.y, li * 131 + world_seed))

	# The slow noise map: high means a cloud bank, low means a gap. Each layer reads its own patch.
	var mid := Vector2((key.x + 0.5) * size, (key.y + 0.5) * size)
	var bank: float = 0.5 + 0.5 * _cover.get_noise_2d(mid.x + li * 9100.0, mid.y - li * 4700.0)
	var need: float = 1.0 - float(layer["coverage"]) * coverage
	if bank < need:
		return cell
	var richness: float = clampf((bank - need) / 0.25, 0.0, 1.0)
	var count: int = 1 + int(rng.randf() * float(layer["max_clouds"]) * (0.4 + 0.6 * richness))
	count = mini(count, layer["max_clouds"])

	var transforms: Array = []
	var customs: Array = []
	var colors: Array = []
	for i in count:
		var first: int = transforms.size()
		var cloud: Cloud = _grow_cloud(layer, key, rng, richness, transforms, customs, colors)
		cell.clouds.append(cloud)
		cell.spans.append([first, transforms.size(), cloud])
	if transforms.is_empty():
		return cell

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _mesh_lo
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
		mm.set_instance_custom_data(i, customs[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = _materials[li]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader swells the spheres, so give the culling some room.
	node.extra_cull_margin = (layer["puff"] as Vector2).y * 0.6
	cell.node = node
	cell.puff_count = transforms.size()
	cell.base = transforms
	for i in transforms.size():
		cell.radii.append((transforms[i] as Transform3D).basis.x.length())
		cell.tuft.append(1 if (customs[i] as Color).a > 0.5 else 0)
	return cell


func _grow_cloud(layer: Dictionary, key: Vector2i, rng: RandomNumberGenerator, richness: float,
		transforms: Array, customs: Array, colors: Array) -> Cloud:
	var cell_size: float = layer["cell"]
	var sizes: Vector2 = layer["size"]
	var puff_sizes: Vector2 = layer["puff"]
	var squash: float = layer["squash"]
	var flat_base: bool = layer["flat_base"]

	var half: float = lerpf(sizes.x, sizes.y, rng.randf() * (0.5 + 0.5 * richness))
	var rx: float = half
	var rz: float = half * rng.randf_range(0.55, 1.0)
	var turn: float = rng.randf() * TAU
	var base_y: float = float(layer["base"]) + altitude_shift + rng.randf_range(-1.0, 1.0) * float(layer["base_jitter"])
	var height: float = half * float(layer["tall"]) * rng.randf_range(0.7, 1.2)
	var foot := Vector3((key.x + rng.randf_range(0.2, 0.8)) * cell_size, base_y,
			(key.y + rng.randf_range(0.2, 0.8)) * cell_size)
	var core: Vector3 = foot + Vector3.UP * height * 0.3

	var cloud := Cloud.new()
	cloud.foot = foot
	cloud.foot_radius = maxf(rx, rz) * 0.8
	var size_share: float = inverse_lerp(sizes.x, sizes.y, half)
	cloud.thermal = float(layer["thermal"]) * lerpf(4.5, 9.0, size_share)

	# Stand columns of puffs on the footprint: tall in the middle, low at the rim, like a dome.
	var mean_puff: float = (puff_sizes.x + puff_sizes.y) * 0.5
	var columns: int = clampi(int(rx * rz / (mean_puff * mean_puff) * 1.15), 5, 26)
	var max_puffs: int = layer["max_puffs"]
	var low := Vector3.INF
	var high := -Vector3.INF
	for c in columns:
		var out: float = sqrt(rng.randf())
		var ang: float = rng.randf() * TAU
		var spot := Vector2(cos(ang) * out * rx, sin(ang) * out * rz).rotated(turn)
		var r: float = lerpf(puff_sizes.y, puff_sizes.x, out) * rng.randf_range(0.8, 1.1)
		var column_top: float = height * (1.0 - out * out) * rng.randf_range(0.55, 1.0)
		var y: float = base_y + r * squash * 0.5
		var lean := Vector2.ZERO
		while true:
			var at := Vector3(foot.x + spot.x + lean.x, y, foot.z + spot.y + lean.y)
			var cut: float = -2.0
			if flat_base:
				cut = clampf((base_y - y) / r, -2.0, 1.0)
			var share: float = clampf((y - base_y) / maxf(height, 1.0), 0.0, 1.0)
			var from_core: Vector3 = (at - core).normalized()
			transforms.append(Transform3D(
					Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r, r * squash, r)), at))
			customs.append(Color(rng.randf(), cut, share, 0.0))
			colors.append(Color(from_core.x * 0.5 + 0.5, from_core.y * 0.5 + 0.5, from_core.z * 0.5 + 0.5, 1.0))
			cloud.puffs.append_array(PackedFloat32Array([at.x, at.y, at.z, r]))
			low = low.min(at - Vector3.ONE * r)
			high = high.max(at + Vector3.ONE * r)
			# Climb the column: each puff a little smaller and a little off to one side.
			y += r * squash * rng.randf_range(0.75, 1.0)
			r *= rng.randf_range(0.8, 0.93)
			lean += Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * r * 0.3
			if y > base_y + column_top or cloud.puffs.size() / 4 >= max_puffs:
				break
		if cloud.puffs.size() / 4 >= max_puffs:
			break
	if layer["anvil"]:
		# The thunderhead: at the top the tower hits a ceiling and spreads out sideways into a
		# wide flat-bottomed anvil, blown out further downwind, with the tower's own head
		# bulging up through the middle of it.
		var blown: Vector2 = ANVIL_LEAN.normalized()
		var across := Vector2(-blown.y, blown.x)
		var spread: float = half * rng.randf_range(1.25, 1.6)
		var deck: float = high.y - puff_sizes.y * 0.75
		var middle := Vector3(foot.x + blown.x * spread * 0.3, deck, foot.z + blown.y * spread * 0.3)
		var below: Vector3 = middle - Vector3.UP * spread * 0.3
		var slabs: int = 30 + int(8.0 * richness)
		for a in slabs:
			var out: float = sqrt((a + rng.randf()) / slabs)
			var ang: float = a * 2.39996 + rng.randf_range(-0.3, 0.3)
			var along: float = cos(ang) * out * spread * 1.35
			var side: float = sin(ang) * out * spread * 0.9
			var r: float = lerpf(puff_sizes.y * 1.05, puff_sizes.x * 0.85, out) * rng.randf_range(0.85, 1.1)
			var flat: float = lerpf(0.5, 0.36, out)
			var at := Vector3(middle.x + blown.x * along + across.x * side,
					deck + r * flat * rng.randf_range(0.1, 0.4) * (1.0 - out),
					middle.z + blown.y * along + across.y * side)
			var from_core: Vector3 = (at - below).normalized()
			transforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r, r * flat, r)), at))
			customs.append(Color(rng.randf(), -0.45, 1.0, 0.0))
			colors.append(Color(from_core.x * 0.5 + 0.5, from_core.y * 0.5 + 0.5, from_core.z * 0.5 + 0.5, 1.0))
			# For the air's sake it counts as a ball as thick as the anvil, not as wide.
			cloud.puffs.append_array(PackedFloat32Array([at.x, at.y, at.z, r * flat * 1.3]))
			low = low.min(at - Vector3(r, r * flat, r))
			high = high.max(at + Vector3(r, r * flat, r))

	# The tufts: tiny puffs sitting just proud of the heap's outer puffs, ready to be knocked off.
	var heap_count: int = cloud.puffs.size() / 4
	var heap_from: int = transforms.size() - heap_count
	for t in int(layer["tufts"]):
		var host: Transform3D = transforms[heap_from + rng.randi() % heap_count]
		var host_r: Vector3 = host.basis.get_scale()
		var out_dir: Vector3 = (host.origin - core).normalized() + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.2, 1.0), rng.randf_range(-1.0, 1.0)) * 0.9
		# Mostly off to the sides, where they show against the sky, and never under a flat base.
		out_dir.y *= 0.45
		if flat_base:
			out_dir.y = absf(out_dir.y)
		out_dir = out_dir.normalized()
		var r: float = clampf(host_r.x * rng.randf_range(0.2, 0.36), 7.0, 46.0)
		var at: Vector3 = host.origin + out_dir * host_r * rng.randf_range(0.95, 1.15) + out_dir * r * 0.6
		var from_core: Vector3 = (at - core).normalized()
		# A wisp, wider than it is tall.
		transforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r * rng.randf_range(1.0, 1.5), r * 0.62 * maxf(squash, 0.7), r)), at))
		customs.append(Color(rng.randf(), -2.0, clampf((at.y - base_y) / maxf(height, 1.0), 0.0, 1.0), 1.0))
		colors.append(Color(from_core.x * 0.5 + 0.5, from_core.y * 0.5 + 0.5, from_core.z * 0.5 + 0.5, 1.0))

	cloud.center = (low + high) * 0.5
	cloud.radius = (high - low).length() * 0.5
	cloud.top_y = high.y
	return cloud


# ----------------------------------------------------------------------------------------------
# Questions about the air

## The clouds of one layer that could matter at p (its own cell and the eight around it).
func _near(li: int, p: Vector3) -> Array:
	var out: Array = []
	var cells: Dictionary = _cells[li]
	var at: Vector2i = _cell_of(p, LAYERS[li]["cell"])
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cell: Cell = cells.get(Vector2i(at.x + dx, at.y + dz))
			if cell:
				out.append_array(cell.clouds)
	return out


## 0..1: how deep inside cloud a world point is. 0 is clear air.
func density_at(world: Vector3) -> float:
	var p: Vector3 = world - drift
	var best: float = 0.0
	for li in LAYERS.size():
		var squash: float = LAYERS[li]["squash"]
		for cloud: Cloud in _near(li, p):
			if p.distance_squared_to(cloud.center) > cloud.radius * cloud.radius:
				continue
			var puffs: PackedFloat32Array = cloud.puffs
			for i in range(0, puffs.size(), 4):
				var d := Vector3(p.x - puffs[i], (p.y - puffs[i + 1]) / squash, p.z - puffs[i + 2])
				best = maxf(best, 1.0 - d.length() / puffs[i + 3])
	var inside: float = smoothstep(0.0, 0.3, best)
	if not sea_enabled:
		return inside
	var sea: float = smoothstep(SEA_Y + SEA_AMP * 0.6, SEA_Y + SEA_AMP * 0.25, p.y)
	return maxf(inside, sea)


## The air's velocity at a world point.
func wind_at(world: Vector3) -> Vector3:
	var p: Vector3 = world - drift
	var lift: float = 0.0
	# Thermals: a column of rising air from the cloud sea up into each cumulus and tower.
	for li in LAYERS.size():
		if float(LAYERS[li]["thermal"]) <= 0.0:
			continue
		for cloud: Cloud in _near(li, p):
			var out: float = Vector2(p.x - cloud.foot.x, p.z - cloud.foot.z).length() / cloud.foot_radius
			if out >= 1.0:
				continue
			var column: float = smoothstep(SEA_Y, SEA_Y + 160.0, p.y) * (1.0 - smoothstep(cloud.top_y - 60.0, cloud.top_y + 60.0, p.y))
			lift += cloud.thermal * (1.0 - out * out) * column
	# The wind will not let its daughter drown: strong lift once she sinks into the cloud sea.
	if sea_enabled:
		lift += RESCUE_LIFT * smoothstep(SEA_Y + SEA_AMP * 0.45, SEA_Y - 60.0, p.y)
	var air := Vector3(0.0, lift, 0.0)
	# Inside cloud the air is rough.
	var thick: float = density_at(world)
	if thick > 0.0:
		var t: float = _time * 40.0
		air += Vector3(_gust.get_noise_3d(p.x, p.y, t), _gust.get_noise_3d(p.y, p.z, t + 500.0),
				_gust.get_noise_3d(p.z, p.x, t + 900.0)) * 5.0 * thick
	return air

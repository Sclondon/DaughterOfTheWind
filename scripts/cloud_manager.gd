extends Node3D
## The sky's clouds, and the air they stand in.
##
## The sky is cut into square cells, one grid per cloud layer (see LAYERS). Cells stream in around
## `focus` and are freed behind it. What a cell holds depends only on its grid position and
## `world_seed`, so flying away and back finds the same clouds. A slow noise map decides where the
## cloud banks and the clear gaps are, and `coverage` (the weather) scales how much sky fills in.
##
## Each cloud is a heap of puffs drawn as one MultiMesh per cell with shaders/cloud_puff. Nearby
## cells use a rounder sphere than far ones. Under everything lies the sea of clouds, one big sheet
## that follows the focus (shaders/cloud_sea).
##
## The whole lot drifts on the wind: this node moves, and cells are worked out in its own space.
##
## The manager also answers questions about the air, in world space:
##   density_at(p)  0..1, how deep inside cloud a point is (the camera's whiteout uses it)
##   wind_at(p)     the air's velocity at a point: thermals rising under the cumulus and towers,
##                  gusts inside cloud, and the strong lift over the cloud sea that carries a
##                  sinking glider back up.

const PuffShader := preload("res://shaders/cloud_puff.gdshader")
const SeaShader := preload("res://shaders/cloud_sea.gdshader")

const SEA_Y := 0.0
const SEA_AMP := 170.0
const SEA_SIZE := 18000.0
const SEA_STEP := 100.0
## How many cells may be generated per frame while streaming.
const BUILDS_PER_FRAME := 2
## Lift (m/s) the air gives a glider that has sunk into the cloud sea.
const RESCUE_LIFT := 30.0
const WEATHERS := [0.55, 1.0, 1.7]

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
##   max_puffs  cap on puffs in one cloud
const LAYERS := [
	{
		"name": "cumulus", "cell": 900.0, "radius": 4, "lod": 1,
		"base": 330.0, "base_jitter": 60.0, "coverage": 0.52, "max_clouds": 2,
		"size": Vector2(110.0, 250.0), "puff": Vector2(36.0, 76.0), "tall": 0.95,
		"squash": 1.0, "flat_base": true, "thermal": 1.0, "max_puffs": 64,
	},
	{
		"name": "towers", "cell": 2600.0, "radius": 2, "lod": 2,
		"base": 60.0, "base_jitter": 40.0, "coverage": 0.4, "max_clouds": 1,
		"size": Vector2(380.0, 640.0), "puff": Vector2(130.0, 230.0), "tall": 2.3,
		"squash": 1.0, "flat_base": false, "thermal": 1.5, "max_puffs": 110,
	},
	{
		"name": "wisps", "cell": 1300.0, "radius": 3, "lod": 0,
		"base": 1250.0, "base_jitter": 220.0, "coverage": 0.48, "max_clouds": 2,
		"size": Vector2(200.0, 460.0), "puff": Vector2(30.0, 62.0), "tall": 0.1,
		"squash": 0.5, "flat_base": false, "thermal": 0.0, "max_puffs": 40,
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
var _time := 0.0


func _ready() -> void:
	# This node is moved every frame by the wind, so it must not be physics-interpolated.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_cover.seed = world_seed
	_cover.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cover.frequency = 1.0 / 5200.0
	_gust.seed = world_seed + 7
	_gust.frequency = 0.02
	_noise_tex = _make_noise()
	_mesh_hi = _make_sphere(28, 14)
	_mesh_lo = _make_sphere(16, 9)
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


func _process(delta: float) -> void:
	_time += delta
	drift += wind * delta
	position = drift
	_sea_mat.set_shader_parameter("drift", Vector2(drift.x, drift.z))
	if focus == null:
		return
	var here: Vector3 = focus.global_position - drift
	# The sheet steps along with the focus in whole grid steps, so its billows never swim.
	_sea.position = Vector3(snappedf(here.x, SEA_STEP), SEA_Y, snappedf(here.z, SEA_STEP))
	_look_around(here)
	for i in BUILDS_PER_FRAME:
		if _queue.is_empty():
			break
		var job: Array = _queue.pop_front()
		_build(job[0], job[1])


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
	coverage = WEATHERS[clampi(index, 0, WEATHERS.size() - 1)]
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
	for li in LAYERS.size():
		var layer_cells: Dictionary = _cells[li]
		cells += layer_cells.size()
		for key: Vector2i in layer_cells:
			var cell: Cell = layer_cells[key]
			clouds += cell.clouds.size()
			puffs += cell.puff_count
	return {"cells": cells, "clouds": clouds, "puffs": puffs, "queued": _queue.size()}


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
		var cloud: Cloud = _grow_cloud(layer, key, rng, richness, transforms, customs, colors)
		cell.clouds.append(cloud)
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

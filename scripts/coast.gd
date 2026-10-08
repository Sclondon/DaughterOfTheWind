extends Node3D
## The Windward Coast: an ocean, and in it a long island that rises straight out of the water in
## cliffs. On top is rolling grass with a patchwork of farms, hamlets, a village of stone towers,
## windmills turning in the sea wind, and woods. Rock spires stand in the sea around it and on the
## high ground.
##
## The shape of the land is one function, height_at(x, z), made from noise. The ground mesh, the
## ocean's shallows and foam, where things are placed, and the collision all come from it.
##
## For the glider this node is both a solid and a wind:
##   hit(p, radius)  pushes it back out of the ground, the sea, spires and towers
##   wind_at(p)      the sea wind is pushed upward where it meets rising ground, so there is lift
##                   all along the windward cliffs to soar on, and sink behind the hills

const MeshKit := preload("res://scripts/mesh_kit.gd")
const TerrainShader := preload("res://shaders/terrain.gdshader")
const OceanShader := preload("res://shaders/ocean.gdshader")

## Half the island's length (X) and depth (Z) before the noise roughs up the coastline.
const RX := 4300.0
const RZ := 2700.0
## The ground mesh covers this much each way, in squares of STEP metres.
const HALF_X := 5800.0
const HALF_Z := 3900.0
const STEP := 28.0
## How much of the island's edge is cliff. Smaller is steeper.
const CLIFF_BAND := 0.022
## The wind off the sea, blowing onto the south cliffs.
const SEA_WIND := Vector3(1.5, 0.0, -8.0)
const OCEAN_SIZE := 34000.0

var focus: Node3D
var noise_tex: Texture2D
var sun_dir := Vector3.UP
var haze_color := Color(0.73, 0.85, 0.96)
var sky_color := Color(0.09, 0.29, 0.7)
var haze_distance := 8500.0
var world_seed := 414

## Counts of what was placed, for the tests.
var windmills := 0
var houses := 0
var spires := 0

var _shore := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _fields := FastNoiseLite.new()
var _woods := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _ground_mat: ShaderMaterial
var _rock_mat: ShaderMaterial
var _ocean: MeshInstance3D
# Upright things to bump into: [Vector3 foot, float height, float radius at the foot, float radius at the top]
var _columns: Array = []
var _hubs: Array = []


func _ready() -> void:
	_rng.seed = world_seed
	_shore.seed = world_seed
	_shore.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_shore.frequency = 1.0 / 2400.0
	_shore.fractal_octaves = 3
	_hills.seed = world_seed + 1
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 1.0 / 900.0
	_hills.fractal_octaves = 3
	_fields.seed = world_seed + 2
	_fields.frequency = 1.0 / 1500.0
	_woods.seed = world_seed + 3
	_woods.frequency = 1.0 / 420.0

	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = TerrainShader
	_ground_mat.set_shader_parameter("noise_tex", noise_tex)
	_rock_mat = _ground_mat.duplicate() as ShaderMaterial
	_rock_mat.set_shader_parameter("use_farms", false)

	var height_map: ImageTexture = _build_ground()
	_build_ocean(height_map)
	_build_spires()
	_build_farms()
	_build_woods()


## Where the glider starts: out over the sea, flying in toward the south cliffs.
func start_position() -> Vector3:
	return Vector3(200, 400, RZ + 2400.0)


func _process(delta: float) -> void:
	for hub: Node3D in _hubs:
		hub.rotate_object_local(Vector3.BACK, delta * 0.9)
	if focus:
		_ocean.position = Vector3(focus.global_position.x, 0.0, focus.global_position.z)


# ----------------------------------------------------------------------------------------------
# The shape of the land

## How far inside the island a point is: 0 at the shoreline, rising inland, negative out at sea.
func _inland(x: float, z: float) -> float:
	return 1.0 - Vector2(x / RX, z / RZ).length() + _shore.get_noise_2d(x, z) * 0.24


## Height of the ground (or the sea bed, below zero) at a point.
func height_at(x: float, z: float) -> float:
	var m: float = _inland(x, z)
	if m < 0.0:
		return maxf(m * 900.0, -120.0)
	# Straight up out of the water in a cliff, then a tableland that rolls and climbs inland.
	var cliff: float = 105.0 + 85.0 * (0.5 + 0.5 * _hills.get_noise_2d(x * 0.35 + 900.0, z * 0.35))
	var rolling: float = _hills.get_noise_2d(x, z) * 55.0 * smoothstep(0.03, 0.25, m)
	return smoothstep(0.0, CLIFF_BAND, m) * cliff + smoothstep(0.03, 0.7, m) * 190.0 + rolling


## Which way the ground faces at a point.
func normal_at(x: float, z: float) -> Vector3:
	var e: float = 12.0
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e,
			height_at(x, z - e) - height_at(x, z + e)).normalized()


## 0..1: how much a point is farmland. Fields keep to the gentle ground away from the cliff edge.
func farm_at(x: float, z: float) -> float:
	return smoothstep(0.07, 0.15, _inland(x, z)) * smoothstep(-0.12, 0.12, _fields.get_noise_2d(x, z))


func _build_ground() -> ImageTexture:
	var nx: int = int(HALF_X * 2.0 / STEP) + 1
	var nz: int = int(HALF_Z * 2.0 / STEP) + 1
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for j in nz:
		for i in nx:
			heights[j * nx + i] = height_at(-HALF_X + i * STEP, -HALF_Z + j * STEP)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(nx * nz)
	normals.resize(nx * nz)
	colors.resize(nx * nz)
	for j in nz:
		for i in nx:
			var k: int = j * nx + i
			var x: float = -HALF_X + i * STEP
			var z: float = -HALF_Z + j * STEP
			var h: float = heights[k]
			verts[k] = Vector3(x, h, z)
			var n := Vector3(heights[j * nx + maxi(i - 1, 0)] - heights[j * nx + mini(i + 1, nx - 1)], 2.0 * STEP,
					heights[maxi(j - 1, 0) * nx + i] - heights[mini(j + 1, nz - 1) * nx + i]).normalized()
			normals[k] = n
			# Red carries the farmland to the shader. No fields on slopes or under water.
			var farm: float = 0.0
			if h > 20.0:
				farm = farm_at(x, z) * smoothstep(0.88, 0.96, n.y)
			colors[k] = Color(farm, 0.0, 0.0)

	var indices := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			var a: int = j * nx + i
			var b: int = a + 1
			var c: int = a + nx
			var d: int = c + 1
			# Leave out the sea bed where it is too deep to see.
			if heights[a] < -60.0 and heights[b] < -60.0 and heights[c] < -60.0 and heights[d] < -60.0:
				continue
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))

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

	# The same heights as a texture, so the ocean knows where its shallows are.
	var image := Image.create_from_data(nx, nz, false, Image.FORMAT_RF, heights.to_byte_array())
	image.convert(Image.FORMAT_RH)
	return ImageTexture.create_from_image(image)


func _build_ocean(height_map: ImageTexture) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(OCEAN_SIZE, OCEAN_SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = OceanShader
	mat.set_shader_parameter("noise_tex", noise_tex)
	mat.set_shader_parameter("height_tex", height_map)
	# Texel centres sit on the grid points, so the map covers half a step more on every side.
	mat.set_shader_parameter("land_rect", Vector4(-HALF_X - STEP * 0.5, -HALF_Z - STEP * 0.5,
			(int(HALF_X * 2.0 / STEP) + 1) * STEP, (int(HALF_Z * 2.0 / STEP) + 1) * STEP))
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
# Spires

func _build_spires() -> void:
	# Sea stacks: a ring of them standing in the water off the coast.
	var tries: int = 0
	while spires < 26 and tries < 600:
		tries += 1
		var ang: float = _rng.randf() * TAU
		var out: float = _rng.randf_range(1.0, 1.45)
		var x: float = cos(ang) * RX * out
		var z: float = sin(ang) * RZ * out
		var m: float = _inland(x, z)
		if m > -0.03 or m < -0.4 or _crowded(x, z, 260.0):
			continue
		var tall: float = _rng.randf_range(70.0, 290.0)
		_add_spire(Vector3(x, -25.0, z), tall + 25.0, tall * _rng.randf_range(0.16, 0.3) + 14.0)
	# Pinnacles: a few great needles of rock on the high ground.
	tries = 0
	var inland: int = 0
	while inland < 7 and tries < 400:
		tries += 1
		var x: float = _rng.randf_range(-RX, RX) * 0.7
		var z: float = _rng.randf_range(-RZ, RZ) * 0.7
		if _inland(x, z) < 0.25 or farm_at(x, z) > 0.3 or _crowded(x, z, 500.0):
			continue
		var tall: float = _rng.randf_range(160.0, 330.0)
		_add_spire(Vector3(x, height_at(x, z) - 15.0, z), tall, tall * _rng.randf_range(0.13, 0.2) + 16.0)
		inland += 1


func _crowded(x: float, z: float, gap: float) -> bool:
	for c: Array in _columns:
		var foot: Vector3 = c[0]
		if Vector2(foot.x - x, foot.z - z).length() < gap:
			return true
	return false


## A spire's radius, as a share of its foot, at a share t of the way up.
func _taper(t: float) -> float:
	return 1.0 - 0.72 * pow(t, 1.25)


func _add_spire(foot: Vector3, height: float, radius: float) -> void:
	var sides: int = 11
	var levels: int = 9
	var lean := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * radius * 0.35
	var twist: float = _rng.randf() * TAU
	var rings: Array = []
	for i in levels + 1:
		var t: float = float(i) / float(levels)
		var ring := PackedVector3Array()
		var mid := Vector2(lean.x, lean.y) * t * t
		for j in sides:
			# Counter-clockwise seen from above, as MeshKit.loft wants for rings that climb.
			var a: float = TAU * float(j) / float(sides) + twist
			var r: float = radius * _taper(t) * _rng.randf_range(0.8, 1.15)
			ring.append(Vector3(mid.x + cos(a) * r, t * height, mid.y - sin(a) * r))
		rings.append(ring)
	var node := MeshInstance3D.new()
	node.mesh = MeshKit.loft(rings)
	node.material_override = _rock_mat
	node.position = foot
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_columns.append([foot, height, radius * 1.05, radius * _taper(1.0) * 1.1 + absf(lean.length())])
	spires += 1


# ----------------------------------------------------------------------------------------------
# Farms, the village and the windmills

func _paint(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


## A random spot on the island that passes `test` (called with x, z), or Vector3.INF.
func _find_spot(test: Callable, tries: int = 200) -> Vector3:
	for i in tries:
		var x: float = _rng.randf_range(-RX, RX)
		var z: float = _rng.randf_range(-RZ, RZ)
		if test.call(x, z):
			return Vector3(x, height_at(x, z), z)
	return Vector3.INF


func _build_farms() -> void:
	var walls: Array = []  # [Transform3D, Color] for each house body
	var roofs: Array = []
	var on_farm := func(x: float, z: float) -> bool:
		return farm_at(x, z) > 0.7 and normal_at(x, z).y > 0.95

	# Hamlets scattered through the fields.
	for i in 16:
		var heart: Vector3 = _find_spot(on_farm)
		if heart == Vector3.INF:
			continue
		for k in _rng.randi_range(5, 11):
			var at := Vector2(heart.x, heart.z) + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(15.0, 95.0)
			_add_house(at, walls, roofs)

	# The village: on the south cliff top, looking out to sea, with stone towers among the houses.
	var village := Vector2(-500.0, 0.0)
	for z in range(int(RZ * 1.3), 0, -20):
		if _inland(village.x, float(z)) > 0.07:
			village.y = float(z) - 60.0
			break
	for k in 46:
		_add_house(village + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * 190.0, walls, roofs)
	var stone := _paint(Color(0.78, 0.74, 0.66))
	var slate := _paint(Color(0.24, 0.33, 0.45), 0.6)
	for k in 6:
		var at: Vector2 = village + Vector2.from_angle(TAU * float(k) / 6.0 + 0.4) * _rng.randf_range(40.0, 150.0)
		_add_tower(at, _rng.randf_range(32.0, 58.0) if k > 0 else 78.0, stone, slate)

	_scatter(walls, BoxMesh.new(), 0.85)
	var prism := PrismMesh.new()
	_scatter(roofs, prism, 0.8)
	houses = walls.size()

	# Windmills: in the fields, and a line of them along the windward cliff top.
	var cream := _paint(Color(0.9, 0.86, 0.76))
	var cap := _paint(Color(0.55, 0.25, 0.18), 0.7)
	var sail := _paint(Color(0.95, 0.93, 0.86), 0.8)
	var timber := _paint(Color(0.35, 0.25, 0.18))
	var spots: Array = []
	var on_edge := func(x: float, z: float) -> bool:
		var m: float = _inland(x, z)
		return z > 0.0 and m > 0.04 and m < 0.075 and normal_at(x, z).y > 0.93
	for i in 34:
		var at: Vector3 = _find_spot(on_edge if i % 3 == 0 else on_farm)
		if at == Vector3.INF:
			continue
		var clear := true
		for other: Vector3 in spots:
			if other.distance_to(at) < 230.0:
				clear = false
		if clear:
			spots.append(at)
			_add_windmill(at, _rng.randf_range(2.0, 3.2), cream, cap, sail, timber)


func _add_house(at: Vector2, walls: Array, roofs: Array) -> void:
	if normal_at(at.x, at.y).y < 0.94:
		return
	var size := Vector3(_rng.randf_range(8.0, 14.0), _rng.randf_range(4.5, 6.5), _rng.randf_range(6.0, 9.0))
	var ground: float = height_at(at.x, at.y)
	var turn := Basis(Vector3.UP, _rng.randf() * TAU)
	var wall := Color(0.9, 0.86, 0.76).lerp(Color(0.72, 0.66, 0.56), _rng.randf())
	var tile: Color = [Color(0.62, 0.27, 0.18), Color(0.5, 0.3, 0.2), Color(0.32, 0.36, 0.42)][_rng.randi() % 3]
	walls.append([Transform3D(turn.scaled_local(size), Vector3(at.x, ground + size.y * 0.5 - 0.5, at.y)), wall])
	var pitch: float = size.z * 0.45
	roofs.append([Transform3D(turn.scaled_local(Vector3(size.x + 1.2, pitch, size.z + 1.4)),
			Vector3(at.x, ground + size.y - 0.5 + pitch * 0.5, at.y)), tile])


## Many copies of one mesh, each with its own transform and colour, drawn in one go.
func _scatter(items: Array, mesh: Mesh, roughness: float) -> void:
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
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = roughness
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _add_tower(at: Vector2, height: float, stone: Material, slate: Material) -> void:
	var ground: float = height_at(at.x, at.y) - 2.0
	var radius: float = height * 0.11 + 2.0
	var shaft := CylinderMesh.new()
	shaft.top_radius = radius * 0.82
	shaft.bottom_radius = radius
	shaft.height = height
	shaft.radial_segments = 12
	var body := MeshInstance3D.new()
	body.mesh = shaft
	body.material_override = stone
	body.position = Vector3(at.x, ground + height * 0.5, at.y)
	add_child(body)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius * 1.05
	cone.height = height * 0.42
	cone.radial_segments = 12
	var roof := MeshInstance3D.new()
	roof.mesh = cone
	roof.material_override = slate
	roof.position = Vector3(at.x, ground + height + cone.height * 0.5, at.y)
	add_child(roof)
	_columns.append([Vector3(at.x, ground, at.y), height + cone.height, radius, radius * 0.4])


func _add_windmill(at: Vector3, size: float, cream: Material, cap: Material, sail: Material, timber: Material) -> void:
	var mill := Node3D.new()
	mill.position = at - Vector3.UP
	# Face into the sea wind.
	mill.rotation.y = atan2(SEA_WIND.x, SEA_WIND.z) + _rng.randf_range(-0.15, 0.15)
	mill.scale = Vector3.ONE * size
	add_child(mill)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 2.3
	shaft.bottom_radius = 3.8
	shaft.height = 16.0
	shaft.radial_segments = 10
	var body := MeshInstance3D.new()
	body.mesh = shaft
	body.material_override = cream
	body.position.y = 8.0
	mill.add_child(body)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.9
	cone.height = 4.2
	cone.radial_segments = 10
	var roof := MeshInstance3D.new()
	roof.mesh = cone
	roof.material_override = cap
	roof.position.y = 18.1
	mill.add_child(roof)
	# Four sails on a hub at the front. Each is a spar with a wide cloth vane along one side.
	var hub := Node3D.new()
	hub.position = Vector3(0, 15.0, -3.1)
	hub.rotation.z = _rng.randf() * TAU
	mill.add_child(hub)
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.z = TAU * float(i) / 4.0
		hub.add_child(arm)
		arm.add_child(MeshKit.rod(Vector3.ZERO, Vector3(0, 11.5, 0), 0.16, timber))
		var vane := MeshInstance3D.new()
		var cloth := BoxMesh.new()
		cloth.size = Vector3(2.4, 8.6, 0.1)
		vane.mesh = cloth
		vane.material_override = sail
		vane.position = Vector3(1.25, 7.0, 0.0)
		arm.add_child(vane)
	_hubs.append(hub)
	_columns.append([mill.position, 19.0 * size, 4.0 * size, 2.5 * size])
	windmills += 1


func _build_woods() -> void:
	var trees: Array = []
	for i in 14000:
		if trees.size() >= 3200:
			break
		var x: float = _rng.randf_range(-RX, RX) * 1.1
		var z: float = _rng.randf_range(-RZ, RZ) * 1.1
		if _inland(x, z) < 0.035 or _woods.get_noise_2d(x, z) < 0.12 or farm_at(x, z) > 0.4:
			continue
		if normal_at(x, z).y < 0.9:
			continue
		var r: float = _rng.randf_range(5.0, 9.5)
		var green := Color(0.16, 0.33, 0.14).lerp(Color(0.26, 0.42, 0.16), _rng.randf())
		trees.append([Transform3D(Basis.from_scale(Vector3(r, r * _rng.randf_range(1.0, 1.5), r)),
				Vector3(x, height_at(x, z) + r * 0.6, z)), green])
	var blob := SphereMesh.new()
	blob.radius = 1.0
	blob.height = 2.0
	blob.radial_segments = 7
	blob.rings = 4
	_scatter(trees, blob, 1.0)


# ----------------------------------------------------------------------------------------------
# For the glider

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
	for c: Array in _columns:
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

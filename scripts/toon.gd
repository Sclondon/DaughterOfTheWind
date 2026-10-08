extends RefCounted
## Makes the cel-shaded watercolour materials (shaders/toon) that everything solid is painted with.

const ToonShader := preload("res://shaders/toon.gdshader")


## A plain colour. `wash_size` is how many metres one tile of the watercolour texture covers:
## small for small things. `world` paints by world position, for things that never move.
static func paint(color: Color, wash_size: float = 2.0, world: bool = false) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ToonShader
	mat.set_shader_parameter("albedo", color)
	mat.set_shader_parameter("wash_size", wash_size)
	mat.set_shader_parameter("world_wash", world)
	return mat


## For a MultiMesh whose copies each carry their own colour.
static func tinted(wash_size: float = 40.0, world: bool = true) -> ShaderMaterial:
	var mat: ShaderMaterial = paint(Color.WHITE, wash_size, world)
	mat.set_shader_parameter("use_vertex_color", true)
	return mat


## A colour that also gives off light (windows, lanterns).
static func glowing(color: Color, glow: Color, wash_size: float = 2.0) -> ShaderMaterial:
	var mat: ShaderMaterial = paint(color, wash_size)
	mat.set_shader_parameter("glow", glow)
	return mat

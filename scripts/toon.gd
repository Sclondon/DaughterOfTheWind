extends RefCounted
## Makes the cel-shaded materials (shaders/toon) that everything solid is painted with.

const ToonShader := preload("res://shaders/toon.gdshader")


## A plain flat colour.
static func paint(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ToonShader
	mat.set_shader_parameter("albedo", color)
	return mat


## For a MultiMesh whose copies each carry their own colour.
static func tinted() -> ShaderMaterial:
	var mat: ShaderMaterial = paint(Color.WHITE)
	mat.set_shader_parameter("use_vertex_color", true)
	return mat


## A colour that also gives off light (windows, lanterns).
static func glowing(color: Color, glow: Color) -> ShaderMaterial:
	var mat: ShaderMaterial = paint(color)
	mat.set_shader_parameter("glow", glow)
	return mat


## Matte, with the faint speckle of an eggshell.
static func eggshell(color: Color) -> ShaderMaterial:
	var mat: ShaderMaterial = paint(color)
	mat.set_shader_parameter("eggshell", 1.0)
	mat.set_shader_parameter("rim", 0.3)
	return mat


## With a hard highlight (glass, polished metal).
static func shiny(color: Color, glow: Color = Color.BLACK) -> ShaderMaterial:
	var mat: ShaderMaterial = glowing(color, glow)
	mat.set_shader_parameter("shine", 1.0)
	return mat

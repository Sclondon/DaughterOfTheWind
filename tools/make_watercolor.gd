extends SceneTree
## Paints art/watercolor.png, the texture every shader uses for the watercolour look.
##   red:   wide soft blotches, where a wash dried lighter or darker
##   green: pooling, where pigment gathered and went richer
##   blue:  paper grain
## It tiles. Run: godot --headless --path . -s res://tools/make_watercolor.gd

func _initialize() -> void:
	var size := 512
	var layers: Array = []
	for spec: Array in [[11, 0.006, 3], [23, 0.016, 4], [37, 0.11, 2]]:
		var noise := FastNoiseLite.new()
		noise.seed = spec[0]
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = spec[1]
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = spec[2]
		layers.append(noise.get_seamless_image(size, size, false, false, 0.15, true))
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var blot: float = (layers[0] as Image).get_pixel(x, y).r
			# Pooling: sharpen the middle of the second layer into soft-edged puddles.
			var pool: float = smoothstep(0.42, 0.62, (layers[1] as Image).get_pixel(x, y).r)
			var grain: float = (layers[2] as Image).get_pixel(x, y).r
			image.set_pixel(x, y, Color(blot, pool, grain))
	image.save_png("res://art/watercolor.png")
	print("saved art/watercolor.png")
	quit()

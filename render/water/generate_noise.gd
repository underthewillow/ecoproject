extends SceneTree

## One-off asset generator, not part of the runtime. Produces
## caustic_noise.png: a tileable Simplex noise field used by
## water_background.gdshader for caustics, sampled twice at different
## scales/scroll speeds and multiplied together (the standard real-time
## caustics technique - genuine noise instead of hand-written sine math,
## which reads as too mathematically regular no matter how many layers
## you stack).
##
## Regenerate with:
##   godot --headless --path . -s res://render/water/generate_noise.gd
## then force an import pass so the engine picks up the new file:
##   godot --headless --editor --quit

func _initialize() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.025
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4

	var image := noise.get_image(512, 512, false, false, true)
	var err := image.save_png("res://render/water/caustic_noise.png")
	print("save_png result: %d" % err)
	quit()

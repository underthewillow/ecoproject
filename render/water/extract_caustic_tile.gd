extends SceneTree

## One-off extraction (not part of the runtime): crops the pure "upper"
## terrain tile (all four corners = caustic-lit water, not a lower/transition
## tile) out of the PixelLab Wang tileset sheet, per its metadata bounding_box.
## This tile is genuinely seamless by construction (it's a Wang autotile
## interior tile), unlike the hand-written sine/noise attempts.
##
## Run: godot --headless --path . -s res://render/water/extract_caustic_tile.gd

func _initialize() -> void:
	var sheet := Image.new()
	var err := sheet.load("res://render/water/tileset_raw.png")
	if err != OK:
		print("failed to load sheet: %d" % err)
		quit()
		return

	var tile := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	tile.blit_rect(sheet, Rect2i(0, 96, 32, 32), Vector2i.ZERO)
	var save_err := tile.save_png("res://render/water/caustic_tile.png")
	print("save_png result: %d" % save_err)
	quit()

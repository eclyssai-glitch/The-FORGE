extends SceneTree
## Rasterizes res://icon.svg into res://icon.png (256×256) for the Windows executable icon.
## Usage: godot --headless --path . -s tools/make_icon.gd

func _init() -> void:
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	var img := Image.new()
	var err := img.load_svg_from_string(svg, 2.0)
	if err != OK:
		push_error("SVG load failed: %d" % err)
		quit(1)
		return
	img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	err = img.save_png("res://icon.png")
	print("icon.png written (%dx%d): %s" % [img.get_width(), img.get_height(), error_string(err)])
	quit(0 if err == OK else 1)

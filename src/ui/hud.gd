extends CanvasLayer
## Native UI root. (Loop 1 skeleton: DEMO MODE badge.)

func _ready() -> void:
	var badge := Label.new()
	badge.name = "DemoBadge"
	badge.text = "DEMO MODE · SIMULATED EVENTS"
	badge.add_theme_color_override("font_color", Palette.EMBER)
	badge.position = Vector2(24, 20)
	add_child(badge)

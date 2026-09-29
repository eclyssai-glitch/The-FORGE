class_name UniversePanel
extends PanelContainer
## UNIVERSE: the sites of the universe — the ORIGIN CHAMBER and three dormant seeds. Clicking a
## row selects it and asks the camera to frame it (Session.select + Session.focus). A short
## navigation hint closes the panel (drag / wheel / WASD / C).

const SITES: Array[StringName] = [&"origin_chamber", &"seed_aurel", &"seed_vesper", &"seed_lattice"]
const HINTS: Array = [["DRAG", "ORBIT"], ["WHEEL", "ZOOM"], ["WASD", "FLY"], ["C", "RESET VIEW"]]

var list: EntityList


func _init() -> void:
	name = "UniversePanel"
	theme_type_variation = &"HudPanel"
	UiKit.catch_mouse(self)
	var v := UiKit.vbox(8)
	add_child(v)
	var head := UiKit.header("SITES")
	v.add_child(head[0])
	(head[1] as Label).text = "%d" % SITES.size()
	list = EntityList.new(SITES, {}, true)
	list.name = "Sites"
	v.add_child(list)
	v.add_child(UiKit.separator())
	var grid := GridContainer.new()
	grid.name = "Hint"
	grid.columns = 4
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	# Key and action share one font and size (spaced caps, SIZE_SMALL): same line height and
	# baseline on every row; only the colour tells the key (BONE) from the action (TEXT_DIM).
	for h: Array in HINTS:
		grid.add_child(UiKit.label(String(h[0]), &"RowText"))
		grid.add_child(UiKit.label(String(h[1]), &"Caption"))
	v.add_child(grid)

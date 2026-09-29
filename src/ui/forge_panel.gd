class_name ForgePanel
extends PanelContainer
## FORGE: the construct at a glance — origin core, the five layers and the verification array,
## each with its derived status. Clicking a row selects the entity (Session.select).

var list: EntityList
var count_label: Label


func _init() -> void:
	name = "ForgePanel"
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UiKit.vbox(8)
	add_child(v)
	var head := UiKit.header("CONSTRUCT")
	v.add_child(head[0])
	count_label = head[1]
	list = EntityList.new(ids())
	list.name = "Entities"
	v.add_child(list)


## Rows, top to bottom: core, layers I–V, verification array.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = [&"origin_core"]
	for i in OriginChamberScript.LAYER_COUNT:
		out.append(OriginChamberScript.layer_entity(i))
	out.append(&"verification_array")
	return out


func _ready() -> void:
	Simulation.event_emitted.connect(_on_event)
	Simulation.world_rebuilt.connect(refresh)
	refresh()


func refresh() -> void:
	count_label.text = "LAYERS %d/%d" % [Simulation.world.layers_built(), OriginChamberScript.LAYER_COUNT]


func _on_event(_e: SimEvent) -> void:
	refresh()

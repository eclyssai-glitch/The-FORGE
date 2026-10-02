class_name WorkWorld
extends Node3D
## The work worlds of the living prototype (Loop 5): one WorkSite per LivingLayout.WORLDS entry
## (three worlds the user can point at). Owner: animator. Only MIKU's hands change them (through
## Miku: WorldBuild.work/fault/repair/dismantle); this node steps their visuals. Group GROUP.
## Each site is an entity (`world_vesper`, `world_calyx`, `world_orrin`): pick body on layer 2 with
## meta entity_id, group SessionState.entity_group(id), focus bounds.

const GROUP := &"living_worlds"

var sites: Dictionary = {}


func _init() -> void:
	name = "WorkWorld"
	for w in LivingLayout.WORLDS:
		var s := WorkSite.new(w[0], w[1], w[2], w[3])
		sites[w[0]] = s
		add_child(s)


func _ready() -> void:
	add_to_group(GROUP)


func ids() -> Array[StringName]:
	return LivingLayout.world_ids()


func site(id: StringName) -> WorkSite:
	return sites.get(id, null)


func has_world(id: StringName) -> bool:
	return sites.has(id)


## World point the flying matter of `id` passes through (the working hand's palm); INF = none.
func set_via(id: StringName, p: Vector3) -> void:
	var s := site(id)
	if s != null:
		s.via = p


func step(dt: float) -> void:
	for s: WorkSite in sites.values():
		s.step(dt)

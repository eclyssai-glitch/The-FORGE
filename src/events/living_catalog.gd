class_name LivingCatalog
extends RefCounted
## Selectable entities of the LIVING scenario (Loop 5): MIKU and the worlds she can work on.
## Each pick body carries the meta `entity_id` (Picker) and each visual root joins
## Session.entity_group(id). Fictional.

const IDS: Array[StringName] = [&"miku", &"world_vesper", &"world_calyx", &"world_orrin"]


static func all_ids() -> Array[StringName]:
	return IDS.duplicate()


## {"id", "title", "kind", "kind_name", "body", "summary"}, or {} for an unknown id.
static func info(id: StringName) -> Dictionary:
	if id == &"miku":
		return {"id": id, "title": "MIKU", "kind": 0, "kind_name": "CENTRAL AGENT", "body": "figure",
			"summary": "She thinks, commands her hands and builds. Click to call her; Enter to speak to her."}
	var w := LivingScript.world(id)
	if w.is_empty():
		return {}
	return {"id": id, "title": String(w["name"]), "kind": 1, "kind_name": "WORLD", "body": "planet",
		"summary": "A world MIKU can work on. Click it to point her at it."}


static func status(id: StringName, s: LivingState) -> String:
	if id == &"miku":
		if s.test == 0:
			return "STILL"
		if s.is_failing():
			return "STRAINED"
		return LivingState.PHASE_NAMES[s.phase]
	if LivingScript.world(id).is_empty():
		return "UNKNOWN"
	if id != s.order_world:
		return "WAITING"
	if s.world_complete_at >= 0.0:
		return "WHOLE"
	if s.is_failing():
		return "FAILING"
	if s.step >= 0:
		return "%s · %d/%d" % [s.step_name, s.steps_done(), LivingScript.STEPS.size()]
	return "ORDERED"

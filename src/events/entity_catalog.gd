class_name EntityCatalog
extends RefCounted
## Static catalog of selectable entities and their derived status.
## All entities are fictional elements of the demo universe.

enum Kind { SITE, CORE, FIELD, LAYER, ARRAY, DORMANT }

const KIND_NAMES: Array[String] = ["SITE", "CORE", "FIELD", "LAYER", "ARRAY", "DORMANT SEED"]


static func all_ids() -> Array[StringName]:
	var ids: Array[StringName] = [&"origin_chamber", &"origin_core", &"fragment_field"]
	for i in OriginChamberScript.LAYER_COUNT:
		ids.append(OriginChamberScript.layer_entity(i))
	ids.append_array([&"verification_array", &"seed_aurel", &"seed_vesper", &"seed_lattice"])
	return ids


static func info(id: StringName) -> Dictionary:
	match id:
		&"origin_chamber":
			return _row(id, "ORIGIN CHAMBER", Kind.SITE, "The first site of the universe, where constructs are born.")
		&"origin_core":
			return _row(id, "ORIGIN CORE", Kind.CORE, "Suspended energy core that drives every construction step.")
		&"fragment_field":
			return _row(id, "FRAGMENT FIELD", Kind.FIELD, "Loose geometric fragments released by the core.")
		&"verification_array":
			return _row(id, "VERIFICATION ARRAY", Kind.ARRAY, "Sweeping ring that runs the simulated checks.")
		&"seed_aurel":
			return _row(id, "SEED · AUREL", Kind.DORMANT, "Dormant site reserved for a future construct.")
		&"seed_vesper":
			return _row(id, "SEED · VESPER", Kind.DORMANT, "Dormant site reserved for a future construct.")
		&"seed_lattice":
			return _row(id, "SEED · LATTICE", Kind.DORMANT, "Dormant site reserved for a future construct.")
	var i := layer_index(id)
	if i >= 0:
		return _row(id, "LAYER %s · %s" % [OriginChamberScript.roman(i + 1), OriginChamberScript.LAYER_NAMES[i]],
				Kind.LAYER, "Ring %d of the construct, assembled from fragments." % (i + 1))
	return {}


## Human-readable status of an entity given the current world.
static func status(id: StringName, w: WorldState) -> String:
	match id:
		&"origin_chamber":
			return w.phase_name()
		&"origin_core":
			if w.core_online_at >= 0.0:
				return "ONLINE"
			return "ACTIVATING" if w.core_activation_at >= 0.0 else "DORMANT"
		&"fragment_field":
			if w.fragments_at < 0.0:
				return "LATENT"
			return "ASSEMBLED" if w.layers_built() == w.layer_times.size() else "%d FRAGMENTS" % w.fragment_count
		&"verification_array":
			if w.verified_at >= 0.0:
				return "PASSED"
			if w.verification_at >= 0.0:
				return "CHECK %d/%d" % [w.checks.size(), OriginChamberScript.CHECKS.size()]
			return "STANDBY"
		&"seed_aurel", &"seed_vesper", &"seed_lattice":
			return "DORMANT"
	var i := layer_index(id)
	if i >= 0:
		if i >= w.layer_times.size() or w.layer_times[i] < 0.0:
			return "PENDING"
		if w.finalized_at >= 0.0:
			return "FINAL"
		if w.verified_at >= 0.0:
			return "VERIFIED"
		return "FINISHED" if w.materials_at >= 0.0 else "RAW"
	return "UNKNOWN"


## Layer index encoded in an id like &"layer_3", or -1 if the id is not a valid layer.
static func layer_index(id: StringName) -> int:
	var s := String(id)
	if not s.begins_with("layer_"):
		return -1
	var digits := s.trim_prefix("layer_")
	if not digits.is_valid_int():
		return -1
	var i := digits.to_int()
	return i if i >= 0 and i < OriginChamberScript.LAYER_COUNT else -1


static func _row(id: StringName, title: String, kind: Kind, summary: String) -> Dictionary:
	return {"id": id, "title": title, "kind": kind, "kind_name": KIND_NAMES[kind], "summary": summary}

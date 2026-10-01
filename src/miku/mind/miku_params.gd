class_name MikuParams
extends RefCounted
## The numbers of MIKU's personality and body that the configuration can change (Loop 5, ADR-016).
## Owner: animator. The schema, ranges and validation belong to the interaction system
## (src/agent/, game-engineer); this class only reads an already validated configuration
## ({"identity": {...}, "behaviour": {...}, "appearance": {...}}), clamps every value to the range
## the runtime supports and fills the missing keys with the defaults below. Pure.
##
## identity  (0..1): temperament (0 serene .. 1 fiery), curiosity, patience, pride.
## behaviour (0..1): frustration_threshold (frustration at which she becomes FRUSTRATED),
##                   aggression_peak (how far composure falls when ANGRY), recovery_speed,
##                   interruption_tolerance (how willingly she leaves the work for the user).
## appearance: height, shoulder_width, neck_length, chest_volume (bone scales, 1 = sculpted),
##             halo_radius (scale of the halo), glow (0..1, inner light of the body).

const IDENTITY_DEFAULTS := {
	"temperament": 0.45, "curiosity": 0.7, "patience": 0.6, "pride": 0.6,
}
const BEHAVIOUR_DEFAULTS := {
	"frustration_threshold": 0.4, "aggression_peak": 0.85, "recovery_speed": 0.5,
	"interruption_tolerance": 0.5,
}
const APPEARANCE_DEFAULTS := {
	"height": 1.0, "shoulder_width": 1.0, "neck_length": 1.0, "chest_volume": 1.0,
	"halo_radius": 1.0, "glow": 0.5,
}
## Supported range of each appearance value (the rig deforms cleanly inside it).
const APPEARANCE_RANGES := {
	"height": Vector2(0.85, 1.15), "shoulder_width": Vector2(0.85, 1.2), "neck_length": Vector2(0.8, 1.3),
	"chest_volume": Vector2(0.85, 1.2), "halo_radius": Vector2(0.6, 1.6), "glow": Vector2(0.0, 1.0),
}
const SECTIONS := [&"identity", &"behaviour", &"appearance"]

var identity: Dictionary = IDENTITY_DEFAULTS.duplicate()
var behaviour: Dictionary = BEHAVIOUR_DEFAULTS.duplicate()
var appearance: Dictionary = APPEARANCE_DEFAULTS.duplicate()


## Merges a (partial) configuration. Returns the keys that actually changed, as
## "section.key" strings (empty when nothing changed).
func apply(config: Dictionary) -> PackedStringArray:
	var changed := PackedStringArray()
	_merge(&"identity", identity, IDENTITY_DEFAULTS, config.get("identity", {}), changed)
	_merge(&"behaviour", behaviour, BEHAVIOUR_DEFAULTS, config.get("behaviour", {}), changed)
	_merge(&"appearance", appearance, APPEARANCE_DEFAULTS, config.get("appearance", {}), changed)
	return changed


func value(section: StringName, key: String) -> float:
	match section:
		&"identity":
			return float(identity.get(key, IDENTITY_DEFAULTS.get(key, 0.0)))
		&"behaviour":
			return float(behaviour.get(key, BEHAVIOUR_DEFAULTS.get(key, 0.0)))
		&"appearance":
			return float(appearance.get(key, APPEARANCE_DEFAULTS.get(key, 0.0)))
	return 0.0


## The whole configuration as one dictionary (copies).
func to_dict() -> Dictionary:
	return {"identity": identity.duplicate(), "behaviour": behaviour.duplicate(),
		"appearance": appearance.duplicate()}


static func clamp_value(section: StringName, key: String, v: float) -> float:
	if section == &"appearance":
		var rng: Vector2 = APPEARANCE_RANGES.get(key, Vector2(0.0, 2.0))
		return clampf(v, rng.x, rng.y)
	return clampf(v, 0.0, 1.0)


func _merge(section: StringName, into: Dictionary, defaults: Dictionary, from: Variant,
		changed: PackedStringArray) -> void:
	if not from is Dictionary:
		return
	for k: Variant in (from as Dictionary):
		var key := String(k)
		if not defaults.has(key):
			continue
		var raw: Variant = (from as Dictionary)[k]
		if not (raw is float or raw is int):
			continue
		var v := clamp_value(section, key, float(raw))
		if not is_equal_approx(float(into[key]), v):
			into[key] = v
			changed.append("%s.%s" % [section, key])

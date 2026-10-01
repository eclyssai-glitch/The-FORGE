class_name ConfigValidator
extends RefCounted
## Validates a StructuredPatch against ConfigSchema and the current configuration (ADR-016).
## Pure logic: it decides, it never applies (MikuConfig.apply does, with the validated value).
##
## Checks, in order: target file (ConfigSchema.FILE) -> path (section + key; a key filed under
## the wrong section is moved to its own section with a note; an appearance request with no real
## support is REQUIRES_ASSET) -> type (numbers only) -> relative resolution (current + delta) ->
## range (clamped to [min, max] with an explanation) -> change (same as current = UNCHANGED).
## Values are rounded to ROUND_DECIMALS.

enum Status {
	## Valid, applied as requested.
	OK,
	## Valid after clamping into the property's range (see notes).
	CLAMPED,
	## Valid but equal to the current value (nothing to apply; e.g. already at the limit).
	UNCHANGED,
	## Invalid (unknown file/property, wrong type...): nothing applied. See `reason`.
	REJECTED,
	## The request needs new assets (no rig/material support): refused, nothing applied.
	REQUIRES_ASSET,
}

const STATUS_NAMES: Array[String] = ["OK", "CLAMPED", "UNCHANGED", "REJECTED", "REQUIRES_ASSET"]
const ROUND_DECIMALS := 3

## Note codes (Result.codes) explaining adjustments.
const NOTE_CLAMPED := &"clamped"
const NOTE_SECTION := &"section_corrected"
const NOTE_UNCHANGED := &"unchanged"
const NOTE_ROUNDED := &"rounded"


## Outcome of one validation.
class Result:
	extends RefCounted
	var status: Status = Status.REJECTED
	## Resolved "section.key" ("" when the property could not be resolved).
	var path := ""
	var section: StringName = &""
	var key := ""
	## Value as requested (absolute, after resolving a relative patch), and the value to apply.
	var requested: Variant = null
	var value: Variant = null
	var old_value: Variant = null
	## Why it was rejected / requires assets ("" otherwise).
	var reason := ""
	## Human explanations of every adjustment (clamp, section moved, rounding, unchanged).
	var notes := PackedStringArray()
	## Machine codes of the notes (NOTE_*).
	var codes: Array[StringName] = []

	## True when there is a value to write (OK or CLAMPED).
	func applicable() -> bool:
		return status == Status.OK or status == Status.CLAMPED

	func status_name() -> String:
		return STATUS_NAMES[status]

	func to_dict() -> Dictionary:
		return {"status": status_name(), "path": path, "requested": requested, "value": value,
			"old_value": old_value, "reason": reason, "notes": Array(notes)}


## Validates `patch` given the current configuration `values` ({"identity": {...}, ...}).
static func validate(patch: StructuredPatch, values: Dictionary) -> Result:
	var r := Result.new()
	if patch == null:
		r.reason = "no patch"
		return r
	if patch.file != ConfigSchema.FILE:
		r.reason = "unknown file %s (only %s is editable)" % [patch.file, ConfigSchema.FILE]
		return r
	var parts := ConfigSchema.split_path(patch.path)
	var section: StringName = parts[0]
	var key: String = parts[1]
	if key == "":
		r.reason = "empty path"
		return r
	if ConfigSchema.requires_asset(key):
		r.status = Status.REQUIRES_ASSET
		r.section = ConfigSchema.APPEARANCE
		r.key = key
		r.path = "%s.%s" % [ConfigSchema.APPEARANCE, key]
		r.reason = "%s needs new assets (no rig or material support)" % ConfigSchema.label(&"", key, "en")
		return r
	if section != &"" and not ConfigSchema.has_section(section):
		r.reason = "unknown section %s" % section
		return r
	var owner := ConfigSchema.section_of(key)
	if owner == &"":
		r.reason = "unknown property %s" % key
		return r
	if section != &"" and section != owner:
		r.codes.append(NOTE_SECTION)
		r.notes.append("%s belongs to %s, not %s: applied to %s.%s" % [key, owner, section, owner, key])
	r.section = owner
	r.key = key
	r.path = "%s.%s" % [owner, key]
	var spec := ConfigSchema.spec(owner, key)
	var current: Variant = (values.get(String(owner), {}) as Dictionary).get(key)
	r.old_value = current
	var raw: Variant = patch.resolve(current)
	if patch.relative and raw == null:
		r.reason = "no current value for %s" % r.path
		return r
	if not (raw is float or raw is int) or raw is bool:
		r.reason = "%s expects a number, got %s" % [r.path, type_string(typeof(raw))]
		return r
	var v := float(raw)
	if is_nan(v) or is_inf(v):
		r.reason = "%s expects a finite number" % r.path
		return r
	r.requested = v
	var lo := float(spec["min"])
	var hi := float(spec["max"])
	var clamped := clampf(v, lo, hi)
	var rounded := snappedf(clamped, pow(10.0, -ROUND_DECIMALS))
	if not is_equal_approx(rounded, clamped):
		r.codes.append(NOTE_ROUNDED)
		r.notes.append("%s rounded to %.3f" % [r.path, rounded])
	r.value = rounded
	if not is_equal_approx(clamped, v):
		r.codes.append(NOTE_CLAMPED)
		r.notes.append("%s %.3f is outside [%.3f, %.3f]: clamped to %.3f" % [r.path, v, lo, hi, rounded])
	if current != null and (current is float or current is int) and is_equal_approx(float(current), rounded):
		r.status = Status.UNCHANGED
		r.codes.append(NOTE_UNCHANGED)
		r.notes.append("%s is already %.3f" % [r.path, rounded])
		return r
	r.status = Status.CLAMPED if r.codes.has(NOTE_CLAMPED) else Status.OK
	return r

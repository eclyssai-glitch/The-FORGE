class_name StructuredPatch
extends RefCounted
## One requested change to MIKU's configuration, as data (ADR-016): which file, which
## "section.key" path and which value. Produced by the local parser or by a provider's
## `mutation` ({file, path, value}); never applied directly — it goes through ConfigValidator,
## then the store (MikuConfig) applies the validated value.
##
## A patch is absolute (`value` is the new value) or relative (`delta` is added to the current
## value: "a bit taller"). `resolve(current)` gives the absolute value of a relative patch.

## The configuration file the patch targets (ConfigSchema.FILE).
var file: String = ConfigSchema.FILE
## "section.key" as requested (the section may be missing or wrong; the validator resolves it).
var path: String = ""
## Absolute value (absolute patches). Any Variant as received (validated later).
var value: Variant = null
## True when the patch is relative: the new value is current + `delta`.
var relative := false
var delta := 0.0
## Where it came from: &"local" (parser) or &"provider".
var source: StringName = &"local"
## Original text that produced it ("" for a structured provider mutation).
var text := ""


static func absolute(p_path: String, p_value: Variant, p_source: StringName = &"local") -> StructuredPatch:
	var p := StructuredPatch.new()
	p.path = p_path
	p.value = p_value
	p.source = p_source
	return p


static func relative_change(p_path: String, p_delta: float, p_source: StringName = &"local") -> StructuredPatch:
	var p := StructuredPatch.new()
	p.path = p_path
	p.relative = true
	p.delta = p_delta
	p.source = p_source
	return p


## Patch from a provider's `mutation` Dictionary {file, path, value}; null when malformed
## (missing path/value, non-text file or path).
static func from_mutation(m: Variant) -> StructuredPatch:
	if not m is Dictionary:
		return null
	var d := m as Dictionary
	if not d.has("path") or not d.has("value"):
		return null
	if not (d["path"] is String or d["path"] is StringName):
		return null
	var p := absolute(String(d["path"]), d["value"], &"provider")
	if d.has("file"):
		if not (d["file"] is String or d["file"] is StringName):
			return null
		p.file = String(d["file"])
	return p


## Absolute value requested given the property's `current` value.
func resolve(current: Variant) -> Variant:
	if not relative:
		return value
	if current is float or current is int:
		return float(current) + delta
	return null


## {file, path, value} (relative patches as {file, path, delta}).
func to_dict() -> Dictionary:
	if relative:
		return {"file": file, "path": path, "delta": delta}
	return {"file": file, "path": path, "value": value}


func _to_string() -> String:
	if relative:
		return "%s %s %+.3f" % [file, path, delta]
	return "%s %s = %s" % [file, path, str(value)]

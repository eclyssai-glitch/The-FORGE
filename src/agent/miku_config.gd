class_name MikuConfig
extends RefCounted
## Store of MIKU's configuration (Loop 5, ADR-016): the versioned defaults
## (res://config/miku_default.json, read-only) overlaid with the user's state
## (user://miku/miku.config.json — never in the repository).
##
## - reload(): defaults, then the user file (or its recovery temp file, see below); every value is
##   checked against ConfigSchema (unknown keys dropped, out-of-range values clamped, wrong
##   types ignored — each with a warning). Missing user file = defaults.
## - apply(validation): writes ONE validated value (a ConfigValidator.Result that is applicable)
##   atomically: the whole new state goes to "<file>.tmp", is read back and parsed, then renamed
##   over the user file. On any failure the in-memory state and the file stay as they were.
##   If the process dies between the rename's remove and move (Windows), reload() recovers from
##   the complete ".tmp".
## - reset(): removes the user file (and any temp) — back to the defaults.
## The store never decides what is valid: ConfigValidator does (apply refuses non-applicable
## results). Signals: `changed(path, old_value, new_value)` after a successful apply,
## `reset_done` after reset().

signal changed(path: String, old_value: Variant, new_value: Variant)
signal reset_done

const DEFAULT_PATH := "res://config/miku_default.json"
const USER_DIR := "user://miku"
const USER_PATH := "user://miku/" + ConfigSchema.FILE
const TEMP_SUFFIX := ".tmp"

var default_path: String
var user_path: String
## Version of the defaults file loaded ("version" field).
var version := 0
## Warnings produced by the last reload() (also pushed with push_warning).
var load_warnings := PackedStringArray()

var _defaults: Dictionary = {}
var _values: Dictionary = {}


func _init(p_default_path: String = DEFAULT_PATH, p_user_path: String = USER_PATH) -> void:
	default_path = p_default_path
	user_path = p_user_path
	_defaults = ConfigSchema.fallback_values()
	_values = _defaults.duplicate(true)


## Loads the defaults and the user state. Returns false only when the defaults file is missing
## or unreadable (the schema's fallback values are used then).
func reload() -> bool:
	load_warnings = PackedStringArray()
	var ok := true
	var d: Variant = _read_json(default_path)
	if d is Dictionary and int((d as Dictionary).get("version", 0)) == ConfigSchema.VERSION:
		version = int(d["version"])
		_defaults = _sanitize(d as Dictionary, ConfigSchema.fallback_values(), "default")
	else:
		ok = false
		version = 0
		_warn("defaults %s missing, unreadable or of another version: schema fallback used" % default_path)
		_defaults = ConfigSchema.fallback_values()
	_values = _defaults.duplicate(true)
	var source := user_path
	if not FileAccess.file_exists(user_path) and FileAccess.file_exists(user_path + TEMP_SUFFIX):
		source = user_path + TEMP_SUFFIX
		_warn("user config recovered from %s" % source)
	if FileAccess.file_exists(source):
		var u: Variant = _read_json(source)
		if u is Dictionary and int((u as Dictionary).get("version", -1)) == ConfigSchema.VERSION:
			_values = _sanitize(u as Dictionary, _defaults, "user")
		else:
			_warn("user config %s unreadable or of another version: ignored (defaults kept)" % source)
	return ok


## Current value of "section.key" (null if unknown).
func get_value(path: String) -> Variant:
	var parts := ConfigSchema.split_path(path)
	return (_values.get(String(parts[0]), {}) as Dictionary).get(String(parts[1]))


## Default value of "section.key" (null if unknown).
func default_value(path: String) -> Variant:
	var parts := ConfigSchema.split_path(path)
	return (_defaults.get(String(parts[0]), {}) as Dictionary).get(String(parts[1]))


## Deep copy of the current configuration {"identity": {...}, "appearance": {...}, "behaviour": {...}}.
func values() -> Dictionary:
	return _values.duplicate(true)


func defaults() -> Dictionary:
	return _defaults.duplicate(true)


## Section -> {key: value} of the values that differ from the defaults.
func overrides() -> Dictionary:
	var out := {}
	for s in ConfigSchema.SECTIONS:
		var sec := String(s)
		for k: String in _values.get(sec, {}):
			if not is_equal_approx(float(_values[sec][k]), float(_defaults[sec].get(k, NAN))):
				if not out.has(sec):
					out[sec] = {}
				out[sec][k] = _values[sec][k]
	return out


func has_user_file() -> bool:
	return FileAccess.file_exists(user_path)


## Applies one validated change (ConfigValidator.Result with applicable() true) atomically.
## Returns false (nothing changed, file untouched) when the result is not applicable or the
## write fails.
func apply(result: ConfigValidator.Result) -> bool:
	if result == null or not result.applicable():
		return false
	var sec := String(result.section)
	if not _values.has(sec) or not (_values[sec] as Dictionary).has(result.key):
		return false
	var old: Variant = _values[sec][result.key]
	var next := _values.duplicate(true)
	next[sec][result.key] = float(result.value)
	if not _write_atomic(next):
		return false
	_values = next
	changed.emit(result.path, old, float(result.value))
	return true


## Back to the defaults: removes the user file (and a stale temp). Emits reset_done and one
## `changed` per value that actually moved. Returns false if the file could not be removed.
func reset() -> bool:
	for p in [user_path + TEMP_SUFFIX, user_path]:
		if FileAccess.file_exists(p) and DirAccess.remove_absolute(_abs(p)) != OK:
			_warn("could not remove %s" % p)
			return false
	var before := _values
	_values = _defaults.duplicate(true)
	for s in ConfigSchema.SECTIONS:
		var sec := String(s)
		for k: String in _values[sec]:
			var old: Variant = (before.get(sec, {}) as Dictionary).get(k)
			if old == null or not is_equal_approx(float(old), float(_values[sec][k])):
				changed.emit("%s.%s" % [sec, k], old, _values[sec][k])
	reset_done.emit()
	return true


## Raw bytes of the user file (or null when there is none) — with restore_snapshot(), lets a
## test or the smoke put the user's state back exactly as it was.
func snapshot() -> Variant:
	if not FileAccess.file_exists(user_path):
		return null
	return FileAccess.get_file_as_bytes(user_path)


## Restores a snapshot() (null = no user file) and reloads.
func restore_snapshot(snap: Variant) -> bool:
	if snap == null:
		var ok := reset()
		reload()
		return ok
	DirAccess.make_dir_recursive_absolute(_abs(user_path.get_base_dir()))
	var f := FileAccess.open(user_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(snap as PackedByteArray)
	f.close()
	reload()
	return true


## Text of a config file holding `vals` (same layout as the defaults file).
static func serialize(vals: Dictionary) -> String:
	var doc := {"format": ConfigSchema.FORMAT, "version": ConfigSchema.VERSION}
	for s in ConfigSchema.SECTIONS:
		doc[String(s)] = vals.get(String(s), {})
	return JSON.stringify(doc, "\t", false) + "\n"


# ------------------------------------------------------------------ internals


func _write_atomic(vals: Dictionary) -> bool:
	var dir := user_path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(_abs(dir)) != OK and not DirAccess.dir_exists_absolute(_abs(dir)):
		_warn("cannot create %s" % dir)
		return false
	var text := serialize(vals)
	var tmp := user_path + TEMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		_warn("cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(text)
	f.close()
	# Read back: only a complete, parseable file replaces the user's state.
	var check: Variant = _read_json(tmp)
	if not check is Dictionary or int((check as Dictionary).get("version", -1)) != ConfigSchema.VERSION:
		DirAccess.remove_absolute(_abs(tmp))
		_warn("temp config %s did not read back: discarded" % tmp)
		return false
	if DirAccess.rename_absolute(_abs(tmp), _abs(user_path)) != OK:
		DirAccess.remove_absolute(_abs(tmp))
		_warn("cannot move %s over %s" % [tmp, user_path])
		return false
	return true


## Config of `doc` checked against the schema, starting from `base` (values missing or invalid
## in `doc` keep the base's).
func _sanitize(doc: Dictionary, base: Dictionary, what: String) -> Dictionary:
	var out := base.duplicate(true)
	for sec: Variant in doc:
		var name := String(sec)
		if name in ["format", "version"]:
			continue
		if not ConfigSchema.has_section(StringName(name)):
			_warn("%s config: unknown section %s ignored" % [what, name])
			continue
		var given: Variant = doc[sec]
		if not given is Dictionary:
			_warn("%s config: section %s is not an object" % [what, name])
			continue
		for k: Variant in given:
			var key := String(k)
			var spec := ConfigSchema.spec(StringName(name), key)
			if spec.is_empty():
				_warn("%s config: unknown property %s.%s ignored" % [what, name, key])
				continue
			var v: Variant = given[k]
			if not (v is float or v is int) or v is bool:
				_warn("%s config: %s.%s is not a number: ignored" % [what, name, key])
				continue
			var c := clampf(float(v), float(spec["min"]), float(spec["max"]))
			if not is_equal_approx(c, float(v)):
				_warn("%s config: %s.%s %.3f clamped to %.3f" % [what, name, key, float(v), c])
			out[name][key] = c
	return out


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


static func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path


func _warn(msg: String) -> void:
	load_warnings.append(msg)
	push_warning("MikuConfig: " + msg)

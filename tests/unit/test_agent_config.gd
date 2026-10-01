extends GutTest
## ConfigSchema, StructuredPatch, ConfigValidator and the MikuConfig store (Loop 5). The store is
## exercised in a temporary user:// directory (never the player's user://miku).

const TMP_DIR := "user://_test_agent_config"

var user_path: String


func before_each() -> void:
	user_path = TMP_DIR.path_join(ConfigSchema.FILE)
	_clean()


func after_each() -> void:
	_clean()


func _clean() -> void:
	for f in [user_path, user_path + MikuConfig.TEMP_SUFFIX, TMP_DIR.path_join("blocker")]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(TMP_DIR)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_DIR))


func _store() -> MikuConfig:
	var c := MikuConfig.new(MikuConfig.DEFAULT_PATH, user_path)
	c.reload()
	return c


func _defaults() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(MikuConfig.DEFAULT_PATH))


# ------------------------------------------------------------------ schema


func test_schema_sections_and_contract_properties() -> void:
	assert_eq(ConfigSchema.SECTIONS, [&"identity", &"appearance", &"behaviour"] as Array[StringName])
	var expected := {
		&"identity": ["temperament", "curiosity", "patience", "pride"],
		&"appearance": ["height", "shoulder_width", "neck_length", "chest_volume", "halo_radius", "glow"],
		&"behaviour": ["frustration_threshold", "aggression_peak", "recovery_speed", "interruption_tolerance"],
	}
	for s: StringName in expected:
		assert_eq((ConfigSchema.PROPERTIES[s] as Dictionary).keys(), expected[s], String(s))
	var seen := {}
	for p in ConfigSchema.paths():
		var key: String = ConfigSchema.split_path(p)[1]
		assert_false(seen.has(key), "%s unique across sections" % key)
		seen[key] = true
		var parts := ConfigSchema.split_path(p)
		var spec := ConfigSchema.spec(parts[0], key)
		assert_eq(int(spec["type"]), TYPE_FLOAT, p)
		assert_lt(float(spec["min"]), float(spec["max"]), p)
		assert_gt(float(spec["step"]), 0.0, p)
		assert_ne(String(spec["binding"]), "", p)
		assert_false(ConfigSchema.requires_asset(key), "%s is supported" % p)
	assert_eq(ConfigSchema.section_of("patience"), &"identity")
	assert_eq(ConfigSchema.section_of("glow"), &"appearance")
	assert_eq(ConfigSchema.section_of("wings"), &"")
	assert_true(ConfigSchema.requires_asset("wings"))


func test_default_file_matches_the_schema() -> void:
	var d := _defaults()
	assert_eq(String(d["format"]), ConfigSchema.FORMAT)
	assert_eq(int(d["version"]), ConfigSchema.VERSION)
	for s in ConfigSchema.SECTIONS:
		var sec: Dictionary = d[String(s)]
		assert_eq(sec.keys(), (ConfigSchema.PROPERTIES[s] as Dictionary).keys(), "%s complete and ordered" % s)
		for k: String in sec:
			var spec := ConfigSchema.spec(s, k)
			assert_between(float(sec[k]), float(spec["min"]), float(spec["max"]), "%s.%s default in range" % [s, k])
	assert_eq(float(d["appearance"]["height"]), 1.0, "sculpted height")


# ------------------------------------------------------------------ patch


func test_patch_from_mutation_and_resolve() -> void:
	var p := StructuredPatch.from_mutation({"file": "miku.config.json", "path": "appearance.glow", "value": 0.8})
	assert_not_null(p)
	assert_eq(p.source, &"provider")
	assert_eq(p.resolve(0.1), 0.8)
	assert_null(StructuredPatch.from_mutation({"path": "x"}), "no value")
	assert_null(StructuredPatch.from_mutation({"path": 3, "value": 1}), "path not text")
	assert_null(StructuredPatch.from_mutation({"file": 2, "path": "glow", "value": 1}), "file not text")
	assert_null(StructuredPatch.from_mutation("glow=1"))
	var r := StructuredPatch.relative_change("appearance.height", 0.03)
	assert_almost_eq(float(r.resolve(1.0)), 1.03, 1e-6)
	assert_null(r.resolve(null))
	assert_eq(r.to_dict(), {"file": ConfigSchema.FILE, "path": "appearance.height", "delta": 0.03})


# ------------------------------------------------------------------ validator


func test_validator_ok_clamped_unchanged() -> void:
	var vals := ConfigSchema.fallback_values()
	vals["appearance"]["height"] = 1.0
	var ok := ConfigValidator.validate(StructuredPatch.absolute("appearance.height", 1.04), vals)
	assert_eq(ok.status, ConfigValidator.Status.OK)
	assert_eq(ok.path, "appearance.height")
	assert_almost_eq(float(ok.value), 1.04, 1e-6)
	assert_eq(ok.old_value, 1.0)
	assert_true(ok.applicable())
	var hi := ConfigValidator.validate(StructuredPatch.absolute("height", 1.5), vals)
	assert_eq(hi.status, ConfigValidator.Status.CLAMPED)
	assert_almost_eq(float(hi.value), 1.1, 1e-6)
	assert_has(hi.codes, ConfigValidator.NOTE_CLAMPED)
	assert_true(hi.notes[0].contains("clamped"), "clamp explained: %s" % hi.notes)
	assert_true(hi.applicable())
	vals["appearance"]["height"] = 1.1
	var same := ConfigValidator.validate(StructuredPatch.relative_change("appearance.height", 0.03), vals)
	assert_eq(same.status, ConfigValidator.Status.UNCHANGED, "already at the maximum")
	assert_false(same.applicable())
	assert_has(same.codes, ConfigValidator.NOTE_UNCHANGED)
	var r := ConfigValidator.validate(StructuredPatch.absolute("glow", 0.12345), vals)
	assert_almost_eq(float(r.value), 0.123, 1e-9, "rounded")
	assert_has(r.codes, ConfigValidator.NOTE_ROUNDED)


func test_validator_section_type_file_and_assets() -> void:
	var vals := ConfigSchema.fallback_values()
	var moved := ConfigValidator.validate(StructuredPatch.absolute("behaviour.patience", 0.7), vals)
	assert_eq(moved.status, ConfigValidator.Status.OK)
	assert_eq(moved.path, "identity.patience", "moved to its own section")
	assert_has(moved.codes, ConfigValidator.NOTE_SECTION)
	assert_eq(ConfigValidator.validate(StructuredPatch.absolute("nope.height", 1.0), vals).status,
		ConfigValidator.Status.REJECTED, "unknown section")
	assert_eq(ConfigValidator.validate(StructuredPatch.absolute("appearance.sparkle", 1.0), vals).status,
		ConfigValidator.Status.REJECTED, "unknown property")
	var txt := ConfigValidator.validate(StructuredPatch.absolute("glow", "bright"), vals)
	assert_eq(txt.status, ConfigValidator.Status.REJECTED)
	assert_true(txt.reason.contains("number"))
	assert_eq(ConfigValidator.validate(StructuredPatch.absolute("glow", true), vals).status, ConfigValidator.Status.REJECTED)
	assert_eq(ConfigValidator.validate(StructuredPatch.absolute("glow", INF), vals).status, ConfigValidator.Status.REJECTED)
	var other := StructuredPatch.absolute("glow", 0.5)
	other.file = "project.godot"
	assert_eq(ConfigValidator.validate(other, vals).status, ConfigValidator.Status.REJECTED, "only miku.config.json")
	var wings := ConfigValidator.validate(StructuredPatch.absolute("appearance.wings", "yes"), vals)
	assert_eq(wings.status, ConfigValidator.Status.REQUIRES_ASSET)
	assert_false(wings.applicable())
	assert_eq(ConfigValidator.validate(StructuredPatch.absolute("hair_color", "pink"), vals).status,
		ConfigValidator.Status.REQUIRES_ASSET)
	assert_eq(ConfigValidator.validate(null, vals).status, ConfigValidator.Status.REJECTED)


# ------------------------------------------------------------------ store


func test_store_defaults_without_user_file() -> void:
	var c := _store()
	assert_eq(c.version, ConfigSchema.VERSION)
	assert_false(c.has_user_file())
	assert_eq(c.get_value("appearance.height"), 1.0)
	assert_eq(c.values(), c.defaults())
	assert_eq(c.overrides(), {})
	assert_null(c.get_value("appearance.wings"))


func test_store_apply_is_atomic_and_persistent() -> void:
	var c := _store()
	watch_signals(c)
	var v := ConfigValidator.validate(StructuredPatch.absolute("appearance.height", 1.04), c.values())
	assert_true(c.apply(v))
	assert_signal_emitted_with_parameters(c, "changed", ["appearance.height", 1.0, 1.04])
	assert_almost_eq(float(c.get_value("appearance.height")), 1.04, 1e-6)
	assert_true(FileAccess.file_exists(user_path))
	assert_false(FileAccess.file_exists(user_path + MikuConfig.TEMP_SUFFIX), "temp file renamed away")
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(user_path))
	assert_eq(String(doc["format"]), ConfigSchema.FORMAT)
	assert_almost_eq(float(doc["appearance"]["height"]), 1.04, 1e-6)
	assert_eq(c.overrides(), {"appearance": {"height": 1.04}})
	# A fresh store reads it back.
	var again := _store()
	assert_almost_eq(float(again.get_value("appearance.height")), 1.04, 1e-6)
	# Not applicable results change nothing.
	var bad := ConfigValidator.validate(StructuredPatch.absolute("appearance.wings", 1), c.values())
	assert_false(c.apply(bad))
	assert_false(c.apply(null))
	assert_almost_eq(float(_store().get_value("appearance.height")), 1.04, 1e-6)


func test_store_write_failure_keeps_state() -> void:
	# The user directory cannot be created: a plain file sits where it should be.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var blocker := FileAccess.open(TMP_DIR.path_join("blocker"), FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	var c := MikuConfig.new(MikuConfig.DEFAULT_PATH, TMP_DIR.path_join("blocker").path_join(ConfigSchema.FILE))
	c.reload()
	var v := ConfigValidator.validate(StructuredPatch.absolute("glow", 0.9), c.values())
	assert_false(c.apply(v), "write failed")
	assert_eq(c.get_value("appearance.glow"), 0.5, "memory unchanged")
	assert_false(c.has_user_file())


func test_store_reset_and_snapshot() -> void:
	var c := _store()
	assert_null(c.snapshot(), "no user file yet")
	c.apply(ConfigValidator.validate(StructuredPatch.absolute("glow", 0.9), c.values()))
	var snap: Variant = c.snapshot()
	assert_not_null(snap)
	watch_signals(c)
	assert_true(c.reset())
	assert_signal_emitted(c, "reset_done")
	assert_signal_emitted_with_parameters(c, "changed", ["appearance.glow", 0.9, 0.5])
	assert_false(c.has_user_file())
	assert_eq(c.get_value("appearance.glow"), 0.5)
	assert_true(c.restore_snapshot(snap))
	assert_almost_eq(float(c.get_value("appearance.glow")), 0.9, 1e-6)
	assert_true(c.restore_snapshot(null))
	assert_false(c.has_user_file())
	assert_eq(c.get_value("appearance.glow"), 0.5)


func test_store_sanitizes_user_file_and_recovers_temp() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var f := FileAccess.open(user_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": ConfigSchema.FORMAT, "version": 1,
		"appearance": {"height": 9.0, "wings": 1, "glow": "x"}, "secrets": {"a": 1}}))
	f.close()
	var c := _store()
	assert_almost_eq(float(c.get_value("appearance.height")), 1.1, 1e-6, "clamped on load")
	assert_eq(c.get_value("appearance.glow"), 0.5, "wrong type ignored")
	assert_null(c.get_value("appearance.wings"), "unknown key dropped")
	assert_gt(c.load_warnings.size(), 2)
	# Another version is ignored entirely.
	f = FileAccess.open(user_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 99, "appearance": {"height": 1.05}}))
	f.close()
	assert_eq(_store().get_value("appearance.height"), 1.0)
	# Interrupted rename: only the complete temp file is there.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(user_path))
	f = FileAccess.open(user_path + MikuConfig.TEMP_SUFFIX, FileAccess.WRITE)
	f.store_string(MikuConfig.serialize({"appearance": {"height": 1.06}}))
	f.close()
	var rec := _store()
	assert_almost_eq(float(rec.get_value("appearance.height")), 1.06, 1e-6, "recovered from temp")
	assert_true(rec.reset())
	assert_false(FileAccess.file_exists(user_path + MikuConfig.TEMP_SUFFIX))


func test_store_missing_defaults_uses_schema_fallback() -> void:
	var c := MikuConfig.new("res://config/does_not_exist.json", user_path)
	assert_false(c.reload())
	assert_eq(c.values(), ConfigSchema.fallback_values())

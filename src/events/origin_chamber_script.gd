class_name OriginChamberScript
extends RefCounted
## Canonical scripted timeline of the ORIGIN CHAMBER demonstration.
## Entirely fictional. Times are seconds from session start and must be ascending.

const LAYER_COUNT := 5
const FRAGMENT_COUNT := 96
const CHECKS: Array[StringName] = [&"integrity", &"alignment", &"load", &"resonance"]
const LAYER_NAMES: Array[String] = ["FOUNDATION", "SPAN", "GIRDLE", "CROWN", "APEX"]


static func build() -> Array[SimEvent]:
	var e: Array[SimEvent] = []
	e.append(SimEvent.new(&"ev-000", 0.0, SimEvent.SESSION_OPENED,
		"SESSION OPENED", "Demo session opened. All events in this session are simulated.",
		&"origin_chamber"))
	e.append(SimEvent.new(&"ev-001", 1.5, SimEvent.CORE_ACTIVATION,
		"CORE ACTIVATION", "Activation sequence started on the origin core.", &"origin_core"))
	e.append(SimEvent.new(&"ev-002", 4.0, SimEvent.CORE_ONLINE,
		"CORE ONLINE", "Origin core reached a stable energy state.", &"origin_core"))
	e.append(SimEvent.new(&"ev-003", 6.0, SimEvent.FRAGMENTS_EMITTED,
		"FRAGMENTS EMITTED", "%d geometric fragments released into the chamber." % FRAGMENT_COUNT,
		&"fragment_field", {"count": FRAGMENT_COUNT}))
	e.append(SimEvent.new(&"ev-004", 9.5, SimEvent.STRUCTURE_SEEDED,
		"STRUCTURE SEEDED", "Construction axis locked around the core.", &"structure"))
	var t := 11.0
	for i in LAYER_COUNT:
		e.append(SimEvent.new(StringName("ev-%03d" % (5 + i)), t, SimEvent.LAYER_ADDED,
			"LAYER %s — %s" % [roman(i + 1), LAYER_NAMES[i]],
			"Fragments assembled into layer %d of %d." % [i + 1, LAYER_COUNT],
			layer_entity(i), {"layer": i}))
		t += 3.0
	e.append(SimEvent.new(&"ev-010", 26.5, SimEvent.MATERIALS_APPLIED,
		"MATERIALS APPLIED", "Raw fragments resolved into finished surfaces.", &"structure"))
	e.append(SimEvent.new(&"ev-011", 29.0, SimEvent.LIGHTING_APPLIED,
		"LIGHTING APPLIED", "Chamber lighting brought up to working level.", &"origin_chamber"))
	e.append(SimEvent.new(&"ev-012", 32.0, SimEvent.VERIFICATION_STARTED,
		"VERIFICATION STARTED", "Verification array sweeping the structure.", &"verification_array"))
	var check_t := 33.5
	for i in CHECKS.size():
		var check: StringName = CHECKS[i]
		e.append(SimEvent.new(StringName("ev-%03d" % (13 + i)), check_t, SimEvent.CHECK_PASSED,
			"CHECK · %s" % String(check).to_upper(), "Simulated %s check passed." % check,
			&"verification_array", {"check": check, "index": i}))
		check_t += 2.5
	e.append(SimEvent.new(&"ev-017", 43.0, SimEvent.VERIFICATION_PASSED,
		"VERIFICATION PASSED", "All %d simulated checks passed." % CHECKS.size(),
		&"verification_array"))
	e.append(SimEvent.new(&"ev-018", 45.0, SimEvent.STRUCTURE_FINALIZED,
		"STRUCTURE FINALIZED", "Structure locked into its final form.", &"structure"))
	e.append(SimEvent.new(&"ev-019", 50.0, SimEvent.SESSION_COMPLETED,
		"SESSION COMPLETE", "Demo session complete. Nothing was sent or received.",
		&"origin_chamber"))
	return e


static func layer_entity(index: int) -> StringName:
	return StringName("layer_%d" % index)


static func roman(n: int) -> String:
	const NUMERALS := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
	return NUMERALS[n] if n >= 0 and n < NUMERALS.size() else str(n)
